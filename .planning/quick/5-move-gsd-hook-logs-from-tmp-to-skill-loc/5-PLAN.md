---
phase: 5-move-gsd-hook-logs-from-tmp-to-skill-loc
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/stop-hook.sh
  - scripts/notification-idle-hook.sh
  - scripts/notification-permission-hook.sh
  - scripts/pre-tool-use-hook.sh
  - scripts/session-end-hook.sh
  - scripts/pre-compact-hook.sh
  - scripts/diagnose-hooks.sh
  - lib/hook-utils.sh
  - .gitignore
autonomous: true
requirements: [LOGS-01, LOGS-02, LOGS-03, LOGS-04, LOGS-05]
must_haves:
  truths:
    - "Hook debug logs write to logs/ directory inside gsd-code-skill, not /tmp"
    - "Each tmux session gets its own log file (logs/{SESSION_NAME}.log)"
    - "Pre-session-name log lines go to logs/hooks.log as a shared fallback"
    - "Pane state files (prev/lock) live in logs/ instead of /tmp"
    - "logs/ directory is gitignored"
    - "diagnose-hooks.sh reads from the new log location"
  artifacts:
    - path: ".gitignore"
      provides: "logs/ exclusion"
      contains: "logs/"
    - path: "scripts/stop-hook.sh"
      provides: "Two-phase log path: hooks.log then SESSION_NAME.log"
      contains: "logs/"
    - path: "lib/hook-utils.sh"
      provides: "Pane state files in logs/ directory"
      contains: "logs/gsd-pane-prev-"
  key_links:
    - from: "scripts/*-hook.sh"
      to: "logs/"
      via: "GSD_HOOK_LOG variable"
      pattern: "SKILL_LOG_DIR.*logs"
    - from: "lib/hook-utils.sh"
      to: "logs/"
      via: "previous_file and lock_file paths"
      pattern: "SKILL_LOG_DIR.*logs/gsd-pane"
    - from: "scripts/session-end-hook.sh"
      to: "logs/"
      via: "cleanup of pane state files"
      pattern: "rm -f.*logs/gsd-pane"
---

<objective>
Move all GSD hook logging and pane state files from /tmp to a skill-local logs/ directory with per-session log files.

Purpose: Logs in /tmp are ephemeral, mixed across all agents, and lost on reboot. Moving to skill-local logs/ with per-session files makes debugging straightforward — each agent session has its own isolated log file.

Output: All 6 hook scripts, diagnose-hooks.sh, hook-utils.sh updated; logs/ gitignored.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@scripts/stop-hook.sh
@scripts/notification-idle-hook.sh
@scripts/notification-permission-hook.sh
@scripts/pre-tool-use-hook.sh
@scripts/session-end-hook.sh
@scripts/pre-compact-hook.sh
@scripts/diagnose-hooks.sh
@lib/hook-utils.sh
@.gitignore
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update all 6 hook scripts with two-phase log path and gitignore logs/</name>
  <files>
    scripts/stop-hook.sh
    scripts/notification-idle-hook.sh
    scripts/notification-permission-hook.sh
    scripts/pre-tool-use-hook.sh
    scripts/session-end-hook.sh
    scripts/pre-compact-hook.sh
    .gitignore
  </files>
  <action>
In each of the 6 hook scripts, replace the preamble (lines 4-12) with a two-phase logging approach:

**Phase 1 — Before SESSION_NAME is known (lines 4-11 replacement):**
```bash
# Resolve skill-local log directory from this script's location
SKILL_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$SKILL_LOG_DIR"

# Phase 1: log to shared file until session name is known
GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" >> "$GSD_HOOK_LOG" 2>/dev/null || true
}

debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"
```

**Phase 2 — After SESSION_NAME is extracted (right after `debug_log "tmux_session=$SESSION_NAME"`):**
Add this line immediately after the existing `debug_log "tmux_session=$SESSION_NAME"` line:
```bash
# Phase 2: redirect to per-session log file
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
debug_log "=== log redirected to per-session file ==="
```

The debug_log function does NOT need to be redefined — it reads $GSD_HOOK_LOG on each call (not captured at define time). Reassigning the variable is sufficient.

**IMPORTANT details per script:**

For ALL scripts: The `SCRIPT_DIR` variable computed later (in the registry lookup section) is SEPARATE from `SKILL_LOG_DIR`. Do NOT remove or rename `SCRIPT_DIR` — it is used for `REGISTRY_PATH` and `LIB_PATH`. `SKILL_LOG_DIR` is a NEW variable computed at the top specifically for logging.

For `session-end-hook.sh` (lines 90-92): Also update the cleanup section to clean up from logs/ instead of /tmp:
```bash
rm -f "${SKILL_LOG_DIR}/gsd-pane-prev-${SESSION_NAME}.txt"
rm -f "${SKILL_LOG_DIR}/gsd-pane-lock-${SESSION_NAME}"
debug_log "Cleaned up pane state files for session=$SESSION_NAME"
```
Note: `SKILL_LOG_DIR` is already available at the top of the script, so it is in scope here.

For `.gitignore`: Append `logs/` on a new line after the existing `config/recovery-registry.json` line.
  </action>
  <verify>
