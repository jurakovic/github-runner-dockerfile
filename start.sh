#!/bin/bash

# Initialize variables from environment
RUNNER_NAME="${NAME}"
REPOSITORY="${REPO}"
ACCESS_TOKEN="${TOKEN}"

# Parse named arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) RUNNER_NAME="$2"; shift 2;;
    --repo) REPOSITORY="$2"; shift 2;;
    --token) ACCESS_TOKEN="$2"; shift 2;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

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
  echo "Error: Runner '$RUNNER_NAME' already exists. Please use a different name." >&2
  exit 1
fi

mkdir "$RUNNER_NAME" && tar xzf ./actions-runner-linux-x64-*.tar.gz -C "./$RUNNER_NAME" && cd "./$RUNNER_NAME"

./config.sh --name "$RUNNER_NAME" --url "https://github.com/$REPOSITORY" --token "$REG_TOKEN"

cleanup() {
  echo "Removing runner $RUNNER_NAME..."
  ./config.sh remove --unattended --token "$REG_TOKEN"
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Central log file
CENTRAL_LOG_FILE="/home/docker/actions-runner/runners.log"

# Append all output to the central log file
./run.sh >> "$CENTRAL_LOG_FILE" 2>&1 &
RUNNER_PID=$!

# If this is the main container process (PID 1), tail the central log file.
if [ $$ -eq 1 ]; then
  # Create the log file if it doesn't exist
  touch "$CENTRAL_LOG_FILE"
  # Tail the central log file and send its output to the container's stdout
  tail -f "$CENTRAL_LOG_FILE" &
fi

wait $RUNNER_PID
