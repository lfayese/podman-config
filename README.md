# 🐳 Podman VM Provisioning: Multi-User Dev Environment

This repository contains scripts to provision a Podman-managed VM (using `podman-machine-wsl`) with secure TLS trust, developer toolchains, Node.js environments, and container-based development tools for users.

---

## 📦 Files

- **config.sh**  
  Central configuration file containing all customizable settings for the provisioning process.

- **common.sh**  
  Shared utility functions for logging, error handling, and common operations.

- **provision-machine.sh**  
  Host-side script. Verifies environment, optimizes VM settings, injects TLS cert, and executes the provisioning scripts inside the Podman VM.

- **setup-users.sh**  
  VM-side script. Sets up users, installs the Zscaler TLS cert, configures dev tools, and bootstraps development environments.

- **container-setup.sh**  
  Manages container images and configurations for MCP, AI models, and Sourcegraph tooling.

- **version-tracker.sh**  
  Tracks container versions and checks for updates.

- **user-manager.sh**  
  Manages user accounts and resource quotas.

- **podman-diagnostics.sh**  
  Provides system monitoring and diagnostic tools.

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

2. Customize the configuration (optional):

   ```bash
   cp config.sh.template config.sh
   # Edit config.sh to customize settings
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

### User Configuration

Edit the `USERS` array in `config.sh`:

```bash
# Define users to be created
USERS=("user1" "user2" "user3")
```

### Resource Limits

Adjust resource limits in `config.sh`:

```bash
# Resource limits
MAX_MEMORY="8Gi"
MAX_CPU="4"
```

### Container Configuration

Modify container groups in `config.sh`:

```bash
# Container groups
declare -A CONTAINER_GROUPS
CONTAINER_GROUPS=(
  ["mcp"]="core-api code-intelligence ai-assistant"
  ["base"]="mcr.microsoft.com/powershell:latest docker.io/library/python:3.9-slim"
  ["custom"]="your-custom-image:latest"
)
```

---

## 🔧 Management Tools

The environment comes with several improved management tools:

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

# List all managed users
podman-user-manager list
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

# Track current versions
podman-version-tracker track

# Compare with previous versions
podman-version-tracker diff
```

### podman-diagnostics

Enhanced system monitoring and diagnostics:

```bash
# Collect system diagnostics
podman-diagnostics collect

# Start health monitoring
podman-diagnostics monitor 300  # Check every 5 minutes

# Clean up old reports
podman-diagnostics cleanup 7    # Remove reports older than 7 days

# Generate performance report
podman-diagnostics report

# Check system health
podman-diagnostics health
```

## 📊 Monitoring & Diagnostics

### Enhanced Health Monitoring

- Automatic health checks run every 5 minutes
- Resource usage monitoring (CPU, memory, disk)
- Container status monitoring with detailed health checks
- Automatic alert generation for issues
- Historical performance tracking

### Improved Resource Management

- Per-user resource quotas with enforcement
- Dynamic resource allocation
- Resource usage tracking with historical data
- Performance optimization via parallel pulls
- Automatic cleanup of unused resources

### Security Scanning

- Container security scanning with CVE detection
- Privilege escalation detection
- Environment variable auditing
- Port exposure monitoring
- Certificate validation

## 🔄 Maintenance

### Updates

- Weekly automatic update checks
- Update notifications for containers
- Version tracking with diff capabilities
- Registry mirror optimization
- Automatic security patches

### Cleanup

```bash
# Clean up specific user's resources
podman-cleanup --user USERNAME

# Remove home directory when cleaning up user
podman-cleanup --user USERNAME --remove-home

# Full system cleanup including all configured users
podman-cleanup --all

# Preview cleanup actions (dry run)
podman-cleanup --dry-run --user USERNAME

# Clean up only specific resources
podman-cleanup --user USERNAME --containers --volumes
```

The cleanup script now includes:

- Idempotent operations (safe to run multiple times)
- Detailed logging of all actions
- Selective cleanup options
- Backup of important data before removal
- Verification of cleanup success

## 💡 Troubleshooting

### Common Issues

1. Container Pull Failures
   - Check network connectivity
   - Verify registry mirrors in /etc/containers/registries.conf
   - Review logs in /var/log/podman-provision/
   - Use `podman-diagnostics network` to check connectivity

2. Resource Limits
   - Check quota status with `podman-user-manager status USERNAME`
   - Review diagnostic reports
   - Adjust limits in config.sh
   - Use `podman-diagnostics resources` to check system-wide usage

3. Performance Issues
   - Check parallel pull configuration
   - Verify registry mirror settings
   - Monitor resource usage with `podman-diagnostics monitor`
   - Use `podman-diagnostics optimize` for suggestions

### Diagnostic Tools

Run comprehensive diagnostics:

```bash
podman-diagnostics collect
```

View real-time monitoring:

```bash
podman-diagnostics monitor
```

Check specific subsystems:

```bash
podman-diagnostics network
podman-diagnostics storage
podman-diagnostics memory
```

### Logs

- Main logs: /var/log/podman-provision/
- Per-script logs: /var/log/podman-provision/{script}-{timestamp}.log
- Diagnostic reports: /var/log/podman-provision/reports/
- Health monitoring: /var/log/podman-provision/health-monitor.log
- Container logs: /var/log/podman-provision/containers/

## 🔐 Security Notes

- The TLS certificate is installed system-wide at `/etc/pki/ca-trust/source/anchors/zscaler.crt`
- All configuration files have proper permissions (600)
- User directories have restricted permissions (700)
- Comprehensive shell trust configuration:
  - `NODE_EXTRA_CA_CERTS` for Node.js
  - `PIP_CERT` for Python packages
  - `REQUESTS_CA_BUNDLE` for Python requests
  - `SSL_CERT_FILE` for OpenSSL
  - `GIT_SSL_CAINFO` for Git operations
  - `CURL_CA_BUNDLE` for curl commands
- Default user password must be changed on first login
- Container capabilities are restricted to minimum required

## 🖥️ VS Code Integration

The environment comes pre-configured for VS Code with:

- Container support via Podman
- Default extensions for development
- MCP tools integration
- Shared volume mounts for persistence
- Resource limits for optimal performance
- PowerShell as default terminal

---

## 🤝 Credits

Built with ❤️ using Podman, NVM, Yarn, and container technologies by your infrastructure automation team
