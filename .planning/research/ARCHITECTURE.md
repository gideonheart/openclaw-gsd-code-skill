# Architecture Research: v3.1 Hook Refactoring & Migration Completion

**Domain:** Shell hook refactoring — shared preamble extraction, settings unification, wake format migration
**Researched:** 2026-02-18
**Confidence:** HIGH (all 7 hook scripts, lib/hook-utils.sh, and docs/v3-retrospective.md read in full)

---

## Current Architecture (v3.0 — shipped state)

```
Claude Code Session (tmux pane)
         |
         | hook event fires
         v
┌──────────────────────────────────────────────────────────────┐
│              7 Hook Entry Points                             │
│                                                             │
│  stop-hook.sh              (Stop event)                     │
│  pre-tool-use-hook.sh      (PreToolUse/AskUserQuestion)     │
│  post-tool-use-hook.sh     (PostToolUse/AskUserQuestion)    │
│  notification-idle-hook.sh (Notification/idle_prompt)       │
│  notification-permission-hook.sh (Notification/permission)  │
│  session-end-hook.sh       (SessionEnd)                     │
│  pre-compact-hook.sh       (PreCompact)                     │
│                                                             │
│  PROBLEM: Lines 1-27 copy-pasted 7x (preamble block)       │
│  PROBLEM: Lines 92-104 copy-pasted 4x (settings block)     │
│  PROBLEM: [PANE CONTENT] vs [CONTENT] inconsistency 3 hooks │
└──────────────┬──────────────────────────────────────────────┘
               |
               | source lib/hook-utils.sh (all 7 hooks, at top)
               v
┌──────────────────────────────────────────────────────────────┐
│    lib/hook-utils.sh — 6 shared functions                   │
│                                                             │
│  lookup_agent_in_registry()         — registry prefix match │
│  extract_last_assistant_response()  — transcript JSONL read │
│  extract_pane_diff()                — flock-protected diff  │
│  format_ask_user_questions()        — AskUserQuestion fmt   │
│  write_hook_event_record()          — atomic JSONL append   │
│  deliver_async_with_logging()       — async delivery wrap   │
│                                                             │
│  MISSING: extract_hook_settings() — not yet extracted       │
└──────────────┬──────────────────────────────────────────────┘
               |
               | openclaw agent --session-id UUID --message MSG
               v
┌──────────────────────────────────────────────────────────────┐
│    logs/ directory (skill-local)                            │
│                                                             │
│  hooks.log                    — shared pre-session log      │
│  {SESSION_NAME}.log           — per-session plain-text      │
│  {SESSION_NAME}.jsonl         — per-session JSONL records   │
│  gsd-pane-prev-{SESSION}.txt  — pane diff state file        │
│  gsd-pane-lock-{SESSION}      — flock coordination file     │
└──────────────────────────────────────────────────────────────┘
```

---

## Target Architecture (v3.1 — after refactoring)

