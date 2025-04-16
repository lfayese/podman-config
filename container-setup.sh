#!/bin/bash
set -euo pipefail

# Load shared configuration
if [[ -f "/tmp/config.sh" ]]; then
  source "/tmp/config.sh"
fi

VOLUME_ROOT="/var/lib/containers/storage/volumes"
LOG_FILE="/var/log/container-setup.log"

# === Helper Functions ===
MAX_RETRIES=3
RETRY_DELAY=5

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

check_container_health() {
  local container=$1
  local image_id=$(podman inspect --format '{{.Id}}' "$container" 2>/dev/null)

  if [[ -z "$image_id" ]]; then
    log "❌ Failed health check: $container not found"
    return 1
  fi

  # Verify image can be loaded properly
  if ! podman image inspect "$container" &>/dev/null; then
    log "❌ Image verification failed: $container may be corrupt"
    return 1
  fi

  # Try running a simple command in the container
  if ! podman run --rm "$container" echo "Container health check" &>/dev/null; then
    log "❌ Container runtime test failed: $container"
    return 1
  fi

  log "✅ Container health check passed: $container"
  return 0
}

retry_operation() {
  local operation=$1
  local description=$2
  local attempt=1

  while ((attempt <= MAX_RETRIES)); do
    if $operation; then
      return 0
    fi

    log "⚠️ Attempt $attempt of $MAX_RETRIES for $description failed. Retrying in ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
    ((attempt++))
  done

  log "❌ All attempts failed for $description"
  return 1
}

setup_volumes() {
  local username=$1
  local volumes=(
    "mcp-data"
    "ai-models"
    "sourcegraph-data"
    "powershell-modules"
  )

  log "Setting up volumes for $username"
  for vol in "${volumes[@]}"; do
    podman volume create "${username}-${vol}" || log "Warning: Volume ${username}-${vol} may already exist"
  done
}

pull_containers() {
  local group=$1
  local containers=$2

  log "Pulling containers for group: $group"

  for container in $containers; do
    if [[ "$group" == "mcp" && "$container" != *"/"* ]]; then
      container="mcp/$container"
    fi

    log "Pulling: $container"
    if retry_operation "podman pull $container &>> $LOG_FILE" "pulling $container"; then
      if retry_operation "check_container_health $container" "health check for $container"; then
        log "✅ Successfully pulled and verified: $container"
      else
        log "⚠️ Container pulled but failed health check: $container"
      fi
    else
      log "❌ Failed to pull: $container after $MAX_RETRIES attempts"
    fi
  done
}

configure_vscode() {
  local username=$1
  local home="/home/$username"
  local settings_dir="$home/.config/Code/User"

  mkdir -p "$settings_dir"
  cat > "$settings_dir/settings.json" <<EOF
{
  "remote.containers.defaultExtensions": [
    "ms-vscode.cpptools",
    "ms-python.python",
    "golang.go",
    "ms-vscode.powershell"
  ],
  "dev.containers.dockerPath": "podman",
  "dev.containers.environment": {
    "DOCKER_HOST": "unix:///run/user/1000/podman/podman.sock",
    "POWERSHELL_TELEMETRY_OPTOUT": "1",
    "POWERSHELL_UPDATECHECK": "Off"
  },
  "terminal.integrated.defaultProfile.linux": "pwsh",
  "terminal.integrated.profiles.linux": {
    "pwsh": {
      "path": "/usr/bin/pwsh",
      "icon": "terminal-powershell"
    }
  }
}
EOF
}

setup_mcp_config() {
  local username=$1
  local home="/home/$username"
  local mcp_dir="$home/.config/mcp"

  mkdir -p "$mcp_dir"
  cat > "$mcp_dir/config.yaml" <<EOF
version: '1'
storage:
  type: "podman"
  settings:
    socket: "unix:///run/user/1000/podman/podman.sock"

volumes:
  data: "${username}-mcp-data"
  models: "${username}-ai-models"
  powershell: "${username}-powershell-modules"

resource_limits:
  memory: "${MAX_MEMORY:-8Gi}"
  cpu: "${MAX_CPU:-4}"

services:
  enabled:
$(for service in "${MCP_ENABLED_SERVICES[@]}"; do echo "    - $service"; done)
EOF
}

install_podman_compose() {
  local username=$1
  log "Installing podman-compose for $username"

  sudo -u "$username" python3 -m pip install --user podman-compose
}

# === Main Logic ===
main() {
  local username=$1

  log "Starting container setup for user: $username"

  # Create necessary directories
  mkdir -p "$(dirname "$LOG_FILE")"

  # Setup volumes
  setup_volumes "$username"

  # Install podman-compose
  install_podman_compose "$username"

  # Pull container images by group
  for group in "${!CONTAINER_GROUPS[@]}"; do
    log "Processing $group containers..."
    pull_containers "$group" "${CONTAINER_GROUPS[$group]}"
  done

  # Configure VS Code integration
  log "Configuring VS Code integration"
  configure_vscode "$username"

  # Setup MCP configuration
  log "Setting up MCP configuration"
  setup_mcp_config "$username"

  log "Container setup completed for $username"
}

# Allow script to be sourced without executing main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <username>"
    exit 1
  fi
  main "$1"
fi
