# Pitfalls Research

**Domain:** Adding Transcript Extraction, PreToolUse Hook, Diff Delivery, and Deduplication to an Existing Production Hook System
**Researched:** 2026-02-17
**Confidence:** HIGH — based on official Claude Code documentation, confirmed GitHub issues (2026), and analysis of the existing v1.0 codebase

---

## Scope

This document covers pitfalls specific to v2.0 Smart Hook Delivery features added to the existing v1.0 hook system. The v1.0 pitfalls (stop_hook_active loop, stdin blocking, registry corruption, background stdin inheritance, fast-path guards) are already solved and are NOT re-documented here. This focuses exclusively on integration risks when adding new capabilities to a working production system.

---

## Critical Pitfalls

### Pitfall 1: Transcript JSONL Content Is Not Always `message.content[0].text`

**What goes wrong:**
The script extracts the last assistant message using `jq -r 'select(.type == "assistant") | .message.content[0].text'` on the JSONL file. This fails silently and returns empty or null whenever: (a) the last assistant turn contains thinking blocks before the text block, (b) the content array has `tool_use` entries interleaved, or (c) Claude used extended thinking and `content[0]` is a `{"type": "thinking"}` block rather than a `{"type": "text"}` block.

**Why it happens:**
The JSONL `message.content` field is an array of typed blocks. The assumption that `content[0]` is always the text response is false. Claude Code transcripts include thinking blocks, tool_use blocks, and tool_result blocks within a single assistant turn. Indexing by position is fragile; filtering by type is required.

**How to avoid:**
Filter content blocks by type, not by index:
```bash
# WRONG — assumes content[0] is text
jq -r 'select(.type == "assistant") | .message.content[0].text'

# CORRECT — filter for text blocks explicitly
jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text'
```
Then take `tail -1` of the pipeline output to get the last text block from the last assistant turn.

**Warning signs:**
- `[RESPONSE]` section in wake message is empty or contains "null"
- Works in simple sessions but fails in sessions with extended thinking enabled
- Works on short sessions but fails on longer sessions where Claude uses tools before responding

**Phase to address:**
Phase 1 (Transcript Extraction) — use typed content filtering from the start; never use positional indexing on `message.content`.

---

### Pitfall 2: JSONL File Is Being Written While You Read It (Partial-Line Reads)

**What goes wrong:**
The transcript JSONL file at `transcript_path` is actively written by Claude Code during and after hook execution. When the Stop hook fires and reads the file with `tail -N`, it may read a partially written JSON line that Claude Code is mid-write. `jq` fails with a parse error on a truncated line, the entire extraction returns empty, and the wake message has no `[RESPONSE]` section.

**Why it happens:**
The Stop hook fires when Claude finishes responding, but Claude Code may not have flushed the final JSONL line to disk yet, or may be writing metadata lines after the assistant message. `tail` reads whatever bytes are on disk at the moment of the call. A partial JSON line at the tail causes `jq` to fail the entire input.

**How to avoid:**
Use `jq --seq` (streaming mode) which skips malformed lines, or filter out parse errors explicitly:
```bash
# Resilient extraction — skips malformed lines at EOF
LAST_RESPONSE=$(tail -20 "$TRANSCRIPT_PATH" 2>/dev/null \
  | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' \
  2>/dev/null | tail -1)

# LAST_RESPONSE will be empty string if no valid assistant message found
LAST_RESPONSE="${LAST_RESPONSE:-<response not available>}"
```
The `2>/dev/null` suppresses jq parse errors from partial lines. The fallback string prevents empty `[RESPONSE]` sections.

**Warning signs:**
- Intermittent failures on the first hook fire after a session starts
- `[RESPONSE]` is empty on some hook fires but not others
- jq parse errors in the hook log file
- Works reliably when testing with static JSONL files but fails with live sessions

**Phase to address:**
Phase 1 (Transcript Extraction) — use `2>/dev/null` on all jq invocations against transcript files; always provide a non-empty fallback string.

---

### Pitfall 3: Large Transcript Files Cause Hook Latency Spikes