```
Claude Code Session (tmux pane)
         |
         | hook event fires
         v
┌──────────────────────────────────────────────────────────────┐
│              7 Hook Scripts — REFACTORED (thinner)          │
│                                                             │
│  stop-hook.sh              MODIFIED: preamble → source      │
│  pre-tool-use-hook.sh      MODIFIED: preamble → source      │
│  post-tool-use-hook.sh     MODIFIED: preamble → source      │
│  notification-idle-hook.sh MODIFIED: preamble + settings    │
│                             + [CONTENT] migration           │
│  notification-permission-hook.sh  MODIFIED: same as idle    │
│  session-end-hook.sh       MODIFIED: preamble → source      │
│                             + 2>/dev/null guards added      │
│  pre-compact-hook.sh       MODIFIED: preamble + settings    │
│                             + [CONTENT] migration           │
│                                                             │
│  Hook body = guard chain + content + wake msg + delivery    │
│  NO preamble code, NO settings extraction inline            │
└──────────────┬──────────────────────────────────────────────┘
               |
               | source lib/hook-preamble.sh
               v
┌──────────────────────────────────────────────────────────────┐
│    lib/hook-preamble.sh — NEW (27 lines → 1 source call)   │
│                                                             │
│  Sets: SKILL_LOG_DIR (resolved via BASH_SOURCE)            │
│  Sets: GSD_HOOK_LOG (with ${GSD_HOOK_LOG:-} fallback)      │
│  Sets: HOOK_SCRIPT_NAME (basename of caller)               │
│  Sets: SCRIPT_DIR (resolved via BASH_SOURCE)               │
│  Defines: debug_log() function                             │
│  Emits:   "FIRED — PID=$$ TMUX=..." debug_log call         │
│  Sources: lib/hook-utils.sh (with file-missing guard)      │
│  Emits:   "sourced lib/hook-utils.sh" on success           │
│                                                             │
│  DESIGN RULE: No set -euo pipefail here (caller sets it)   │
│  DESIGN RULE: No side effects beyond variable assignment    │
│               and function definition + the two log calls  │
└──────────────┬──────────────────────────────────────────────┘
               |
               | source lib/hook-utils.sh (via preamble)
               v
┌──────────────────────────────────────────────────────────────┐
│    lib/hook-utils.sh — EXTENDED (+1 function)               │
│                                                             │
│  [Existing — unchanged]                                     │
│  lookup_agent_in_registry()                                 │
│  extract_last_assistant_response()                          │
│  extract_pane_diff()                                        │
│  format_ask_user_questions()                                │
│  write_hook_event_record()                                  │
│  deliver_async_with_logging()                               │
│                                                             │
│  [New in v3.1]                                              │
│  extract_hook_settings()   — three-tier jq fallback        │
│    args: registry_path, agent_data_json                     │
│    sets: PANE_CAPTURE_LINES, CONTEXT_PRESSURE_THRESHOLD,    │
│          HOOK_MODE (in caller's scope via printf+eval OR    │
│          outputs JSON for caller to parse)                  │
└──────────────────────────────────────────────────────────────┘
```

---

## Component Boundaries

### New Components

| Component | Location | Responsibility | What It Replaces |
|-----------|----------|----------------|------------------|
| `hook-preamble.sh` | `lib/hook-preamble.sh` | Sets up SKILL_LOG_DIR, GSD_HOOK_LOG, HOOK_SCRIPT_NAME, SCRIPT_DIR, debug_log(), fires FIRED log, sources hook-utils.sh | Lines 1-27 copy-pasted in all 7 hooks |
| `extract_hook_settings()` | `lib/hook-utils.sh` | Three-tier jq fallback for pane_capture_lines, context_pressure_threshold, hook_mode | 12-line block copy-pasted in 4 hooks |

### Modified Components

| Component | v3.0 State | v3.1 Change |
|-----------|-----------|-------------|
| All 7 hook scripts | 27-line preamble inline | Replace lines 1-27 with: `source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/hook-preamble.sh"` |
| `notification-idle-hook.sh` | `[PANE CONTENT]` section header | Migrate to `[CONTENT]` header (v2.0 format completion) |
| `notification-permission-hook.sh` | `[PANE CONTENT]` section header | Same migration |
| `pre-compact-hook.sh` | `[PANE CONTENT]` section header + settings block inline | `[CONTENT]` migration + `extract_hook_settings()` call |
| `stop-hook.sh` | Settings block inline | Replace with `extract_hook_settings()` call |
| `session-end-hook.sh` | jq calls without `2>/dev/null || echo ""` guards | Add guards (lines 71-72 pattern fix) |
| `lib/hook-utils.sh` | 6 functions | Add `extract_hook_settings()` as 7th function |

### Unchanged Components

| Component | Reason |
|-----------|--------|
| `lookup_agent_in_registry()` | No change to registry lookup logic |
| `extract_last_assistant_response()` | No change to extraction logic |
| `extract_pane_diff()` | No change to diff logic |
| `format_ask_user_questions()` | No change to formatting |
| `write_hook_event_record()` | No change to JSONL writing |
| `deliver_async_with_logging()` | No change to async delivery |
| `config/recovery-registry.json` | Schema unchanged |
| `logs/` directory and file paths | Unchanged |
| `spawn.sh`, `menu-driver.sh`, `register-hooks.sh`, etc. | Not hook scripts |

---

## Source Chain

### Current Source Chain (v3.0)

Each hook does this inline at lines 1-27:

```
hook-script.sh
  ├── set -euo pipefail                         (line 2)
  ├── SKILL_LOG_DIR="..." mkdir -p ...          (lines 4-5)
  ├── GSD_HOOK_LOG="${GSD_HOOK_LOG:-...}"        (line 8)
  ├── HOOK_SCRIPT_NAME="$(basename ...)"         (line 9)
  ├── debug_log() { printf ... }                (lines 11-13)
  ├── debug_log "FIRED ..."                     (line 15)
  ├── SCRIPT_DIR="$(cd ... && pwd)"             (line 18)
  ├── LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"  (line 19)
  └── if [ -f "$LIB_PATH" ]; then source; else exit 0; fi  (lines 20-26)
         └── lib/hook-utils.sh (6 functions)
```

