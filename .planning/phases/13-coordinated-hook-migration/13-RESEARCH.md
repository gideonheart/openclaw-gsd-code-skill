# Phase 13: Coordinated Hook Migration - Research

**Researched:** 2026-02-18
**Domain:** Bash hook script refactoring (internal codebase)
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Wake message label migration: Clean break — [PANE CONTENT] replaced with [CONTENT] in all 3 remaining hooks (notification-idle, notification-permission, pre-compact). No backward compatibility shim.
- Pre-compact pattern normalization: Full normalization — pre-compact must use the same detect_session_state() function as all other hooks. Divergent case-sensitive grep patterns replaced with shared function's case-insensitive extended regex.
- Hook settings adoption scope: Every hook that currently inlines settings extraction calls extract_hook_settings() instead. Hooks that don't use settings don't get the call.

### Claude's Discretion
- Migration ordering across the 7 hooks (grouped by similarity, complexity, or alphabetical)
- Whether to normalize any other minor inconsistencies discovered during the sweep
- Exact printf format patterns where echo replacement isn't 1:1

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| REFAC-03 | All 7 hooks source hook-preamble.sh as single entry point (no direct hook-utils.sh source) | Preamble analysis below identifies exact line ranges to replace in each hook |
| MIGR-01 | notification-idle-hook.sh wake message uses [CONTENT] instead of [PANE CONTENT] | Line 161 identified — single string replacement |
| MIGR-02 | notification-permission-hook.sh wake message uses [CONTENT] instead of [PANE CONTENT] | Line 162 identified — single string replacement |
| MIGR-03 | pre-compact-hook.sh wake message uses [CONTENT] instead of [PANE CONTENT] | Line 136 identified — single string replacement |
| FIX-03 | session-end-hook.sh jq calls have 2>/dev/null error guards | Lines 71-72 identified — missing error guards |
| QUAL-01 | All jq piping across all 7 hooks uses printf '%s' instead of echo | Full echo-to-jq audit below with exact line numbers |
</phase_requirements>

## Summary

Phase 13 is a pure internal refactoring of 7 existing bash hook scripts. Every change is mechanical and verifiable by grep. The hook-preamble.sh (created in Phase 12) already provides all the infrastructure — this phase replaces duplicated code with calls to that shared library.

Three distinct change categories span all 7 hooks: (1) replacing the duplicated 15-27 line preamble block with a single `source` of hook-preamble.sh, (2) replacing inline settings extraction blocks with `extract_hook_settings()` calls in the 4 hooks that use settings, and (3) replacing `echo "$var" | jq` patterns with `printf '%s' "$var" | jq` across all hooks. Two hooks (pre-tool-use, post-tool-use) already use printf for jq piping — they only need the preamble migration. Three hooks need the [PANE CONTENT] to [CONTENT] label rename. Session-end needs jq error guards.

**Primary recommendation:** Group by wave — Wave 1 migrates the 4 simpler hooks (notification-idle, notification-permission, pre-compact, session-end) that share identical structure, Wave 2 migrates stop-hook.sh (most complex, has transcript extraction), Wave 3 migrates pre-tool-use and post-tool-use (already partially migrated, minimal changes).

## Codebase Audit

### Current Preamble Block (duplicated in all 7 hooks)

Every hook currently has this block at lines 1-27 (varies slightly):

```bash
#!/usr/bin/env bash
set -euo pipefail

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

# Source shared library BEFORE any guard exits (Phase 9 requirement)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"
if [ -f "$LIB_PATH" ]; then
  source "$LIB_PATH"
else
  debug_log "FATAL: hook-utils.sh not found at $LIB_PATH"
  exit 0
fi
```

