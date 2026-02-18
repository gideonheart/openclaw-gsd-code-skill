# Architecture Research: v3.0 Structured Hook Observability

**Domain:** Hook-driven OpenClaw agent control — structured JSONL event logging integration
**Researched:** 2026-02-18
**Confidence:** HIGH

## System Overview

### Current Architecture (v2.0 — shipping state)

```
Claude Code Session (tmux pane)
         |
         | hook event fires
         v
┌──────────────────────────────────────────────────────────┐
│              6 Hook Entry Points (SRP, one per event)    │
│                                                          │
│  stop-hook.sh              (Stop event)                  │
│  pre-tool-use-hook.sh      (PreToolUse/AskUserQuestion)  │
│  notification-idle-hook.sh (Notification/idle)           │
│  notification-permission-hook.sh (Notification/perm)     │
│  session-end-hook.sh       (SessionEnd)                  │
│  pre-compact-hook.sh       (PreCompact)                  │
│                                                          │
│  Each script: inline debug_log() → plain-text line       │
│  Format: [ISO8601] [script-name] message text            │
│  Target: $GSD_HOOK_LOG (hooks.log → SESSION.log)         │
└──────────────┬───────────────────────────────────────────┘
               |
               | source lib/hook-utils.sh (stop + pre-tool-use only)
               v
┌──────────────────────────────────────────────────────────┐
│    lib/hook-utils.sh — 4 shared extraction functions     │
│                                                          │
│  lookup_agent_in_registry()                              │
│  extract_last_assistant_response()                       │
│  extract_pane_diff()                                     │
│  format_ask_user_questions()                             │
└──────────────┬───────────────────────────────────────────┘
               |
               | openclaw agent --session-id UUID --message MSG
               |   async (background &) — response dumps to log as raw text
               |   bidirectional (foreground) — response parsed for decision
               v
┌──────────────────────────────────────────────────────────┐
│    logs/ directory (skill-local)                         │
│                                                          │
│  hooks.log              — pre-session plain-text lines   │
│  {SESSION_NAME}.log     — per-session plain-text lines   │
│  gsd-pane-prev-{SESSION}.txt  — pane state file          │
│  gsd-pane-lock-{SESSION}      — flock coordination file  │
└──────────────────────────────────────────────────────────┘
```

**Current problem:** `openclaw agent` async responses dump as raw unlabeled text into the log
file. Plain-text debug_log lines are not machine-parseable. No way to correlate which response
belongs to which hook invocation. No way to reconstruct the full lifecycle of a hook interaction
programmatically.

### Target Architecture (v3.0)

```
Claude Code Session (tmux pane)
         |
         | hook event fires
         v
┌──────────────────────────────────────────────────────────┐
│              6 Hook Entry Points (unchanged structure)   │
│                                                          │
│  stop-hook.sh              (Stop event)    MODIFIED      │
│  pre-tool-use-hook.sh      (PreToolUse)    MODIFIED      │
│  notification-idle-hook.sh                MODIFIED       │
│  notification-permission-hook.sh          MODIFIED       │
│  session-end-hook.sh                      MODIFIED       │
│  pre-compact-hook.sh                      MODIFIED       │
│                                                          │
│  Replace: debug_log() inline function                    │
│  With: source lib/hook-utils.sh + jsonl_log() calls      │
└──────────────┬───────────────────────────────────────────┘
               |
               | source lib/hook-utils.sh (ALL 6 hooks now)
               v
┌──────────────────────────────────────────────────────────┐
│    lib/hook-utils.sh — EXTENDED (new functions added)    │
│                                                          │
│  [Existing, unchanged]                                   │
│  lookup_agent_in_registry()                              │
│  extract_last_assistant_response()                       │
│  extract_pane_diff()                                     │
│  format_ask_user_questions()                             │
│                                                          │
│  [New in v3.0]                                           │
│  generate_correlation_id()    — printf '%s' "$(date...)" │
│  jsonl_log()                  — write one JSONL event    │
│  log_hook_request()           — request event wrapper    │
│  log_hook_response()          — response event wrapper   │
│  deliver_async_with_logging() — wrap openclaw + capture  │
└──────────────┬───────────────────────────────────────────┘
               |
               | openclaw captured via deliver_async_with_logging()
               v
┌──────────────────────────────────────────────────────────┐
│    logs/ directory (skill-local)                         │
│                                                          │
│  hooks.log              — JSONL events pre-session       │
│  {SESSION_NAME}.log     — JSONL events per-session       │
│  gsd-pane-prev-{SESSION}.txt  — unchanged (pane state)   │
│  gsd-pane-lock-{SESSION}      — unchanged (flock)        │
└──────────────────────────────────────────────────────────┘
```

