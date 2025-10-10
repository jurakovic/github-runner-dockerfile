#!/bin/bash

# --- Central Log File ---
CENTRAL_LOG_FILE="/home/docker/actions-runner/runners.log"

# --- Supervisor Logic for PID 1 ---
# If this is the main container process, it becomes a supervisor that never exits.
if [ $$ -eq 1 ]; then
  echo "Supervisor process (PID 1) started." | tee -a "$CENTRAL_LOG_FILE"
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
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

# --- Action: Remove Runner ---
if [ "$ACTION" = "remove" ]; then
  if [ -z "$RUNNER_NAME" ] || [ -z "$REPOSITORY" ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "Error: --remove requires --name, --repo, and --token to be specified." >&2
    exit 1
  fi

  RUNNER_DIR="/home/docker/actions-runner/$RUNNER_NAME"
  if [ ! -d "$RUNNER_DIR" ]; then
    echo "Error: Runner directory '$RUNNER_DIR' not found." >&2
    exit 1
  fi

  echo "Removing runner $RUNNER_NAME..."
  # A registration token is needed to authenticate the removal request
  REG_TOKEN=$(curl -sS -X POST -H "Authorization: token $ACCESS_TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/repos/$REPOSITORY/actions/runners/registration-token | jq .token --raw-output)

  cd "$RUNNER_DIR"
  # This command may fail if the runner is already gone from GitHub, which is fine.
  ./config.sh remove --unattended --token "$REG_TOKEN" || true

  # Clean up the directory
  cd ..
  rm -rf "$RUNNER_NAME"
  echo "Runner $RUNNER_NAME removed successfully."
  exit 0
fi

# --- Action: Start Runner ---
# Check for required variables
if [ -z "$REPOSITORY" ] || [ -z "$ACCESS_TOKEN" ]; then
  echo "Error: --repo and --token arguments or REPO and TOKEN environment variables must be set." >&2
  exit 1
fi

# Fallback to HOSTNAME if name not set
if [ -z "$RUNNER_NAME" ]; then
  RUNNER_NAME=$HOSTNAME
fi

echo "RUNNER_NAME: $RUNNER_NAME"
echo "REPOSITORY: $REPOSITORY"
echo "ACCESS_TOKEN: (hidden)"

REG_TOKEN=$(curl -sS -X POST -H "Authorization: token $ACCESS_TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/repos/$REPOSITORY/actions/runners/registration-token | jq .token --raw-output)

cd /home/docker/actions-runner

if [ -d "$RUNNER_NAME" ]; then
  echo "Error: Runner '$RUNNER_NAME' already exists. Please use a different name or remove the existing runner." >&2
  exit 1
fi

mkdir "$RUNNER_NAME" && tar xzf ./actions-runner-linux-x64-*.tar.gz -C "./$RUNNER_NAME" && cd "./$RUNNER_NAME"

./config.sh --name "$RUNNER_NAME" --url "https://github.com/$REPOSITORY" --token "$REG_TOKEN"

cleanup() {
  echo "Signal received. Removing runner $RUNNER_NAME..." | tee -a "$CENTRAL_LOG_FILE"
  # This command may fail if the runner is already gone from GitHub, which is fine.
  ./config.sh remove --unattended --token "$REG_TOKEN" || true
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
echo "Runner process for '$RUNNER_NAME' has exited. Cleaning up..." | tee -a "$CENTRAL_LOG_FILE"
cd /home/docker/actions-runner
rm -rf "$RUNNER_NAME"
echo "Local directory for runner '$RUNNER_NAME' has been removed." | tee -a "$CENTRAL_LOG_FILE"