**After migration, this entire block is replaced with:**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/hook-preamble.sh"
```

hook-preamble.sh already sets: `SKILL_LOG_DIR`, `REGISTRY_PATH`, `HOOK_SCRIPT_NAME`, `SCRIPT_DIR`, `GSD_HOOK_LOG`, and provides `debug_log()`. It also sources hook-utils.sh internally.

### Inline Settings Block (duplicated in 4 hooks)

stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, and pre-compact-hook.sh all have this block:

```bash
GLOBAL_SETTINGS=$(jq -r '.hook_settings // {}' "$REGISTRY_PATH" 2>/dev/null || echo "{}")

PANE_CAPTURE_LINES=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.pane_capture_lines // $global.pane_capture_lines // 100)' 2>/dev/null || echo "100")

CONTEXT_PRESSURE_THRESHOLD=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.context_pressure_threshold // $global.context_pressure_threshold // 50)' 2>/dev/null || echo "50")

HOOK_MODE=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.hook_mode // $global.hook_mode // "async")' 2>/dev/null || echo "async")
```

**After migration, replaced with:**

```bash
HOOK_SETTINGS_JSON=$(extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA")
PANE_CAPTURE_LINES=$(printf '%s' "$HOOK_SETTINGS_JSON" | jq -r '.pane_capture_lines')
CONTEXT_PRESSURE_THRESHOLD=$(printf '%s' "$HOOK_SETTINGS_JSON" | jq -r '.context_pressure_threshold')
HOOK_MODE=$(printf '%s' "$HOOK_SETTINGS_JSON" | jq -r '.hook_mode')
```

### echo-to-jq Pattern Audit (QUAL-01)

Exact locations of `echo "$VAR" | jq` patterns that need conversion to `printf '%s' "$VAR" | jq`:

**stop-hook.sh:**
- Line 37: `echo "$STDIN_JSON" | jq -r '.hook_event_name`
- Line 42: `echo "$STDIN_JSON" | jq -r '.stop_hook_active`
- Line 87: `echo "$AGENT_DATA" | jq -r '.agent_id'`
- Line 88: `echo "$AGENT_DATA" | jq -r '.openclaw_session_id'`
- Line 99: `GLOBAL_SETTINGS=$(jq -r ...` (reads file, not echo — OK)
- Line 101-103: `echo "$AGENT_DATA" | jq` (settings block — replaced by extract_hook_settings)
- Line 105-107: `echo "$AGENT_DATA" | jq` (settings block — replaced)
- Line 109-111: `echo "$AGENT_DATA" | jq` (settings block — replaced)
- Line 121: `printf '%s' "$STDIN_JSON"` (already printf — OK)
- Line 134: `echo "$PANE_CONTENT" | grep` (not jq — but should use printf for consistency)
- Line 149: `echo "$PANE_CONTENT" | tail` (not jq — but should use printf for consistency)
- Line 235: `echo "$RESPONSE" | jq -r '.decision'`
- Line 236: `echo "$RESPONSE" | jq -r '.reason'`

**notification-idle-hook.sh:**
- Line 36: `echo "$STDIN_JSON" | jq`
- Line 80: `echo "$AGENT_DATA" | jq -r '.agent_id'`
- Line 81: `echo "$AGENT_DATA" | jq -r '.openclaw_session_id'`
- Lines 92-104: settings block (replaced by extract_hook_settings)
- Lines 116-123: `echo "$PANE_CONTENT" | grep` (not jq, but printf preferred)
- Line 131: `echo "$PANE_CONTENT" | tail`

**notification-permission-hook.sh:**
- Line 37: `echo "$STDIN_JSON" | jq`
- Line 81: `echo "$AGENT_DATA" | jq -r '.agent_id'`
- Line 82: `echo "$AGENT_DATA" | jq -r '.openclaw_session_id'`
- Lines 93-105: settings block (replaced by extract_hook_settings)
- Lines 117-123: `echo "$PANE_CONTENT" | grep`
- Line 132: `echo "$PANE_CONTENT" | tail`

**pre-compact-hook.sh:**
- Line 35: `echo "$STDIN_JSON" | jq`
- Line 71: `echo "$AGENT_DATA" | jq -r '.agent_id'` **MISSING 2>/dev/null**
- Line 72: `echo "$AGENT_DATA" | jq -r '.openclaw_session_id'` **MISSING 2>/dev/null**
- Lines 81-93: settings block (replaced by extract_hook_settings)
- Lines 99-100: `echo "$PANE_CONTENT" | tail` and `echo "$LAST_LINES" | grep`
- Lines 110-117: `echo "$PANE_CONTENT" | grep` (state detection — replaced by detect_session_state)

**session-end-hook.sh:**
- Line 35: `echo "$STDIN_JSON" | jq`
- Line 71: `echo "$AGENT_DATA" | jq -r '.agent_id'` **MISSING 2>/dev/null**
- Line 72: `echo "$AGENT_DATA" | jq -r '.openclaw_session_id'` **MISSING 2>/dev/null**

**pre-tool-use-hook.sh:** Already uses `printf '%s'` throughout. No echo-to-jq patterns.

**post-tool-use-hook.sh:** Already uses `printf '%s'` throughout. No echo-to-jq patterns.

### State Detection Audit (pre-compact divergence)

pre-compact-hook.sh uses divergent state detection (lines 110-118):
```bash
if echo "$PANE_CONTENT" | grep -q "Choose an option:"; then
  STATE="menu"
elif echo "$PANE_CONTENT" | grep -q "Continue this conversation"; then
  STATE="idle_prompt"
elif echo "$PANE_CONTENT" | grep -q "permission to"; then
  STATE="permission_prompt"
else
  STATE="active"
```

All other hooks and detect_session_state() use:
- Case-insensitive extended regex (`grep -Eiq`)
- State names: `menu`, `permission_prompt`, `idle`, `error`, `working`
- Patterns: `Enter to select|numbered.*option`, `permission|allow|dangerous`, `What can I help|waiting for`, `error|failed|exception`

**Per user decision:** pre-compact MUST be normalized to use `detect_session_state()`. State names change: `idle_prompt` -> `idle`, `active` -> `working`.

### session-end-hook.sh jq Error Guards (FIX-03)

Lines 71-72 are missing both 2>/dev/null and fallback:
```bash
AGENT_ID=$(echo "$AGENT_DATA" | jq -r '.agent_id')
OPENCLAW_SESSION_ID=$(echo "$AGENT_DATA" | jq -r '.openclaw_session_id')
```

Should be:
```bash
AGENT_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.agent_id' 2>/dev/null || echo "")
OPENCLAW_SESSION_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.openclaw_session_id' 2>/dev/null || echo "")
```

Same pattern also missing in pre-compact-hook.sh lines 71-72.

### [PANE CONTENT] Label Locations

- notification-idle-hook.sh line 161: `[PANE CONTENT]`
- notification-permission-hook.sh line 162: `[PANE CONTENT]`
- pre-compact-hook.sh line 136: `[PANE CONTENT]`

stop-hook.sh already uses `[CONTENT]` (line 198). pre-tool-use and post-tool-use don't have pane content sections.

## Architecture Patterns

### Hook Migration Pattern

Each hook migration follows the same mechanical steps:

1. **Replace preamble block** (lines 1-27) with 3-line bootstrap
2. **Replace settings block** (if present) with extract_hook_settings() call
3. **Replace echo-to-jq** patterns with printf '%s' equivalents
4. **Replace [PANE CONTENT]** with [CONTENT] (if present)
5. **Replace inline state detection** with detect_session_state() (pre-compact only)
6. **Add 2>/dev/null guards** to bare jq calls (session-end, pre-compact)

### Variables Provided by hook-preamble.sh

After sourcing hook-preamble.sh, hooks get these for free (no need to set):
- `SKILL_LOG_DIR` — already set and mkdir'd
- `REGISTRY_PATH` — already set
- `HOOK_SCRIPT_NAME` — already set from BASH_SOURCE[1]
- `SCRIPT_DIR` — already set from BASH_SOURCE[1]
- `GSD_HOOK_LOG` — already set
- `debug_log()` — already defined
- All hook-utils.sh functions — already sourced

### Post-Migration Hook Structure

After migration, every hook follows this structure:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/hook-preamble.sh"

# [Hook-specific comment describing purpose]

# 1. Consume stdin
STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)
debug_log "stdin: ${#STDIN_JSON} bytes, ..."