---

## Component Boundaries

### New Components (v3.0 additions to lib/hook-utils.sh)

| Function | Responsibility | Notes |
|----------|----------------|-------|
| `generate_correlation_id()` | Produce a unique ID linking request + response events for one hook invocation | Called once per hook script execution, stored in local variable |
| `jsonl_log()` | Serialize a JSONL event record to the log file atomically | Receives field values, calls `jq -n` to build valid JSON, appends one line |
| `log_hook_request()` | Emit a `hook.request` event — the wake message and metadata being sent to OpenClaw | Called immediately before the `openclaw` call |
| `log_hook_response()` | Emit a `hook.response` event — the raw response from OpenClaw and outcome | Called from inside the async wrapper after OpenClaw returns |
| `deliver_async_with_logging()` | Replace the bare `openclaw ... &` pattern with a wrapper that captures response and logs it | Called instead of bare `openclaw agent ... >> $GSD_HOOK_LOG 2>&1 &` |

### Modified Components

| Component | Current State | v3.0 Change |
|-----------|--------------|-------------|
| `lib/hook-utils.sh` | 4 extraction functions, 150 lines | Add 5 new functions for JSONL logging |
| `stop-hook.sh` | Inline `debug_log()`, bare `openclaw &` | Remove inline `debug_log`, source lib earlier, call `jsonl_log` at key steps, use `deliver_async_with_logging` |
| `pre-tool-use-hook.sh` | Inline `debug_log()`, bare `openclaw &` | Same as stop-hook.sh pattern |
| `notification-idle-hook.sh` | Inline `debug_log()`, bare `openclaw &` | Same pattern — lib sourced before registry lookup (earlier than v2.0) |
| `notification-permission-hook.sh` | Same as idle hook | Same pattern |
| `session-end-hook.sh` | Inline `debug_log()`, bare `openclaw &` | Same pattern |
| `pre-compact-hook.sh` | Inline `debug_log()`, bare `openclaw &` | Same pattern |

### Unchanged Components

| Component | Reason |
|-----------|--------|
| `lookup_agent_in_registry()` | No change to registry lookup logic |
| `extract_last_assistant_response()` | No change to extraction logic |
| `extract_pane_diff()` | No change to diff logic |
| `format_ask_user_questions()` | No change to formatting logic |
| `spawn.sh`, `menu-driver.sh` | Not hook scripts — no debug_log involvement |
| `register-hooks.sh` | Hook registration unchanged |
| `config/recovery-registry.json` | Schema unchanged |
| `logs/` pane state files | gsd-pane-prev-*, gsd-pane-lock-* unchanged |

---

## Recommended File Structure After v3.0

