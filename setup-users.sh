#!/bin/bash
set -euo pipefail

# Load common functions and configuration
source "/tmp/config.sh"
source "/tmp/common.sh"

# Setup logging
setup_logging
trap 'handle_error ${LINENO}' ERR

# === User Creation ===
create_user() {
  local username=$1
  log "👤 Creating user: $username"

  # Check if user already exists
  if user_exists "$username"; then
    log "User $username already exists"
  else
    # Create user with secure defaults
    useradd -m -s /bin/bash -G wheel "$username"

    # Set a default password that must be changed on first login
    echo "${username}:${DEFAULT_PASSWORD}" | chpasswd
    passwd -e "$username"
    log "Created user $username with password expiration enabled"
  fi

  # Setup certificate directory
  mkdir -p "/home/$username/certs"
  cp "$ZSCALER_HOME_CERT" "/home/$username/certs/"
  chown -R "$username:$username" "/home/$username/certs"
  chmod 700 "/home/$username/certs"
}

# === Container Configuration ===
create_containers_config() {
  local username=$1
  local home="/home/$username"
  local conf_dir="$home/.config/containers"

  log "⚙️ Setting up containers config for $username"
  mkdir -p "$conf_dir"

  # Create containers.conf with secure defaults
  cat > "$conf_dir/containers.conf" <<CONF
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

  # Create registries.conf with secure defaults
  cat > "$conf_dir/registries.conf" <<CONF2
unqualified-search-registries = ["docker.io"]
short-name-mode = "permissive"

[registries.search]
registries = ["docker.io", "quay.io", "registry.fedoraproject.org", "mcr.microsoft.com"]

[registries.insecure]
registries = []

[registries.block]
registries = []
CONF2

  # Set proper permissions
  chown -R "$username:$username" "$conf_dir"
  chmod 700 "$conf_dir"
  chmod 600 "$conf_dir"/*.conf
}

# === Shell Trust Configuration ===
apply_shell_trust() {
  local username=$1
  local home="/home/$username"
  local bashrc="$home/.bashrc"

  log "🌐 Configuring shell trust for $username"

  # Backup existing bashrc if it exists
  if [[ -f "$bashrc" ]]; then
    cp "$bashrc" "${bashrc}.bak.$(date +%Y%m%d)"
  fi

  # Add environment variables for TLS trust
  cat <<EOF | tee -a "$bashrc" > /dev/null
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

  # Set proper permissions
  chown "$username:$username" "$bashrc"
  chmod 644 "$bashrc"
}

# === Node.js and Yarn Setup ===
setup_node_yarn() {
  local username=$1
  local home="/home/$username"
  local nvm_dir="$home/.nvm"

  log "🟢 Installing Node & Yarn for $username"

  # Check if already installed
  if [[ -d "$nvm_dir" ]] && sudo -u "$username" bash -c "source $nvm_dir/nvm.sh && command -v node && command -v yarn" &>/dev/null; then
    log "Node.js and Yarn already installed for $username"
    return 0
  fi

  # Install with retry and fallback
  if ! retry_operation "sudo -u '$username' bash -c '
    export NVM_DIR=\"$nvm_dir\"
    mkdir -p \$NVM_DIR
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    source \$NVM_DIR/nvm.sh
    nvm install --lts
    nvm use --lts
    nvm alias default \"lts/*\"
    corepack enable
    corepack prepare yarn@1.22.19 --activate
  '" "installing Node.js and Yarn"; then
    log "⚠️ Error installing Node/Yarn. Retrying with system Node..."
    dnf install -y nodejs npm
    npm install -g yarn@1.22.19
  fi
}

# === PowerShell Setup ===
setup_powershell() {
  local username=$1
  log "💻 Setting up PowerShell for $username"

  # Install PowerShell if not present
  if ! command_exists pwsh; then
    log "Installing PowerShell..."
    retry_operation "dnf install -y powershell" "installing PowerShell"
  fi

  # Create PowerShell profile directory
  local profile_dir="/home/$username/.config/powershell"
  mkdir -p "$profile_dir"

  # Create PowerShell profile
  cat <<EOF > "$profile_dir/Microsoft.PowerShell_profile.ps1"
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

  # Set proper permissions
  chown -R "$username:$username" "$profile_dir"
  chmod 700 "$profile_dir"
  chmod 600 "$profile_dir/Microsoft.PowerShell_profile.ps1"
}

# === Podman Socket Setup ===
setup_podman_socket() {
  local username=$1
  log "🔌 Setting up Podman socket for $username"

  # Create systemd user directories
  local systemd_dir="/home/$username/.config/systemd/user"
  local socket_dir="$systemd_dir/podman.socket.d"
  mkdir -p "$socket_dir"

  # Create podman socket service override
  cat <<EOF > "$socket_dir/override.conf"
[Socket]
SocketMode=0660
SocketUser=$username
ListenStream=%t/podman/podman.sock
EOF

  # Set proper permissions
  chown -R "$username:$username" "$systemd_dir"
  chmod 700 "$systemd_dir"
  chmod 600 "$socket_dir/override.conf"

  # Enable and start the socket
  local uid=$(id -u "$username")
  XDG_RUNTIME_DIR="/run/user/$uid" sudo -u "$username" systemctl --user daemon-reload
  XDG_RUNTIME_DIR="/run/user/$uid" sudo -u "$username" systemctl --user enable --now podman.socket

  # Verify socket is running
  if ! XDG_RUNTIME_DIR="/run/user/$uid" sudo -u "$username" systemctl --user is-active podman.socket; then
    log "⚠️ Warning: podman.socket not active for $username"
  fi

  # Enable user linger for systemd services to persist
  loginctl enable-linger "$username"
}

# === Management Tools Installation ===
install_management_tools() {
  local username=$1
  log "🛠️ Installing management tools for $username"

  # Create bin directories
  mkdir -p /usr/local/bin
  mkdir -p "/home/$username/.local/bin"

  # Copy management scripts
  for tool in cleanup.sh user-manager.sh version-tracker.sh podman-diagnostics.sh; do
    if [[ -f "/tmp/$tool" ]]; then
      cp "/tmp/$tool" "/usr/local/bin/podman-${tool%.sh}"
      chmod +x "/usr/local/bin/podman-${tool%.sh}"

      # Make tools available to user
      cp "/usr/local/bin/podman-${tool%.sh}" "/home/$username/.local/bin/"
    else
      log "⚠️ Tool script /tmp/$tool not found"
    fi
  done

  # Set proper permissions
  chown -R "$username:$username" "/home/$username/.local/bin"
  chmod 755 "/home/$username/.local/bin/podman-"*

  # Setup initial diagnostics for first user only
  if [[ "$username" == "${USERS[0]}" ]]; then
    log "Setting up health monitoring for $username"
    sudo -u "$username" bash -c "/home/$username/.local/bin/podman-diagnostics monitor 300 &>> $LOG_DIR/health-monitor.log &"
  fi

  # Setup automatic update checks (weekly)
  local cron_job="0 0 * * 0 /home/$username/.local/bin/podman-version-tracker check-updates"
  (sudo -u "$username" crontab -l 2>/dev/null | grep -v "podman-version-tracker"; echo "$cron_job") | sudo -u "$username" crontab -
}

# === Certificate Installation ===
install_cert_to_ca() {
  log "🔒 Installing root certificate to system CA store"

  # Check if cert already installed
  if [[ -f "$CERT_VM_PATH" ]]; then
    log "Certificate already installed at $CERT_VM_PATH"
  else
    # Copy cert to CA store
    mkdir -p "$(dirname "$CERT_VM_PATH")"
    cp "$ZSCALER_HOME_CERT" "$CERT_VM_PATH"
    chmod 644 "$CERT_VM_PATH"

    # Update CA certificates
    if command_exists update-ca-certificates; then
      update-ca-certificates
    elif command_exists update-ca-trust; then
      update-ca-trust
    else
      log "⚠️ Could not update CA certificates - command not found"
    fi
  fi
}

# === Security Hardening ===
harden_user_environment() {
  local username=$1
  local home="/home/$username"

  log "🔒 Applying security hardening for $username"

  # Set secure umask
  echo "umask 027" >> "$home/.bashrc"

  # Configure container seccomp profile
  local seccomp_dir="$home/.config/containers/seccomp"
  mkdir -p "$seccomp_dir"
  cat > "$seccomp_dir/default.json" <<EOF
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    // ... minimal required syscalls ...
  ]
}
EOF

  # Set secure limits
  cat >> "/etc/security/limits.d/${username}.conf" <<EOF
$username soft nproc 2048
$username hard nproc 4096
$username soft nofile 4096
$username hard nofile 8192
EOF

  # Set proper permissions
  chown -R "$username:$username" "$seccomp_dir"
  chmod 700 "$seccomp_dir"
}

# === Main Execution ===
main() {
  log "Starting user provisioning process"

  # Install certificate to system CA store
  install_cert_to_ca

  # Process each user
  for user in "${USERS[@]}"; do
    log "Processing user: $user"

    create_user "$user"
    create_containers_config "$user"
    apply_shell_trust "$user"
    setup_node_yarn "$user"
    setup_powershell "$user"
    setup_podman_socket "$user"
    install_management_tools "$user"

    # Track versions before container setup
    sudo -u "$user" "/home/$user/.local/bin/podman-version-tracker" track

    # Run container setup
    if [[ -f "/tmp/container-setup.sh" ]]; then
      log "🐋 Setting up containers for $user..."
      sudo -u "$user" bash "/tmp/container-setup.sh" "$user"
    else
      log "⚠️ Container setup script not found at /tmp/container-setup.sh"
    fi
  done

  log "✅ All users created and fully provisioned!"
}

main