**What goes wrong:**
Long sessions accumulate thousands of JSONL lines. `tail -20` is fast, but `jq` parsing 20 lines of a potentially large multi-MB file is also fast — however, if the implementation incorrectly reads the entire file instead of tailing it (e.g., `cat "$TRANSCRIPT_PATH" | jq ...` instead of `tail -20 "$TRANSCRIPT_PATH" | jq ...`), the hook blocks for 100ms–2s on large files. For non-managed sessions, the fast-path exits before transcript reading, so this only affects managed sessions, but it can still violate the "hooks exit fast" principle and delay orchestrator wake delivery.

**Why it happens:**
Developers default to `cat file | jq` because it's readable. The JSONL file grows unbounded per session (no rotation). In a long day of Claude Code usage, a single session transcript can exceed 10MB.

**How to avoid:**
Always use `tail -N` before piping to jq, where N is the minimum lines needed to reliably find the last assistant message. 20 lines is sufficient for all current Claude Code response patterns:
```bash
# WRONG — reads entire potentially large file
LAST_RESPONSE=$(jq -r '...' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)

# CORRECT — reads only last 20 lines
LAST_RESPONSE=$(tail -20 "$TRANSCRIPT_PATH" 2>/dev/null \
  | jq -r '...' 2>/dev/null | tail -1)
```
The tradeoff: if Claude sends an unusually long response that spans more than 20 lines in the JSONL (unlikely since each line is one message object), extraction fails. 20 lines is a safe buffer.

**Warning signs:**
- Hook log shows execution times >100ms for managed sessions in long-running projects
- Tail latency increases over the course of a work session
- Hook execution time correlates with session age, not response length

**Phase to address:**
Phase 1 (Transcript Extraction) — enforce `tail -20` pattern in code review; document the pattern in the extraction function's comments.

---

### Pitfall 4: `AskUserQuestion` PreToolUse Hook Has a Known Result-Stripping Bug (Fixed in v2.0.76)

**What goes wrong:**
On Claude Code versions prior to v2.0.76, any active PreToolUse hook causes `AskUserQuestion` tool results to be stripped. The user answers the question in the CLI, but Claude Code only receives an empty result back: `"User has answered your questions: ."` instead of the actual answer. Claude cannot proceed intelligently because it cannot see what the user chose.

**Why it happens:**
This was a confirmed Claude Code bug in the hook result processing pipeline for UI-only tools. When any PreToolUse hook is active (even for unrelated tools), the `AskUserQuestion` result data is dropped. The fix was shipped in v2.0.76 (January 2026).

**How to avoid:**
1. Verify the production Claude Code version is >= v2.0.76 before deploying the PreToolUse hook: `claude --version`
2. Add a version check to the deployment/registration step in `register-hooks.sh`
3. Document the minimum version requirement in SKILL.md

If the system cannot be upgraded past v2.0.76:
- Do NOT add a PreToolUse hook that matches `AskUserQuestion` or uses `"*"` matcher
- Use the Notification hook for `elicitation_dialog` events as a read-only alternative

**Warning signs:**
- After deploying the PreToolUse hook, Claude sessions that ask questions appear confused or repeat questions
- Hook log shows `AskUserQuestion` being intercepted but subsequent Claude behavior is wrong
- `claude --version` shows a version below 2.0.76

**Phase to address:**
Phase 1 (PreToolUse Hook Creation) — add explicit version gate; test against real `AskUserQuestion` flow before production deployment.

---

### Pitfall 5: PreToolUse Hook Fires for Every Tool, Not Just `AskUserQuestion`

**What goes wrong:**
The PreToolUse hook is registered with matcher `"AskUserQuestion"` in settings.json. However, developers later change the matcher to `"*"` or `""` (intending to add other tool handling), or they add a second PreToolUse matcher group that catches everything. Now the hook fires for every single tool call — `Bash`, `Edit`, `Write`, `Read`, `Glob`, `Grep`, `Task`, `WebFetch`, `WebSearch` — and for all MCP tool calls. Even with a fast-path exit in the hook script, registry lookup runs on every tool invocation, adding 10–50ms latency to each tool call in managed sessions.