```
gsd-code-skill/
├── scripts/
│   ├── stop-hook.sh                  MODIFIED: remove inline debug_log, use lib
│   ├── pre-tool-use-hook.sh          MODIFIED: same
│   ├── notification-idle-hook.sh     MODIFIED: same
│   ├── notification-permission-hook.sh  MODIFIED: same
│   ├── session-end-hook.sh           MODIFIED: same
│   ├── pre-compact-hook.sh           MODIFIED: same
│   ├── register-hooks.sh             unchanged
│   ├── spawn.sh                      unchanged
│   ├── menu-driver.sh                unchanged
│   ├── recover-openclaw-agents.sh    unchanged
│   ├── sync-recovery-registry-session-ids.sh  unchanged
│   └── diagnose-hooks.sh             unchanged (may warrant update)
├── lib/
│   └── hook-utils.sh                 MODIFIED: +5 new JSONL logging functions
├── config/
│   ├── recovery-registry.json        unchanged
│   ├── recovery-registry.example.json  unchanged
│   └── default-system-prompt.txt     unchanged
└── logs/
    ├── hooks.log                     now JSONL (one JSON object per line)
    ├── {SESSION_NAME}.log            now JSONL (one JSON object per line)
    ├── gsd-pane-prev-{SESSION}.txt   unchanged
    └── gsd-pane-lock-{SESSION}       unchanged
```

**Structure rationale:**

- **lib/hook-utils.sh extension:** All new JSONL logic lives in the single shared library. Six hook scripts all source it — no duplication. Single fix point for any JSONL serialization bug.
- **No new files:** v3.0 adds functions to an existing file, not new lib files. The logging concern is small enough that a separate `lib/jsonl-log.sh` would be over-engineering. One shared library with clear function namespacing is sufficient.
- **logs/ format change:** The log files transition from plain-text to JSONL. Same file paths, same two-phase routing. Consumers (humans, future dashboard) can parse with `jq` per line.

---

## JSONL Event Schema

Every log entry is one JSON object on one line (standard JSONL). Two event types cover the full hook lifecycle.

### Event Type: `hook.request`

Emitted immediately before the `openclaw agent` call. Captures everything that was sent.

```json
{
  "event": "hook.request",
  "ts": "2026-02-18T14:22:01Z",
  "correlation_id": "warden-main-3_stop-hook_1708262521_42761",
  "hook": "stop-hook.sh",
  "session": "warden-main-3",
  "agent_id": "warden",
  "openclaw_session_id": "d52a3453-3ac6-464b-9533-681560695394",
  "trigger": "response_complete",
  "mode": "async",
  "wake_message": "[SESSION IDENTITY]\nagent_id: warden\n..."
}
```

### Event Type: `hook.response`

Emitted from inside the async wrapper after `openclaw` returns. Captures the raw response and outcome classification.

```json
{
  "event": "hook.response",
  "ts": "2026-02-18T14:22:03Z",
  "correlation_id": "warden-main-3_stop-hook_1708262521_42761",
  "hook": "stop-hook.sh",
  "session": "warden-main-3",
  "openclaw_session_id": "d52a3453-3ac6-464b-9533-681560695394",
  "exit_code": 0,
  "raw_response": "OK message queued",
  "outcome": "delivered"
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `event` | string | yes | `"hook.request"` or `"hook.response"` |
| `ts` | ISO8601 | yes | UTC timestamp at event emission time |
| `correlation_id` | string | yes | Links request + response for one hook invocation |
| `hook` | string | yes | Script filename (`stop-hook.sh`, etc.) |
| `session` | string | yes | tmux session name; empty string if not yet known |
| `agent_id` | string | request only | Agent identifier from registry |
| `openclaw_session_id` | string | yes | OpenClaw session UUID |
| `trigger` | string | request only | Hook trigger type (matches `[TRIGGER] type:` value) |
| `mode` | string | request only | `"async"` or `"bidirectional"` |
| `wake_message` | string | request only | Full wake message body sent to OpenClaw |
| `exit_code` | integer | response only | Exit code of `openclaw` command |
| `raw_response` | string | response only | Raw stdout+stderr from `openclaw` (trimmed) |
| `outcome` | string | response only | `"delivered"`, `"error"`, `"blocked"` |

---

## Architectural Patterns

### Pattern 1: Separate Library for JSONL Logic — Not Extending Inline

**What:** All JSONL serialization and logging functions live in `lib/hook-utils.sh`, not inline in each hook script. Hook scripts call `jsonl_log()` or higher-level wrappers.

**When to use:** Any logging behavior that 2+ scripts need.

**Trade-offs:**
- Pro: Single fix point — fix `jsonl_log()` once, all 6 scripts benefit
- Pro: Hook scripts stay thin (SRP preserved)
- Pro: `jq -n` inside the lib function handles all JSON escaping — no inline jq in hooks
- Con: All 6 scripts now source lib (v2.0 was stop + pre-tool-use only). Sourcing adds ~1ms overhead. Acceptable — hooks run in the 5-100ms range.

**Why not a separate `lib/jsonl-log.sh`:** The logging concern does not warrant a second lib file. hook-utils.sh grows from ~150 lines to ~220 lines — still a single-responsibility shared utility file. A separate file adds path management without benefit.

**Example (in hook script):**

```bash
# At top of hook, after SKILL_LOG_DIR + GSD_HOOK_LOG setup:
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/hook-utils.sh"
source "$LIB_PATH"