### Target Source Chain (v3.1)

Each hook does this at line 4:

```
hook-script.sh
  ├── set -euo pipefail                         (line 2)
  └── source ".../lib/hook-preamble.sh"         (line 4)
         ├── SKILL_LOG_DIR="..." mkdir -p ...
         ├── GSD_HOOK_LOG="${GSD_HOOK_LOG:-...}"
         ├── HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]}")"  ← caller's name
         ├── debug_log() { printf ... }
         ├── debug_log "FIRED ..."
         ├── SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"  ← caller's dir
         ├── LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"
         └── if [ -f "$LIB_PATH" ]; then source; else ... exit 0; fi
                └── lib/hook-utils.sh (7 functions, including extract_hook_settings)
```

### Critical Design Constraint for hook-preamble.sh

`BASH_SOURCE[0]` inside `hook-preamble.sh` resolves to `hook-preamble.sh` itself. To get the calling hook's path, use `BASH_SOURCE[1]`. This is the key difference from inline code where `BASH_SOURCE[0]` was always the hook script.

Verified bash behavior: when script A sources script B, inside B `BASH_SOURCE[0]` is B and `BASH_SOURCE[1]` is A. This is HIGH confidence — standard bash documented behavior.

The preamble must use `BASH_SOURCE[1]` for both `HOOK_SCRIPT_NAME` and `SCRIPT_DIR` resolution. All other code is identical to the inline version.

---

## File Structure After v3.1

```
gsd-code-skill/
├── scripts/
│   ├── stop-hook.sh                      MODIFIED: preamble → source, settings → extract_hook_settings()
│   ├── pre-tool-use-hook.sh              MODIFIED: preamble → source
│   ├── post-tool-use-hook.sh             MODIFIED: preamble → source
│   ├── notification-idle-hook.sh         MODIFIED: preamble → source, [PANE CONTENT] → [CONTENT]
│   ├── notification-permission-hook.sh   MODIFIED: preamble → source, [PANE CONTENT] → [CONTENT]
│   ├── session-end-hook.sh               MODIFIED: preamble → source, add 2>/dev/null guards
│   ├── pre-compact-hook.sh               MODIFIED: preamble → source, settings → extract_hook_settings(), [PANE CONTENT] → [CONTENT]
│   ├── register-hooks.sh                 unchanged
│   ├── spawn.sh                          unchanged
│   ├── menu-driver.sh                    unchanged
│   ├── recover-openclaw-agents.sh        unchanged
│   ├── sync-recovery-registry-session-ids.sh  unchanged
│   ├── diagnose-hooks.sh                 MODIFIED (separate scope): fix Step 7 prefix-match + Step 2 script list
│   └── install.sh                        unchanged
├── lib/
│   ├── hook-utils.sh                     MODIFIED: +extract_hook_settings() as 7th function
│   └── hook-preamble.sh                  NEW: extracted 27-line preamble block
├── config/
│   └── ...                               unchanged
└── logs/
    └── ...                               unchanged
```

---

## Architectural Patterns

### Pattern 1: Sourced Preamble via BASH_SOURCE[1]

**What:** A shared setup file (`lib/hook-preamble.sh`) sources into each hook as its first executable line. The preamble uses `BASH_SOURCE[1]` (not `BASH_SOURCE[0]`) to resolve the caller's script name and directory.

**When to use:** Any hook that needs SKILL_LOG_DIR, GSD_HOOK_LOG, HOOK_SCRIPT_NAME, SCRIPT_DIR, debug_log, and lib/hook-utils.sh. That is every hook.

**Trade-offs:**
- Pro: Single preamble definition — a fix in hook-preamble.sh propagates to all 7 hooks
- Pro: New hooks get correct setup for free
- Pro: Hook scripts shrink from ~27 lines of boilerplate to 1 source line
- Con: `BASH_SOURCE[1]` is less familiar than `BASH_SOURCE[0]` — must be documented
- Con: If preamble is missing, all 7 hooks fail identically — but the file-missing guard handles this with a plain printf + exit 0

**Example (in each hook, line 4):**