**Why it happens:**
The matcher is a regex. `"AskUserQuestion"` is the correct matcher for targeting only that tool. But if the hook script has logic for "if tool_name is X do Y, else exit 0", developers think it's safe to use a broad matcher because "the script handles it." The performance cost of the fast-path exit (stdin consumption + optional jq parse) is invisible in single-session testing.

**How to avoid:**
Use the most specific matcher possible. `"AskUserQuestion"` matches only `AskUserQuestion`. Do not use `"*"` unless the hook genuinely needs to fire for every tool:
```json
{
  "PreToolUse": [
    {
      "matcher": "AskUserQuestion",
      "hooks": [{ "type": "command", "command": "/path/to/pre-tool-use-hook.sh" }]
    }
  ]
}
```
If the hook needs to handle other tools in the future, add separate matcher groups rather than broadening the existing one.

**Warning signs:**
- Hook log shows `pre-tool-use-hook.sh` firing dozens of times per Claude response (one per tool call)
- Claude Code sessions feel slower than before the PreToolUse hook was added
- Hook log shows `tool_name=Bash`, `tool_name=Edit`, etc. when only `AskUserQuestion` was expected

**Phase to address:**
Phase 1 (PreToolUse Hook Creation) — set matcher to `"AskUserQuestion"` explicitly in settings.json; document why the matcher must not be broadened.

---

### Pitfall 6: PreToolUse Must Exit Immediately (No Blocking, No OpenClaw Wake)

**What goes wrong:**
The PreToolUse hook for `AskUserQuestion` synchronously calls `openclaw agent --session-id ... --message ...` in the foreground (not backgrounded) to notify the orchestrator. The `openclaw` CLI call takes 200ms–2s. During this time, Claude Code is blocked waiting for the hook to return. The user sees the CLI freeze before the question is displayed. If the `openclaw` call times out or fails, Claude Code's hook timeout eventually kills it, and the question may never display.

**Why it happens:**
Developers copy the async delivery pattern from `stop-hook.sh` correctly (backgrounding the `openclaw` call), but then forget to add `&` when writing the PreToolUse hook, or they intentionally make it synchronous to ensure delivery before the question appears. The urge to "guarantee delivery before the question shows" leads to synchronous calls.

**How to avoid:**
Always background the `openclaw` call in PreToolUse hooks, identical to the stop-hook.sh pattern:
```bash
# WRONG — blocks Claude Code while waiting for openclaw
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE"

# CORRECT — backgrounds immediately, hook exits fast
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" \
  </dev/null >/dev/null 2>&1 &
exit 0
```
The PreToolUse hook cannot inject an answer anyway (the feature request for that is unresolved). It is purely a notification-only hook. Fast exit is non-negotiable.

**Warning signs:**
- Claude Code pauses for 0.5–2s before showing the `AskUserQuestion` prompt
- Hook log shows the hook running for longer than 100ms
- `openclaw` process is not in the background (`ps aux` shows it as foreground child of the hook)

**Phase to address:**
Phase 1 (PreToolUse Hook Creation) — enforce `</dev/null >/dev/null 2>&1 &` on all openclaw calls; add timing assertion in testing.

---

### Pitfall 7: Pane Delta Temp Files Accumulate When Sessions Die Without Cleanup

**What goes wrong:**
The diff-based delivery system writes previous pane content to `/tmp/gsd-pane-prev-${SESSION_NAME}` each hook fire. When a tmux session is killed unexpectedly (OOM, user `kill`, server restart without graceful shutdown), the temp file is never deleted. Over time (days of operation), `/tmp/` accumulates stale pane files from dead sessions. On systems with small `/tmp/` (e.g., a RAM-backed tmpfs with 2GB limit), these files can exhaust /tmp space. More subtly, if a new session is created with the same `SESSION_NAME` as a previously dead session, it reads a stale pane file as its "previous" state and generates a diff against the wrong baseline — sending a confusing "delta" to the orchestrator that shows the previous session's last screen compared to the new session's first screen.

**Why it happens:**
The cleanup hook (`session-end-hook.sh`) is supposed to delete the temp file when the session ends. But `SessionEnd` only fires on clean exits. It does not fire on `SIGKILL`, OOM kills, or server crashes. The v1.0 `session-end-hook.sh` already exists but does not yet know about pane delta files.

