#!/usr/bin/env bash
set -euo pipefail

RUNNER_BASE_DIR="/home/docker/actions-runner"
CENTRAL_LOG_FILE="$RUNNER_BASE_DIR/runners.log"

# -----------------------------
# Logging
# -----------------------------
log_message() {
  local ts
  ts="$(date +'%Y-%m-%d %H:%M:%SZ')"
  echo "$ts $*" >> "$CENTRAL_LOG_FILE"

  if [[ -n "${RUNNER_LOG_FILE:-}" && -f "$RUNNER_LOG_FILE" ]]; then
    echo "$ts $*" >> "$RUNNER_LOG_FILE"
  fi
}

# -----------------------------
# Utilities
# -----------------------------
require_vars() {
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      log_message "Error: Required variable '$var' is not set."
      exit 1
    fi
  done
}

get_registration_token() {
  curl -sS -X POST \
    -H "Authorization: token $ACCESS_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPOSITORY/actions/runners/registration-token" \
  | jq -r .token
}

# -----------------------------
# Supervisor (PID 1)
# -----------------------------
start_existing_runners() {
  local found=0

  for dir in "$RUNNER_BASE_DIR"/*/; do
    [[ -x "${dir}/run.sh" ]] || continue

    found=1
    export RUNNER_LOG_FILE="${dir}/runner.log"
    log_message "Starting existing runner at $dir"

    (
      cd "$dir"
      ./run.sh >> "$CENTRAL_LOG_FILE" 2>&1 &
    )
  done

  return $found
}

supervisor_main() {
  set +e  # PID 1 must not die easily

  touch "$CENTRAL_LOG_FILE"
  log_message "Supervisor process (PID 1) started."

  tail -f "$CENTRAL_LOG_FILE" &
  TAIL_PID=$!

  start_existing_runners

  if [ $? -eq 0 ]; then
    log_message "No existing runners found."

    if [[ "$#" -gt 0 || -n "${NAME:-}" || -n "${TOKEN:-}" ]]; then
      log_message "Attempting initial runner setup."
      ./start.sh "$@" &
    else
      log_message "No runner arguments or environment variables provided; waiting indefinitely."
    fi
  fi

  trap 'log_message "Supervisor SIGTERM"; kill 0; exit 143' TERM
  trap 'log_message "Supervisor SIGINT"; kill 0; exit 130' INT

  wait
}

# -----------------------------
# Argument parsing
# -----------------------------
parse_args() {
  RUNNER_NAME="${NAME:-}"
  REPOSITORY="${REPO:-}"
  ACCESS_TOKEN="${TOKEN:-}"
  ACTION="start"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --name) RUNNER_NAME="$2"; shift 2;;
      --repo) REPOSITORY="$2"; shift 2;;
      --token) ACCESS_TOKEN="$2"; shift 2;;
      --remove) ACTION="remove"; RUNNER_NAME="$2"; shift 2;;
      *)
        log_message "Unknown option: $1"
        exit 1
        ;;
    esac
  done
}

# -----------------------------
# Runner removal
# -----------------------------
remove_runner() {
  require_vars RUNNER_NAME REPOSITORY ACCESS_TOKEN

  local runner_dir="$RUNNER_BASE_DIR/$RUNNER_NAME"

  if [[ ! -d "$runner_dir" ]]; then
    log_message "Error: Runner '$RUNNER_NAME' not found."
    exit 1
  fi

  log_message "Removing runner '$RUNNER_NAME'."
  local reg_token
  reg_token="$(get_registration_token)"

  cd "$runner_dir"
  # todo: find pid and kill if running?
  ./config.sh remove --token "$reg_token" >> "$CENTRAL_LOG_FILE" 2>&1 || true

  cd ..
  rm -rf "$RUNNER_NAME"
  log_message "Runner '$RUNNER_NAME' removed."
}

# -----------------------------
# Runner creation & execution
# -----------------------------
create_runner() {
  require_vars REPOSITORY ACCESS_TOKEN

  log_message "RUNNER_NAME: $RUNNER_NAME"
  log_message "REPOSITORY: $REPOSITORY"
  log_message "ACCESS_TOKEN: (hidden)"

  RUNNER_NAME="${RUNNER_NAME:-$HOSTNAME}"
  local runner_dir="$RUNNER_BASE_DIR/$RUNNER_NAME"

  if [[ -d "$runner_dir" ]]; then
    log_message "Runner '$RUNNER_NAME' already exists. Remove it first or set different name."
    exit 0
  fi

  log_message "Creating runner '$RUNNER_NAME'."
  local reg_token
  reg_token="$(get_registration_token)"

  mkdir "$runner_dir"
  cd "$RUNNER_BASE_DIR"
  tar xzf ./actions-runner-linux-x64-*.tar.gz -C "$runner_dir"
  cd "$runner_dir"

  export RUNNER_LOG_FILE="$runner_dir/runner.log"
  touch "$RUNNER_LOG_FILE"

  export ACTIONS_RUNNER_INPUT_TOKEN="$reg_token" # pass token via env variable to avoid showing in process list
  ./config.sh \
    --disableupdate \
    --name "$RUNNER_NAME" \
    --url "https://github.com/$REPOSITORY" \
    >> "$CENTRAL_LOG_FILE" 2>&1
}

run_runner() {
  log_message "Starting runner '$RUNNER_NAME'."
  ./run.sh >> "$CENTRAL_LOG_FILE" 2>&1 &
  log_message "Runner '$RUNNER_NAME' started (PID $!)."
}

# -----------------------------
# Main
# -----------------------------
main() {
  parse_args "$@"

  if [[ "$ACTION" == "remove" ]]; then
    remove_runner
    exit 0
  fi

  create_runner
  run_runner
}

# -----------------------------
# Entrypoint
# -----------------------------
if [[ $$ -eq 1 ]]; then
  supervisor_main "$@"
else
  main "$@"
fi
