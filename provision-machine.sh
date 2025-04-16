#!/bin/bash
set -euo pipefail

# Load common functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/common.sh"

# Setup logging
setup_logging
trap 'handle_error ${LINENO}' ERR

# === SYSTEM REQUIREMENTS ===
check_requirements() {
  log "🔍 Checking system requirements..."

  # Check WSL2
  if ! wsl.exe -l -v | grep -q "2"; then
    log "❌ WSL2 is required but not enabled."
    exit 1
  fi

  # Verify PowerShell is available
  if ! command_exists powershell.exe; then
    log "❌ PowerShell is required but not found."
    exit 1
  fi

  # Check Podman version
  if ! command_exists podman; then
    log "❌ Podman is required but not found."
    exit 1
  fi

  local version=$(podman version --format '{{.Version}}')
  if [[ "$(printf '%s\n' "$MIN_PODMAN_VERSION" "$version" | sort -V | head -n1)" == "$version" ]]; then
    log "❌ Podman version $MIN_PODMAN_VERSION or higher is required. Found: $version"
    exit 1
  fi

  # Check available memory using PowerShell
  local mem_gb
  mem_gb=$(powershell.exe -NoProfile -Command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)" || echo 0)
  if ! [[ "$mem_gb" =~ ^[0-9]+$ ]]; then
    log "⚠️ Could not determine system memory. Continuing anyway..."
  elif (( mem_gb < MIN_MEMORY_GB )); then
    read -p "⚠️ Less than ${MIN_MEMORY_GB}GB RAM available (${mem_gb}GB detected). Performance may be impacted. Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi

  # Check if Podman machine exists
  if ! podman machine list | grep -q "$PODMAN_VM"; then
    log "❌ Podman machine '$PODMAN_VM' not found."
    exit 1
  fi

  # Check if certificate exists
  if [[ ! -f "$LOCAL_CERT" ]]; then
    log "❌ Zscaler cert not found at: $LOCAL_CERT"
    exit 1
  fi
}

# === OPTIMIZATION ===
optimize_podman_machine() {
  log "⚙️ Optimizing Podman machine configuration..."

  # Configure registry settings
  podman machine ssh "$PODMAN_VM" "sudo tee /etc/containers/registries.conf" > /dev/null <<EOF
unqualified-search-registries = ["docker.io"]
short-name-mode = "permissive"

[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry]]
prefix = "mcr.microsoft.com"
location = "mcr.microsoft.com"

[engine]
parallel_pull = true
max_parallel_pulls = 4
max_concurrent_downloads = 3
EOF

  # Optimize podman settings
  podman machine ssh "$PODMAN_VM" "sudo tee -a /etc/containers/containers.conf" > /dev/null <<EOF
[engine]
cgroup_manager = "systemd"
events_logger = "journald"
runtime = "crun"
network_backend = "netavark"
parallel_pull = true

[engine.worker_opts]
max_parallel_downloads = 4
max_concurrent_uploads = 3

[engine.cgroup_manager]
memory_limit = "${MAX_MEMORY}"
cpu_quota = "${MAX_CPU}0000"
EOF

  log "✅ Podman machine optimized"
}

# === COPY FILES ===
copy_files_to_vm() {
  log "📦 Sending cert and setup scripts to Podman VM..."

  # Create directories
  podman machine ssh "$PODMAN_VM" "mkdir -p ~/certs"

  # Copy certificate
  cat "$LOCAL_CERT" | podman machine ssh "$PODMAN_VM" "cat > ~/certs/$REMOTE_CERT_NAME"

  # Copy configuration
  cat "${SCRIPT_DIR}/config.sh" | podman machine ssh "$PODMAN_VM" "cat > /tmp/config.sh"
  cat "${SCRIPT_DIR}/common.sh" | podman machine ssh "$PODMAN_VM" "cat > /tmp/common.sh"

  # Copy scripts
  local scripts=(
    "container-setup.sh"
    "setup-users.sh"
    "version-tracker.sh"
    "cleanup.sh"
    "user-manager.sh"
    "podman-diagnostics.sh"
  )

  for script in "${scripts[@]}"; do
    if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
      cat "${SCRIPT_DIR}/${script}" | podman machine ssh "$PODMAN_VM" "cat > /tmp/${script}"
      podman machine ssh "$PODMAN_VM" "chmod +x /tmp/${script}"
    else
      log "⚠️ Script ${script} not found in ${SCRIPT_DIR}"
    fi
  done

  log "✅ Files copied to VM"
}

# === MAIN EXECUTION ===
main() {
  # Run checks
  check_requirements

  # Optimize Podman machine
  optimize_podman_machine

  # Copy files to VM
  copy_files_to_vm

  # Execute setup-users script on VM
  log "👥 Setting up users and containers..."
  podman machine ssh "$PODMAN_VM" "sudo bash /tmp/setup-users.sh"

  log "✅ Provisioning complete!"
}

main
