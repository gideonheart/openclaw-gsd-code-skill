---
phase: quick-13
plan: 01
type: execute
wave: 1
depends_on: []
files_modified: [bin/hook-event-logger.sh]
autonomous: true
requirements: [REV-3.1]
must_haves:
  truths:
    - "Timestamp is computed once and reused in debug_log, JSONL record, and any other time-stamped output"
    - "No .log file output exists — JSONL is the sole structured log format"
    - "No flock or .lock file usage — each session writes to its own JSONL file"
    - "JSONL builder is a single jq call, not two near-identical blocks"
    - "Only two debug_log calls remain (event received + JSONL appended) — no noise between"
  artifacts:
    - path: "bin/hook-event-logger.sh"
      provides: "Universal hook event logger (DRY/SRP cleaned)"
      contains: "TIMESTAMP_ISO.*date -u"
  key_links:
    - from: "TIMESTAMP_ISO variable"
      to: "debug_log calls, JSONL --arg timestamp"
      via: "single date -u call reused everywhere"
      pattern: "TIMESTAMP_ISO=.*date -u"
---

<objective>
DRY/SRP refactor of bin/hook-event-logger.sh — 5 targeted fixes to eliminate redundant timestamps, remove the .log file output (JSONL is source of truth), remove dead flock locking, collapse the duplicate JSONL builder, and remove the noise debug_log call.

Purpose: Align hook-event-logger.sh with established project DRY/SRP standards. The .log output is redundant with JSONL (use `jq` for pretty-print on demand). The flock is dead code since session_id-based naming means no concurrent writers. The JSONL builder has two near-identical 6-line blocks differing only by --argjson vs --arg.
Output: A cleaner bin/hook-event-logger.sh with fewer lines, one timestamp, one JSONL builder, no .log output, no flock.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@bin/hook-event-logger.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Apply all 5 DRY/SRP fixes to hook-event-logger.sh</name>
  <files>bin/hook-event-logger.sh</files>
  <action>
Apply these 5 changes to bin/hook-event-logger.sh in a single pass:

**Fix 1 — Single timestamp (DRY):**
Move the timestamp computation to immediately after stdin consumption and event name extraction (after current line 30). Compute once:
```bash
TIMESTAMP_ISO=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
```
Remove the second `date -u` call at current line 55 (`LOG_BLOCK_TIMESTAMP=...`) and the third at current line 72 (`TIMESTAMP_ISO=...`). Update the `debug_log` function to accept an optional timestamp parameter or — simpler — replace the `date -u` inside `debug_log` with `$TIMESTAMP_ISO`. This means debug_log no longer spawns a subshell for date. All time-stamped output uses this single `TIMESTAMP_ISO` value.

**Fix 2 — Remove .log file output (SRP):**
Delete the entire block from current lines 52-63 (the `GSD_HOOK_LOG` variable assignment and the `{ printf ... } >> "$GSD_HOOK_LOG"` heredoc block). JSONL is the source of truth; `jq .` on the JSONL file gives pretty-print on demand. This also removes the `LOG_BLOCK_TIMESTAMP` variable which was only used by the .log block.

**Fix 3 — Remove noise debug_log call (DRY):**
Delete the debug_log call at current line 65 (`debug_log "logged event=$EVENT_NAME to ${LOG_FILE_PREFIX}.log"`). It just confirms step 6 happened — noise. Keep only the initial "received event" debug_log (line 33) and the final "appended to JSONL" debug_log (line 99). Update the final debug_log message to not reference .log since that output no longer exists.

**Fix 4 — Collapse JSONL builder (DRY):**
The two 6-line jq blocks (lines 75-80 and 83-88) differ only in `--argjson payload "$STDIN_JSON"` vs `--arg payload "$STDIN_JSON"`. Collapse into one block:
```bash
if printf '%s' "$STDIN_JSON" | jq empty 2>/dev/null; then
  PAYLOAD_FLAG="--argjson"
else
  PAYLOAD_FLAG="--arg"
fi

JSONL_RECORD=$(jq -cn \
  --arg event "$EVENT_NAME" \
  --arg timestamp "$TIMESTAMP_ISO" \
  --arg session "$LOG_FILE_PREFIX" \
  $PAYLOAD_FLAG payload "$STDIN_JSON" \
  '{timestamp: $timestamp, event: $event, session: $session, payload: $payload}' 2>/dev/null || echo "")
```
Note: `$PAYLOAD_FLAG` is intentionally unquoted so it expands as a flag argument to jq.

**Fix 5 — Remove flock + .lock file (dead code):**
Delete the `JSONL_LOCK_FILE` variable (line 69). Replace the flock subshell block (lines 93-96) with a direct append:
```bash
if [ -n "$JSONL_RECORD" ]; then
  printf '%s\n' "$JSONL_RECORD" >> "$RAW_EVENTS_FILE" 2>/dev/null || true
fi
```
No concurrent writers exist because each session writes to its own file (session_id-based naming).

**Preserve:** The shebang, set -euo pipefail, the header comment block, SKILL_ROOT bootstrapping, stdin consumption, trap, event/session extraction, tmux session name resolution, LOG_FILE_PREFIX logic, and the exit 0.

**Update header comment** (line 5): Change "per-session log files" to "per-session JSONL files" since .log output is removed.
  </action>
  <verify>
Run `bash -n bin/hook-event-logger.sh` to verify no syntax errors.
Run `grep -c 'date -u' bin/hook-event-logger.sh` — must return exactly 1 (the single TIMESTAMP_ISO assignment).
Run `grep -c 'flock' bin/hook-event-logger.sh` — must return exactly 0.
Run `grep -c '\.lock' bin/hook-event-logger.sh` — must return exactly 0.
Run `grep -c 'GSD_HOOK_LOG' bin/hook-event-logger.sh` — must return exactly 0.
Run `grep -c 'LOG_BLOCK_TIMESTAMP' bin/hook-event-logger.sh` — must return exactly 0.
Run `grep -c 'debug_log' bin/hook-event-logger.sh` — must return exactly 3 (function definition + 2 calls).
Run `grep -c 'PAYLOAD_FLAG' bin/hook-event-logger.sh` — must return at least 2 (assignment + usage).
  </verify>
  <done>
bin/hook-event-logger.sh has: one timestamp computed once, no .log file output, no flock/lock usage, one collapsed JSONL builder block, exactly 2 debug_log call sites (received + appended). Script passes bash -n syntax check.
  </done>
</task>

</tasks>

<verification>
- `bash -n bin/hook-event-logger.sh` passes (no syntax errors)
- Single `date -u` call in the entire script
- Zero references to flock, .lock, GSD_HOOK_LOG, or LOG_BLOCK_TIMESTAMP
- JSONL builder uses PAYLOAD_FLAG pattern (one block, not two)
- Exactly 2 debug_log call sites (not counting function definition)
</verification>

<success_criteria>
All 5 DRY/SRP fixes applied. Script is syntactically valid. Line count reduced by ~20 lines. No functional regression — still logs events to per-session JSONL files with valid/invalid JSON payload handling.
</success_criteria>

<output>
After completion, create `.planning/quick/13-dry-srp-refactor-hook-event-logger-sh-si/13-SUMMARY.md`
</output>
