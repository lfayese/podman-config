#!/bin/bash
set -euo pipefail

# Load configuration
if [[ -f "/tmp/config.sh" ]]; then
  source "/tmp/config.sh"
else
  # Default configuration
  USERS=("ofayese" "639016")
  LOG_DIR="/var/log/podman-provision"
fi

LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

cleanup_user() {
  local username=$1
  local remove_home=$2

  log "Cleaning up user: $username"

  # Stop all user containers
  log "Stopping containers for $username..."
  podman ps -a --filter "label=user=$username" -q | xargs -r podman stop

  # Remove user containers
  log "Removing containers for $username..."
  podman ps -a --filter "label=user=$username" -q | xargs -r podman rm

  # Remove user volumes
  log "Removing volumes for $username..."
  for vol in $(podman volume ls --filter "label=user=$username" -q); do
    podman volume rm -f "$vol"
  done

  # Remove systemd user services
  if systemctl --user -q is-active podman.socket; then
    systemctl --user stop podman.socket
    systemctl --user disable podman.socket
  fi

  # Optionally remove home directory
  if [[ "$remove_home" == "true" ]]; then
    log "Removing home directory for $username..."
    sudo rm -rf "/home/$username"
  fi

  # Remove user from system
  sudo userdel -r "$username" || true
}

cleanup_system() {
  log "Performing system cleanup..."

  # Clean up container storage
  podman system prune -af

  # Clean up unused volumes
  podman volume prune -f

  # Remove configuration files
  sudo rm -rf /etc/podman-provision

  # Clean up logs
  sudo rm -rf "$LOG_DIR"
}

show_help() {
  cat <<EOF
Usage: cleanup.sh [OPTIONS]

Options:
  --help          Show this help message
  --user USER     Clean up specific user
  --remove-home   Remove home directory when cleaning up user
  --all          Clean up all users and system files
  --dry-run      Show what would be done without doing it
EOF
}

main() {
  local target_user=""
  local remove_home="false"
  local clean_all="false"
  local dry_run="false"

  while [[ $# -gt 0 ]]; do
    case $1 in
      --help)
        show_help
        exit 0
        ;;
      --user)
        target_user="$2"
        shift 2
        ;;
      --remove-home)
        remove_home="true"
        shift
        ;;
      --all)
        clean_all="true"
        shift
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done

  if [[ "$dry_run" == "true" ]]; then
    log "DRY RUN - No changes will be made"
  fi

  if [[ "$clean_all" == "true" ]]; then
    for user in "${USERS[@]}"; do
      if [[ "$dry_run" == "true" ]]; then
        log "Would clean up user: $user"
      else
        cleanup_user "$user" "$remove_home"
      fi
    done

    if [[ "$dry_run" == "true" ]]; then
      log "Would perform system cleanup"
    else
      cleanup_system
    fi
  elif [[ -n "$target_user" ]]; then
    if [[ "$dry_run" == "true" ]]; then
      log "Would clean up user: $target_user"
    else
      cleanup_user "$target_user" "$remove_home"
    fi
  else
    show_help
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
