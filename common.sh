#!/bin/bash
# Common functions for all provisioning scripts

# Source configuration
if [[ -f "/tmp/config.sh" ]]; then
  source "/tmp/config.sh"
fi

# Setup logging
setup_logging() {
  local script_name=$(basename "$0" .sh)
  local log_file="${LOG_DIR:-/var/log/podman-provision}/${script_name}-$(date +%Y%m%d-%H%M%S).log"

  sudo mkdir -p "$(dirname "$log_file")"
  sudo touch "$log_file"
  sudo chown $USER:$USER "$log_file"
  exec > >(tee -a "$log_file") 2>&1

  log "Starting $script_name"
}

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling
handle_error() {
  local exit_code=$?
  local line_no=$1
  log "Error on line $line_no: Command exited with status $exit_code"

  # Cleanup running processes
  jobs -p | xargs -r kill

  # Reset terminal
  stty sane 2>/dev/null || true

  # Restore file descriptors
  exec 1>&- 2>&-
  exec 1>/dev/tty 2>/dev/tty

  exit $exit_code
}

# Verify required environment variables
verify_env() {
  local vars=("$@")
  local missing=()

  for var in "${vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    log "❌ Missing required environment variables: ${missing[*]}"
    return 1
  fi
  return 0
}

# Retry function
retry_operation() {
  local operation=$1
  local description=$2
  local attempt=1
  local max_retries=${3:-$MAX_RETRIES}
  local retry_delay=${4:-$RETRY_DELAY}

  while ((attempt <= max_retries)); do
    if $operation; then
      return 0
    fi

    log "⚠️ Attempt $attempt of $max_retries for $description failed. Retrying in ${retry_delay}s..."
    sleep $retry_delay
    ((attempt++))
  done

  log "❌ All attempts failed for $description"
  return 1
}

# Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if a user exists
user_exists() {
  id "$1" &>/dev/null
}

# Run a command as a specific user
run_as_user() {
  local username=$1
  shift
  sudo -u "$username" "$@"
}

# Export all functions
export -f log handle_error verify_env retry_operation command_exists user_exists run_as_user
