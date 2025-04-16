#!/bin/bash
# Central configuration file for all provisioning scripts

# User configuration
USERS=("ofayese" "639016")
DEFAULT_PASSWORD="changeme"  # Consider using a more secure approach

# System requirements
MIN_MEMORY_GB=8
MIN_PODMAN_VERSION="4.0.0"
MAX_MEMORY="8Gi"
MAX_CPU="4"

# Paths
PODMAN_VM="podman-machine-wsl"
LOG_DIR="/var/log/podman-provision"
CERT_VM_PATH="/etc/pki/ca-trust/source/anchors/zscaler.crt"
LOCAL_CERT="$HOME/certs/ZscalerRootCertificate-2048-SHA256.crt"
ZSCALER_HOME_CERT="$HOME/certs/zscaler.crt"
REMOTE_CERT_NAME="zscaler.crt"

# Container groups - define all container images to pull
declare -A CONTAINER_GROUPS
CONTAINER_GROUPS=(
  ["mcp"]="core-api code-intelligence ai-assistant"
  ["base"]="mcr.microsoft.com/powershell:latest docker.io/library/python:3.9-slim"
)

# MCP configuration
MCP_ENABLED_SERVICES=("code-intelligence" "ai-assistant")

# Retry settings
MAX_RETRIES=3
RETRY_DELAY=5

# Export all variables
export USERS DEFAULT_PASSWORD MIN_MEMORY_GB MIN_PODMAN_VERSION MAX_MEMORY MAX_CPU
export PODMAN_VM LOG_DIR CERT_VM_PATH LOCAL_CERT ZSCALER_HOME_CERT REMOTE_CERT_NAME
export CONTAINER_GROUPS MCP_ENABLED_SERVICES MAX_RETRIES RETRY_DELAY
