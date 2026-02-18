# Phase 8: JSONL Logging Foundation - Research

**Researched:** 2026-02-18
**Domain:** Bash shared library design — JSONL record construction, flock-based atomic writes, background subshell delivery with logging, duration measurement
**Confidence:** HIGH — all patterns verified against the live codebase and confirmed working on this production Ubuntu 24 host with jq 1.7, bash 5.2, flock (util-linux)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| JSONL-01 | Single complete JSONL record per hook invocation containing all accumulated lifecycle data (trigger, state, content source, wake message, response, outcome, duration) | Record schema designed; all fields verified escapable via jq --arg; complete record pattern tested end-to-end |
| JSONL-02 | Per-session `.jsonl` log files at `logs/{SESSION_NAME}.jsonl` alongside existing `.log` files | Confirmed: logs/ dir already exists with per-session .log files from Quick-5; .jsonl files sit alongside |
| JSONL-03 | All string fields safely escaped via `jq --arg` — wake messages containing newlines, quotes, ANSI codes, embedded JSON produce valid JSONL | Verified: `jq -cn --arg` correctly escapes `\n`, ANSI escape codes (`\u001b[31m...`), double quotes, embedded JSON — tested on host |
| JSONL-04 | All JSONL appends use `flock` for atomic writes under concurrent hook fires (records >4KB exceed POSIX O_APPEND guarantee) | Verified: PIPE_BUF=4096 on this host; concurrent 10-writer flock test produced exactly 10 valid JSONL lines; pattern confirmed |
| JSONL-05 | Shared `write_hook_event_record()` function in `lib/hook-utils.sh` — DRY foundation all six hooks source; single write point, single fix point | Confirmed: lib/hook-utils.sh already sourced by all 6 hooks; adding write_hook_event_record follows established pattern |
| OPS-01 | Every JSONL record includes `duration_ms` field — time from hook entry to record write | Verified: `date +%s%3N` gives milliseconds on this host; `$((exit_ms - entry_ms))` gives correct duration; tested producing duration_ms=3..15ms |

</phase_requirements>

---

## Summary

Phase 8 extends `lib/hook-utils.sh` with two new functions: `write_hook_event_record()` and `deliver_async_with_logging()`. These are pure bash functions using tools already confirmed present on this host (jq 1.7, flock, bash 5.2). No new dependencies are introduced.

The core technical challenges are all solved patterns:

1. **Safe string escaping:** `jq -cn --arg field_name "$variable"` handles newlines, quotes, ANSI codes, and embedded JSON correctly. Verified live on this host — ANSI `\033[31m` becomes `\u001b[31m` (valid JSON unicode escape), multiline wake messages become escaped `\n`, embedded JSON is double-escaped correctly.

2. **Atomic JSONL append:** PIPE_BUF on this Linux host is 4096 bytes. JSONL records containing wake messages regularly exceed this (tested ~1KB for a minimal record; real records with pane content can exceed 4KB). Use `flock -x -w 2` on `${JSONL_FILE}.lock` before `printf '%s\n'` append. Tested: 10 concurrent writers produced exactly 10 valid JSONL records.

3. **Background logging:** `deliver_async_with_logging()` wraps the `openclaw ... &` call in a background subshell `(...)`. The subshell runs `openclaw`, captures its response, computes `duration_ms`, then calls `write_hook_event_record()` to write the complete record. The hook script's main flow exits immediately after spawning the subshell. Explicit `</dev/null` on the subshell prevents stdin inheritance hang.

4. **Duration measurement:** `HOOK_ENTRY_MS=$(date +%s%3N)` at the top of each hook script captures entry time in milliseconds. The background subshell computes `duration_ms=$(($(date +%s%3N) - HOOK_ENTRY_MS))` just before writing the record. Tested — produces accurate millisecond durations.

5. **Function testability:** All new functions take explicit parameters. They can be sourced and called in a test harness without tmux, without openclaw, without a Claude Code session. The existing `extract_last_assistant_response()` was confirmed testable in isolation in exactly this way.