# Generate once per invocation:
CORRELATION_ID=$(generate_correlation_id "$SESSION_NAME" "$HOOK_SCRIPT_NAME")

# Before delivery:
log_hook_request "$CORRELATION_ID" "$HOOK_SCRIPT_NAME" "$SESSION_NAME" \
  "$AGENT_ID" "$OPENCLAW_SESSION_ID" "$TRIGGER_TYPE" "$HOOK_MODE" "$WAKE_MESSAGE"

# Delivery (replaces bare openclaw & call):
deliver_async_with_logging "$CORRELATION_ID" "$HOOK_SCRIPT_NAME" \
  "$SESSION_NAME" "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE"
```

### Pattern 2: correlation_id Generation — Timestamp Plus PID

**What:** `generate_correlation_id()` produces a string combining session name, script name, Unix timestamp in seconds, and shell PID.

**Why timestamp + PID:** No UUID generator is guaranteed available in bash without external tools. `date +%s` is standard. `$$` (PID) is unique per process invocation. Together they produce a collision-resistant identifier within the scope of a single host and session.

**Why not just PID alone:** PIDs recycle. Two hook fires with the same PID (reuse across session lifetime) would collide.

**Why not `uuidgen`:** Not guaranteed installed. `date +%s%N` (nanoseconds) + `$$` is sufficient and universally available.

**Implementation:**

```bash
generate_correlation_id() {
  local session_name="$1"
  local hook_script_name="$2"
  printf '%s_%s_%s_%s' \
    "${session_name:-unknown}" \
    "${hook_script_name%.sh}" \
    "$(date -u +'%s')" \
    "$$"
}
```

**Example output:** `warden-main-3_stop-hook_1708262521_42761`

**Confidence:** HIGH. Collision-free within realistic operating parameters (one session, multiple hook invocations per minute, PID reuse unlikely within a single tmux session lifetime).

### Pattern 3: Async Response Capture via Background Subshell with Temp File

**What:** The async delivery path (`openclaw ... &`) currently dumps to the log via `>> $GSD_HOOK_LOG 2>&1 &`. This is unstructured. To capture the response and write a structured `hook.response` event, a wrapper function runs in background: it captures stdout+stderr to a temp variable, then calls `log_hook_response()`.

**Why temp file approach is NOT needed:** The response can be captured inside a background subshell via command substitution. The subshell then calls `log_hook_response()` which calls `jsonl_log()` which appends to the log. No intermediary temp file required.

**Why stdout capture works here:** `openclaw agent --session-id UUID --message MSG` returns a short confirmation string (e.g., `"OK message queued"` or an error). This is not multi-megabyte output. Command substitution is safe.

**Implementation:**

```bash
deliver_async_with_logging() {
  local correlation_id="$1"
  local hook_script_name="$2"
  local session_name="$3"
  local openclaw_session_id="$4"
  local wake_message="$5"

  # Run in background — hook exits immediately, subshell handles capture + logging
  (
    local raw_response
    local exit_code
    raw_response=$(openclaw agent \
      --session-id "$openclaw_session_id" \
      --message "$wake_message" 2>&1) && exit_code=0 || exit_code=$?

    local outcome
    if [ "$exit_code" -eq 0 ]; then
      outcome="delivered"
    else
      outcome="error"
    fi

    log_hook_response \
      "$correlation_id" \
      "$hook_script_name" \
      "$session_name" \
      "$openclaw_session_id" \
      "$exit_code" \
      "$raw_response" \
      "$outcome"
  ) &
}
```

**Critical constraint:** The background subshell must not inherit `set -e` from the caller in a way that causes it to exit on non-zero `openclaw` exit code before capturing `exit_code`. The `&& exit_code=0 || exit_code=$?` pattern handles this correctly.

### Pattern 4: jsonl_log() Uses jq -n for Safe JSON Serialization

**What:** All JSONL event serialization goes through `jq -n` with `--arg` for string fields. Never string-interpolate JSON manually.

**Why:** Wake messages contain newlines, quotes, backslashes, and Unicode. Manual string interpolation produces malformed JSON. `jq -n --arg field "$value"` handles all escaping correctly.

**Why not `printf '%s\n' "$json"` with manually built JSON:** A wake message like `"What can I help\nyou with?"` would break a manually assembled JSON string immediately. `jq` is already a hard dependency of all hook scripts.

**Implementation:**

```bash
jsonl_log() {
  local log_file="$1"
  local event_type="$2"
  local correlation_id="$3"
  local hook_script_name="$4"
  local session_name="$5"
  # Additional fields passed as name=value pairs via remaining args
  # OR: use a single pre-built jq expression per event type

  # Simpler: each event type has its own dedicated function that builds
  # the correct jq expression. jsonl_log() is just the atomic append primitive.
  jq -cn "$@" >> "$log_file" 2>/dev/null || true
}
```

**Preferred approach — dedicated builder per event type:**

```bash
log_hook_request() {
  local correlation_id="$1"
  local hook_script_name="$2"
  local session_name="$3"
  local agent_id="$4"
  local openclaw_session_id="$5"
  local trigger_type="$6"
  local hook_mode="$7"
  local wake_message="$8"

  jq -cn \
    --arg event "hook.request" \
    --arg ts "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --arg correlation_id "$correlation_id" \
    --arg hook "$hook_script_name" \
    --arg session "$session_name" \
    --arg agent_id "$agent_id" \
    --arg openclaw_session_id "$openclaw_session_id" \
    --arg trigger "$trigger_type" \
    --arg mode "$hook_mode" \
    --arg wake_message "$wake_message" \
    '{event: $event, ts: $ts, correlation_id: $correlation_id,
      hook: $hook, session: $session, agent_id: $agent_id,
      openclaw_session_id: $openclaw_session_id, trigger: $trigger,
      mode: $mode, wake_message: $wake_message}' \
    >> "$GSD_HOOK_LOG" 2>/dev/null || true
}
```

**The `|| true` is mandatory:** Log failures must never propagate. Hooks must always exit 0 for Claude Code. A full disk or permission error on the log file should not break the session.

---

## Data Flow

### Full Hook Lifecycle (async mode)

```
Claude Code fires hook event
         |
         v