```bash
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../lib/hook-preamble.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/hook-preamble.sh"

# [guard chain + hook-specific logic follows]
```

**Example (hook-preamble.sh itself):**

```bash
#!/usr/bin/env bash
# lib/hook-preamble.sh — Shared preamble for all GSD hook scripts.
# Sourced as the first action of every hook. Sets up logging, SCRIPT_DIR, and sources hook-utils.sh.
# Uses BASH_SOURCE[1] throughout — the caller's path, not this file's path.
# No set -euo pipefail here — caller sets shell options before sourcing this.

SKILL_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)/logs"
mkdir -p "$SKILL_LOG_DIR"

GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]}")"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" \
    >> "$GSD_HOOK_LOG" 2>/dev/null || true
}

debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"
if [ -f "$LIB_PATH" ]; then
  source "$LIB_PATH"
  debug_log "sourced lib/hook-utils.sh"
else
  printf '[%s] [%s] FATAL: hook-utils.sh not found at %s\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$LIB_PATH" \
    >> "$GSD_HOOK_LOG" 2>/dev/null || true
  exit 0
fi
```

### Pattern 2: extract_hook_settings() — Variable-Setting Function

**What:** A function in `lib/hook-utils.sh` that accepts `registry_path` and `agent_data_json` and sets `PANE_CAPTURE_LINES`, `CONTEXT_PRESSURE_THRESHOLD`, and `HOOK_MODE` in the caller's scope via `printf` + `eval` OR via direct assignment using `declare -g`.

**Recommended approach — direct `declare` (bash 4.2+):** The function uses `declare -g` to set variables in the calling scope. This is cleaner than eval and avoids subshell traps.

**Alternative approach — output JSON + caller parses:** The function echoes a JSON object; the caller parses it with three jq calls. This is pure (no eval, no declare -g) but requires the caller to have three parse lines instead of one function call.

**Recommended approach for this codebase:** Use named output variables with `printf '%s' VAR=VALUE` format (same pattern as bash return-by-reference idioms in lib functions). Given the codebase already uses `2>/dev/null || echo "default"` defensive patterns, `declare -g` with fallbacks is the cleanest fit.

**Implementation:**

```bash
# ==========================================================================
# extract_hook_settings
# ==========================================================================
# Extracts hook_settings fields from registry with three-tier fallback:
#   1. Per-agent hook_settings (agent_data .hook_settings.field)
#   2. Global hook_settings (registry root .hook_settings.field)
#   3. Hardcoded defaults (100, 50, "async")
#
# Arguments:
#   $1 - registry_path: path to recovery-registry.json
#   $2 - agent_data_json: JSON string of matched agent from registry
# Sets in caller scope (via declare -g):
#   PANE_CAPTURE_LINES, CONTEXT_PRESSURE_THRESHOLD, HOOK_MODE
# Returns:
#   0 always (never fails — falls back to hardcoded defaults on jq error)
# ==========================================================================
extract_hook_settings() {
  local registry_path="$1"
  local agent_data_json="$2"

  local global_settings
  global_settings=$(jq -r '.hook_settings // {}' "$registry_path" 2>/dev/null || printf '{}')

  declare -g PANE_CAPTURE_LINES
  PANE_CAPTURE_LINES=$(printf '%s' "$agent_data_json" | jq -r \
    --argjson global "$global_settings" \
    '(.hook_settings.pane_capture_lines // $global.pane_capture_lines // 100)' \
    2>/dev/null || printf '100')

  declare -g CONTEXT_PRESSURE_THRESHOLD
  CONTEXT_PRESSURE_THRESHOLD=$(printf '%s' "$agent_data_json" | jq -r \
    --argjson global "$global_settings" \
    '(.hook_settings.context_pressure_threshold // $global.context_pressure_threshold // 50)' \
    2>/dev/null || printf '50')

  declare -g HOOK_MODE
  HOOK_MODE=$(printf '%s' "$agent_data_json" | jq -r \
    --argjson global "$global_settings" \
    '(.hook_settings.hook_mode // $global.hook_mode // "async")' \
    2>/dev/null || printf 'async')
}
```

**Caller site (before → after):**

```bash
# BEFORE (12 lines inline, 4 copies):
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

# AFTER (1 line):
extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA"
```