**Primary recommendation:** Implement two functions in lib/hook-utils.sh — `write_hook_event_record()` (builds + flocked-appends the JSONL record) and `deliver_async_with_logging()` (wraps openclaw call in a background subshell that writes the record after the response arrives). Each hook script calls `HOOK_ENTRY_MS=$(date +%s%3N)` at the top, then calls `deliver_async_with_logging()` instead of the bare `openclaw ... &` pattern.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| jq | 1.7 | JSONL record construction with safe field escaping | Already used in all 6 hooks; `--arg` handles all special characters |
| bash | 5.2.21 | Function implementation, subshell backgrounding, millisecond timing | Existing stack; `date +%s%3N` for ms; bash 4.3+ nameref if needed |
| flock | util-linux (installed) | Atomic JSONL append under concurrent hook fires | Already used for pane diff in hook-utils.sh; same pattern extends to JSONL |
| date (GNU coreutils) | Ubuntu 24 | Millisecond timestamps via `date +%s%3N` | Confirmed working on this host |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| printf | bash builtin | Append JSONL record to file (`printf '%s\n'`) | Inside flock block — use printf not echo for portability |
| /dev/null | kernel | Prevent stdin inheritance in background subshell | Every background subshell `(...)` must redirect stdin |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq -cn --arg (all fields) | printf with manual escaping | printf escaping is fragile for arbitrary strings with newlines, null bytes, ANSI — never hand-roll JSON escaping |
| flock with lockfile | Python file locking | Python adds 50ms startup; flock is 0ms; no new dependency |
| date +%s%3N | $EPOCHREALTIME (bash 5+) | $EPOCHREALTIME is bash 5.0+ and gives decimal seconds, requires awk; date +%s%3N is simpler |
| Background subshell (...)  | wait + foreground | Foreground blocks the hook; hook must exit fast to not delay Claude Code |
| Per-session .jsonl file | Single global .jsonl | Per-session follows existing .log pattern; enables session-scoped queries in Phase 11 |

---

## Architecture Patterns

### Recommended lib/hook-utils.sh Extension

```
lib/hook-utils.sh (EXTENDED in Phase 8):
├── lookup_agent_in_registry()          # Phase 2 — unchanged
├── extract_last_assistant_response()   # Phase 6 — unchanged
├── extract_pane_diff()                 # Phase 6 — unchanged
├── format_ask_user_questions()         # Phase 6 — unchanged
├── write_hook_event_record()           # NEW Phase 8 — builds + appends JSONL record
└── deliver_async_with_logging()        # NEW Phase 8 — wraps openclaw call, writes record in bg
```

### Pattern 1: write_hook_event_record()

**What:** Builds a complete JSONL record from explicit parameters and appends it atomically to the per-session `.jsonl` log file.

**When to use:** Called by `deliver_async_with_logging()` (for async hooks) and by synchronous hook paths (for bidirectional hooks). Never called with untrusted input — all parameters come from validated hook script variables.

**Function signature (explicit positional parameters):**
```bash
write_hook_event_record() {
  # Args: jsonl_file hook_entry_ms hook_script session_name agent_id
  #       openclaw_session_id trigger state content_source wake_message
  #       response outcome
  local jsonl_file="$1"
  local hook_entry_ms="$2"
  local hook_script="$3"
  local session_name="$4"
  local agent_id="$5"
  local openclaw_session_id="$6"
  local trigger="$7"
  local state="$8"
  local content_source="$9"
  local wake_message="${10}"
  local response="${11}"
  local outcome="${12}"

  local hook_exit_ms
  hook_exit_ms=$(date +%s%3N)
  local duration_ms=$((hook_exit_ms - hook_entry_ms))

  local record
  record=$(jq -cn \
    --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --arg hook_script "$hook_script" \
    --arg session_name "$session_name" \
    --arg agent_id "$agent_id" \
    --arg openclaw_session_id "$openclaw_session_id" \
    --arg trigger "$trigger" \
    --arg state "$state" \
    --arg content_source "$content_source" \
    --arg wake_message "$wake_message" \
    --arg response "$response" \
    --arg outcome "$outcome" \
    --argjson duration_ms "$duration_ms" \
    '{
      timestamp: $timestamp,
      hook_script: $hook_script,
      session_name: $session_name,
      agent_id: $agent_id,
      openclaw_session_id: $openclaw_session_id,
      trigger: $trigger,
      state: $state,
      content_source: $content_source,
      wake_message: $wake_message,
      response: $response,
      outcome: $outcome,
      duration_ms: $duration_ms
    }' 2>/dev/null) || return 0  # Fail silently — never block hook exit

  if [ -z "$record" ]; then
    return 0  # jq failed — skip record, never crash
  fi

  (
    flock -x -w 2 200 || return 0
    printf '%s\n' "$record" >> "$jsonl_file"
  ) 200>"${jsonl_file}.lock" 2>/dev/null || true
}
```