hook-script.sh starts (PID = $$)

1. SKILL_LOG_DIR + GSD_HOOK_LOG set (Phase 1: hooks.log)
2. source lib/hook-utils.sh
3. CORRELATION_ID = generate_correlation_id(SESSION_NAME, HOOK_SCRIPT_NAME)
4. stdin consumed (STDIN_JSON = cat)
5. Guards: stop_hook_active, TMUX env, SESSION_NAME extraction
6. Phase 2: GSD_HOOK_LOG = logs/{SESSION_NAME}.log
7. Registry lookup: AGENT_DATA, AGENT_ID, OPENCLAW_SESSION_ID
8. hook_settings extraction (pane_capture_lines, hook_mode, etc.)
9. Content extraction (pane capture, transcript, diff — per hook type)
10. State detection, context pressure
11. WAKE_MESSAGE assembled
         |
12. log_hook_request(CORRELATION_ID, ..., WAKE_MESSAGE)
    → jq -cn ... >> GSD_HOOK_LOG      [hook.request event written]
         |
13. deliver_async_with_logging(CORRELATION_ID, ..., WAKE_MESSAGE)
    → background subshell launched (&)
         |
14. hook script exits 0                [Claude Code proceeds immediately]
         |
         | (in background, after hook exits)
         v
    subshell: openclaw agent --session-id UUID --message MSG
    raw_response = captured stdout+stderr
    exit_code captured
         |
    log_hook_response(CORRELATION_ID, ..., raw_response, outcome)
    → jq -cn ... >> GSD_HOOK_LOG      [hook.response event written]
    subshell exits
