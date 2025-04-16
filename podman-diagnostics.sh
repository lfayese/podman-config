#!/bin/bash
set -euo pipefail

DIAG_DIR="/var/log/podman-provision/diagnostics"
REPORT_DIR="/var/log/podman-provision/reports"

collect_diagnostics() {
  local timestamp=$(date +"%Y%m%d-%H%M%S")
  local report_file="$REPORT_DIR/diagnostic-report-$timestamp.txt"

  mkdir -p "$DIAG_DIR" "$REPORT_DIR"

  echo "🔍 Collecting system diagnostics..."

  # System info
  {
    echo "=== System Information ==="
    echo "Date: $(date)"
    echo "Kernel: $(uname -a)"
    echo "Memory: $(free -h)"
    echo "Disk Space: $(df -h)"
    echo

    echo "=== Podman Information ==="
    podman info
    echo

    echo "=== Container Status ==="
    podman ps -a
    echo

    echo "=== Volume Information ==="
    podman volume ls
    echo

    echo "=== Network Information ==="
    podman network ls
    echo

    echo "=== Recent Logs ==="
    tail -n 1000 /var/log/podman-provision/*.log
    echo

    echo "=== Resource Usage ==="
    podman stats --no-stream --all

  } > "$report_file"

  echo "✅ Diagnostic report generated: $report_file"
}

monitor_health() {
  local check_interval=${1:-300} # Default 5 minutes

  while true; do
    echo "🏥 Performing health check..."

    # Check system resources
    local mem_free=$(free | awk '/Mem:/ {print $4/$2 * 100.0}')
    local disk_free=$(df / | awk 'NR==2 {print $4/$2 * 100.0}')

    # Alert on low resources
    if (( $(echo "$mem_free < 20" | bc -l) )); then
      log "⚠️ Low memory warning: ${mem_free}% free"
    fi
    if (( $(echo "$disk_free < 20" | bc -l) )); then
      log "⚠️ Low disk space warning: ${disk_free}% free"
    fi

    # Check container health
    podman ps -a --format '{{.Names}}' | while read container; do
      local status=$(podman inspect --format '{{.State.Status}}' "$container")
      if [[ "$status" != "running" ]]; then
        log "⚠️ Container $container is not running (status: $status)"
      fi
    done

    sleep "$check_interval"
  done
}

cleanup_old_reports() {
  local max_age_days=${1:-7}

  find "$REPORT_DIR" -type f -mtime +"$max_age_days" -delete
  find "$DIAG_DIR" -type f -mtime +"$max_age_days" -delete

  echo "✅ Cleaned up reports older than $max_age_days days"
}

main() {
  case "${1:-help}" in
    collect)
      collect_diagnostics
      ;;
    monitor)
      monitor_health "${2:-300}"
      ;;
    cleanup)
      cleanup_old_reports "${2:-7}"
      ;;
    help|*)
      echo "Usage: $0 {collect|monitor|cleanup} [interval_seconds|max_age_days]"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