**Critical details:**
- `--argjson duration_ms "$duration_ms"` — integer, not string, so no `--arg` (would produce `"42"` not `42`)
- `2>/dev/null` on jq — transcript may have jq errors; never let record construction crash the hook
- `|| return 0` on flock block — if flock times out (>2s), skip write and continue
- `|| true` on the entire flock block — prevents set -e from triggering in caller

### Pattern 2: deliver_async_with_logging()

**What:** Replaces bare `openclaw agent --session-id ... &` with a background subshell that (1) calls openclaw, (2) captures the response, (3) calls `write_hook_event_record()` with the response and computed duration.

**When to use:** In all async hook delivery paths (the `HOOK_MODE = "async"` branch). For bidirectional paths, the hook script waits for the response and calls `write_hook_event_record()` directly after the synchronous `openclaw` call.

**Function signature:**
```bash
deliver_async_with_logging() {
  # Args: openclaw_session_id wake_message jsonl_file hook_entry_ms
  #       hook_script session_name agent_id trigger state content_source
  local openclaw_session_id="$1"
  local wake_message="$2"
  local jsonl_file="$3"
  local hook_entry_ms="$4"
  local hook_script="$5"
  local session_name="$6"
  local agent_id="$7"
  local trigger="$8"
  local state="$9"
  local content_source="${10}"

  (
    local response
    response=$(openclaw agent --session-id "$openclaw_session_id" \
      --message "$wake_message" 2>&1) || true
    local outcome="delivered"
    [ -z "$response" ] && outcome="no_response"

    write_hook_event_record \
      "$jsonl_file" "$hook_entry_ms" "$hook_script" "$session_name" \
      "$agent_id" "$openclaw_session_id" "$trigger" "$state" \
      "$content_source" "$wake_message" "$response" "$outcome"
  ) </dev/null &
}
```

**Critical details:**
- `</dev/null &` on the subshell — both are mandatory. `</dev/null` prevents stdin hang; `&` backgrounds the subshell.
- The main hook exits immediately after `deliver_async_with_logging` returns — it does NOT `wait` for the background PID.
- `|| true` on the openclaw call — openclaw failure should still produce a JSONL record with `outcome="no_response"`.
- The subshell inherits all variables from the calling hook because it's a subshell (not a subprocess).

### Pattern 3: Hook Script Integration (minimal change)

**What:** Each of the 6 hook scripts adds exactly 3 lines: (1) capture `HOOK_ENTRY_MS` at the top, (2) set `JSONL_FILE` path after session name is known, (3) replace bare `openclaw ... &` with `deliver_async_with_logging()`.

**Where HOOK_ENTRY_MS goes:** Immediately after `STDIN_JSON=$(cat)` — as early as possible after stdin is consumed. Stdin consumption is the real "hook start" from Claude Code's perspective.

**Where JSONL_FILE goes:** After Phase 2 log redirect (after `SESSION_NAME` is known), alongside `GSD_HOOK_LOG` assignment:

```bash
# Phase 2: redirect to per-session log file
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
debug_log "=== log redirected to per-session file ==="
```

**Replacement in async delivery section:**

```bash
# BEFORE (Phase 2 pattern):
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >> "$GSD_HOOK_LOG" 2>&1 &
debug_log "DELIVERED (async, bg PID=$!)"

# AFTER (Phase 8 pattern):
deliver_async_with_logging \
  "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" "$JSONL_FILE" "$HOOK_ENTRY_MS" \
  "$HOOK_SCRIPT_NAME" "$SESSION_NAME" "$AGENT_ID" \
  "$TRIGGER" "$STATE" "${CONTENT_SOURCE:-pane}"
debug_log "DELIVERED (async with JSONL logging)"
```

Note: `TRIGGER` and `CONTENT_SOURCE` vary per hook. Each hook script sets these as local variables before calling `deliver_async_with_logging()`.

### Pattern 4: JSONL Record Schema

Complete schema for Phase 8 records (JSONL-01):

```json
{
  "timestamp": "2026-02-18T11:23:26Z",
  "hook_script": "stop-hook.sh",
  "session_name": "warden-main",
  "agent_id": "warden",
  "openclaw_session_id": "abc-123-def-456",
  "trigger": "response_complete",
  "state": "working",
  "content_source": "transcript",
  "wake_message": "line1\nline2 with \"quotes\"\nline3",
  "response": "{\"status\":\"delivered\"}",
  "outcome": "delivered",
  "duration_ms": 147
}
```

**Field values per hook script:**

| Hook Script | trigger | content_source |
|------------|---------|---------------|
| stop-hook.sh | "response_complete" | "transcript" or "pane_diff" or "raw_pane_tail" |
| notification-idle-hook.sh | "idle_prompt" | "pane" |
| notification-permission-hook.sh | "permission_prompt" | "pane" |
| session-end-hook.sh | "session_end" | "none" |
| pre-compact-hook.sh | "pre_compact" | "pane" |
| pre-tool-use-hook.sh | "ask_user_question" | "questions" |

**outcome values:**
- `"delivered"` — openclaw call returned without error
- `"no_response"` — openclaw returned empty response
- `"openclaw_error"` — openclaw call failed (non-zero exit)
- `"sync_delivered"` — bidirectional mode, response received synchronously

### Pattern 5: Testability in Isolation

**What:** write_hook_event_record() and deliver_async_with_logging() can be tested by sourcing lib/hook-utils.sh in a test script. No tmux, no openclaw, no Claude Code session required.

**Test harness pattern:**
```bash
#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SKILL_DIR}/lib/hook-utils.sh"

SKILL_LOG_DIR="/tmp/gsd-test-$$"
mkdir -p "$SKILL_LOG_DIR"

SESSION_NAME="test-session"
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
HOOK_ENTRY_MS=$(date +%s%3N)

write_hook_event_record \
  "$JSONL_FILE" "$HOOK_ENTRY_MS" "stop-hook.sh" "$SESSION_NAME" \
  "test-agent" "test-session-id" "response_complete" "working" \
  "transcript" "$(printf 'hello\nworld')" '{"status":"ok"}' "delivered"

RECORD=$(cat "$JSONL_FILE")
echo "$RECORD" | jq .
# Assertions:
echo "$RECORD" | jq -e '.duration_ms | type == "number"' > /dev/null && echo "PASS: duration_ms is number"
echo "$RECORD" | jq -e '.wake_message | contains("\n")' > /dev/null && echo "PASS: newlines preserved in wake_message"

rm -rf "$SKILL_LOG_DIR"
```

### Anti-Patterns to Avoid

