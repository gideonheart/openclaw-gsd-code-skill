#!/usr/bin/env bash
set -euo pipefail

# install-logrotate.sh - Install logrotate config for gsd-code-skill hook logs
# Usage: scripts/install-logrotate.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOGROTATE_CONF="${SKILL_ROOT}/config/logrotate.conf"
LOGROTATE_DEST="/etc/logrotate.d/gsd-code-skill"

log_message() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

if [ ! -f "$LOGROTATE_CONF" ]; then
  log_message "ERROR: Config template not found: $LOGROTATE_CONF"
  exit 1
fi

log_message "Installing logrotate config to $LOGROTATE_DEST"
sudo tee "$LOGROTATE_DEST" < "$LOGROTATE_CONF" > /dev/null
log_message "Installed successfully"

log_message "Verifying config syntax with logrotate -d ..."
logrotate -d "$LOGROTATE_DEST" 2>&1 | grep -v 'debug mode\|state file' || true

log_message "Config installed at $LOGROTATE_DEST"
log_message "To force a test rotation: sudo logrotate --force $LOGROTATE_DEST"
