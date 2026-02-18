# Pitfalls Research

**Domain:** Adding structured JSONL event logging to existing bash hook scripts (v3.0 Structured Hook Observability)
**Researched:** 2026-02-18
**Confidence:** HIGH — based on Linux kernel documentation, empirical write-atomicity research, analysis of the existing v2.0 codebase, and confirmed bash+jq behavior patterns

---

## Scope

This document covers pitfalls specific to v3.0: replacing plain-text `debug_log()` with structured JSONL event logging in 6 bash hook scripts. The prior milestone pitfalls (transcript extraction, PreToolUse blocking, race conditions on pane state files, wake format changes) are already solved and NOT re-documented here. This document focuses exclusively on integration risks when adding JSONL logging to a working production hook system.

---

## Critical Pitfalls

### Pitfall 1: Wake Message Contains Characters That Break JSON Validity

**What goes wrong:**
The `wake_message` field in the `hook.request` event contains the full multiline wake message body. Wake messages are free-form text that can include: newlines, tabs, backslashes, double quotes (from code blocks, JSON output, file paths), null bytes (from binary pane content leaking into tmux capture), and ANSI escape codes. If the JSONL serialization uses naive bash string interpolation — even a `printf '{"wake_message": "%s"}\n' "$WAKE_MESSAGE"` — the resulting JSON is invalid. jq will fail to parse any record containing an unescaped newline, double quote, or control character. This silently corrupts the entire log file from that record onward for any consumer that streams the file.

**Why it happens:**
JSON prohibits unescaped characters in the range U+0000–U+001F (including newlines U+000A, carriage returns U+000D, and tabs U+0009) inside string values. Wake messages routinely contain all of these: the structured sections use newlines as delimiters, pane content contains tab-indented code, and tmux capture occasionally emits raw ANSI sequences. Developers test with clean messages like `"idle_prompt"` and miss the failure mode for real production messages containing error stack traces, JSONL content from other tools, or markdown code fences.

**How to avoid:**
Use `jq -n --arg` for ALL string fields without exception. The `--arg` flag routes values through jq's internal string encoder, which correctly escapes newlines as `\n`, tabs as `\t`, double quotes as `\"`, backslashes as `\\`, and all U+0000–U+001F control characters as `\uXXXX`. This is the only correct approach in bash+jq:

```bash
# WRONG — any special character in $WAKE_MESSAGE invalidates the JSON line
printf '{"event":"hook.request","wake_message":"%s"}\n' "$WAKE_MESSAGE"

# WRONG — heredoc string interpolation has the same problem
jq -n "{\"wake_message\": \"$WAKE_MESSAGE\"}"

# CORRECT — jq --arg handles all escaping internally
jq -n \
  --arg event "hook.request" \
  --arg ts "$TIMESTAMP" \
  --arg correlation_id "$CORRELATION_ID" \
  --arg wake_message "$WAKE_MESSAGE" \
  '{event: $event, ts: $ts, correlation_id: $correlation_id, wake_message: $wake_message}'
```

For the `raw_response` field (OpenClaw stdout), use the same pattern. OpenClaw responses can also contain arbitrary text including JSON, error messages with colons and quotes, and stack traces.

**Warning signs:**
- `jq .` run on the log file exits with `parse error: Invalid string: control characters from U+0000 through U+001F must be escaped`
- Log reader shows events for simple sessions but not for sessions where Claude ran tool calls (pane content includes error output)
- `grep -c '^{' hooks.log` count is lower than the number of hook fires in the plain-text hook log
- Log corruption is intermittent — clean in testing, broken in production where pane content is richer

**Phase to address:**
Phase 1 (JSONL schema and `jsonl_log()` function) — the `jsonl_log()` function must use `jq -n --arg` for every field; this is non-negotiable and must be established in the shared library before any hook script calls it.

---

### Pitfall 2: Concurrent Hook Fires to the Same Log File Without Atomic Append Guarantee

**What goes wrong:**
Multiple hooks can fire simultaneously for the same session — Stop hook and a Notification hook can both be executing concurrently, both writing to `logs/{SESSION_NAME}.log`. The current `printf ... >> "$GSD_HOOK_LOG"` pattern uses bash's `>>` redirect, which opens the file with `O_WRONLY|O_APPEND`. On Linux ext4, POSIX atomicity guarantees apply for writes up to `PIPE_BUF` (4,096 bytes on Linux). But a JSONL event containing a full wake message body easily exceeds 4,096 bytes — a wake message with 100 lines of pane content plus a multiline assistant response can be 8–15KB. Writes larger than 4,096 bytes are not atomically guaranteed: two concurrent writes can interleave at arbitrary byte boundaries, producing a corrupted line in the log that is neither valid JSON nor a complete event record.

