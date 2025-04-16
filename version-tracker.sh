#!/bin/bash
set -euo pipefail

VERSION_FILE="/etc/podman-provision/version.json"
CONTAINER_VERSIONS_FILE="/etc/podman-provision/container-versions.json"

track_versions() {
  local username=$1
  local timestamp=$(date +"%Y-%m-%d-%H:%M:%S")

  mkdir -p "$(dirname "$VERSION_FILE")"

  # Create main version file
  cat > "$VERSION_FILE" <<EOF
{
  "timestamp": "$timestamp",
  "podman_version": "$(podman version --format '{{.Version}}')",
  "kernel_version": "$(uname -r)",
  "distro": "$(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')",
  "nvm_version": "$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep tag_name | cut -d'\"' -f4)",
  "yarn_version": "1.22.19"
}
EOF

  # Track container versions
  echo "{" > "$CONTAINER_VERSIONS_FILE"
  echo "  \"timestamp\": \"$timestamp\"," >> "$CONTAINER_VERSIONS_FILE"
  echo "  \"containers\": {" >> "$CONTAINER_VERSIONS_FILE"

  first=true
  for group in "${!CONTAINER_GROUPS[@]}"; do
    for container in ${CONTAINER_GROUPS[$group]}; do
      if [[ "$group" == "mcp" && "$container" != *"/"* ]]; then
        container="mcp/$container"
      fi

      version=$(podman image inspect "$container" --format '{{.Id}}' 2>/dev/null || echo "not-found")

      if ! $first; then
        echo "," >> "$CONTAINER_VERSIONS_FILE"
      fi
      first=false

      echo "    \"$container\": \"$version\"" >> "$CONTAINER_VERSIONS_FILE"
    done
  done

  echo "  }" >> "$CONTAINER_VERSIONS_FILE"
  echo "}" >> "$CONTAINER_VERSIONS_FILE"
}

print_versions() {
  if [[ -f "$VERSION_FILE" ]]; then
    echo "System Versions:"
    cat "$VERSION_FILE"
    echo
  fi

  if [[ -f "$CONTAINER_VERSIONS_FILE" ]]; then
    echo "Container Versions:"
    cat "$CONTAINER_VERSIONS_FILE"
  fi
}

check_updates() {
  local username=$1
  local updates_found=false

  log "Checking for container updates..."

  for group in "${!CONTAINER_GROUPS[@]}"; do
    for container in ${CONTAINER_GROUPS[$group]}; do
      if [[ "$group" == "mcp" && "$container" != *"/"* ]]; then
        container="mcp/$container"
      fi

      # Get current and latest versions
      local current=$(podman image inspect "$container" --format '{{.Id}}' 2>/dev/null || echo "not-found")
      podman pull "$container" &>/dev/null
      local latest=$(podman image inspect "$container" --format '{{.Id}}' 2>/dev/null || echo "not-found")

      if [[ "$current" != "$latest" && "$latest" != "not-found" ]]; then
        echo "📦 Update available for $container"
        updates_found=true
      fi
    done
  done

  if ! $updates_found; then
    echo "✅ All containers are up to date"
  fi
}

scan_security() {
  local container=$1
  local scan_dir="/etc/podman-provision/security-scans"
  mkdir -p "$scan_dir"

  echo "🔍 Scanning $container for security issues..."

  # Basic security checks
  podman image inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' > "$scan_dir/${container//\//_}_env.txt"
  podman image inspect "$container" --format '{{range $k,$v := .Config.ExposedPorts}}{{$k}}{{println ""}}{{end}}' > "$scan_dir/${container//\//_}_ports.txt"

  # Check for running as root
  if podman inspect "$container" --format '{{.Config.User}}' | grep -q '^0\|^root'; then
    echo "⚠️ Warning: Container $container runs as root"
  fi

  # Check for privileged mode
  if podman inspect "$container" --format '{{.HostConfig.Privileged}}' | grep -q "true"; then
    echo "⚠️ Warning: Container $container runs in privileged mode"
  fi

  echo "✅ Security scan complete for $container"
}

# Add to main logic
main() {
  local command=$1
  shift

  case "$command" in
    track)
      track_versions "$@"
      ;;
    print)
      print_versions
      ;;
    check-updates)
      check_updates "$@"
      ;;
    scan)
      for container in "$@"; do
        scan_security "$container"
      done
      ;;
    *)
      echo "Usage: $0 {track|print|check-updates|scan} [arguments]"
      exit 1
      ;;
  esac
}
