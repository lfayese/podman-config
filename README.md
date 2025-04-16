# 🐳 Podman VM Provisioning: Multi-User Dev Environment

This repository contains scripts to provision a Podman-managed VM (using `podman-machine-wsl`) with secure TLS trust, developer toolchains, Node.js environments, and container-based development tools for users.

---

## 📦 Files

- **provision-machine.sh**  
  Host-side script. Verifies environment, optimizes VM settings, injects TLS cert, and executes the provisioning scripts inside the Podman VM.

- **setup-users.sh**  
  VM-side script. Sets up users, installs the Zscaler TLS cert, configures dev tools, and bootstraps development environments.

- **container-setup.sh**  
  Manages container images and configurations for MCP, AI models, and Sourcegraph tooling.

---

## ✅ Prerequisites

- WSL2 enabled
- Podman 4.0.0+ installed with WSL support
- Podman machine already created: `podman-machine-wsl`
- Minimum 8GB RAM recommended
- Zscaler cert available locally at:  
  `~/certs/ZscalerRootCertificate-2048-SHA256.crt`

---

## 🚀 How to Use

1. Place the Zscaler certificate at:

   ```bash
   mkdir -p ~/certs
   cp ZscalerRootCertificate-2048-SHA256.crt ~/certs/
   ```

2. (Optional) Customize the configuration:

   ```bash
   cp config.sh.template /tmp/config.sh
   # Edit /tmp/config.sh to customize settings
   ```

3. Run the provisioning script:

   ```bash
   chmod +x provision-machine.sh
   ./provision-machine.sh
   ```

4. Done! Users are created inside the Podman VM with:
   - Trusted TLS cert
   - Containers config
   - Node.js (via NVM), Yarn, Python
   - VS Code + MCP packages installed
   - Pre-configured container environments:
     - MCP tools (filesystem, git, memory, etc.)
     - AI models (Llama, Mistral)
     - Sourcegraph tooling

---

## 🛠 Customization

To provision more users:

- Edit the `USERS=(...)` array in `setup-users.sh`
- Re-run `provision-machine.sh`

To modify container configurations:

- Edit `~/.config/mcp/config.yaml` in user's home directory
- Adjust resource limits in container-setup.sh

---

## 🔧 Management Tools

The environment comes with several management tools:

### podman-user-manager

Manage users and their resource quotas:

```bash
# Show user status
podman-user-manager status USERNAME

# Set resource quotas
podman-user-manager quota USERNAME cpu 200     # CPU limit
podman-user-manager quota USERNAME memory 4Gi  # Memory limit
podman-user-manager quota USERNAME disk 20Gi   # Disk quota

# Reset user environment
podman-user-manager reset USERNAME
```

### podman-version-tracker

Track and manage container versions:

```bash
# Check for updates
podman-version-tracker check-updates

# View current versions
podman-version-tracker print

# Scan container security
podman-version-tracker scan CONTAINER_NAME
```

### podman-diagnostics

System monitoring and diagnostics:

```bash
# Collect system diagnostics
podman-diagnostics collect

# Start health monitoring
podman-diagnostics monitor 300  # Check every 5 minutes

# Clean up old reports
podman-diagnostics cleanup 7    # Remove reports older than 7 days
```

## 📊 Monitoring & Diagnostics

### Health Monitoring

- Automatic health checks run every 5 minutes
- Resource usage monitoring (CPU, memory, disk)
- Container status monitoring
- Automatic alert generation for issues

### Resource Management

- Per-user resource quotas
- Automatic quota enforcement
- Resource usage tracking
- Performance optimization via parallel pulls

### Security Scanning

- Container security scanning
- Privilege escalation detection
- Environment variable auditing
- Port exposure monitoring

## 🔄 Maintenance

### Updates

- Weekly automatic update checks
- Update notifications for containers
- Version tracking for reproducibility
- Registry mirror optimization

### Cleanup

```bash
# Clean up specific user's resources
./cleanup.sh --user USERNAME

# Remove home directory when cleaning up user
./cleanup.sh --user USERNAME --remove-home

# Full system cleanup including all configured users
./cleanup.sh --all

# Preview cleanup actions (dry run)
./cleanup.sh --dry-run --user USERNAME

# Show help
./cleanup.sh --help
```

The cleanup script will:
- Stop and remove user containers
- Remove user volumes
- Cleanup systemd services
- Optionally remove home directory
- Remove user from system
- When using --all, also performs system-wide cleanup

## 💡 Troubleshooting

### Common Issues

1. Container Pull Failures
   - Check network connectivity
   - Verify registry mirrors in /etc/containers/registries.conf
   - Review logs in /var/log/podman-provision/

2. Resource Limits
   - Check quota status with podman-user-manager
   - Review diagnostic reports
   - Adjust limits in container-setup.sh

3. Performance Issues
   - Check parallel pull configuration
   - Verify registry mirror settings
   - Monitor resource usage with podman-diagnostics

### Diagnostic Tools

Run comprehensive diagnostics:

```bash
podman-diagnostics collect
```

View real-time monitoring:

```bash
podman-diagnostics monitor
```

### Logs

- Main logs: /var/log/podman-provision/
- Diagnostic reports: /var/log/podman-provision/reports/
- Health monitoring: /var/log/podman-provision/health-monitor.log

## 🔐 Notes

- The TLS certificate is injected into the VM at `/etc/pki/ca-trust/source/anchors/zscaler.crt`
- Comprehensive shell trust configuration:
  - `NODE_EXTRA_CA_CERTS` for Node.js
  - `PIP_CERT` for Python packages
  - `REQUESTS_CA_BUNDLE` for Python requests
  - `SSL_CERT_FILE` for OpenSSL
  - `GIT_SSL_CAINFO` for Git operations
  - `CURL_CA_BUNDLE` for curl commands
- All yarn tooling is installed **globally** in each user's environment
- Container volumes are persisted at `/var/lib/containers/storage/volumes`
- VS Code is configured to use Podman as the container runtime
- Default user password is 'changeme' (must be changed on first login)
- Detailed logging at `/var/log/podman-provision/`

## 🖥️ VS Code Integration

The environment comes pre-configured for VS Code with:

- Container support via Podman
- Default extensions for development
- MCP tools integration
- Shared volume mounts for persistence
- Resource limits for optimal performance

---

## 🤝 Credits

Built with ❤️ using Podman, NVM, Yarn, and container technologies by your infrastructure automation team.