**Trade-offs:**
- Pro: One function, zero duplication — the three-tier fallback logic is auditable in one place
- Pro: Adding a new setting requires editing one function, not 4 hook scripts
- Con: `declare -g` requires bash 4.2+ — Ubuntu 24 ships bash 5.2, HIGH confidence this is fine
- Con: Variable setting side effects are less explicit than inline code — mitigated by clear function docstring

### Pattern 3: Wake Message Format Migration ([PANE CONTENT] → [CONTENT])

**What:** Three hooks (`notification-idle-hook.sh`, `notification-permission-hook.sh`, `pre-compact-hook.sh`) use the v1.0/pre-v2.0 `[PANE CONTENT]` section header. The v2.0 format uses `[CONTENT]` with the understanding that content source varies (pane vs transcript). Completing the migration makes all wake messages consistent.

**Migration decision — raw pane vs extracted content:**

For notification hooks (idle_prompt, permission_prompt), the Stop hook fires after Claude finishes responding, so transcript extraction makes sense there. Notification hooks fire on Claude's TUI state changes where there may be no new transcript entry to extract. Raw pane content is therefore correct for notification hooks — the section header change is purely cosmetic (rename `[PANE CONTENT]` → `[CONTENT]`), and `CONTENT_SOURCE` in the JSONL record already distinguishes the source.

For `pre-compact-hook.sh`, same reasoning applies — pane content is the right source, header rename only.

**Example migration:**

```bash
# BEFORE:
WAKE_MESSAGE="...
[PANE CONTENT]
${PANE_CONTENT}
..."

# AFTER:
WAKE_MESSAGE="...
[CONTENT]
${PANE_CONTENT}
..."
```

No functional change — only the header label changes. JSONL `content_source` field (`"pane"`) continues to document the actual source.

---

## Data Flow

### Hook Invocation Flow (after v3.1)

```
Claude Code fires hook event
         |
         v
hook-script.sh starts (PID = $$)

1. set -euo pipefail
2. source lib/hook-preamble.sh
   ├── SKILL_LOG_DIR set, logs/ created
   ├── GSD_HOOK_LOG set (initial: hooks.log)
   ├── HOOK_SCRIPT_NAME set (basename of caller via BASH_SOURCE[1])
   ├── debug_log() defined
   ├── debug_log "FIRED — PID=$$ TMUX=..."  ← written to hooks.log
   ├── SCRIPT_DIR set (caller's scripts/ dir via BASH_SOURCE[1])
   └── lib/hook-utils.sh sourced (all 7 functions available)

3. STDIN_JSON=$(cat); HOOK_ENTRY_MS=$(date +%s%3N)
4. Guards: stop_hook_active (stop only), TMUX env, session name
5. GSD_HOOK_LOG redirected to {SESSION_NAME}.log; JSONL_FILE set
6. Registry lookup via lookup_agent_in_registry()
7. extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA"
   └── sets PANE_CAPTURE_LINES, CONTEXT_PRESSURE_THRESHOLD, HOOK_MODE
8. Hook-specific content extraction + state detection
9. WAKE_MESSAGE assembled with [CONTENT] header (consistent across all hooks)
10. deliver_async_with_logging() or bidirectional openclaw call
    → JSONL record written to {SESSION_NAME}.jsonl
11. exit 0
```

### Source Chain Dependency Graph

```
hook-script.sh
  └──source──► lib/hook-preamble.sh
                 └──source──► lib/hook-utils.sh
                                ├── lookup_agent_in_registry()
                                ├── extract_last_assistant_response()
                                ├── extract_pane_diff()
                                ├── format_ask_user_questions()
                                ├── write_hook_event_record()
                                ├── deliver_async_with_logging()
                                └── extract_hook_settings()  [NEW]
```

**Dependency rule:** hook-preamble.sh MUST be in lib/ (not scripts/) because it sources hook-utils.sh using a relative path from its own location. If preamble is in scripts/, the relative path `../lib/hook-utils.sh` still resolves correctly — but lib/ is the better semantic home since preamble is a library component, not an executable entry point.

---

## Build Order

The refactoring has a strict dependency: hook-preamble.sh and extract_hook_settings() must exist before any hook script is simplified to use them. Within each phase, scripts can be modified in parallel.