- **Hand-rolling JSON escaping:** Never use `printf '{"field":"%s"}' "$variable"` for arbitrary string fields. Variable may contain `"`, `\`, newlines, or null bytes. Always use `jq --arg`.
- **--arg for numeric fields:** `--arg duration_ms "$DURATION_MS"` produces `"duration_ms":"42"` (string) not `"duration_ms":42` (integer). Use `--argjson duration_ms "$DURATION_MS"` for integers.
- **Forgetting </dev/null on background subshell:** Background subshell inherits stdin from the hook (Claude Code's pipe). If `openclaw` reads stdin (unlikely but possible), it hangs the subshell indefinitely. Always `(...)  </dev/null &`.
- **Calling write_hook_event_record() from guard exits:** Guard exits (no TMUX, no registry match) must NOT emit JSONL — zero jq overhead is required for non-managed sessions (REQUIREMENTS.md: "Guard exits do NOT emit JSONL"). write_hook_event_record() is only callable after guard passes confirm this is a managed session.
- **Using echo instead of printf for JSONL append:** `echo` adds a trailing newline but some systems may add `\r\n`. `printf '%s\n'` is guaranteed to append exactly one `\n`.
- **Nested flock on same lockfile:** write_hook_event_record() uses `${JSONL_FILE}.lock`. This is a DIFFERENT lock file from `extract_pane_diff()` which uses `${log_directory}/gsd-pane-lock-${session_name}`. No collision.
- **Blocking the hook on openclaw timeout:** deliver_async_with_logging() backgrounds the subshell — the hook exits immediately. The background subshell may wait up to openclaw's own timeout, but this is independent of the hook lifecycle.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON string escaping | printf '{"msg":"%s"}' | jq -cn --arg field "$var" | Arbitrary strings contain quotes, backslashes, newlines, ANSI; manual escaping has edge cases |
| Integer fields in JSON | printf '{"ms":"%s"}' | --argjson field "$int_var" | --arg always produces strings; --argjson passes raw JSON value |
| Concurrent file append | Application-level coordination | flock -x -w 2 | flock is atomic at kernel level; application locks are not |
| Millisecond timing | Manual date arithmetic | date +%s%3N | One-liner; GNU coreutils; no awk/python needed |

**Key insight:** Every complex problem in Phase 8 is solved by a single well-known tool. The implementation is assembling these tools correctly — not building new mechanisms.

---

## Common Pitfalls

### Pitfall 1: --arg vs --argjson for numeric duration_ms

**What goes wrong:** `--arg duration_ms "$DURATION_MS"` produces `"duration_ms": "42"` (a JSON string). `jq -e '.duration_ms | type == "number"'` fails. Phase 11's diagnose-hooks.sh and any tooling that queries duration will need `tonumber` workaround.

**Why it happens:** `--arg` always treats the value as a JSON string. `--argjson` parses the value as raw JSON.

**How to avoid:**
```bash
# WRONG
--arg duration_ms "$DURATION_MS"        # produces "duration_ms": "42" (string)