```

### Full Hook Lifecycle (bidirectional mode)

```
[Steps 1-11 identical to async]
         |
12. log_hook_request(CORRELATION_ID, ..., WAKE_MESSAGE)
    → jq -cn ... >> GSD_HOOK_LOG      [hook.request event written]
         |
13. RESPONSE = openclaw agent --session-id UUID --message MSG --json
    (synchronous — hook blocks here until OpenClaw responds)
    exit_code captured
         |
14. DECISION = jq -r '.decision' <<< "$RESPONSE"
    if DECISION == "block": echo JSON to stdout (Claude Code sees it)
         |
15. log_hook_response(CORRELATION_ID, ..., RESPONSE, outcome)
    → jq -cn ... >> GSD_HOOK_LOG      [hook.response event written]
         |
16. hook script exits 0
```

### Correlation ID Lifetime

```
Hook invocation starts
  CORRELATION_ID generated (local variable in hook script)
       |
  hook.request event written (CORRELATION_ID embedded)
       |
  Background subshell inherits CORRELATION_ID via closure
       |
  hook.response event written (same CORRELATION_ID)

Result: grep correlation_id logs/warden-main-3.log | jq -r '.correlation_id'
        produces matched pairs linkable with jq select()
```

---

## Integration Points

### What Changes in Each Hook Script

All 6 hooks follow the same modification pattern. The changes are mechanical (find-and-replace pattern).

| Hook Script | Remove | Add | Notes |
|-------------|--------|-----|-------|
| All 6 | Inline `debug_log()` function definition (4 lines) | `source lib/hook-utils.sh` moved earlier (before stdin consume) | lib sourced once, provides both old extraction functions and new logging functions |
| All 6 | `debug_log "..."` calls | `jsonl_log` / inline `jq -cn` calls at key milestones | Replace plain-text diagnostic with JSONL event at meaningful lifecycle points |
| All 6 | Bare `openclaw ... >> $GSD_HOOK_LOG 2>&1 &` | `log_hook_request(...)` then `deliver_async_with_logging(...)` | The two-step replaces the single bare call |
| stop-hook.sh only | Bare bidirectional `openclaw ... --json` call | `log_hook_request(...)` then synchronous openclaw then `log_hook_response(...)` | Bidirectional needs inline response capture, not `deliver_async_with_logging` |
| pre-tool-use-hook.sh | Always async, no `--json` mode | Same async pattern as notification hooks | pre-tool-use always exits 0 immediately |

### Where lib/hook-utils.sh Is Sourced (Before vs After)

**Before (v2.0):** lib sourced after guards (after TMUX check, after session extraction, after registry path check) — line 60-68 in most scripts.

**After (v3.0):** lib sourced at top of script, before stdin consume. Reason: `generate_correlation_id()` and `jsonl_log()` must be available for pre-guard logging (e.g., logging the "FIRED" event with the correlation_id attached from the start).

**Impact:** The lib sourcing failure path (`debug_log "EXIT: hook-utils.sh not found"`) must itself use `jsonl_log` if lib loaded, or fall back to plain printf if lib not found. The `|| true` pattern in all lib functions makes this safe.

### Log File Format Change

The two log files (`hooks.log`, `{SESSION_NAME}.log`) transition from plain-text to JSONL. This is a breaking change in file format. Consumers:

- `diagnose-hooks.sh` — reads these files; may need updating to parse JSONL
- Human operators tailing the log — `tail -f logs/warden-main-3.log | jq .` is the new idiom
- Future dashboard — benefits from JSONL directly (no parsing layer needed)

### New Hook Script Boilerplate (v3.0 pattern)

```bash
#!/usr/bin/env bash
set -euo pipefail

