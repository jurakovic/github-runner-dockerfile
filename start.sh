#!/bin/bash

# --- Central Log File ---
CENTRAL_LOG_FILE="/home/docker/actions-runner/runners.log"

# --- Logging Function ---
# This function logs a message ONLY to the central log file.
# The supervisor's 'tail -f' process is responsible for showing it in 'docker logs'.
log_message() {
  echo "$@" >> "$CENTRAL_LOG_FILE"
}

# --- Supervisor Logic for PID 1 ---
# If this is the main container process, it becomes a supervisor that never exits.
if [ $$ -eq 1 ]; then
  log_message "Supervisor process (PID 1) started."
  # Create the log file if it doesn't exist
  touch "$CENTRAL_LOG_FILE"
  # Tail the central log file to the container's stdout so 'docker logs' works
  tail -f "$CENTRAL_LOG_FILE" &
  
  # Check if an initial runner should be started.
  # This is true if arguments were passed OR if the required ENV VARS are set.
  if [ "$#" -gt 0 ] || [ -n "$NAME" ] || [ -n "$TOKEN" ] || [ -n "$TOKEN" ]; then
    # Run this script again in the background, but not as PID 1.
    # Pass along any arguments that were provided. The new process will inherit the environment variables.
    ./start.sh "$@" &
  fi
  
  # Wait indefinitely for background jobs (like tail -f).
  # This keeps the container alive.
  wait
  exit 0
fi

# --- Runner Management Logic (for all non-PID 1 processes) ---

# --- Argument Parsing ---
# Initialize variables from environment
RUNNER_NAME="${NAME}"
REPOSITORY="${REPO}"
ACCESS_TOKEN="${TOKEN}"
ACTION="start" # Default action

# Parse named arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) RUNNER_NAME="$2"; shift 2;;
    --repo) REPOSITORY="$2"; shift 2;;
    --token) ACCESS_TOKEN="$2"; shift 2;;
    --remove) ACTION="remove"; RUNNER_NAME="$2"; shift 2;;
    *) log_message "Unknown option: $1"; exit 1;;
  esac
done

# --- Action: Remove Runner ---
if [ "$ACTION" = "remove" ]; then
  if [ -z "$RUNNER_NAME" ] || [ -z "$REPOSITORY" ] || [ -z "$ACCESS_TOKEN" ]; then
    log_message "Error: --remove requires --name, --repo, and --token to be specified."
    exit 1
  fi

  RUNNER_DIR="/home/docker/actions-runner/$RUNNER_NAME"
  if [ ! -d "$RUNNER_DIR" ]; then
    log_message "Error: Runner directory '$RUNNER_DIR' not found."
    exit 1
  fi

  log_message "Removing runner $RUNNER_NAME..."
  # A registration token is needed to authenticate the removal request
  REG_TOKEN=$(curl -sS -X POST -H "Authorization: token $ACCESS_TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/repos/$REPOSITORY/actions/runners/registration-token | jq .token --raw-output)

  cd "$RUNNER_DIR"
  # This command may fail if the runner is already gone from GitHub, which is fine.
  ./config.sh remove --unattended --token "$REG_TOKEN" >> "$CENTRAL_LOG_FILE" 2>&1 || true

  # Clean up the directory
  cd ..
  rm -rf "$RUNNER_NAME"
  log_message "Runner $RUNNER_NAME removed successfully."
  exit 0
fi

# --- Action: Start Runner ---
# Check for required variables
if [ -z "$REPOSITORY" ] || [ -z "$ACCESS_TOKEN" ]; then
  log_message "Error: --repo and --token arguments or REPO and TOKEN environment variables must be set."
  exit 1
fi

# Fallback to HOSTNAME if name not set
if [ -z "$RUNNER_NAME" ]; then
  RUNNER_NAME=$HOSTNAME
fi

log_message "RUNNER_NAME: $RUNNER_NAME"
log_message "REPOSITORY: $REPOSITORY"
log_message "ACCESS_TOKEN: (hidden)"

REG_TOKEN=$(curl -sS -X POST -H "Authorization: token $ACCESS_TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/repos/$REPOSITORY/actions/runners/registration-token | jq .token --raw-output)

cd /home/docker/actions-runner

if [ -d "$RUNNER_NAME" ]; then
  log_message "Runner '$RUNNER_NAME' already exists. Reusing existing runner."
  cd "$RUNNER_NAME"
else
  log_message "Creating new runner '$RUNNER_NAME'."
  mkdir "$RUNNER_NAME" && tar xzf ./actions-runner-linux-x64-*.tar.gz -C "./$RUNNER_NAME" && cd "./$RUNNER_NAME"
  ./config.sh --name "$RUNNER_NAME" --url "https://github.com/$REPOSITORY" --token "$REG_TOKEN" >> "$CENTRAL_LOG_FILE" 2>&1
fi

cleanup() {
  log_message "Signal received. Removing runner $RUNNER_NAME..."
  # This command may fail if the runner is already gone from GitHub, which is fine.
  ./config.sh remove --unattended --token "$REG_TOKEN" >> "$CENTRAL_LOG_FILE" 2>&1 || true
  cd /home/docker/actions-runner
  rm -rf "$RUNNER_NAME"
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Append all output to the central log file
./run.sh >> "$CENTRAL_LOG_FILE" 2>&1 &
RUNNER_PID=$!

wait $RUNNER_PID

# --- Self-Cleaning Logic ---
# This code runs after the runner process (run.sh) has exited.
log_message "Runner process for '$RUNNER_NAME' has exited. Cleaning up..."
cd /home/docker/actions-runner
rm -rf "$RUNNER_NAME"
log_message "Local directory for runner '$RUNNER_NAME' has been removed."