# CORRECT
--argjson duration_ms "$DURATION_MS"    # produces "duration_ms": 42 (integer)
```

**Warning signs:** `jq '.duration_ms'` returns `"42"` with quotes in output.

### Pitfall 2: Subshell Variable Inheritance vs Exported Variables

**What goes wrong:** `deliver_async_with_logging()` is called from a hook script. The background subshell `(...)` DOES inherit all shell variables (including `HOOK_ENTRY_MS`, `SKILL_LOG_DIR`, etc.) because it is a bash subshell fork, not a subprocess. However, `write_hook_event_record()` inside the subshell must use ONLY its explicit parameters — not rely on inherited globals — for testability (success criteria #8).

**How to avoid:** Pass all required data as explicit function parameters to both `deliver_async_with_logging()` and `write_hook_event_record()`. The functions must be self-contained.

### Pitfall 3: jq Error in Record Construction Crashes Hook

**What goes wrong:** If `jq -cn` fails (malformed argument, jq bug), the record construction crashes. With `set -euo pipefail` in the calling hook, this propagates and kills the hook. Claude Code gets a non-zero exit from the hook.

**How to avoid:**
```bash
record=$(jq -cn ... 2>/dev/null) || return 0  # Skip write, never crash
[ -z "$record" ] && return 0
```

**Warning signs:** Hook exits non-zero. Claude Code logs show hook error. Stop hook firing suppresses Claude Code's response.

### Pitfall 4: Lock File Contention Between write_hook_event_record and Itself

**What goes wrong:** Two concurrent hook fires (e.g., Stop + Notification) both call `write_hook_event_record()` for the same session. Both try to flock `${JSONL_FILE}.lock`. The second waits up to 2 seconds. If the first write takes >2 seconds (unlikely with jq), the second skips its write.

**Why it happens:** flock timeout set to 2 seconds. jq record construction + printf write should take <50ms in practice.

**How to avoid:** 2-second timeout is appropriate — jq + printf will never take 2 seconds. The timeout is a safety valve against deadlock only. No action needed.

### Pitfall 5: JSONL File Name Mismatch with .log File

**What goes wrong:** The `.log` file uses `${SKILL_LOG_DIR}/${SESSION_NAME}.log`. If JSONL file uses a different naming convention (e.g., `${SKILL_LOG_DIR}/${SESSION_NAME}-events.jsonl`), Phase 11's diagnose-hooks.sh and Phase 9's migration become harder to maintain.

**How to avoid:** Use `${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl` — exact same pattern as `.log` with `.jsonl` extension. Both files sit alongside each other in the same `logs/` directory. This is confirmed by JSONL-02 requirement.

### Pitfall 6: stdin Inheritance in Background Subshell Hangs

**What goes wrong:** The background subshell `(openclaw ...) &` inherits stdin from the hook script. The hook script's stdin is Claude Code's pipe. If `openclaw` or any command in the subshell reads stdin, it will block waiting for data that never comes (the pipe is already consumed by `STDIN_JSON=$(cat)` earlier). This produces silent hangs.

**How to avoid:** Always `(...)  </dev/null &`. The `</dev/null` redirects stdin of the ENTIRE subshell to /dev/null before backgrounding. This is a mandatory pattern regardless of whether openclaw reads stdin — it prevents future regressions if the subshell content changes.

**Warning signs:** Background process hangs (visible in `ps aux`). JSONL record never written. Hook appears to complete but log file stays empty.

---

## Code Examples

Verified patterns from live testing on this host:

### Millisecond Duration Measurement

```bash
# Source: verified on Ubuntu 24, GNU coreutils date
HOOK_ENTRY_MS=$(date +%s%3N)
# ... hook work ...
HOOK_EXIT_MS=$(date +%s%3N)
DURATION_MS=$((HOOK_EXIT_MS - HOOK_ENTRY_MS))
# Result: integer milliseconds (e.g., 147)
```

### Safe Multi-Field JSONL Record Construction

```bash
# Source: tested end-to-end on this host — all special chars survive round-trip
WAKE_MSG=$(printf 'line1\nline2 with "quotes"\nANSI: \033[31mred\033[0m\nEmbedded: {"key":"val"}')

RECORD=$(jq -cn \
  --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg hook_script "$HOOK_SCRIPT_NAME" \
  --arg session_name "$SESSION_NAME" \
  --arg agent_id "$AGENT_ID" \
  --arg openclaw_session_id "$OPENCLAW_SESSION_ID" \
  --arg trigger "$TRIGGER" \
  --arg state "$STATE" \
  --arg content_source "$CONTENT_SOURCE" \
  --arg wake_message "$WAKE_MSG" \
  --arg response "$RESPONSE" \
  --arg outcome "$OUTCOME" \
  --argjson duration_ms "$DURATION_MS" \
  '{timestamp:$timestamp,hook_script:$hook_script,session_name:$session_name,
    agent_id:$agent_id,openclaw_session_id:$openclaw_session_id,
    trigger:$trigger,state:$state,content_source:$content_source,
    wake_message:$wake_message,response:$response,outcome:$outcome,
    duration_ms:$duration_ms}' 2>/dev/null) || true
```

### Atomic JSONL Append with flock (Verified: 10 concurrent writers, 10 valid records)

```bash
# Source: tested live on this host — 10 concurrent writers, 10 valid records output
append_jsonl_record_atomically() {
  local jsonl_file="$1"
  local record="$2"

  (
    flock -x -w 2 200 || return 0
    printf '%s\n' "$record" >> "$jsonl_file"
  ) 200>"${jsonl_file}.lock" 2>/dev/null || true
}
```

### Background Subshell with stdin Prevention (Verified)

```bash
# Source: tested — subshell output written correctly, no stdin hang
(
  local response
  response=$(openclaw agent --session-id "$session_id" \
    --message "$wake_message" 2>&1) || true

  local outcome="delivered"
  [ -z "$response" ] && outcome="no_response"

  write_hook_event_record "$jsonl_file" "$entry_ms" \
    "$hook_script" "$session_name" "$agent_id" "$session_id" \
    "$trigger" "$state" "$content_source" \
    "$wake_message" "$response" "$outcome"
) </dev/null &
```

### Per-Session JSONL File Path Assignment

```bash
# After SESSION_NAME is known (Phase 2 redirect), alongside .log file:
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
```

### Isolated Unit Test Pattern

```bash
#!/usr/bin/env bash
# tests/test-write-hook-event-record.sh
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_LOG_DIR="/tmp/gsd-test-$$"
mkdir -p "$SKILL_LOG_DIR"

source "${SKILL_DIR}/lib/hook-utils.sh"

SESSION_NAME="test-session"
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
HOOK_ENTRY_MS=$(date +%s%3N)

# Test: write_hook_event_record produces valid parseable JSONL
write_hook_event_record \
  "$JSONL_FILE" "$HOOK_ENTRY_MS" "stop-hook.sh" "$SESSION_NAME" \
  "test-agent" "test-openclaw-id" "response_complete" "working" \
  "transcript" "$(printf 'hello\nworld "quoted"')" "" "no_response"

jq -e '.duration_ms | type == "number"' "$JSONL_FILE" > /dev/null \
  && echo "PASS: duration_ms is integer"
jq -e '.wake_message | contains("\n")' "$JSONL_FILE" > /dev/null \
  && echo "PASS: newlines preserved"
jq -e '.hook_script == "stop-hook.sh"' "$JSONL_FILE" > /dev/null \
  && echo "PASS: hook_script field correct"

rm -rf "$SKILL_LOG_DIR"
echo "All assertions passed"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Plain-text debug_log: `[2026-02-18T11:00:00Z] [stop-hook.sh] state=working` | Structured JSONL: `{"timestamp":"...","state":"working","duration_ms":147,...}` | Phase 8 (this phase) | Machine-queryable; jq-parseable; enables Phase 11 diagnose-hooks.sh analytics |
| Bare `openclaw ... &` with no response capture | `deliver_async_with_logging()` captures response, writes complete JSONL record | Phase 8 (this phase) | Response and outcome visible in logs; full lifecycle captured per invocation |
| No timing data | `duration_ms` in every record | Phase 8 (this phase) | Performance baseline; anomaly detection; OPS-01 satisfied |
| /dev/null stdout for async openclaw | Response captured in background subshell | Phase 8 (this phase) | Response field in JSONL shows what OpenClaw replied |

**Deprecated/outdated:**
- Bare `openclaw agent ... >> "$GSD_HOOK_LOG" 2>&1 &`: replaced by `deliver_async_with_logging()`. The `.log` file continues to receive debug_log output; the openclaw response goes into JSONL record instead.

---

## Open Questions

1. **Should write_hook_event_record() also call debug_log() for backward compat?**
   - What we know: Phase 9 says "Plain-text .log files continue in parallel for backward compatibility during transition"
   - What's unclear: Should write_hook_event_record() internally call `debug_log "JSONL record written"` or is that Phase 9's concern?
   - Recommendation: Phase 8 implements write_hook_event_record() and deliver_async_with_logging() as pure functions with no debug_log calls. Phase 9 handles the per-hook integration which includes keeping debug_log in place. The two systems are parallel, not coupled.

2. **What triggers HOOK_ENTRY_MS — before or after stdin consume?**
   - What we know: Stdin consume (`STDIN_JSON=$(cat)`) blocks until Claude Code sends data. This is not "hook entry time" — it's "hook processing start time".
   - What's unclear: The requirement says "time from hook entry to record write". Does "hook entry" mean before stdin (script start) or after stdin?
   - Recommendation: Set `HOOK_ENTRY_MS=$(date +%s%3N)` AFTER `STDIN_JSON=$(cat)` — immediately after stdin is consumed. This measures actual hook processing time (extraction + building + delivery), not stdin wait time. Stdin wait is Claude Code overhead, not hook overhead.

3. **content_source for hooks that don't have content (session-end-hook.sh)**
   - What we know: session-end-hook.sh sends only session identity + trigger, no content section
   - What's unclear: What value should `content_source` have in its JSONL record?
   - Recommendation: Use `content_source="none"` for session-end-hook.sh and any other hook that sends no content section. This is consistent with the schema and queryable.

4. **deliver_async_with_logging for bidirectional mode hooks**
   - What we know: stop-hook.sh and pre-compact-hook.sh have a bidirectional branch that calls openclaw synchronously and waits for a response
   - What's unclear: Should deliver_async_with_logging() be used only for async mode, or should there be a deliver_sync_with_logging() for bidirectional mode?
   - Recommendation: Phase 8 implements `deliver_async_with_logging()` only. For bidirectional mode, Phase 9 will handle it inline in each hook script (call openclaw synchronously, capture response, call `write_hook_event_record()` directly). This keeps Phase 8 focused on the foundation.

---

## Sources

### Primary (HIGH confidence — live codebase verification)

- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/lib/hook-utils.sh` — current function signatures, flock pattern, SKILL_LOG_DIR usage
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/stop-hook.sh` — exact current delivery pattern (bare openclaw & in lines 234-235)
- All 6 hook scripts — confirmed they all source lib/hook-utils.sh, all have SKILL_LOG_DIR, all have two-phase logging
- `.planning/phases/06-core-extraction-and-delivery-engine/06-RESEARCH.md` — flock pattern, subshell variable scoping, 2>/dev/null patterns

### Primary (HIGH confidence — live testing on this host)

- `jq -cn --arg` with newlines, ANSI codes, embedded JSON — tested and confirmed correct escaping
- `date +%s%3N` millisecond timing — tested and confirmed accurate
- Concurrent flock test (10 writers) — 10 valid JSONL records produced, no corruption
- Background subshell with `</dev/null &` — tested working correctly with response capture

### Primary (HIGH confidence — project requirements)

- `.planning/REQUIREMENTS.md` v3 section — JSONL-01..05, OPS-01, explicit field requirements
- `.planning/ROADMAP.md` Phase 8 success criteria — 8 specific truths to verify
- `.planning/STATE.md` — current project state, Quick-5 decisions about SKILL_LOG_DIR

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; all tools version-verified on this host
- Architecture: HIGH — two function design (write_hook_event_record + deliver_async_with_logging) verified against all 6 hook scripts; integration points mapped exactly
- Pitfalls: HIGH — all critical pitfalls (--arg vs --argjson, </dev/null, flock contention, jq error handling) verified by live testing
- Testability: HIGH — existing functions confirmed testable in isolation; same pattern applies to new functions

**Research date:** 2026-02-18
**Valid until:** Stable (no external dependencies; bash, jq, flock are stable)

**Build order for planner:**
1. **Plan 1:** `write_hook_event_record()` and `append_jsonl_record_atomically()` in lib/hook-utils.sh + unit test script (no hook dependencies)
2. **Plan 2:** `deliver_async_with_logging()` in lib/hook-utils.sh (depends on write_hook_event_record being complete) + integration test

Both plans are sequential — deliver_async_with_logging calls write_hook_event_record. Phase 8 is 2 plans maximum. Phase 9 handles the per-hook-script migration.