Run `grep -r '/tmp/gsd-hooks' scripts/` — should return ZERO matches.
Run `grep -r '/tmp/gsd-pane' scripts/` — should return ZERO matches.
Run `grep 'logs/' .gitignore` — should return `logs/`.
Run `bash -n scripts/stop-hook.sh && bash -n scripts/session-end-hook.sh && bash -n scripts/notification-idle-hook.sh && bash -n scripts/notification-permission-hook.sh && bash -n scripts/pre-tool-use-hook.sh && bash -n scripts/pre-compact-hook.sh` — all syntax checks pass.
  </verify>
  <done>All 6 hook scripts log to logs/hooks.log initially, then redirect to logs/{SESSION_NAME}.log once session name is known. No /tmp references remain in any hook script. logs/ is gitignored.</done>
</task>

<task type="auto">
  <name>Task 2: Update hook-utils.sh pane state paths and diagnose-hooks.sh log location</name>
  <files>
    lib/hook-utils.sh
    scripts/diagnose-hooks.sh
  </files>
  <action>
**lib/hook-utils.sh — extract_pane_diff function (lines 54-85):**

The function currently hardcodes `/tmp/gsd-pane-prev-{session}.txt` and `/tmp/gsd-pane-lock-{session}`. These need to use the caller's `SKILL_LOG_DIR` variable (which is set at the top of every hook script that sources this library).

Replace lines 57-58:
```bash
  local previous_file="/tmp/gsd-pane-prev-${session_name}.txt"
  local lock_file="/tmp/gsd-pane-lock-${session_name}"
```
With:
```bash
  # SKILL_LOG_DIR is set by the calling hook script before sourcing this library
  local log_directory="${SKILL_LOG_DIR:-/tmp}"
  local previous_file="${log_directory}/gsd-pane-prev-${session_name}.txt"
  local lock_file="${log_directory}/gsd-pane-lock-${session_name}"
```

The fallback `:-/tmp` is defensive — if somehow sourced without `SKILL_LOG_DIR`, it still works. In practice, every caller sets `SKILL_LOG_DIR` at the top of the script (from Task 1).

**scripts/diagnose-hooks.sh — line 48:**

Replace:
```bash
HOOK_LOG="/tmp/gsd-hooks.log"
```
With:
```bash
HOOK_LOG="${SKILL_ROOT}/logs"
```

Then update Step 9 (Hook Debug Log section, around lines 299-312) to check for the logs/ directory and list per-session log files instead of checking a single file:
```bash
echo "--- Step 9: Hook Debug Logs ---"

TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if [ -d "$HOOK_LOG" ]; then
  LOG_FILE_COUNT=$(ls -1 "$HOOK_LOG"/*.log 2>/dev/null | wc -l || echo "0")
  pass "Log directory exists: $HOOK_LOG ($LOG_FILE_COUNT log files)"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))
  # Show session-specific log if it exists
  SESSION_LOG_FILE="${HOOK_LOG}/${TMUX_SESSION_NAME}.log"
  if [ -f "$SESSION_LOG_FILE" ]; then
    SESSION_LOG_LINES=$(wc -l < "$SESSION_LOG_FILE")
    LAST_ENTRY=$(tail -1 "$SESSION_LOG_FILE" 2>/dev/null || echo "")
    info "Session log: $SESSION_LOG_FILE ($SESSION_LOG_LINES lines)"
    info "Last entry: $LAST_ENTRY"
  else
    info "No session-specific log yet for $TMUX_SESSION_NAME"
  fi
else
  info "Log directory does not exist yet: $HOOK_LOG"
  info "It will be created when hooks fire"
  PASSED_CHECKS=$((PASSED_CHECKS + 1))  # Not a failure
fi
```

Also update the summary output at the end (lines 360-370) — change `tail -f $HOOK_LOG` reference to `tail -f ${HOOK_LOG}/${TMUX_SESSION_NAME}.log` in the hint text (around line 362):
```bash
  echo "  2. Run: tail -f ${HOOK_LOG}/${TMUX_SESSION_NAME}.log"
```
  </action>
  <verify>
Run `grep -r '/tmp/gsd-pane' lib/` — should return ZERO matches.
Run `grep '/tmp/gsd-hooks' scripts/diagnose-hooks.sh` — should return ZERO matches.
Run `bash -n lib/hook-utils.sh && bash -n scripts/diagnose-hooks.sh` — syntax checks pass.
  </verify>
  <done>hook-utils.sh pane state files use SKILL_LOG_DIR (with /tmp fallback). diagnose-hooks.sh checks the logs/ directory and shows per-session log info. No /tmp references remain anywhere in the codebase for hook logging or pane state.</done>
</task>

</tasks>

<verification>
After both tasks complete:
1. `grep -rn '/tmp/gsd' scripts/ lib/` returns ZERO lines — no /tmp references for hook files remain
2. `bash -n` passes on all 8 modified shell scripts
3. `grep 'logs/' .gitignore` confirms logs/ is gitignored
4. The logs/ directory structure is: `logs/hooks.log` (early/shared), `logs/{SESSION_NAME}.log` (per-session), `logs/gsd-pane-prev-{session}.txt` (pane state), `logs/gsd-pane-lock-{session}` (flock)
</verification>

<success_criteria>
- All hook debug logging goes to gsd-code-skill/logs/ directory, not /tmp
- Each tmux session gets its own log file named after the session
- Pre-session-name log lines go to a shared hooks.log fallback
- Pane state files (prev/lock) live in logs/ instead of /tmp
- session-end-hook.sh cleans up pane state from logs/ on exit
- diagnose-hooks.sh reads from the new location
- logs/ is gitignored
- All scripts pass bash -n syntax validation
</success_criteria>

<output>
After completion, create `.planning/quick/5-move-gsd-hook-logs-from-tmp-to-skill-loc/5-SUMMARY.md`
</output>
