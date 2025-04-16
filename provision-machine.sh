#!/bin/bash
set -euo pipefail

# === CONFIG ===
PODMAN_VM="podman-machine-wsl"
TMP_SCRIPT="/tmp/setup-users.sh"
CONTAINER_SETUP_SCRIPT="/tmp/container-setup.sh"
LOCAL_CERT="$HOME/certs/ZscalerRootCertificate-2048-SHA256.crt"
REMOTE_CERT_NAME="zscaler.crt"
MIN_MEMORY_GB=8
MIN_PODMAN_VERSION="4.0.0"

# === SYSTEM REQUIREMENTS ===
check_requirements() {
  echo "🔍 Checking system requirements..."

  # Check WSL2
  if ! wsl.exe -l -v | grep -q "2"; then
    echo "❌ WSL2 is required but not enabled."
    exit 1
  fi

  # Check Podman version
  local version=$(podman version --format '{{.Version}}')
  if [[ "$(printf '%s\n' "$MIN_PODMAN_VERSION" "$version" | sort -V | head -n1)" == "$version" ]]; then
    echo "❌ Podman version $MIN_PODMAN_VERSION or higher is required. Found: $version"
    exit 1
  fi

  # Check available memory
  local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
  if (( mem_gb < MIN_MEMORY_GB )); then
    read -p "⚠️ Less than ${MIN_MEMORY_GB}GB RAM available. Performance may be impacted. Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
}

# === CHECKS ===
if ! podman machine list | grep -q "$PODMAN_VM"; then
  echo "❌ Podman machine '$PODMAN_VM' not found."
  exit 1
fi

if [[ ! -f "$LOCAL_CERT" ]]; then
  echo "❌ Zscaler cert not found at: $LOCAL_CERT"
  exit 1
fi

# === OPTIMIZATION ===
optimize_podman_machine() {
  # Configure registry mirrors for better performance
  podman machine ssh "$PODMAN_VM" "sudo tee /etc/containers/registries.conf" > /dev/null <<EOF
unqualified-search-registries = ["docker.io"]
short-name-mode = "permissive"

[registries.search]
registries = ${REGISTRY_MIRRORS[@]/#/\"}
registries = ${REGISTRY_MIRRORS[@]/%/\"}

[[registry]]
prefix = "docker.io"
location = "docker.io"
mirror = [
  "https://mirror.gcr.io",
  "https://registry-1.docker.io"
]

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
}

echo "📦 Sending cert and setup scripts to Podman VM..."

# === CERT COPY ===
podman machine ssh "$PODMAN_VM" "mkdir -p ~/certs"
cat "$LOCAL_CERT" | podman machine ssh "$PODMAN_VM" "cat > ~/certs/$REMOTE_CERT_NAME"

# === SCRIPT COPY ===
# Copy setup scripts to VM
cat "$(dirname "$0")/container-setup.sh" | podman machine ssh "$PODMAN_VM" "cat > $CONTAINER_SETUP_SCRIPT"
cat "$(dirname "$0")/version-tracker.sh" | podman machine ssh "$PODMAN_VM" "cat > /tmp/version-tracker.sh"
cat "$(dirname "$0")/cleanup.sh" | podman machine ssh "$PODMAN_VM" "cat > /tmp/cleanup.sh"
cat "$(dirname "$0")/user-manager.sh" | podman machine ssh "$PODMAN_VM" "cat > /tmp/user-manager.sh"

# Set execute permissions
podman machine ssh "$PODMAN_VM" "chmod +x $CONTAINER_SETUP_SCRIPT"
podman machine ssh "$PODMAN_VM" "chmod +x /tmp/version-tracker.sh"
podman machine ssh "$PODMAN_VM" "chmod +x /tmp/cleanup.sh"
podman machine ssh "$PODMAN_VM" "chmod +x /tmp/user-manager.sh"

# === EXECUTE ===
check_requirements
optimize_podman_machine
podman machine ssh "$PODMAN_VM" "chmod +x $TMP_SCRIPT && sudo bash $TMP_SCRIPT"

echo "✅ Provisioning complete!"