**Why it happens:**
Developers assume `>>` append is atomic. This is true for small writes (debug log lines of 50–200 bytes are well under 4KB). But JSONL event records with full wake message bodies embedded are large. The failure mode is invisible in single-session testing because only one hook fires at a time. In production with multiple simultaneous sessions or events like Stop + Notification firing within milliseconds of each other, interleaved writes appear as lines that start with `{` but end mid-field or are merged with the start of another record.

**How to avoid:**
Use `flock` on a per-session log lock file for any JSONL append that may exceed 4,096 bytes. The existing `gsd-pane-lock-{SESSION}` pattern is already proven in the codebase — apply the same pattern to log writes:

```bash
# In jsonl_log() in lib/hook-utils.sh:
jsonl_log() {
  local log_file="$1"
  local json_record="$2"
  local lock_file="${log_file}.lock"

  (
    flock -x -w 2 200 || return 0  # Timeout = skip write, not block forever
    printf '%s\n' "$json_record" >> "$log_file" 2>/dev/null || true
  ) 200>"$lock_file"
}
```

Alternative: keep wake message body in a separate field with a length cap (truncate to 4,000 bytes if needed) so every record fits within the atomicity guarantee. However, this loses the full wake message, defeating v3.0's primary goal.

Flock is the correct solution. It is already used in the codebase for pane state files. Applying the same pattern to log writes is consistent and well-understood.

**Warning signs:**
- `jq -c '.' logs/warden-main.log 2>&1 | grep 'parse error'` reports errors on specific lines
- Lines in the log file that do not begin with `{` or do not end with `}`
- Two partial records appear merged on one line (starts with `{..."event":"hook.request"...{"event":"hook.response"`)
- Only visible in long sessions or when Stop + Notification hooks fire within 50ms of each other

**Phase to address:**
Phase 1 (JSONL logging library) — `jsonl_log()` must use `flock` from the first implementation; add it to the function definition before any hook script calls it.

---

### Pitfall 3: Correlation ID Only Links the Synchronous Path — Async Background Subprocess Loses It

**What goes wrong:**
The correlation ID is generated in the hook script's main process: `CORRELATION_ID=$(generate_correlation_id ...)`. The `hook.request` event is logged before the `openclaw` call. The `openclaw` call is then backgrounded with `&` in the async delivery wrapper (`deliver_async_with_logging()`). The background subprocess must also emit the `hook.response` event using the same correlation ID. If the correlation ID is passed as a function argument and the background subshell captures it correctly via closure, this works. But if the background subshell is defined in a context where the variable is not yet set, or if the wrapper function does not explicitly pass the ID to the subshell, the response event either has an empty correlation ID or a different generated ID — breaking the pairing entirely.

**Why it happens:**
Bash background subshells (`&`) inherit the parent's environment, but only variables that exist at the time of the fork. If the correlation ID is stored as a local variable inside a function, and the background subshell is spawned from inside the same function (which is the correct pattern), the local variable IS visible to the subshell because the subshell duplicates the function's stack frame. However, if the subshell is spawned from a subshell (double fork, e.g., `( openclaw ... ) &`), the local variable scope may not propagate correctly depending on the function structure. This is a subtle bash scoping issue that only manifests in specific implementations of `deliver_async_with_logging()`.

**How to avoid:**
Pass the correlation ID explicitly as a function argument — never rely on implicit variable inheritance across forks. The wrapper function signature should be:

```bash
deliver_async_with_logging() {
  local openclaw_session_id="$1"
  local wake_message="$2"
  local log_file="$3"
  local correlation_id="$4"   # Explicit parameter, not inherited variable
  local hook_name="$5"
  local session_name="$6"

  (
    local response exit_code
    response=$(openclaw agent --session-id "$openclaw_session_id" --message "$wake_message" 2>&1)
    exit_code=$?
    # correlation_id is available here because it was passed as $4, not inherited
    log_hook_response "$log_file" "$correlation_id" "$hook_name" "$session_name" \
      "$exit_code" "$response"
  ) &
}
```

