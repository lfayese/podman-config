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

  mkdir -p "$(dirname "$log_file")"
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

  # Perform any necessary cleanup here

  exit $exit_code
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
export -f log handle_error retry_operation command_exists user_exists run_as_user
