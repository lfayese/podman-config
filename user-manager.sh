#!/bin/bash
set -euo pipefail

# Configuration
CONFIG_DIR="/etc/podman-provision"
LOG_DIR="/var/log/podman-provision"
LOG_FILE="$LOG_DIR/user-manager-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

check_permissions() {
  if ! groups | grep -qE '(wheel|sudo)'; then
    echo "⚠️ Warning: Some operations require admin privileges"
    return 1
  fi
  return 0
}

show_status() {
  local username=$1
  echo "Status for user: $username"
  echo "-------------------"

  # Check user existence
  if ! id "$username" &>/dev/null; then
    echo "User does not exist"
    return 1
  fi

  # Show container status
  echo "Container Status:"
  podman ps --filter "label=user=$username" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

  # Show volume status
  echo -e "\nVolume Status:"
  podman volume ls --filter "label=user=$username" --format "table {{.Name}}\t{{.Size}}"

  # Show resource usage
  echo -e "\nResource Usage:"
  podman stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" --filter "label=user=$username"

  return 0
}

create_new_user() {
  local username=$1

  if ! check_permissions; then
    return 1
  fi

  if id "$username" &>/dev/null; then
    log "User $username already exists"
    return 1
  fi

  # Source the main setup script to reuse functions
  if [[ -f "/tmp/setup-users.sh" ]]; then
    source "/tmp/setup-users.sh"

    # Call the main user setup functions
    create_user "$username"
    create_containers_config "$username"
    apply_shell_trust "$username"
    setup_node_yarn "$username"
    setup_powershell "$username"
    setup_podman_socket "$username"

    if [[ -f "$CONTAINER_SETUP_SCRIPT" ]]; then
      sudo -u "$username" bash "$CONTAINER_SETUP_SCRIPT" "$username"
    fi
  else
    log "Setup script not found at /tmp/setup-users.sh"
    return 1
  fi
}

reset_user_env() {
  local username=$1

  if ! check_permissions; then
    return 1
  fi

  # Stop user containers
  podman ps -a --filter "label=user=$username" -q | xargs -r podman stop

  # Remove user containers
  podman ps -a --filter "label=user=$username" -q | xargs -r podman rm

  # Reset volumes
  for vol in $(podman volume ls --filter "label=user=$username" -q); do
    podman volume rm -f "$vol"
  done

  # Recreate environment
  if [[ -f "$CONTAINER_SETUP_SCRIPT" ]]; then
    sudo -u "$username" bash "$CONTAINER_SETUP_SCRIPT" "$username"
  fi
}

monitor_resources() {
  local username=$1
  local quota_file="/etc/podman-provision/quotas/$username.json"

  # Get current resource usage
  local cpu_usage=$(podman stats --no-stream --format "{{.CPUPerc}}" --filter "label=user=$username" | awk '{s+=$1} END {print s}')
  local mem_usage=$(podman stats --no-stream --format "{{.MemUsage}}" --filter "label=user=$username" | awk '{s+=$1} END {print s}')
  local disk_usage=$(du -sh "/home/$username" 2>/dev/null | cut -f1)

  # Check against quotas if they exist
  if [[ -f "$quota_file" ]]; then
    local cpu_quota=$(jq -r '.cpu_limit' "$quota_file")
    local mem_quota=$(jq -r '.memory_limit' "$quota_file")
    local disk_quota=$(jq -r '.disk_limit' "$quota_file")

    # Alert if quotas exceeded
    if (( $(echo "$cpu_usage > $cpu_quota" | bc -l) )); then
      log "⚠️ CPU quota exceeded for $username: $cpu_usage > $cpu_quota"
    fi
    if (( $(echo "$mem_usage > $mem_quota" | bc -l) )); then
      log "⚠️ Memory quota exceeded for $username: $mem_usage > $mem_quota"
    fi
  fi

  # Output current usage
  cat <<EOF
Resource Usage for $username:
---------------------------
CPU Usage: $cpu_usage%
Memory Usage: $mem_usage
Disk Usage: $disk_usage
EOF
}

set_quota() {
  local username=$1
  local resource=$2
  local limit=$3

  if ! check_permissions; then
    return 1
  fi

  local quota_dir="/etc/podman-provision/quotas"
  local quota_file="$quota_dir/$username.json"

  mkdir -p "$quota_dir"

  # Create or update quota file
  if [[ ! -f "$quota_file" ]]; then
    echo "{}" > "$quota_file"
  fi

  case "$resource" in
    cpu)
      jq --arg limit "$limit" '.cpu_limit = $limit' "$quota_file" > "$quota_file.tmp"
      ;;
    memory)
      jq --arg limit "$limit" '.memory_limit = $limit' "$quota_file" > "$quota_file.tmp"
      ;;
    disk)
      jq --arg limit "$limit" '.disk_limit = $limit' "$quota_file" > "$quota_file.tmp"
      ;;
    *)
      log "Invalid resource type: $resource"
      return 1
      ;;
  esac

  mv "$quota_file.tmp" "$quota_file"
  log "✅ Set $resource quota for $username to $limit"
}

show_help() {
  cat <<EOF
Usage: user-manager.sh [OPTIONS] COMMAND

Commands:
  status USERNAME       Show status for user
  create USERNAME      Create new user
  reset USERNAME       Reset user environment
  monitor USERNAME     Show resource usage
  quota USERNAME RESOURCE LIMIT  Set resource quota (cpu/memory/disk)
  help                Show this help message

Options:
  --force             Force operation without confirmation
EOF
}

main() {
  local command=""
  local username=""
  local force="false"

  while [[ $# -gt 0 ]]; do
    case $1 in
      status|create|reset|monitor|quota)
        command="$1"
        username="$2"
        shift 2
        ;;
      --force)
        force="true"
        shift
        ;;
      help)
        show_help
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done

  case "$command" in
    status)
      show_status "$username"
      ;;
    create)
      create_new_user "$username"
      ;;
    reset)
      if [[ "$force" == "true" ]] || read -p "Reset environment for $username? [y/N] " -n 1 -r && [[ $REPLY =~ ^[Yy]$ ]]; then
        reset_user_env "$username"
      fi
      ;;
    monitor)
      monitor_resources "$username"
      ;;
    quota)
      set_quota "$username" "$2" "$3"
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
