#!/bin/bash

# Initialize variables from environment
WORKER_NAME="${NAME}"
REPOSITORY="${REPO}"
ACCESS_TOKEN="${TOKEN}"

# Parse named arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) WORKER_NAME="$2"; shift 2;;
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
if [ -z "$WORKER_NAME" ]; then
  WORKER_NAME=$HOSTNAME
fi

echo "WORKER_NAME: $WORKER_NAME"
echo "REPOSITORY: $REPOSITORY"
echo "ACCESS_TOKEN: (hidden)"

REG_TOKEN=$(curl -sS -X POST -H "Authorization: token $ACCESS_TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/repos/$REPOSITORY/actions/runners/registration-token | jq .token --raw-output)

cd /home/docker/actions-runner

if [ -d "$WORKER_NAME" ]; then
  echo "Error: Runner '$WORKER_NAME' already exists. Please use a different name." >&2
  exit 1
fi

mkdir "$WORKER_NAME" && tar xzf ./actions-runner-linux-x64-*.tar.gz -C "./$WORKER_NAME" && cd "./$WORKER_NAME"

./config.sh --name "$WORKER_NAME" --url "https://github.com/$REPOSITORY" --token "$REG_TOKEN"

cleanup() {
  echo "Removing runner..."
  ./config.sh remove --unattended --token "$REG_TOKEN"
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./run.sh & wait $!
