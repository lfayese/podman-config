# 🐳 Podman VM Provisioning: Multi-User Dev Environment

This repository contains scripts to provision a Podman-managed VM (using `podman-machine-default`) with secure TLS trust, developer toolchains, Node.js environments, and container-based development tools for users.

---

## 📦 Files

- **config.sh**  
  Central configuration file containing all customizable settings including:
  - User definitions
  - Resource limits
  - Container groups and registries
  - Volume configurations
  - MCP service enablement
  - PowerShell package settings

- **provision-machine.sh**  
  Host-side script that:
  - Verifies WSL2 and system requirements
  - Optimizes Podman machine settings
  - Configures registry and container settings
  - Copies necessary files to VM
  - Triggers user provisioning

- **setup-users.sh**  
  VM-side provisioning script that:
  - Creates user accounts with secure defaults
  - Installs Zscaler TLS certificates
  - Sets up Node.js with nvm and yarn
  - Configures PowerShell environments
  - Establishes Podman socket services
  - Applies security hardening

- **container-setup.sh**  
  Container management script that:
  - Creates named volumes per user
  - Pulls and verifies container images
  - Sets up container networks
  - Configures VS Code integration
  - Initializes MCP environment

- **user-manager.sh**  
  User administration tool providing:
  - User environment status checks
  - Resource usage monitoring
  - Container and volume management
  - Quota enforcement
  - Environment reset capabilities

- **common.sh**  
  Shared utilities for:
  - Logging and error handling
  - Command retries
  - User verification
  - Common operations

---

## ✅ Prerequisites

- Windows 10/11 with WSL2 enabled
- Podman 4.0.0+ installed with WSL support
- Podman machine already created: `podman-machine-default`
- Minimum 8GB RAM recommended
- Zscaler cert available at: `~/certs/ZscalerRootCertificate-2048-SHA256.crt`

---

## 🚀 Quick Start

1. Verify Prerequisites:

   ```bash
   # Check WSL2 is enabled
   wsl --status
   
   # Verify Podman installation
   podman --version   # Should be 4.0.0+
   
   # Ensure podman-machine-default exists
   podman machine ls
   ```

   ```bash
   mkdir -p ~/certs
   cp ZscalerRootCertificate-2048-SHA256.crt ~/certs/
   cp ZscalerRootCertificate-2048-SHA256.crt ~/certs/
   ```

   ```bash
   cp config.sh.template config.sh
   # Edit config.sh as needed
   # Edit config.sh as needed
   ```

   ```bash
   chmod +x provision-machine.sh
   ./provision-machine.sh
   ./provision-machine.sh
   ```

---

## 🛠 User Management

The `user-manager.sh` script provides several commands:

```bash
# Show user status
./user-manager.sh status USERNAME

# Create new user
./user-manager.sh create USERNAME

# Reset user environment
./user-manager.sh reset USERNAME

# Monitor resource usage
./user-manager.sh monitor USERNAME

# Set resource quota
./user-manager.sh quota USERNAME RESOURCE LIMIT
```

---

## 📊 Resource Management

### Default Quotas

- Memory: 8GB per user
- CPU: 4 cores per user
- Storage: Based on available space

### Container Groups

- MCP Tools (filesystem, git, etc.)
- AI Models (Llama, Mistral)
- Sourcegraph tooling
- PowerShell environments

---

## 🔒 Security Features

- Secure user isolation
- TLS certificate integration
- Container capability restrictions
- Resource quotas and limits
- Seccomp profiles
- Automated security updates

---

## 📝 Notes

- User environments persist across VM restarts
- Container images are shared to save space
- Resource monitoring runs automatically
- Weekly update checks are configured
- All operations are logged to `/var/log/podman-provision/`