Test with: after backgrounding, verify the response event's `correlation_id` matches the request event's `correlation_id` in the log. A mismatch means the correlation is broken.

**Warning signs:**
- Response events in the log have `"correlation_id": ""` (empty)
- Request events have correlation IDs but no matching response event with the same ID
- Works in simple tests but breaks when the delivery wrapper is refactored
- `jq 'select(.event == "hook.response") | .correlation_id' hooks.log` returns empty strings

**Phase to address:**
Phase 1 (JSONL logging library) — `deliver_async_with_logging()` must take correlation ID as an explicit parameter; document why implicit inheritance is insufficient.

---

### Pitfall 4: Log File Switches Mid-Invocation (Phase 1 → Phase 2 Routing) Breaks Correlation Pairing

**What goes wrong:**
Every hook script has a two-phase log file routing: Phase 1 writes to `hooks.log` (before the session name is known), Phase 2 writes to `{SESSION_NAME}.log` (after tmux session name extraction). In the plain-text debug_log, this is transparent — both phases write to wherever `$GSD_HOOK_LOG` points at the moment of the call. With JSONL paired events, the `hook.request` event is emitted late in the script (just before delivery, when the session name is already known — always Phase 2). But early guards that emit JSONL events (e.g., an event for "registry not found" or "agent not matched") may emit to `hooks.log` while the corresponding or related request event goes to `{SESSION_NAME}.log`. A consumer correlating by session cannot find all events for a session in one file.

Additionally, if the `hook.request` event is emitted after session name resolution (Phase 2 file) but the `hook.response` event is emitted from the async background subprocess using a captured `$GSD_HOOK_LOG` value that was set at the time of fork — and if the variable was captured before the Phase 2 redirect — the response event goes to `hooks.log` while the request went to `{SESSION_NAME}.log`. The correlation ID links them but they are in different files.

**Why it happens:**
The `GSD_HOOK_LOG` variable is mutated mid-script. Background subshells fork at the point of the `&` — they inherit whatever value `GSD_HOOK_LOG` had at fork time. If the fork happens after the Phase 2 redirect (`GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"`), they use the correct file. But if the `deliver_async_with_logging()` function captures `GSD_HOOK_LOG` at the time it is defined (not at the time it is called), the file path may be stale.

**How to avoid:**
Pass the log file path as an explicit argument to `deliver_async_with_logging()` — never read it from `$GSD_HOOK_LOG` inside the function. The log file path must be captured by the hook script at the point of the call and passed explicitly:

```bash
# In hook script, after Phase 2 redirect is established:
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"   # Phase 2 redirect

# Pass the current log file explicitly — not read from global inside the function
deliver_async_with_logging \
  "$OPENCLAW_SESSION_ID" \
  "$WAKE_MESSAGE" \
  "$GSD_HOOK_LOG" \        # Explicit path — resolved BEFORE the background fork
  "$CORRELATION_ID" \
  "$HOOK_SCRIPT_NAME" \
  "$SESSION_NAME"
```

For the early-exit guard events (registry not found, agent not matched), emit them to whatever `$GSD_HOOK_LOG` points to at the time — this is acceptable. The key constraint is that the request and response events for one hook invocation always go to the same file.

**Warning signs:**
- `jq 'select(.correlation_id == "X")' logs/hooks.log logs/warden-main.log` finds the request in one file and the response in another
- `jq 'select(.event == "hook.response")' logs/hooks.log` shows response events that should be in the session file
- After a script execution completes, paired events are split across two files

**Phase to address:**
Phase 1 (logging library design) — `deliver_async_with_logging()` must take log_file as an explicit parameter; Phase 1 code review — verify the log file path is captured post-redirect before any `deliver_async_with_logging` call.

---

### Pitfall 5: jq Process Startup Overhead Per Log Call Accumulates to Measurable Latency

**What goes wrong:**
The `jsonl_log()` function spawns a `jq -n` process to build the JSON record. jq has a process startup cost of approximately 5–15ms on a warm system (cold: 20–50ms). The existing hook scripts already use jq multiple times per invocation (stdin parsing, registry lookup, field extraction). Adding 2–3 more jq calls per hook invocation for logging adds 10–45ms to hook execution time in the hot path. For the Stop hook (which must not block Claude Code), this is acceptable — the hook runs on a background thread. But for hooks in bidirectional mode that must return decisions synchronously, added latency delays Claude Code's next action.