**How to avoid:**
1. In `session-end-hook.sh`, add cleanup of the pane delta temp file:
```bash
PANE_PREV_FILE="/tmp/gsd-pane-prev-${SESSION_NAME}"
rm -f "$PANE_PREV_FILE" 2>/dev/null || true
```
2. Detect stale files by checking modification time at hook startup — if the file is older than 24 hours, treat it as stale and delete it before using it:
```bash
if [ -f "$PANE_PREV_FILE" ]; then
  FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$PANE_PREV_FILE" 2>/dev/null || echo 0) ))
  if [ "$FILE_AGE" -gt 86400 ]; then
    rm -f "$PANE_PREV_FILE"
  fi
fi
```
3. Add a periodic cleanup cron: `find /tmp -name 'gsd-pane-prev-*' -mtime +1 -delete` — but this is defense-in-depth, not the primary cleanup.

**Warning signs:**
- `/tmp` usage grows steadily over days
- New sessions receive confusing "delta" content showing unrelated pane state
- `ls /tmp/gsd-pane-prev-*` shows files with session names that no longer exist in tmux (`tmux list-sessions`)

**Phase to address:**
Phase 1 (Diff-Based Delivery) — add stale file detection at hook startup; Phase 2 — update `session-end-hook.sh` to delete the temp file on clean exits.

---

### Pitfall 8: Race Condition Between Concurrent Hook Fires and Pane Delta Temp Files

