#!/bin/bash
set -euo pipefail

# Load common functions and configuration
source "/tmp/config.sh"
source "/tmp/common.sh"

# Setup logging
setup_logging
trap 'handle_error ${LINENO}' ERR

VOLUME_ROOT="/var/lib/containers/storage/volumes"

# === Container Health Check ===
check_container_health() {
  local container=$1
  log "Checking health of container: $container"

  # Check if container exists
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

# === Volume Setup ===
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
    local volume_name="${username}-${vol}"

    # Check if volume exists
    if podman volume inspect "$volume_name" &>/dev/null; then
      log "Volume $volume_name already exists"
    else
      sudo podman volume create "$volume_name"
      sudo chown -R "$username:$username" "$VOLUME_ROOT/$volume_name"
      log "Created volume: $volume_name"
    fi
  done
}

# === Container Pulling ===
pull_containers() {
  local group=$1
  local containers=$2

  log "Pulling containers for group: $group"

  for container in $containers; do
    # Prefix MCP containers if needed
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

# === VS Code Configuration ===
configure_vscode() {
  local username=$1
  local home="/home/$username"
  local settings_dir="$home/.config/Code/User"

  log "Configuring VS Code for $username"
  mkdir -p "$settings_dir"

  # Create settings.json with proper permissions
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

  # Set proper permissions
  chown -R "$username:$username" "$settings_dir"
  chmod 600 "$settings_dir/settings.json"
}

# === MCP Configuration ===
setup_mcp_config() {
  local username=$1
  local home="/home/$username"
  local mcp_dir="$home/.config/mcp"

  log "Setting up MCP configuration for $username"
  mkdir -p "$mcp_dir"

  # Create config.yaml with proper permissions
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

  # Set proper permissions
  chown -R "$username:$username" "$mcp_dir"
  chmod 600 "$mcp_dir/config.yaml"
}

# === Podman Compose Installation ===
install_podman_compose() {
  local username=$1
  log "Installing podman-compose for $username"

  # Check if already installed
  if sudo -u "$username" python3 -m pip list | grep -q "podman-compose"; then
    log "podman-compose already installed for $username"
    return 0
  fi

  # Install with retry
  retry_operation "sudo -u '$username' python3 -m pip install --user podman-compose" "installing podman-compose"
}

# === Network Setup ===
setup_networks() {
  local username=$1
  log "Setting up container networks for $username"

  local networks=(
    "${username}-backend"
    "${username}-frontend"
  )

  for net in "${networks[@]}"; do
    if ! podman network exists "$net" 2>/dev/null; then
      podman network create "$net"
      log "Created network: $net"
    fi
  done
}

check_dependencies() {
  local container=$1
  local deps=$(podman inspect "$container" --format '{{.Config.Labels.dependencies}}' 2>/dev/null)

  if [[ -n "$deps" ]]; then
    log "Checking dependencies for $container: $deps"
    for dep in ${deps//,/ }; do
      if ! podman image exists "$dep"; then
        log "Missing dependency: $dep for $container"
        pull_containers "dependency" "$dep"
      fi
    done
  fi
}

# === Main Logic ===
main() {
  if [[ $# -ne 1 ]]; then
    log "Usage: $0 <username>"
    exit 1
  fi

  local username=$1

  # Verify user exists
  if ! user_exists "$username"; then
    log "❌ User $username does not exist"
    exit 1
  fi

  log "Starting container setup for user: $username"

  # Setup volumes
  setup_volumes "$username"

  # Install podman-compose
  install_podman_compose "$username"

  # Setup networks
  setup_networks "$username"

  # Pull container images by group
  for group in "${!CONTAINER_GROUPS[@]}"; do
    log "Processing $group containers..."
    pull_containers "$group" "${CONTAINER_GROUPS[$group]}"
    
    # Check dependencies for each container
    for container in ${CONTAINER_GROUPS[$group]}; do
      check_dependencies "$container"
    done
  done

  # Configure VS Code integration
  configure_vscode "$username"

  # Setup MCP configuration
  setup_mcp_config "$username"

  log "Container setup completed for $username"
}

# Allow script to be sourced without executing main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