Additionally, if `jsonl_log()` is called at every guard exit point (e.g., "TMUX not set", "registry not found", "agent not matched"), hooks that fire for unmanaged sessions — which currently exit in under 5ms — now take 10–30ms. If Claude Code is running many unmanaged sessions (personal use alongside agent sessions), this multiplies.

**Why it happens:**
Each `jq -n` invocation is a full process fork+exec. In a language like Python, you would use a logging library object that stays in memory. In bash, every call is a new process. Developers add `jsonl_log()` calls liberally for debugging without considering that each call costs 5–15ms. Five logging calls = 25–75ms of jq overhead per hook invocation.

**How to avoid:**
- Reserve JSONL events for meaningful lifecycle points only: hook.request (before delivery) and hook.response (after delivery). Do not emit JSONL events for every guard exit. Guard exits are low-value and high-frequency — keep them as plain-text lines or omit them entirely.
- For the `hooks.log` (unmanaged session fast-path), do NOT emit JSONL events. The fast-path guards exit before session name resolution — emitting JSONL here adds jq overhead to every Claude Code session on the system, managed or not.
- Build the JSON record as a single `jq -n` call with all fields at once — do not call jq once per field.
- For the hooks.log early-exit path: keep plain-text `printf` for guard exits, JSONL only for managed session events.

```bash
# WRONG — 3 separate jq process spawns
jsonl_log "$LOG" "event" "hook.start"
jsonl_log "$LOG" "session" "$SESSION_NAME"
jsonl_log "$LOG" "status" "registry_not_found"

# CORRECT — single jq -n builds complete record
jsonl_log "$LOG_FILE" "$CORRELATION_ID" "guard_exit" "$SESSION_NAME" "registry_not_found"
# But better: don't emit JSONL for guard exits at all — use plain printf or omit
```

