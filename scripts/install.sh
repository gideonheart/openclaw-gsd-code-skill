#!/usr/bin/env bash
set -euo pipefail

# install.sh - Single entry point installer for gsd-code-skill
# Orchestrates: hook registration, logrotate setup, log directory creation,
# diagnostic verification, and user-facing next-steps instructions.
#
# Usage: scripts/install.sh [agent-name]
#   agent-name  Optional. If provided, runs diagnose-hooks.sh after installation.

# ============================================================================
# Path Derivation
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ============================================================================
# Logging
# ============================================================================

log_message() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

# ============================================================================
# Arguments
# ============================================================================

AGENT_NAME="${1:-}"
LOGROTATE_FAILED=false

# ============================================================================
# Step 1: Pre-flight Checks
# ============================================================================

log_message "=== Step 1: Pre-flight Checks ==="
log_message "Skill root: ${SKILL_ROOT}"

if ! command -v jq &> /dev/null; then
  log_message "ERROR: jq is not installed. Required by register-hooks.sh."
  log_message "Install it: sudo apt-get install jq"
  exit 1
fi
log_message "jq found: $(command -v jq)"

if ! command -v sudo &> /dev/null; then
  log_message "WARNING: sudo is not available. Logrotate installation will be skipped."
fi

# ============================================================================
# Step 2: Create logs/ Directory
# ============================================================================

log_message "=== Step 2: Create logs/ Directory ==="

LOGS_DIR="${SKILL_ROOT}/logs"
if [ -d "${LOGS_DIR}" ]; then
  log_message "logs/ directory already exists: ${LOGS_DIR}"
else
  mkdir -p "${LOGS_DIR}"
  log_message "Created logs/ directory: ${LOGS_DIR}"
fi

# ============================================================================
# Step 3: Register Hooks
# ============================================================================

log_message "=== Step 3: Register Hooks ==="
log_message "Running register-hooks.sh ..."

if ! bash "${SCRIPT_DIR}/register-hooks.sh"; then
  log_message "ERROR: Hook registration failed. Aborting installation."
  exit 1
fi

log_message "Hook registration completed successfully."

# ============================================================================
# Step 4: Install Logrotate Config
# ============================================================================

log_message "=== Step 4: Install Logrotate Config ==="
log_message "This step requires sudo for /etc/logrotate.d/"

if ! bash "${SCRIPT_DIR}/install-logrotate.sh"; then
  log_message "WARNING: Logrotate installation failed. This is non-critical."
  log_message "You can install it manually later: sudo scripts/install-logrotate.sh"
  LOGROTATE_FAILED=true
else
  log_message "Logrotate config installed successfully."
fi

# ============================================================================
# Step 5: Run Diagnostics (Optional)
# ============================================================================

log_message "=== Step 5: Diagnostics ==="

if [ -n "${AGENT_NAME}" ]; then
  log_message "Running diagnostics for agent: ${AGENT_NAME}"
  bash "${SCRIPT_DIR}/diagnose-hooks.sh" "${AGENT_NAME}" || true
else
  log_message "INFO: No agent name provided -- skipping diagnostics."
  log_message "Run manually: scripts/diagnose-hooks.sh <agent-name>"
fi

# ============================================================================
# Step 6: Next-Steps Banner
# ============================================================================

echo ""
echo "=========================================="
echo "  gsd-code-skill installation complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Restart any running Claude Code sessions (hooks snapshot at startup)"
echo "  2. Register an agent in config/recovery-registry.json (see config/recovery-registry.example.json)"
echo "  3. Spawn a session:  scripts/spawn.sh <agent-name> <workdir>"
echo "  4. Verify hooks:     scripts/diagnose-hooks.sh <agent-name>"

if [ "${LOGROTATE_FAILED}" = true ]; then
  echo ""
  echo "NOTE: Logrotate installation failed. Run manually: sudo scripts/install-logrotate.sh"
fi

echo ""
