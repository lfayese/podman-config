#!/bin/bash
set -euo pipefail

# Load configuration if available
if [[ -f "/tmp/config.sh" ]]; then
  source "/tmp/config.sh"
else
  # Default configuration
  USERS=("ofayese" "639016")
  CERT_VM_PATH="/etc/pki/ca-trust/source/anchors/zscaler.crt"
  ZSCALER_HOME_CERT="$HOME/certs/zscaler.crt"
  CONTAINER_SETUP_SCRIPT="/tmp/container-setup.sh"
  LOG_DIR="/var/log/podman-provision"
fi

# Setup logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-users-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

handle_error() {
  local exit_code=$?
  local line_no=$1
  log "Error on line $line_no: Command exited with status $exit_code"
  exit $exit_code
}
trap 'handle_error ${LINENO}' ERR

create_user() {
  local username=$1
  log "👤 Creating user: $username"
  if ! id "$username" &>/dev/null; then
    sudo useradd -m -s /bin/bash -G wheel "$username"
    # Set a default password that must be changed on first login
    echo "${username}:changeme" | sudo chpasswd
    sudo passwd -e "$username"
  fi

  sudo mkdir -p /home/$username/certs
  sudo cp "$ZSCALER_HOME_CERT" /home/$username/certs/
  sudo chown -R $username:$username /home/$username/certs
}

create_containers_config() {
  local username=$1
  local home="/home/$username"
  local conf_dir="$home/.config/containers"

  log "⚙️ Setting up containers config for $username"
  sudo mkdir -p "$conf_dir"
  sudo tee "$conf_dir/containers.conf" > /dev/null <<CONF
[engine]
cgroup_manager = "systemd"
events_logger = "journald"
runtime = "crun"

[network]
network_backend = "netavark"

[containers]
pids_limit = 2048
default_capabilities = [
  "CHOWN", "DAC_OVERRIDE", "FOWNER", "FSETID", "KILL", "NET_BIND_SERVICE",
  "SETFCAP", "SETGID", "SETPCAP", "SETUID", "SYS_CHROOT"
]
CONF

  sudo tee "$conf_dir/registries.conf" > /dev/null <<CONF2
unqualified-search-registries = ["docker.io"]
short-name-mode = "permissive"

[registries.search]
registries = ["docker.io", "quay.io", "registry.fedoraproject.org", "mcr.microsoft.com"]

[registries.insecure]
registries = []

[registries.block]
registries = []
CONF2

  sudo chown -R $username:$username "$conf_dir"
}

apply_shell_trust() {
  local username=$1
  local home="/home/$username"
  local bashrc="$home/.bashrc"

  log "🌐 Configuring shell trust for $username"

  # Backup existing bashrc if it exists
  if [[ -f "$bashrc" ]]; then
    sudo cp "$bashrc" "${bashrc}.bak"
  fi

  # Add environment variables for TLS trust
  cat <<EOF | sudo tee -a "$bashrc" > /dev/null
# TLS Certificate Trust
export NODE_EXTRA_CA_CERTS=$CERT_VM_PATH
export PIP_CERT=$CERT_VM_PATH
export REQUESTS_CA_BUNDLE=$CERT_VM_PATH
export SSL_CERT_FILE=$CERT_VM_PATH
export GIT_SSL_CAINFO=$CERT_VM_PATH
export CURL_CA_BUNDLE=$CERT_VM_PATH

# PowerShell Certificate Trust
export POWERSHELL_TELEMETRY_OPTOUT=1
export POWERSHELL_UPDATECHECK=Off
export PSCORE_TELEMETRY_OPTOUT=1

# Podman aliases and configuration
alias docker='podman'
alias docker-compose='podman-compose'
export DOCKER_HOST="unix:///run/user/\$(id -u)/podman/podman.sock"

# Path configuration
export PATH="\$HOME/.local/bin:\$HOME/.yarn/bin:\$PATH"
EOF

  sudo chown $username:$username "$bashrc"
}

setup_node_yarn() {
  local username=$1
  local home="/home/$username"
  local nvm_dir="$home/.nvm"

  log "🟢 Installing Node & Yarn for $username"

  if ! sudo -u "$username" bash -c "
    export NVM_DIR=\"$nvm_dir\"
    mkdir -p \$NVM_DIR
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    source \$NVM_DIR/nvm.sh
    nvm install --lts
    nvm use --lts
    nvm alias default 'lts/*'
    corepack enable
    corepack prepare yarn@1.22.19 --activate
  "; then
    log "⚠️ Error installing Node/Yarn. Retrying with system Node..."
    sudo dnf install -y nodejs npm
    sudo npm install -g yarn@1.22.19
  fi
}