# 2-N. Guards, registry, settings, capture, state, message, delivery
# ... (hook-specific logic using shared functions)
```

## Common Pitfalls

### Pitfall 1: REGISTRY_PATH Collision
**What goes wrong:** hook-preamble.sh sets REGISTRY_PATH. Some hooks also set it to `${SCRIPT_DIR}/../config/recovery-registry.json`. After migration, both paths resolve identically, but the hook's line is redundant.
**How to avoid:** Remove the hook's REGISTRY_PATH line after migration. The preamble already sets it correctly.

### Pitfall 2: State Name Changes in pre-compact
**What goes wrong:** Downstream consumers may depend on pre-compact's current state names (`idle_prompt`, `active`).
**Why it happens:** Pre-compact used different state names than the standard.
**How to avoid:** Check if any code reads pre-compact JSONL records and keys on `idle_prompt` or `active`. The state field in wake messages is consumed by OpenClaw's LLM, which is label-agnostic. JSONL records are consumed by tools that should use the standard names.

### Pitfall 3: SCRIPT_DIR vs BASH_SOURCE After Preamble
**What goes wrong:** After sourcing preamble, SCRIPT_DIR is set from BASH_SOURCE[1] (the hook's path). Hooks that previously set SCRIPT_DIR themselves won't collide because preamble already set it.
**How to avoid:** Remove the hook's `SCRIPT_DIR=...` line after migration. Verify REGISTRY_PATH and other derived paths still resolve correctly.

## Verification Commands

After migration, these grep commands verify all success criteria:

```bash
# SC-1: Every hook sources hook-preamble.sh, none source hook-utils.sh directly
grep -l 'source.*hook-preamble.sh' scripts/*-hook.sh | wc -l  # Should be 7
grep -l 'source.*hook-utils.sh' scripts/*-hook.sh | wc -l     # Should be 0

# SC-2: No [PANE CONTENT] anywhere in codebase
grep -r '\[PANE CONTENT\]' scripts/ | wc -l  # Should be 0

# SC-3: No echo-to-jq patterns in hooks
grep -n 'echo.*\$.*| jq' scripts/*-hook.sh | wc -l  # Should be 0

# SC-4: session-end jq calls have 2>/dev/null
grep -c '2>/dev/null' scripts/session-end-hook.sh  # Should be > 0 for jq lines

# SC-5: Performance — preamble sourcing overhead
time bash -c 'source lib/hook-preamble.sh' 2>&1  # Should be < 5ms
```

## Sources

### Primary (HIGH confidence)
- Direct codebase analysis of all 7 hook scripts (read via Read tool)
- lib/hook-preamble.sh and lib/hook-utils.sh (created in Phase 12, read via Read tool)
- Phase 12 CONTEXT.md decisions on detect_session_state() and extract_hook_settings()

### Confidence Assessment
| Area | Level | Reason |
|------|-------|--------|
| Preamble migration | HIGH | Line-by-line audit of all 7 hooks |
| Settings replacement | HIGH | extract_hook_settings() API verified against current inline blocks |
| echo-to-printf sweep | HIGH | Every echo-to-jq instance catalogued with line numbers |
| Label migration | HIGH | Exact line numbers identified in all 3 hooks |
| State detection | HIGH | detect_session_state() patterns verified against pre-compact's inline patterns |

**Research date:** 2026-02-18
**Valid until:** No expiry (internal codebase, no external dependencies)