**Warning signs:**
- Hook log shows timestamps with 50ms+ gaps between sequential steps that should be near-instant
- Claude Code sessions for non-agent users (e.g., Gideon's own Claude Code sessions) become noticeably slower after v3.0 deployment
- `time bash stop-hook.sh < /dev/null` shows >100ms execution for unmanaged sessions

**Phase to address:**
Phase 1 (logging library design) — establish the rule: JSONL events for managed session request/response pairs only, not guard exits; document the performance rationale in lib/hook-utils.sh comments.

---

### Pitfall 6: Response Capture from Async Background Subprocess Hangs on stdin Inheritance

**What goes wrong:**
The `deliver_async_with_logging()` wrapper must capture the output of `openclaw agent --session-id ... --message ...` to store it in the `raw_response` field of the `hook.response` event. The natural bash pattern for capturing subprocess output is `response=$(openclaw ...)`. When this runs inside a background subprocess (`( response=$(openclaw ...) ) &`), the background subprocess inherits stdin from the hook script. The hook script's stdin is the Claude Code hook event JSON (already consumed by `STDIN_JSON=$(cat)` at the start). After `cat` consumes stdin, the file descriptor is at EOF — future reads return immediately. This is fine for the `openclaw` call itself, but if `openclaw` has a subprocess that expects interactive input or reads from stdin, it may block waiting for data that never comes.

More specifically: the background subprocess `&` without stdin redirection inherits the hook's stdin. On some systems, when a background job is launched from a non-interactive shell, bash replaces stdin with `/dev/null` automatically. But this is not guaranteed when using `( ... ) &` with explicit subshell syntax. Without explicit stdin redirection, the behavior is implementation-dependent.

**Why it happens:**
The v2.0 delivery pattern uses `openclaw ... >> "$GSD_HOOK_LOG" 2>&1 &` — no stdin redirection needed because the response was discarded. v3.0 must capture the response: `response=$(openclaw ...)` inside the background subshell. This changes the stdin inheritance behavior because command substitution `$(...)` creates a new pipe for stdout capture, but stdin is still inherited from the outer shell.

**How to avoid:**
Always redirect stdin to `/dev/null` explicitly in the background subprocess, and in the `openclaw` call:

```bash
(
  local response exit_code
  response=$(openclaw agent --session-id "$openclaw_session_id" \
    --message "$wake_message" </dev/null 2>&1)
  exit_code=$?
  log_hook_response "$log_file" "$correlation_id" "$hook_name" "$session_name" \
    "$exit_code" "$response"
) </dev/null &
```

The `</dev/null` on both the `openclaw` call and the outer subshell closes all stdin-related blocking risks. This matches the pattern already documented in v2.0 PITFALLS.md (Pitfall 6: PreToolUse Must Exit Immediately).

**Warning signs:**
- `deliver_async_with_logging` calls appear to hang indefinitely on some hook fires
- `ps aux` shows orphaned `openclaw` processes that never exit
- Hook log shows the `hook.request` event but no corresponding `hook.response` event hours later
- The hanging behavior only occurs when Claude Code passes a specific type of event (may correlate with hook events that include binary content in pane capture)

**Phase to address:**
Phase 1 (delivery wrapper implementation) — explicit `</dev/null` on both the subshell and the `openclaw` call is required from the first implementation.

---

### Pitfall 7: Replacing debug_log Inline Definition Breaks Hooks Before lib is Sourced

**What goes wrong:**
Every hook script currently defines `debug_log()` inline at the top of the file, before any other code runs. This means logging works from line 1. If v3.0 replaces `debug_log()` with `jsonl_log()` that lives in `lib/hook-utils.sh`, the function is not available until `source "$LIB_PATH"` runs — which happens after the TMUX guard and session name extraction (currently around line 35–50 in each hook script). Any `debug_log()` or `jsonl_log()` calls in the early guards (lines 1–35: FIRED message, stdin consumption, TMUX check) would fail with "command not found" if the inline definition is removed before the sourcing is moved earlier.

Additionally, if `source "$LIB_PATH"` fails (lib file missing, permission error, syntax error in lib), the hook script currently falls through to a debug_log call that would also fail — silently. The failure path for a missing lib goes from "logs an error and exits" to "silent exit with no log entry."

**Why it happens:**
Developers move lib sourcing later in the script during v2.0 (to avoid sourcing for non-managed sessions — an optimization). v3.0 needs lib early (for the FIRED event and early guard logging). The tension between "source lib early for logging" and "source lib late for performance on unmanaged sessions" is not obvious until the first logging call fails with a confusing "command not found" error.

**How to avoid:**
Move `source "$LIB_PATH"` to the top of each hook script — immediately after `SKILL_LOG_DIR` and `GSD_HOOK_LOG` are set. The performance cost of sourcing the lib for unmanaged sessions is the 4 function definitions being parsed (~1ms), not any function execution. The tradeoff is acceptable: 1ms extra for unmanaged sessions to enable consistent logging from line 1 of managed sessions.

Remove the inline `debug_log()` function completely. Replace it with calls to the lib's `jsonl_log()` or a plain-text wrapper function defined in the lib. Do not define both — having two logging functions with different outputs in the same invocation creates inconsistent logs.

The failure path for a missing lib must be a plain `printf` fallback:
```bash
LIB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/hook-utils.sh"
if [ ! -f "$LIB_PATH" ]; then
  printf '[%s] [%s] FATAL: lib/hook-utils.sh not found — hook disabled\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$(basename "${BASH_SOURCE[0]}")" \
    >> "$GSD_HOOK_LOG" 2>/dev/null || true
  exit 0
fi
source "$LIB_PATH"
```

**Warning signs:**
- Early hook fires show `command not found: jsonl_log` in stderr (captured in Claude Code's hook error output)
- Hooks appear to run (exit 0) but no log entries appear from the first 30 lines of execution
- After refactoring, some hooks log and some do not — the difference is which hooks had lib sourcing moved to the top

**Phase to address:**
Phase 1 (hook script refactoring) — move lib sourcing to the top of ALL 6 hook scripts before any logging call; maintain a plain-printf fallback for lib-not-found to preserve the silent exit behavior.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| String interpolation in JSON (`"field": "$VAR"`) | Less typing than `--arg` | Invalid JSON whenever `$VAR` contains `"`, `\`, or newline | Never — `--arg` is mandatory |
| JSONL logging for every guard exit point | More visibility | jq overhead on every hook fire for every session (managed or not); 25–75ms latency tax | Never — restrict to managed session lifecycle events only |
| Omitting flock on log appends | Simpler jsonl_log() | Interleaved writes when concurrent hooks fire; corrupted records > 4KB | Never when wake_message field is included (routinely > 4KB) |
| Truncating raw_response to 500 chars in response event | Smaller log records | Lose full error messages from openclaw failures; debugging requires re-running the call | Acceptable in MVP; document truncation with `...<truncated>` suffix |
| Single log file for all sessions | No per-session routing needed | Pre-session events (hooks.log guard exits) mixed with managed session events; hard to filter by session | Acceptable — hooks.log is for unmanaged session events only; SESSION.log is for managed events |
| Relying on implicit variable inheritance to pass correlation_id to background subprocess | Simpler function signatures | Correlation broken if function structure changes (local variable scope) | Never — pass correlation_id as explicit parameter |

---

## Integration Gotchas

Common mistakes when connecting JSONL logging to the existing hook system.

| Integration Point | Common Mistake | Correct Approach |
|-------------------|----------------|------------------|
| jq JSON building | `printf '{"field":"%s"}' "$VAR"` — breaks on any special char | `jq -n --arg field "$VAR" '{field: $field}'` — all escaping done by jq |
| Wake message field | Embedding `$WAKE_MESSAGE` directly in jq template string | Pass as `--arg wake_message "$WAKE_MESSAGE"` — handles multiline, quotes, ANSI codes |
| Raw response field | `response=$(openclaw ...)` then string interpolate | `--arg raw_response "$(printf '%s' "$response" \| head -c 2000)"` — cap length, still use --arg |
| Async subprocess | `( openclaw ... ) &` — inherits hook stdin | `( openclaw ... </dev/null ) </dev/null &` — explicit stdin nulling |
| Correlation ID in async | Generate inside background subshell | Generate in parent, pass as explicit parameter to wrapper function |
| Log file routing | Read `$GSD_HOOK_LOG` from global inside delivery wrapper | Pass log_file as explicit parameter — captured value at call site after Phase 2 redirect |
| lib sourcing order | Source lib after TMUX guard and session extraction | Source lib immediately after SKILL_LOG_DIR/GSD_HOOK_LOG setup (top of script) |
| Guard exit logging | `jsonl_log()` call at every guard exit | Plain `printf` or no log at guard exits — JSONL only for managed session lifecycle events |
| Concurrent log writes | Bare `printf >> $LOG` for JSONL append | `flock` on `$LOG.lock` wrapping the append — prevents interleaving for large records |

---

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| jq process per log call | Each call adds 5–15ms; 5 calls = 25–75ms per hook fire | Single `jq -n` call building full record; JSONL only for lifecycle events | Immediately noticeable in bidirectional mode; subtle in async mode |
| JSONL events at every guard exit | Unmanaged sessions (personal Claude Code use) slow by 20–50ms per hook | Guard exits use plain printf or no log; JSONL for managed only | Every hook fire for every session system-wide |
| No length cap on raw_response | openclaw returns verbose output on error (stack trace, debug JSON); single response event can be 50KB | Cap raw_response at 2–4KB with `head -c N`; log full to separate overflow file if needed | When openclaw encounters errors with verbose output |
| No length cap on wake_message | Full wake message with pane content is 5–15KB; stored in every request event | Cap or omit wake_message in log (log first 2KB + "...truncated"); full message still sent to openclaw | Every hook fire in sessions with active pane content |
| flock timeout too long | Two concurrent hooks both wait 2s = 4s total delay if lock is held during openclaw call | Keep flock scope tight: lock only the `printf >> file` line, not the entire openclaw call | When openclaw call is slow (network timeout, OpenClaw server slow) |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **jq --arg usage:** All string fields use `--arg` not string interpolation — verify by running: `grep -n 'jq.*".*\$' lib/hook-utils.sh` and confirming zero matches (no unquoted variable in jq template strings)
- [ ] **Correlation pairing:** Every `hook.request` has a matching `hook.response` in the same log file — verify by checking `jq -r '.correlation_id' SESSION.log | sort | uniq -c | grep -v '2 '` shows no unpaired IDs after a full hook cycle
- [ ] **File routing:** Request and response events for one hook invocation are in the same file — verify by running two concurrent hooks and checking no split pairs across hooks.log and SESSION.log
- [ ] **stdin nulling:** `deliver_async_with_logging` uses `</dev/null` — verify `grep -n '</dev/null' lib/hook-utils.sh` shows it in the delivery wrapper
- [ ] **lib sourcing order:** All 6 hook scripts source lib BEFORE any jsonl_log call — verify `grep -n 'source.*hook-utils\|jsonl_log' scripts/*.sh` shows source always comes first in each file
- [ ] **Guard exits:** No JSONL events for guard exits in unmanaged session fast path — verify by running a hook in a non-tmux environment and confirming no jq processes are spawned: `strace -e execve bash stop-hook.sh < /dev/null 2>&1 | grep jq` (should show zero or one jq call only)
- [ ] **flock on log write:** `jsonl_log()` uses flock — verify by running Stop + Notification hooks concurrently 20 times and checking `jq -c '.' SESSION.log` returns valid JSON for all lines with zero parse errors
- [ ] **Wake message escaping:** Wake message with embedded JSON, double quotes, and newlines produces valid JSONL — test by crafting a wake message containing `{"key": "value"}`, backticks, and multiline content, then running `jq -c '.' hooks.log`

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Corrupted JSONL record from bad escaping | LOW | 1. Find corrupt line: `jq -c '.' SESSION.log 2>&1 \| grep error` 2. Remove corrupt line: `grep -v 'corrupt_pattern' SESSION.log > SESSION.log.fixed && mv SESSION.log.fixed SESSION.log` 3. Fix jsonl_log() to use --arg 4. Redeploy (requires session restart) |
| Interleaved concurrent writes | LOW-MEDIUM | 1. Identify corrupt lines 2. Delete SESSION.log (lose that session's history) 3. Add flock to jsonl_log() 4. Redeploy |
| Broken correlation (empty correlation_id in response) | LOW | 1. Recheck deliver_async_with_logging signature 2. Ensure correlation_id is explicit parameter 3. Redeploy |
| Split correlation pairs across files | LOW | 1. Merge hooks.log + SESSION.log for the session: `cat hooks.log SESSION.log \| jq -s 'sort_by(.ts)'` 2. Fix log file routing to pass explicit path 3. Redeploy |
| Hook latency spike from jq overhead | LOW | 1. Remove JSONL events from guard exits 2. Reduce jq calls to one per logging event 3. Redeploy (no session restart required for lib-only change if hooks re-source on next fire) |
| Async response capture hangs | MEDIUM | 1. Kill hung openclaw subprocesses: `pkill -f "openclaw agent"` 2. Add `</dev/null` to delivery wrapper 3. Redeploy |
| lib sourcing too late (command not found) | LOW | 1. Move source line to top of affected hook script 2. Redeploy |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| JSON escaping with raw string interpolation | Phase 1: `jsonl_log()` implementation — use `--arg` for all fields | `grep -n 'jq.*"\$' lib/hook-utils.sh` returns zero matches |
| Concurrent write interleaving > 4KB | Phase 1: `jsonl_log()` implementation — flock on every append | Run 20 concurrent Stop+Notification hook pairs, `jq -c '.' SESSION.log` reports zero errors |
| Correlation ID lost in async subprocess | Phase 1: `deliver_async_with_logging()` signature — explicit parameter | `jq '.correlation_id' SESSION.log \| sort \| uniq -c` shows all IDs appear exactly twice |
| Correlation pairs split across log files | Phase 1: delivery wrapper design — explicit log_file parameter captured post-redirect | Check no response events appear in hooks.log for managed sessions |
| jq overhead on guard exits | Phase 1: JSONL logging policy — only lifecycle events get JSONL | Time unmanaged session hook exit: `time bash stop-hook.sh < /dev/null` < 10ms |
| Async stdin inheritance causing hang | Phase 1: `deliver_async_with_logging()` — explicit `</dev/null` | Run delivery wrapper with simulated openclaw that reads stdin; verify no hang |
| lib sourcing before first log call | Phase 1: hook script refactoring — move source to top of all 6 scripts | `grep -n 'source.*hook-utils\|jsonl_log' scripts/stop-hook.sh` shows source before any jsonl_log call |

---

## Sources

### Linux Write Atomicity
- [Are Files Appends Really Atomic? — Not The Wizard (2014)](https://www.notthewizard.com/2014/06/17/are-files-appends-really-atomic/) — empirical PIPE_BUF limits by OS: Debian ext4 safe to ~1,008 bytes, CentOS safe to 4,096 bytes; confirms bash `>>` is not guaranteed atomic above PIPE_BUF (MEDIUM confidence — empirical, pre-2025)
- [Appending to a File from Multiple Processes — nullprogram (2016)](https://nullprogram.com/blog/2016/08/03/) — POSIX O_APPEND atomicity guarantees and limits; explicit warning that PIPE_BUF atomicity for files is "not correct" per POSIX spec (HIGH confidence — references POSIX spec directly)
- [Appending to a log: an introduction to the Linux dark arts — Paul Khuong (2021)](https://pvk.ca/Blog/2021/01/22/appending-to-a-log-an-introduction-to-the-linux-dark-arts/) — buffered I/O risk and flushing policy concerns for concurrent log writes (HIGH confidence)

### jq JSON Escaping
- [How to Resolve JSON Parse Error: Control Characters U+0000–U+001F — codestudy.net](https://www.codestudy.net/blog/parse-error-when-text-is-split-on-multi-lines-control-characters-from-u-0000-through-u-001f-must-be-escaped/) — control character escaping requirement in JSON strings (MEDIUM confidence)
- [How to Escape Characters in Bash for JSON — tutorialpedia.org](https://www.tutorialpedia.org/blog/escaping-characters-in-bash-for-json/) — `--arg` flag as the correct escaping mechanism; `jq -Rsa .` for multiline strings (MEDIUM confidence)
- [Build a JSON String With Bash Variables — Baeldung on Linux](https://www.baeldung.com/linux/bash-variables-create-json-string) — `jq -n --arg` pattern for safe variable injection (HIGH confidence)
- [jq 1.8 Manual — jqlang.org](https://jqlang.org/manual/) — `--arg`, `--rawfile`, `@json` format filter documentation (HIGH confidence — official)

### flock and File Locking
- [flock(1) — Linux Manual Page](https://man7.org/linux/man-pages/man1/flock.1.html) — `-x` exclusive lock, `-w` timeout, fd-based lock file pattern (HIGH confidence — official)
- [Mastering Flock Bash — bashcommands.com](https://bashcommands.com/flock-bash) — practical flock patterns for critical sections (MEDIUM confidence)
- [Introduction to File Locking in Linux — Baeldung](https://www.baeldung.com/linux/file-locking) — advisory vs mandatory locking; kernel manages release on process death (HIGH confidence)

### Structured Logging and Correlation IDs
- [JSONL for Log Processing — JSONL.help](https://jsonl.help/use-cases/log-processing/) — JSONL design rationale for log streaming; append-friendly properties (MEDIUM confidence)
- [Structured Logging Best Practices — Uptrace](https://uptrace.dev/glossary/structured-logging) — essential fields: timestamp, level, correlation_id, component, message (MEDIUM confidence)
- [IBM MCP Context Forge Issue #300 — GitHub](https://github.com/IBM/mcp-context-forge/issues/300) — real-world 2025 example of structured JSON logging with correlation ID schema design (MEDIUM confidence)

### Bash Subprocess Environment
- [Command Execution Environment — Bash Reference Manual](https://www.gnu.org/software/bash/manual/html_node/Command-Execution-Environment.html) — background (`&`) subshells inherit parent environment; changes in child do not propagate to parent (HIGH confidence — official)

---

## Prior Milestone Pitfalls (Already Solved — v2.0)

The following pitfalls were fully documented in the v2.0 PITFALLS.md (researched 2026-02-17) and are not re-litigated here. All prevention measures are implemented in the shipped v2.0 codebase:

- Transcript content[0].text positional indexing failure (use type-filtered content[]?)
- Partial JSONL transcript read during active write (2>/dev/null fallback)
- Full transcript file read latency (tail -20 enforced)
- AskUserQuestion result stripping bug (fixed in Claude Code 2.0.76; production is 2.1.45)
- Wide PreToolUse matcher firing on all tools (matcher scoped to "AskUserQuestion")
- PreToolUse blocking openclaw call (backgrounded with </dev/null >/dev/null 2>&1 &)
- Stale pane delta temp files from dead sessions (age check + session-end cleanup)
- Race condition on pane delta temp files (flock on gsd-pane-lock-SESSION)
- Deduplication over-suppression without minimum context (10-line minimum enforced)
- Wake message v2 format breaking orchestrator (wake_message_version field added)
- transcript_path file not found (existence check before read)

---

*Pitfalls research for: v3.0 Structured JSONL Hook Observability — Adding to existing v2.0 production hook system*
*Researched: 2026-02-18*
*Researcher: GSD Project Researcher*
*Confidence: HIGH — Linux kernel documentation, empirical write-atomicity research, analysis of v2.0 codebase, confirmed bash+jq behavior*
