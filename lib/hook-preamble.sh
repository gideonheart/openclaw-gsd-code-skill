#!/usr/bin/env bash
# lib/hook-preamble.sh — Shared bootstrap for all GSD hook scripts.
# Sourced as the FIRST action of every hook script (after set -euo pipefail).
# Uses BASH_SOURCE[1] throughout — the calling hook's path, not this file's path.
# No set -euo pipefail here — inherits from caller.
# No stdin consumption here — hook body reads stdin after source returns.
# No HOOK_ENTRY_MS here — timing starts in hook body after source returns.

# Source guard: prevent double-sourcing (idempotent)
[[ -n "${_GSD_HOOK_PREAMBLE_LOADED:-}" ]] && return 0

# Direct execution guard: reject bash lib/hook-preamble.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf 'ERROR: %s must be sourced, not executed directly.\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi

readonly _GSD_HOOK_PREAMBLE_LOADED=1

# Resolve skill root from preamble's own location (BASH_SOURCE[0] is preamble)
_GSD_PREAMBLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GSD_SKILL_ROOT="$(cd "${_GSD_PREAMBLE_LIB_DIR}/.." && pwd)"

# Set path variables derived from skill root
SKILL_LOG_DIR="${_GSD_SKILL_ROOT}/logs"
mkdir -p "$SKILL_LOG_DIR" 2>/dev/null || true
REGISTRY_PATH="${_GSD_SKILL_ROOT}/config/recovery-registry.json"

# HOOK_SCRIPT_NAME: use BASH_SOURCE[1] (the calling hook's path, not preamble's)
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]:-hook-unknown.sh}")"
# SCRIPT_DIR: the calling hook's scripts/ directory — used for path construction in hook body
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${_GSD_PREAMBLE_LIB_DIR}}")" && pwd)"

# GSD_HOOK_LOG: conditional — hooks redirect this mid-execution (Phase 2 redirect)
GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" \
    >> "$GSD_HOOK_LOG" 2>/dev/null || true
}

debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"

# Source hook-utils.sh from lib/ directory (same location as this preamble)
_GSD_UTILS_PATH="${_GSD_PREAMBLE_LIB_DIR}/hook-utils.sh"
if [ -f "$_GSD_UTILS_PATH" ]; then
  # shellcheck source=./hook-utils.sh
  source "$_GSD_UTILS_PATH"
  debug_log "sourced lib/hook-utils.sh"
else
  printf '[%s] [%s] FATAL: hook-utils.sh not found at %s\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$_GSD_UTILS_PATH" \
    >> "$GSD_HOOK_LOG" 2>/dev/null || true
  exit 0
fi