setup_powershell() {
  local username=$1
  log "💻 Setting up PowerShell for $username"

  # Install PowerShell if not present
  if ! command -v pwsh &>/dev/null; then
    sudo dnf install -y powershell
  fi

  # Create PowerShell profile directory
  local profile_dir="/home/$username/.config/powershell"
  sudo mkdir -p "$profile_dir"

  # Create PowerShell profile
  cat <<EOF | sudo tee "$profile_dir/Microsoft.PowerShell_profile.ps1" > /dev/null
# Certificate trust configuration
\$env:NODE_EXTRA_CA_CERTS = "$CERT_VM_PATH"
\$env:REQUESTS_CA_BUNDLE = "$CERT_VM_PATH"
\$env:DOTNET_SSL_CERT_FILE = "$CERT_VM_PATH"
\$env:SSL_CERT_FILE = "$CERT_VM_PATH"

# Docker/Podman configuration
\$env:DOCKER_HOST = "unix:///run/user/\$((id -u))/podman/podman.sock"
Set-Alias -Name docker -Value podman
Set-Alias -Name docker-compose -Value podman-compose
EOF

  sudo chown -R $username:$username "$profile_dir"
}

setup_podman_socket() {
  local username=$1
  log "🔌 Setting up Podman socket for $username"

  # Create systemd user directories
  local systemd_dir="/home/$username/.config/systemd/user"
  local socket_dir="$systemd_dir/podman.socket.d"
  sudo mkdir -p "$socket_dir"

  # Create podman socket service override
  cat <<EOF | sudo tee "$socket_dir/override.conf" > /dev/null
[Socket]
SocketMode=0660
SocketUser=$username
ListenStream=%t/podman/podman.sock
EOF

  # Set proper permissions
  sudo chown -R $username:$username "$systemd_dir"

  # Enable and start the socket
  sudo -u "$username" XDG_RUNTIME_DIR="/run/user/$(id -u $username)" systemctl --user enable --now podman.socket

  # Enable user linger for systemd services to persist
  sudo loginctl enable-linger "$username"
}

install_management_tools() {
  local username=$1
  log "🛠️ Installing management tools for $username"

  # Create bin directories
  sudo mkdir -p /usr/local/bin
  sudo mkdir -p "/home/$username/.local/bin"

  # Copy management scripts
  sudo cp /tmp/cleanup.sh /usr/local/bin/podman-cleanup
  sudo cp /tmp/user-manager.sh /usr/local/bin/podman-user-manager
  sudo cp /tmp/version-tracker.sh /usr/local/bin/podman-version-tracker
  sudo cp /tmp/podman-diagnostics.sh /usr/local/bin/podman-diagnostics

  # Set permissions
  sudo chmod +x /usr/local/bin/podman-*

  # Make tools available to user
  sudo cp /usr/local/bin/podman-* "/home/$username/.local/bin/"
  sudo chown -R "$username:$username" "/home/$username/.local/bin"

  # Setup initial diagnostics
  if [[ "$username" == "${USERS[0]}" ]]; then
    # Only set up monitoring for the first user to avoid duplicates
    sudo -u "$username" bash -c "podman-diagnostics monitor 300 &>> /var/log/podman-provision/health-monitor.log &"
  fi

  # Setup automatic update checks (weekly)
  (crontab -l 2>/dev/null; echo "0 0 * * 0 /home/$username/.local/bin/podman-version-tracker check-updates") | crontab -
}

main() {
  install_cert_to_ca
  for user in "${USERS[@]}"; do
    create_user "$user"
    create_containers_config "$user"
    apply_shell_trust "$user"
    setup_node_yarn "$user"
    setup_powershell "$user"
    setup_podman_socket "$user"
    install_management_tools "$user"

    # Track versions before container setup
    sudo -u "$user" podman-version-tracker track

    # Run container setup
    if [[ -f "$CONTAINER_SETUP_SCRIPT" ]]; then
      log "🐋 Setting up containers for $user..."
      sudo -u "$user" bash "$CONTAINER_SETUP_SCRIPT" "$user"
    fi
  done

  log "✅ All users created and fully provisioned!"
}

main