```
Phase A — Foundation (must complete before any hook is simplified)
  A1. Create lib/hook-preamble.sh
      - No dependencies
      - Test: source it from a test script, verify all 5 variables set correctly,
              verify lib/hook-utils.sh is sourced (check that lookup_agent_in_registry
              is defined after the source)
      - BASH_SOURCE[1] behavior is the critical correctness point to test

  A2. Add extract_hook_settings() to lib/hook-utils.sh
      - No external dependencies (self-contained jq function)
      - Test: call with a mock registry path and agent_data JSON string,
              verify PANE_CAPTURE_LINES/CONTEXT_PRESSURE_THRESHOLD/HOOK_MODE
              are set in calling scope with correct values

Phase B — Hook Script Refactoring (all depend on Phase A; can parallel within B)
  B1. Refactor stop-hook.sh
      - Replace lines 1-27 with source hook-preamble.sh
      - Replace settings extraction block with extract_hook_settings()
      - Verify: still fires correctly in managed tmux session, JSONL record written

  B2. Refactor notification-idle-hook.sh
      - Replace preamble
      - Replace settings extraction block with extract_hook_settings()
      - Migrate [PANE CONTENT] → [CONTENT]

  B3. Refactor notification-permission-hook.sh
      - Same as B2

  B4. Refactor pre-compact-hook.sh
      - Replace preamble
      - Replace settings extraction block with extract_hook_settings()
      - Migrate [PANE CONTENT] → [CONTENT]
      - Note: pre-compact-hook.sh settings block (lines 81-93) omits 2>/dev/null
              guards that others have — extract_hook_settings() adds them back

  B5. Refactor session-end-hook.sh
      - Replace preamble
      - Add 2>/dev/null || echo "" to AGENT_ID and OPENCLAW_SESSION_ID extraction
        (lines 71-72) — this hook has no settings block (no pane capture)

  B6. Refactor pre-tool-use-hook.sh
      - Replace preamble only — no settings block in this hook
      - Hook already uses printf '%s' correctly

  B7. Refactor post-tool-use-hook.sh
      - Replace preamble only — no settings block in this hook
      - Hook already uses printf '%s' correctly

Phase C — Diagnostic Fixes (independent of Phase B; can run in parallel with B)
  C1. Fix diagnose-hooks.sh Step 7 prefix-match
      - Replace exact tmux_session_name == match with startswith() prefix logic
        (same as lookup_agent_in_registry uses)
      - Alternatively, call lookup_agent_in_registry directly in Step 7

  C2. Fix diagnose-hooks.sh Step 2 script list
      - Add pre-tool-use-hook.sh and post-tool-use-hook.sh to HOOK_SCRIPTS array

Phase D — Documentation Update
  D1. Update docs/hooks.md
      - Document hook-preamble.sh in "Architecture" section
      - Document extract_hook_settings() in "Shared Library" section
      - Note [CONTENT] now consistent across all 7 hooks

  D2. Update SKILL.md and README.md if materially impacted
```

**Parallelization note:** Phases A1 and A2 can be done in one task (both are modifications to lib/ files). Phases B1-B7 can all be done in one task once Phase A is complete — they are independent of each other. Phase C can be done in the same task as Phase B since it touches a different file. Phase D completes last.

**Recommended task split for Warden:**
- Task 1: Phase A (foundation) — create hook-preamble.sh + add extract_hook_settings()
- Task 2: Phase B + C (all hook refactoring + diagnose fixes) — depends on Task 1
- Task 3: Phase D (documentation) — depends on Task 2

---

## Integration Points

### What Each Hook Loses and What It Gains

| Hook | Lines Removed | Lines Added | Net Change |
|------|---------------|-------------|------------|
| stop-hook.sh | 27 (preamble) + 12 (settings) = 39 | 1 (source preamble) + 1 (extract_hook_settings call) = 2 | -37 lines |
| notification-idle-hook.sh | 27 + 12 = 39 | 2 | -37 lines |
| notification-permission-hook.sh | 27 + 12 = 39 | 2 | -37 lines |
| pre-compact-hook.sh | 27 + 12 = 39 | 2 | -37 lines |
| session-end-hook.sh | 27 | 1 + 2 (guards) = 3 | -24 lines |
| pre-tool-use-hook.sh | 27 | 1 | -26 lines |
| post-tool-use-hook.sh | 27 | 1 | -26 lines |

Total reduction: approximately 224 lines across 7 hook scripts, centralized into 27 lines in hook-preamble.sh + 20 lines in hook-utils.sh.

### hook-preamble.sh vs hook-utils.sh Separation

The key distinction between what goes in hook-preamble.sh and what goes in hook-utils.sh:

| Concern | Where | Reason |
|---------|-------|--------|
| SKILL_LOG_DIR, GSD_HOOK_LOG setup | hook-preamble.sh | Must run before debug_log is usable — bootstrap concern |
| HOOK_SCRIPT_NAME, SCRIPT_DIR | hook-preamble.sh | Depends on BASH_SOURCE[1] (the caller) — only valid in preamble context |
| debug_log() definition | hook-preamble.sh | Used before lib is sourced (for the "FIRED" log line) |
| Sourcing lib/hook-utils.sh | hook-preamble.sh | preamble bootstraps the library chain |
| extract_hook_settings() | hook-utils.sh | Pure function, no BASH_SOURCE dependency, testable in isolation |
| All existing functions | hook-utils.sh | Unchanged location |

**Why not put extract_hook_settings() in hook-preamble.sh:** Preamble is a bootstrap script with side effects (sets variables, creates directories, sources lib). hook-utils.sh is a pure function library with no side effects. Mixing the two concerns would violate the existing design invariant documented in lib/hook-utils.sh line 4: "Contains ONLY function definitions - no side effects on source." extract_hook_settings() belongs in hook-utils.sh because it is a pure function.

### Behavioral Equivalence Verification

After refactoring, each hook must behave identically to its v3.0 version. Verification checklist per hook:

1. `debug_log "FIRED"` still appears in hooks.log with correct HOOK_SCRIPT_NAME
2. SKILL_LOG_DIR points to the correct skill-local logs/ directory
3. SCRIPT_DIR resolves to the hook's scripts/ directory (needed for REGISTRY_PATH)
4. lib/hook-utils.sh functions are available (lookup_agent_in_registry etc.)
5. JSONL record is written to logs/{SESSION_NAME}.jsonl after hook completes
6. Guard exits (no TMUX, no registry match) still exit 0 without JSONL emission

The only way SCRIPT_DIR can be wrong is if BASH_SOURCE[1] is empty or wrong. This happens if hook-preamble.sh is sourced from a context where BASH_SOURCE has fewer than 2 entries. Testing the preamble from a sourced script (not directly executed) is the critical test case.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Using BASH_SOURCE[0] in hook-preamble.sh

**What people do:** Copy the existing inline preamble into hook-preamble.sh without changing `BASH_SOURCE[0]` to `BASH_SOURCE[1]`.

**Why it's wrong:** Inside hook-preamble.sh, `BASH_SOURCE[0]` is `hook-preamble.sh` itself, not the calling hook. `HOOK_SCRIPT_NAME` would be `hook-preamble.sh`, `SCRIPT_DIR` would be `lib/`, and the registry path `${SCRIPT_DIR}/../config/` would resolve to the skill root's config/ — which is actually correct by accident, but `HOOK_SCRIPT_NAME` in logs would show `hook-preamble.sh` instead of `stop-hook.sh`.

**Do this instead:** Use `BASH_SOURCE[1]` for `HOOK_SCRIPT_NAME`, `SKILL_LOG_DIR`, and `SCRIPT_DIR`. Write a test that verifies the hook script name appears correctly in debug output after refactoring.

### Anti-Pattern 2: Putting hook-preamble.sh in scripts/

**What people do:** Place hook-preamble.sh next to the hook scripts in scripts/ for locality.

**Why it's wrong:** hook-preamble.sh is not an executable entry point — it has no meaningful behavior when run directly. It is a sourced library component. Placing it in scripts/ mixes two concerns and would require updating `source` paths in all hooks to `source "${SCRIPT_DIR}/hook-preamble.sh"` rather than `source "${SCRIPT_DIR}/../lib/hook-preamble.sh"`. More importantly, it would be included in the diagnose-hooks.sh Step 2 executable script list check, causing false failures.

**Do this instead:** Place hook-preamble.sh in lib/ alongside hook-utils.sh. The source path from hooks is `$(dirname "${BASH_SOURCE[0]}")/../lib/hook-preamble.sh` — same relative structure as the existing lib/hook-utils.sh source pattern.

### Anti-Pattern 3: extract_hook_settings() Using Subshell Return

**What people do:** Have `extract_hook_settings()` echo a JSON object and require the caller to parse it with three separate jq calls.

**Why it's wrong:** It defeats the purpose of the function — the caller still has to write parsing code. The call site becomes two lines instead of twelve, but three of those lines are still jq parsing. The total reduction is less than using direct variable assignment.