SKILL_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$SKILL_LOG_DIR"
GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Source lib early — provides jsonl_log, generate_correlation_id, and all extraction functions
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/hook-utils.sh"
if [ -f "$LIB_PATH" ]; then
  source "$LIB_PATH"
else
  # Fallback: lib missing, plain-text log and exit
  printf '[%s] [%s] EXIT: lib/hook-utils.sh not found\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" >> "$GSD_HOOK_LOG" 2>/dev/null || true
  exit 0
fi

CORRELATION_ID=$(generate_correlation_id "${SESSION_NAME:-unknown}" "$HOOK_SCRIPT_NAME")
jsonl_log_fired "$CORRELATION_ID" "$HOOK_SCRIPT_NAME" "${SESSION_NAME:-unknown}"

# [rest of existing guard + extraction + delivery logic]
```

---

## Build Order and Dependencies

```
Step 1: Extend lib/hook-utils.sh (MODIFIED)
  - No external dependencies
  - Add: generate_correlation_id, jsonl_log, log_hook_request,
         log_hook_response, deliver_async_with_logging
  - Keep: all 4 existing functions unchanged
  - Test: source in bash, call each function, verify JSONL output with jq

Step 2: Modify stop-hook.sh (MODIFIED)
  - Depends on: Step 1 (lib extended)
  - Changes: source lib earlier, add CORRELATION_ID, replace debug_log,
             replace bare openclaw calls with logging wrappers
  - Test: run in managed tmux session, tail logs/{session}.log | jq .

Step 3: Modify pre-tool-use-hook.sh (MODIFIED)
  - Depends on: Step 1
  - Changes: same pattern as stop-hook
  - Can parallel with Step 2 (different file)

Step 4: Modify notification-idle-hook.sh (MODIFIED)
  - Depends on: Step 1
  - Changes: same pattern
  - Can parallel with Steps 2-3

Step 5: Modify notification-permission-hook.sh (MODIFIED)
  - Depends on: Step 1
  - Changes: same pattern
  - Can parallel with Steps 2-4

Step 6: Modify session-end-hook.sh (MODIFIED)
  - Depends on: Step 1
  - Changes: same pattern (always async, no bidirectional branch)
  - Can parallel with Steps 2-5

Step 7: Modify pre-compact-hook.sh (MODIFIED)
  - Depends on: Step 1
  - Changes: same pattern
  - Can parallel with Steps 2-6

Step 8: Update diagnose-hooks.sh (MODIFIED, if applicable)
  - Depends on: Steps 2-7 (log format changed)
  - Changes: update any plain-text log parsing to jq parsing