**What goes wrong:**
Two hook events fire simultaneously (e.g., Stop hook fires while a Notification hook is also firing for the same session). Both hooks read `gsd-pane-prev-${SESSION_NAME}`, both capture the current pane, and both attempt to write the new pane content to the temp file. The write operations race: Hook A reads prev → Hook B reads prev → Hook A writes new prev → Hook B writes new prev (overwriting A's write). Both hooks generate a diff against the same original baseline, creating duplicate wakes. Worse, if the filesystem write is not atomic, Hook B may read a partially written file from Hook A.

**Why it happens:**
Multiple Claude Code hook events can fire simultaneously for the same session. The Stop hook and Notification hook both capture pane state. Without synchronization on the temp file, they race.

**How to avoid:**
Use `flock` on a session-specific lock file for the read-write-update cycle:
```bash
PANE_LOCK_FILE="/tmp/gsd-pane-lock-${SESSION_NAME}"
PANE_PREV_FILE="/tmp/gsd-pane-prev-${SESSION_NAME}"

(
  flock -x -w 2 200 || { debug_log "WARN: could not acquire pane lock, skipping diff"; exit 0; }

  PREV_HASH=$(cat "$PANE_PREV_FILE" 2>/dev/null || echo "")
  CURRENT_PANE=$(tmux capture-pane -pt "${SESSION_NAME}:0.0" -S "-${PANE_CAPTURE_LINES}" 2>/dev/null || echo "")
  CURRENT_HASH=$(echo "$CURRENT_PANE" | sha256sum | cut -d' ' -f1)

  # Write new state atomically
  echo "$CURRENT_HASH" > "${PANE_PREV_FILE}.tmp.$$"
  mv "${PANE_PREV_FILE}.tmp.$$" "$PANE_PREV_FILE"

) 200>"$PANE_LOCK_FILE"
```
The `flock -w 2` waits up to 2 seconds for the lock. If it cannot acquire within 2 seconds, it skips the diff (logging a warning) rather than blocking the hook indefinitely.

**Warning signs:**
- Orchestrator receives duplicate wake messages within milliseconds of each other
- Wake message delta content repeats across consecutive calls
- `/tmp/gsd-pane-prev-*` files contain partial content (mid-write corruption)
- Hook log shows two hook scripts running simultaneously for the same session

**Phase to address:**
Phase 1 (Diff-Based Delivery) — implement `flock`-based synchronization from the start; never read-modify-write the temp file without a lock.

---

### Pitfall 9: Deduplication Skips Important State Changes (Over-Aggressive Suppression)

**What goes wrong:**
The deduplication logic compares the SHA256 hash of the current pane against the previous pane. If they match exactly, the wake is skipped entirely (or only a lightweight signal is sent). But two scenarios break this:

1. **Visually identical but semantically different**: The pane shows "Claude is working..." both before and after a tool call. The hash matches, so the wake is suppressed. But the orchestrator needed to know Claude called a tool and is now waiting for a different reason.

2. **Minimum context guarantee violated**: The "skip wake" path sends no pane content. If the orchestrator was just recovered (e.g., after a server restart) and has no prior context, it receives a lightweight "no change" signal with zero lines of context, making it unable to assess the session state.

**Why it happens:**
Deduplication is implemented as a binary choice: "same hash = skip everything." This ignores the fact that some state transitions have identical pane appearance but different semantic meaning. The minimum 10-line context guarantee specified in the requirements is easy to omit when implementing the "skip" path.

**How to avoid:**
Never send zero context in the skip path. The minimum-context guarantee must be enforced even when deduplication suppresses the delta:
```bash
if [ "$CURRENT_HASH" = "$PREV_HASH" ]; then
  # Deduplication applies — but still send minimum context
  MINIMUM_CONTEXT=$(echo "$CURRENT_PANE" | tail -10)
  WAKE_MESSAGE="... [RESPONSE] <deduplicated — no change> [PANE DELTA] (none — identical to previous) [MINIMUM CONTEXT] ${MINIMUM_CONTEXT} ..."
  # Send lightweight wake, not full wake
  debug_log "DEDUP: pane unchanged, sending minimum context"
else
  # Full delta delivery
  PANE_DELTA=$(diff <(echo "$PREV_PANE") <(echo "$CURRENT_PANE") --unified=0 2>/dev/null || echo "")
  WAKE_MESSAGE="... [PANE DELTA] ${PANE_DELTA} ..."
fi
```

**Warning signs:**
- Orchestrator misses questions or menus because pane looked the same as before
- After server restart, orchestrator cannot assess session state despite sessions being active
- Wake log shows "DEDUP: skipping" repeatedly while the session is actively doing work

**Phase to address:**
Phase 1 (Deduplication) — minimum 10-line context guarantee is a hard requirement, not optional optimization; enforce with a test case that verifies the "skip" path still delivers context.

---

### Pitfall 10: Wake Message v2 Format Breaks Orchestrator Agents Parsing the Old Format

**What goes wrong:**
The v1.0 wake message contains `[PANE CONTENT]` followed by raw pane text. Orchestrator agents (Gideon) have been trained on or adapted to this format — their parsing logic looks for `[PANE CONTENT]` to find the terminal state. v2.0 replaces this with `[RESPONSE]` (transcript-extracted) and `[PANE DELTA]` (diff-based). If the format change is deployed to all hooks simultaneously, Gideon receives wake messages in a format it doesn't recognize, causing it to miss the session state entirely and potentially make wrong decisions.

**Why it happens:**
Wake message format is an implicit contract between the hook system and the orchestrator agent. There is no schema versioning in the v1.0 format. When the format changes, the orchestrator must be updated simultaneously — or the change must be backward compatible. In a multi-session system, some sessions may still be running v1.0 hooks (loaded at session start, snapshot-based) while new sessions use v2.0 hooks.

**How to avoid:**
1. Add a format version marker to every wake message header that the orchestrator can check:
```
[SESSION IDENTITY]
agent_id: warden
wake_message_version: 2
```
2. During v2.0 rollout, keep `[PANE CONTENT]` in the message alongside `[RESPONSE]` and `[PANE DELTA]` for a transition period (additive change, not replacement)
3. Update Gideon's parsing logic BEFORE or SIMULTANEOUSLY with deploying the new hook format — never after
4. Hooks are snapshotted at session startup — existing sessions keep the old format until they restart

Note: Claude Code hooks snapshot at startup. Existing sessions that were launched before the hook update continues to use the old hook scripts. Only newly started sessions use v2.0 hooks. This means the orchestrator may receive both v1.0 and v2.0 format messages simultaneously during the transition.

**Warning signs:**
- After deploying v2.0 hooks, Gideon sends wrong menu choices or fails to respond
- Gideon reports "no pane content in wake message" in its reasoning
- Wake messages show `[RESPONSE]` and `[PANE DELTA]` but Gideon acts on stale context
- Older sessions (pre-v2.0 hook registration) continue sending `[PANE CONTENT]` while newer sessions send the new format

**Phase to address:**
Phase 1 (Wake Message v2 Structure) — add `wake_message_version` field; Phase 2 (Deployment) — keep backward-compatible sections during rollout; update orchestrator before hook deployment, not after.

---

### Pitfall 11: `transcript_path` Not Available in All Hook Events Where It's Expected

**What goes wrong:**
The implementation reads `transcript_path` from the PreToolUse hook's stdin JSON, assuming it's always present. According to the official docs, `transcript_path` is listed as a common input field received by ALL hooks. However, there are edge cases: if the session was started in a way that bypasses normal session initialization, or if the transcript file has not been created yet (very first hook fire of a new session), the path may be present but the file may not exist yet on disk.

**Why it happens:**
The field is always present in the JSON, but the file it points to may not exist (race condition at session start) or may be a path to a non-existent directory (if `~/.claude/projects/...` was cleared). Code that reads `transcript_path` and immediately passes it to `tail` without checking file existence fails with "No such file or directory" on stderr, which jq then sees as empty input.

**How to avoid:**
Always check file existence before reading:
```bash
TRANSCRIPT_PATH=$(echo "$STDIN_JSON" | jq -r '.transcript_path // ""' 2>/dev/null)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  debug_log "TRANSCRIPT: file not available at $TRANSCRIPT_PATH — skipping extraction"
  LAST_RESPONSE="<transcript not available>"
else
  LAST_RESPONSE=$(tail -20 "$TRANSCRIPT_PATH" 2>/dev/null \
    | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' \
    2>/dev/null | tail -1)
  LAST_RESPONSE="${LAST_RESPONSE:-<no assistant message found>}"
fi
```

**Warning signs:**
- `[RESPONSE]` section shows empty on the very first hook fire of a new session
- Hook log shows "tail: /home/forge/.claude/projects/.../transcript.jsonl: No such file or directory"
- Sessions where Claude responds immediately without any tool use fail to extract responses

**Phase to address:**
Phase 1 (Transcript Extraction) — file existence check is mandatory; add to the pre-submission checklist.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `cat transcript | jq` instead of `tail -20 | jq` | Simpler code | Hook latency spikes on long sessions (>1000 lines) | Never — always `tail -N` |
| `content[0].text` instead of `content[]? \| select(.type=="text") \| .text` | Less typing | Silent extraction failures with thinking blocks | Never — type filtering is required |
| Synchronous `openclaw agent` call in PreToolUse | Guaranteed delivery order | Blocks Claude Code UI for 200ms–2s | Never — PreToolUse must exit fast |
| Wide PreToolUse matcher `"*"` instead of `"AskUserQuestion"` | Future-proofing for other tools | Registry lookup on every tool call, latency tax | Never — add separate matcher groups |
| Skip minimum context guarantee in dedup skip path | Smaller wake messages | Orchestrator cannot assess state after recovery | Never — 10-line minimum is contractual |
| Deploy v2 format without backward compatibility period | Cleaner codebase | Orchestrator receives unknown format for active sessions | Never — always transition additively |
| Pane delta temp files without flock | Simpler code | Race condition on concurrent hook fires, duplicate wakes | Never in production — flock is required |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| JSONL transcript parsing | Use `content[0].text` assuming first block is text | Use `content[]? \| select(.type == "text") \| .text` to filter by type |
| JSONL transcript parsing | `cat transcript \| jq` — reads full file | `tail -20 transcript \| jq` — reads only last 20 lines |
| JSONL transcript parsing | No fallback when extraction returns empty | Always provide `"${EXTRACTED:-<default>}"` fallback |
| PreToolUse hook for AskUserQuestion | Using `"*"` matcher | Use `"AskUserQuestion"` matcher specifically |
| PreToolUse hook for AskUserQuestion | Synchronous openclaw call | Background with `</dev/null >/dev/null 2>&1 &` |
| Pane delta temp files | No cleanup on session death | Check file age at startup; update `session-end-hook.sh` to delete on clean exit |
| Pane delta temp files | Read-write without locking | Use `flock` on a per-session lock file for the read-update-write cycle |
| Deduplication skip path | Send zero context when hash matches | Always send `tail -10` minimum context even in the skip path |
| Wake message v2 format | Replace `[PANE CONTENT]` immediately | Keep v1 sections alongside v2 sections during transition; add version field |
| Claude Code version | Deploy PreToolUse without version check | Verify `claude --version >= 2.0.76` before deploying PreToolUse hook |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full transcript file read | Hook latency grows with session age | Always `tail -20` before jq | Sessions older than ~2 hours (>500 JSONL lines) |
| Wide PreToolUse matcher | Hook fires on every tool call (dozens per Claude response) | Specific matcher `"AskUserQuestion"` | From day 1, invisible in testing |
| Synchronous openclaw in PreToolUse | Claude Code UI freezes 200ms–2s before showing question | Background all openclaw calls | Every AskUserQuestion invocation |
| No flock on pane delta file | Duplicate wakes when Stop + Notification fire simultaneously | `flock -x -w 2` on per-session lock | When claude uses tools that trigger both Stop and Notification |
| Stale pane delta files | Wrong baseline on session reuse | Age check + session-end cleanup | After any unexpected session death |

---

## "Looks Done But Isn't" Checklist

- [ ] **Transcript extraction:** Uses `content[]? | select(.type == "text") | .text` not `content[0].text` — verify with a session that has thinking blocks enabled
- [ ] **Transcript extraction:** Uses `tail -20 "$TRANSCRIPT_PATH"` not `cat "$TRANSCRIPT_PATH"` — verify hook latency stays <100ms on a large transcript (>5MB)
- [ ] **Transcript extraction:** Has fallback string when extraction returns empty — verify with a fresh session where the transcript has only user messages
- [ ] **Transcript extraction:** Checks file existence before reading — verify behavior when `transcript_path` points to a nonexistent file
- [ ] **PreToolUse hook:** Matcher is `"AskUserQuestion"` not `"*"` — verify hook log shows no fires for `Bash`, `Edit`, or other tools
- [ ] **PreToolUse hook:** openclaw call is backgrounded with `</dev/null >/dev/null 2>&1 &` — verify hook exits in <50ms
- [ ] **PreToolUse hook:** Deployment verified on Claude Code >= v2.0.76 — check `claude --version`
- [ ] **Pane delta files:** Uses `flock` on per-session lock file — verify no duplicate wakes when Stop and Notification fire simultaneously
- [ ] **Pane delta files:** Stale file detection at hook startup — verify new session doesn't inherit previous session's pane state
- [ ] **Pane delta files:** `session-end-hook.sh` deletes temp file on clean exit — verify temp files are cleaned after `/clear` or session logout
- [ ] **Deduplication:** "skip" path sends minimum 10 lines of context — verify with two identical pane states that orchestrator still receives actionable content
- [ ] **Wake message v2:** `wake_message_version: 2` field present in all new messages — verify orchestrator can parse both v1 and v2 during transition

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Content extraction returns empty | LOW | 1. Check jq filter syntax 2. Add `2>/dev/null` and fallback string 3. Redeploy hook (requires session restart to pick up new script) |
| Partial JSONL read causes jq error | LOW | 1. Add `2>/dev/null` to suppress errors 2. Redeploy hook 3. Wait for next hook fire |
| Hook latency spike from full transcript read | LOW | 1. Change `cat` to `tail -20` 2. Redeploy hook (requires session restart) |
| AskUserQuestion result stripped bug | MEDIUM | 1. Upgrade Claude Code to >= v2.0.76 2. All existing sessions must restart |
| PreToolUse blocking hook | MEDIUM | 1. Kill the hung hook process 2. Background the openclaw call 3. Redeploy hook |
| Stale pane delta file | LOW | 1. `rm /tmp/gsd-pane-prev-${SESSION_NAME}` manually 2. Next hook fire creates fresh baseline |
| Race condition on pane delta file | MEDIUM | 1. Add flock 2. Redeploy hook 3. Old sessions without fix may still race until restarted |
| Deduplication skipping too aggressively | LOW | 1. Lower the dedup threshold 2. Add minimum context to skip path 3. Redeploy hook |
| Wake v2 format breaks orchestrator | HIGH | 1. Roll back hook to v1 format 2. Update orchestrator to handle both formats 3. Redeploy with backward-compatible format |
| Transcript path file not found | LOW | 1. Add file existence check 2. Redeploy hook |

---

## Pitfall-to-Phase Mapping

| Pitfall | Feature Affected | Prevention Phase | Verification |
|---------|------------------|------------------|--------------|
| `content[0].text` extraction fails | Transcript extraction | Phase 1 (transcript feature) | Test with thinking-enabled session |
| Partial JSONL read from concurrent write | Transcript extraction | Phase 1 (transcript feature) | Test on live session, not static file |
| Full transcript file read latency | Transcript extraction | Phase 1 (transcript feature) | Benchmark with >5MB transcript file |
| AskUserQuestion result stripping bug | PreToolUse hook | Phase 1 (PreToolUse feature) | Verify `claude --version >= 2.0.76` |
| Wide PreToolUse matcher | PreToolUse hook | Phase 1 (PreToolUse feature) | Check hook log for unexpected tool fires |
| PreToolUse blocking hook | PreToolUse hook | Phase 1 (PreToolUse feature) | Time hook exit in <50ms |
| Stale pane delta temp files | Diff-based delivery | Phase 1 (diff feature) + Phase 2 (session-end cleanup) | Verify /tmp after 24h operation |
| Race condition on pane delta temp file | Diff-based delivery | Phase 1 (diff feature) | Test with concurrent Stop + Notification hooks |
| Deduplication over-suppression | Deduplication | Phase 1 (dedup feature) | Test: two identical pane states still deliver 10 lines |
| Wake v2 format breaks orchestrator | Wake message v2 | Phase 1 (format design) + Phase 2 (deployment) | Verify orchestrator parses both v1 and v2 formats |
| transcript_path file not found | Transcript extraction | Phase 1 (transcript feature) | Test at session start before first Claude response |

---

## Sources

### Claude Code Official Documentation
- [Hooks Reference — Claude Code Docs](https://code.claude.com/docs/en/hooks) — PreToolUse stdin format, matcher patterns, transcript_path field, all hook event schemas (HIGH confidence)

### Confirmed GitHub Issues
- [Bug: PreToolUse Hooks Strip Result Data from AskUserQuestion Tool (Issue #12031)](https://github.com/anthropics/claude-code/issues/12031) — confirms v2.0.76 fix, exact symptoms (HIGH confidence)
- [Feature: AskUserQuestion Hook Support (Issue #12605)](https://github.com/anthropics/claude-code/issues/12605) — confirms PreToolUse can detect but not answer AskUserQuestion (HIGH confidence)

### JSONL Structure Research
- [claude-code-log: Python CLI for Claude Code JSONL transcripts](https://github.com/daaain/claude-code-log) — confirms content array with typed blocks (thinking, tool_use, text) (MEDIUM confidence)
- [Claude Code Transcript JSONL Format (Simon Willison)](https://simonwillison.net/2025/Dec/25/claude-code-transcripts/) — confirms JSONL format and session structure (MEDIUM confidence)

### Bash Patterns
- [diff(1) — Linux Manual Page](https://man7.org/linux/man-pages/man1/diff.1.html) — diff unified output format (HIGH confidence)
- [flock(1) — Linux Manual Page](https://man7.org/linux/man-pages/man1/flock.1.html) — exclusive locking for race condition prevention (HIGH confidence)

---

*Pitfalls research for: v2.0 Smart Hook Delivery — Adding to Existing Production Hook System*
*Researched: 2026-02-17*
*Researcher: GSD Project Researcher*
*Confidence: HIGH — official documentation, confirmed GitHub issues (2026), and analysis of existing v1.0 codebase*
