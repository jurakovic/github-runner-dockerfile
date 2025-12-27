#!/bin/bash

# --- Central Log File ---
CENTRAL_LOG_FILE="/home/docker/actions-runner/runners.log"

# --- Logging Function ---
# This function logs a message to the central log file AND per-runner log file (if set),
# each line prefixed with a timestamp.
log_message() {
  TS="$(date +'%Y-%m-%d %H:%M:%SZ')"
  echo "$TS $@" >> "$CENTRAL_LOG_FILE"
  if [ -n "$RUNNER_LOG_FILE" ]; then
    echo "$TS $@" >> "$RUNNER_LOG_FILE"
  fi
}

# --- Supervisor Logic for PID 1 (Container Entrypoint) ---
if [ $$ -eq 1 ]; then
  # Create the log file if it doesn't exist
  touch "$CENTRAL_LOG_FILE"

  log_message "Supervisor process (PID 1) started."
  # Tail the central log file to the container's stdout so 'docker logs' works
  tail -f "$CENTRAL_LOG_FILE" &
  TAIL_PID=$!

  # Start any existing runner directories' run.sh
  RUNNER_BASE_DIR="/home/docker/actions-runner"
  FOUND_RUNNER=0
  for DIR in "$RUNNER_BASE_DIR"/*/; do
    # Skip if not a directory or if not configured (looking for run.sh file)
    if [ -d "$DIR" ] && [ -x "${DIR}/run.sh" ]; then
      FOUND_RUNNER=1
      log_message "Starting existing runner at $DIR"
      (
        cd "$DIR"
        ./run.sh >> "$CENTRAL_LOG_FILE" 2>&1 &
      )
    fi
  done

  # If no runners found, try initial setup if env/args provided
  if [ $FOUND_RUNNER -eq 0 ]; then
    log_message "No existing runners found."
    if [ "$#" -gt 0 ] || [ -n "$NAME" ] || [ -n "$TOKEN" ]; then
      log_message "Attempting initial runner setup with provided arguments/environment variables."
      ./start.sh "$@" &
    else
      log_message "No runner arguments or environment variables provided; supervisor waiting indefinitely."
    fi
  fi

  # Signal handling: only terminate, do not unregister/remove runner!
  trap 'log_message "Supervisor SIGTERM: Exiting."; kill 0; exit 143' TERM
  trap 'log_message "Supervisor SIGINT: Exiting."; kill 0; exit 130' INT

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
    log_message "Error: --remove requires --name, --repo, and --token."
    exit 1
  fi

  RUNNER_DIR="/home/docker/actions-runner/$RUNNER_NAME"
  if [ ! -d "$RUNNER_DIR" ]; then
    log_message "Error: Runner directory '$RUNNER_DIR' not found."
    exit 1
  fi

  log_message "Removing runner $RUNNER_NAME..."
  # A registration token is needed to authenticate the removal request
  REG_TOKEN=$(curl -sS -X POST -H "Authorization: token $ACCESS_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/$REPOSITORY/actions/runners/registration-token | jq .token --raw-output)

  cd "$RUNNER_DIR"
  # This command may fail if the runner is already gone from GitHub, which is fine.
  ./config.sh remove --token "$REG_TOKEN" >> "$CENTRAL_LOG_FILE" 2>&1 || true

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

RUNNER_DIR="/home/docker/actions-runner/$RUNNER_NAME"
export RUNNER_LOG_FILE="$RUNNER_DIR/runner.log"

log_message "RUNNER_NAME: $RUNNER_NAME"
log_message "REPOSITORY: $REPOSITORY"
log_message "ACCESS_TOKEN: (hidden)"

REG_TOKEN=$(curl -sS -X POST -H "Authorization: token $ACCESS_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/$REPOSITORY/actions/runners/registration-token | jq .token --raw-output)

cd /home/docker/actions-runner

if [ -d "$RUNNER_NAME" ]; then
  log_message "Runner '$RUNNER_NAME' already exists. Reusing existing runner."
  cd "$RUNNER_NAME"
else
  log_message "Creating new runner '$RUNNER_NAME'."
  mkdir "$RUNNER_NAME" && tar xzf ./actions-runner-linux-x64-*.tar.gz -C "$RUNNER_NAME" && cd "$RUNNER_NAME"
  touch "$RUNNER_LOG_FILE"
  export ACTIONS_RUNNER_INPUT_TOKEN="$REG_TOKEN" # pass token via env variable to avoid showing in process list
  ./config.sh --disableupdate --name "$RUNNER_NAME" --url "https://github.com/$REPOSITORY" >> "$CENTRAL_LOG_FILE" 2>&1
fi

log_message "Executing run.sh for runner '$RUNNER_NAME'."
./run.sh >> "$CENTRAL_LOG_FILE" 2>&1 &
RUNNER_PID=$!

log_message "Wait for runner '$RUNNER_NAME' (RUNNER_PID: $RUNNER_PID)."
wait $RUNNER_PID

log_message "Runner process for '$RUNNER_NAME' has exited."
# Do not remove the runner or its config unless requested by --remove