```

**Parallelization:** Steps 2-7 are all independent of each other. They only depend on Step 1. A Warden session can implement all 6 hook script changes in a single task after lib is extended.

**Migration safety:** The `|| true` pattern in `jsonl_log` means any failure to write JSONL degrades silently. The hook continues, Claude Code is unaffected.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Building JSON via String Interpolation

**What people do:** `echo "{\"event\": \"hook.request\", \"session\": \"${SESSION_NAME}\", ...}"` to build JSON.

**Why it's wrong:** Session names, wake messages, and agent responses contain quotes, newlines, and backslashes. String interpolation produces invalid JSON on first special character encountered.

**Do this instead:** Use `jq -cn --arg field "$value" ...` for all JSONL serialization. `jq` handles all escaping. This is not negotiable.

### Anti-Pattern 2: Capturing Response Outside Background Subshell

**What people do:** `openclaw agent ... >> $GSD_HOOK_LOG 2>&1 &` and try to read the log file afterward to find the response.

**Why it's wrong:** The background process appends to the log asynchronously. The hook script exits before the response arrives. There is no reliable way to read back just that response from the shared log file.

**Do this instead:** Capture the response inside the background subshell itself via command substitution. The subshell has the `CORRELATION_ID` in scope and can write the paired `hook.response` event directly.

### Anti-Pattern 3: Sourcing lib After Guards in v3.0

**What people do:** Keep the lib source at line 60 (after TMUX guard, after session extraction) to match the v2.0 placement.

**Why it's wrong:** `generate_correlation_id()` and `jsonl_log_fired()` must be called at script start (line ~15) to log the "FIRED" event with a correlation_id attached from the beginning. If lib sources after guards, the early lifecycle is unobservable.

**Do this instead:** Source lib at the top of the script, after only `SKILL_LOG_DIR`, `GSD_HOOK_LOG`, and `HOOK_SCRIPT_NAME` are set. Add a fallback plain-text log + exit if lib is missing.

### Anti-Pattern 4: One JSONL Event Per Hook Script (Not Per Lifecycle Stage)

**What people do:** Write a single JSONL event at hook exit summarizing everything that happened.

**Why it's wrong:** If the hook crashes, times out, or is killed, the exit event never writes. No observability into what the hook was doing when it failed.

**Do this instead:** Write events at meaningful lifecycle points: script start ("fired"), request sent ("hook.request"), response received ("hook.response"). Three events per successful hook invocation is sufficient. Each event is independently observable even if later events are missing.

### Anti-Pattern 5: Blocking the Hook on Response Logging

**What people do:** Wait for the response logging subshell to complete before exiting the hook.

**Why it's wrong:** The async delivery pattern exists precisely because `openclaw agent` takes 100ms-2000ms to return. The hook must exit immediately to avoid blocking Claude Code's event loop.

**Do this instead:** Use `deliver_async_with_logging()` which backgrounds the entire capture-and-log cycle. The hook script exits 0 immediately. The background subshell handles response capture and JSONL logging independently.

---

## Sources

**HIGH confidence (direct source inspection):**
- `lib/hook-utils.sh` — exact function signatures, 150 lines read in full
- `stop-hook.sh` — exact inline debug_log pattern, bare openclaw delivery call, bidirectional branch
- `pre-tool-use-hook.sh`, `notification-idle-hook.sh`, `notification-permission-hook.sh`, `session-end-hook.sh`, `pre-compact-hook.sh` — all read in full, confirmed identical debug_log and delivery patterns
- `PROJECT.md` — v3.0 goal: "paired request/response events linked by correlation_id", "full wake message body captured in request events", "OpenClaw response captured in response events"
- `REQUIREMENTS.md` — confirmed v3.0 scope, existing v2.0 LIB-01/LIB-02 constraints (DRY, SRP)
- `STATE.md` — "lib/hook-utils.sh is the DRY anchor", "fd-based flock with command group for atomic pane diff"
- `config/recovery-registry.example.json` — confirmed `hook_mode: async` default, `bidirectional` per-agent option

**MEDIUM confidence (architectural reasoning, no external source needed):**
- `generate_correlation_id()` design — date +%s + $$ is universally available, collision-resistant for this use case
- `jq -cn --arg` pattern for JSONL serialization — standard jq idiom, verified against jq documentation in training data
- Background subshell response capture — bash subshell semantics for variable inheritance

---
*Architecture research for: gsd-code-skill v3.0 Structured Hook Observability*
*Researched: 2026-02-18*
*Confidence: HIGH — all source files read in full, integration points mapped to exact functions and patterns, build order validated against dependency graph*