**Do this instead:** Use `declare -g` to set PANE_CAPTURE_LINES, CONTEXT_PRESSURE_THRESHOLD, and HOOK_MODE directly in the caller's scope. Document this clearly in the function header. The calling hook site becomes a single `extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA"` line.

### Anti-Pattern 4: Changing hook-utils.sh Side-Effect Contract

**What people do:** Add initialization code (mkdir -p, variable assignments) to hook-utils.sh when adding extract_hook_settings().

**Why it's wrong:** lib/hook-utils.sh line 4 documents its invariant: "Contains ONLY function definitions - no side effects on source." This is why it can be safely sourced before guards in all 7 hooks. Violating this invariant means sourcing hook-utils.sh could fail partway through (e.g., mkdir fails), leaving functions only partially defined.

**Do this instead:** extract_hook_settings() is a pure function with no side effects. The `declare -g` inside the function body is not a side effect of sourcing the library — it only executes when the function is called. This is compliant with the no-side-effects contract.

### Anti-Pattern 5: Migrating [PANE CONTENT] Without Verifying Downstream Consumers

**What people do:** Rename `[PANE CONTENT]` to `[CONTENT]` in wake messages without checking whether Gideon's prompt or parsing logic depends on the exact header text.

**Why it is low risk here (but worth verifying):** STATE.md documents that Gideon consumes wake messages as free-text via LLM — there is no hardcoded parser. The v2.0 format change was confirmed non-breaking for the same reason. However, if any downstream scripts (not agents) grep for `[PANE CONTENT]`, they would break.

**Do this instead:** Search the codebase for literal `[PANE CONTENT]` references before renaming. Confirmed safe to change based on the v2.0 precedent documented in STATE.md.

---

## Scaling Considerations

This is not a user-scale system. The relevant scaling axis is: how many hook scripts fire concurrently across managed sessions.

| Scale | Current behavior | Risk |
|-------|-----------------|------|
| 1 session, 1 hook type | Fully working | None |
| 2-3 sessions, concurrent Stop fires | flock serializes JSONL writes | Handled by existing flock in write_hook_event_record |
| 7 hooks + 3 sessions simultaneously | 21 concurrent processes, all sourcing hook-preamble.sh | Sourcing a 25-line file is effectively zero overhead |
| hook-preamble.sh missing | All 7 hooks fail their preamble check | Same failure mode as hook-utils.sh missing — degrades to plain printf + exit 0 |

The refactoring does not change any concurrent access patterns. The flock guards in extract_pane_diff() and write_hook_event_record() are unchanged.

---

## Sources

**HIGH confidence (direct source inspection — all files read in full):**
- `lib/hook-utils.sh` — 6 functions, design contract at line 4, exact signatures
- `scripts/stop-hook.sh` — full preamble block, settings block, bidirectional branch
- `scripts/notification-idle-hook.sh` — [PANE CONTENT] header confirmed, settings block identical to stop-hook
- `scripts/notification-permission-hook.sh` — same as idle hook
- `scripts/session-end-hook.sh` — missing 2>/dev/null guards at lines 71-72 confirmed
- `scripts/pre-compact-hook.sh` — [PANE CONTENT] confirmed, settings block without 2>/dev/null confirmed
- `scripts/pre-tool-use-hook.sh` — no settings block, uses printf '%s' correctly
- `scripts/post-tool-use-hook.sh` — no settings block, uses printf '%s' correctly
- `docs/v3-retrospective.md` — 8 improvement items with exact file:line citations that validated all findings above
- `STATE.md` — phase decisions, wake message parsing is LLM not hardcoded parser (migration safety)
- `ROADMAP.md` — v3.0 confirmed shipped, v3.1 scope established

**HIGH confidence (bash language semantics):**
- `BASH_SOURCE[0]` vs `BASH_SOURCE[1]` in sourced scripts — documented bash behavior, standard usage in all shell scripting references
- `declare -g` available in bash 4.2+, Ubuntu 24 ships bash 5.2 — HIGH confidence
- `set -euo pipefail` in caller does not propagate to lib source behavior — confirmed by existing hook-utils.sh design (no set -e in library)

---

*Architecture research for: gsd-code-skill v3.1 Hook Refactoring & Migration Completion*
*Researched: 2026-02-18*
*Confidence: HIGH — all 7 hook scripts and lib files read in full, integration points mapped to exact line numbers, source chain validated against bash BASH_SOURCE semantics*
