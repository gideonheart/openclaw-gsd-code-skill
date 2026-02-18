# Phase 9: Hook Script Migration - Research

**Researched:** 2026-02-18
**Domain:** Bash hook script modification — structured JSONL integration, sourcing refactor, deliver_async_with_logging adoption, bidirectional path inline logging
**Confidence:** HIGH — all patterns verified against the live shipped Phase 8 code; both lib functions are confirmed working with unit/integration tests

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| HOOK-12 | stop-hook.sh emits structured JSONL record replacing plain-text debug_log — includes full wake message body and OpenClaw response | deliver_async_with_logging() (async path) + write_hook_event_record() directly (bidirectional path); both already shipped in lib/hook-utils.sh |
| HOOK-13 | pre-tool-use-hook.sh emits structured JSONL record replacing plain-text debug_log — includes AskUserQuestion data forwarded | deliver_async_with_logging() covers the async-only path; questions_forwarded field requires write_hook_event_record() to accept an extra field — see ASK-04 below |
| HOOK-14 | notification-idle-hook.sh emits structured JSONL record replacing plain-text debug_log | Same deliver_async_with_logging() pattern; trigger="idle_prompt", content_source="pane" |
| HOOK-15 | notification-permission-hook.sh emits structured JSONL record replacing plain-text debug_log | Same pattern; trigger="permission_prompt", content_source="pane" |
| HOOK-16 | session-end-hook.sh emits structured JSONL record replacing plain-text debug_log | Always-async; trigger="session_end", content_source="none"; minimal wake message means state="terminated" |
| HOOK-17 | pre-compact-hook.sh emits structured JSONL record replacing plain-text debug_log | Same deliver_async_with_logging() pattern (async branch); write_hook_event_record() directly (bidirectional branch); trigger="pre_compact", content_source="pane" |
| ASK-04 | PreToolUse JSONL record includes `questions_forwarded` field showing what questions, options, and headers were sent to OpenClaw agent | questions_forwarded is an EXTRA field not in the 13-field base schema — must extend write_hook_event_record() OR pass formatted question text as the wake_message and use wake_message to satisfy this (see Architecture Patterns — Option A vs Option B) |

</phase_requirements>

---

## Summary

Phase 9 migrates all 6 hook scripts to emit structured JSONL records using the `write_hook_event_record()` and `deliver_async_with_logging()` functions shipped in Phase 8. The foundation (lib/hook-utils.sh with 6 functions) is complete and tested. Phase 9 is purely a modification pass on 6 existing scripts.

The work per hook follows a consistent pattern: (1) move the `source lib/hook-utils.sh` call to the top of the script before any guard exits, (2) add `HOOK_ENTRY_MS=$(date +%s%3N)` immediately after stdin consumption, (3) add `JSONL_FILE` path assignment alongside `GSD_HOOK_LOG` after session name is known, (4) replace bare `openclaw ... &` with `deliver_async_with_logging()`, and (5) add inline `write_hook_event_record()` call for bidirectional paths in stop-hook.sh and pre-compact-hook.sh.

The most critical design decision for Phase 9 is how to satisfy ASK-04 — the `questions_forwarded` field in pre-tool-use-hook.sh's JSONL record. The base JSONL schema (13 fields) does not include `questions_forwarded`. Two options exist: (A) extend `write_hook_event_record()` with a 13th optional parameter, or (B) embed the questions data in the existing `wake_message` field (which already contains the full formatted question). Option B avoids a function signature change and satisfies ASK-04 because the wake_message already carries the complete `[ASK USER QUESTION]` section. This is the recommended approach.

**Primary recommendation:** Source lib/hook-utils.sh at the very top of every hook script (line 1 after shebang, or before first guard), add `HOOK_ENTRY_MS` after stdin consume, add `JSONL_FILE` alongside log file, and replace bare openclaw calls with `deliver_async_with_logging()`. For bidirectional paths, call `write_hook_event_record()` directly after the synchronous openclaw call. For ASK-04, treat `wake_message` as the `questions_forwarded` vehicle — it already contains the full formatted question data.

---

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| lib/hook-utils.sh | Phase 8 — 6 functions | Provides write_hook_event_record() and deliver_async_with_logging() | Shipped, tested, confirmed working with 44 assertions passing |
| jq | 1.7 (on host) | JSONL record construction via jq -cn --arg / --argjson | Already present in all 6 hooks; no new dependency |
| bash | 5.2.21 (on host) | Sourcing, subshell backgrounding, positional parameters | Existing stack |
| flock | util-linux (installed) | Atomic JSONL append — already inside write_hook_event_record() | Already used in hook-utils.sh |
| date +%s%3N | GNU coreutils | Millisecond timestamp for HOOK_ENTRY_MS | Confirmed working on this host |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| debug_log() | Plain-text backward-compatible logging | Keep all existing debug_log calls intact in parallel with JSONL — "plain-text .log files continue during transition" |
| SKILL_LOG_DIR | Already set at top of each hook | JSONL_FILE path derives from same variable |

### No New Dependencies

Phase 9 introduces zero new tools. All required components are already present in the codebase and on the host.

---

## Architecture Patterns

### Current State of Each Hook Script (Before Phase 9)

All 6 scripts already:
- Set `SKILL_LOG_DIR` at the top
- Define `debug_log()` locally
- Consume stdin immediately: `STDIN_JSON=$(cat)`
- Check `$TMUX` and exit if unset (guard exit 1)
- Extract `SESSION_NAME` via tmux and exit if empty (guard exit 2)
- Redirect `GSD_HOOK_LOG` to per-session `.log` file after session name is known
- Check registry path and exit if missing (guard exit 3)
- Source `lib/hook-utils.sh` (but NOT at top — sourced after guard exits)
- Call `lookup_agent_in_registry()` and exit if no match (guard exit 4)
- Extract `AGENT_ID`, `OPENCLAW_SESSION_ID`
- Build `WAKE_MESSAGE`
- Call bare `openclaw agent ... >> "$GSD_HOOK_LOG" 2>&1 &` (async) or `openclaw ... --json` (sync)

**Critical current state for Phase 9:**
- lib/hook-utils.sh is NOT sourced at the top — it is sourced AFTER registry-file-existence guard (guard exit 3)
- No HOOK_ENTRY_MS exists in any script
- No JSONL_FILE variable exists in any script
- Bare openclaw calls have no JSONL logging

### Pattern 1: Source lib/hook-utils.sh Before All Guard Exits

**Requirement:** Success criteria #4 — "All 6 scripts source lib/hook-utils.sh at top of script (before any guard exit)"

**Current location in scripts:** After registry path check (guard exit 3), after `[ ! -f "$REGISTRY_PATH" ]` check.

**Target location:** Before ANY guard exit — immediately after the two setup lines at the very top of the script (after SKILL_LOG_DIR and GSD_HOOK_LOG setup, before the first guard check).

**Why:** The JSONL infrastructure (write_hook_event_record, deliver_async_with_logging) must be available before any guard exit fires. Guard exits themselves do NOT emit JSONL (success criteria #6), but lib must be sourced early for correctness.

**Pattern:**
```bash
#!/usr/bin/env bash
set -euo pipefail

SKILL_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$SKILL_LOG_DIR"

GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" >> "$GSD_HOOK_LOG" 2>/dev/null || true
}

# Source shared library BEFORE any guard exits (success criteria #4)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"
if [ -f "$LIB_PATH" ]; then
  source "$LIB_PATH"
else
  debug_log "FATAL: hook-utils.sh not found at $LIB_PATH"
  exit 0
fi

debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"

# ... guard exits start AFTER sourcing lib ...
```

**Critical:** After this change, the later `LIB_PATH` block in each hook (currently after registry check) must be REMOVED to avoid double-sourcing. Each script currently has the source-lib block in the middle — that block must be deleted entirely.

### Pattern 2: HOOK_ENTRY_MS Placement

**Requirement:** OPS-01 — every record includes duration_ms.

**Where:** Immediately after `STDIN_JSON=$(cat)` — this is the start of actual hook processing. Stdin consumption blocks until Claude Code sends data; the timestamp before cat would measure process startup time, not hook processing time.

```bash
STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)
debug_log "stdin: ${#STDIN_JSON} bytes ..."
```

**Note:** The 08-RESEARCH.md explicitly recommends this placement: "Set HOOK_ENTRY_MS=$(date +%s%3N) AFTER STDIN_JSON=$(cat) — immediately after stdin is consumed. This measures actual hook processing time."

### Pattern 3: JSONL_FILE Assignment (Phase 2 Redirect Block)

**Where:** Alongside the existing GSD_HOOK_LOG redirect, after SESSION_NAME is known.

```bash
debug_log "tmux_session=$SESSION_NAME"
# Phase 2: redirect to per-session log file
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
debug_log "=== log redirected to per-session file ==="
```

**Important:** JSONL_FILE is defined here but is only USED after registry match confirms this is a managed session. Guard exits that fire BEFORE this point (no TMUX, no SESSION_NAME) do not have JSONL_FILE defined — but they also must not emit JSONL. Guard exits that fire AFTER this point (no registry, no agent match) DO have JSONL_FILE defined but must still not emit JSONL (success criteria #6).

### Pattern 4: Async Delivery Replacement

**In async branch (default):** Replace bare openclaw call with deliver_async_with_logging().

Per-hook trigger and content_source values (from Phase 8 research):

| Hook Script | TRIGGER value | CONTENT_SOURCE value |
|------------|---------------|----------------------|
| stop-hook.sh | "response_complete" | "transcript" or "pane_diff" or "raw_pane_tail" |
| notification-idle-hook.sh | "idle_prompt" | "pane" |
| notification-permission-hook.sh | "permission_prompt" | "pane" |
| session-end-hook.sh | "session_end" | "none" |
| pre-compact-hook.sh | "pre_compact" | "pane" |
| pre-tool-use-hook.sh | "ask_user_question" | "questions" |

**Before (current pattern):**
```bash
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >> "$GSD_HOOK_LOG" 2>&1 &
debug_log "DELIVERED (async, bg PID=$!)"
```

**After (Phase 9 pattern):**
```bash
deliver_async_with_logging \
  "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" "$JSONL_FILE" "$HOOK_ENTRY_MS" \
  "$HOOK_SCRIPT_NAME" "$SESSION_NAME" "$AGENT_ID" \
  "$TRIGGER" "$STATE" "$CONTENT_SOURCE"
debug_log "DELIVERED (async with JSONL logging)"
```

**Note:** `TRIGGER` and `CONTENT_SOURCE` must be set as variables in the hook before calling deliver_async_with_logging(). For stop-hook.sh, CONTENT_SOURCE is determined dynamically (transcript vs pane_diff vs raw_pane_tail) — set it in the content selection block.

### Pattern 5: Bidirectional Path Inline Logging

**Applies to:** stop-hook.sh and pre-compact-hook.sh (the only two scripts with `HOOK_MODE = "bidirectional"` branch).

The bidirectional branch calls openclaw synchronously (with `--json`), waits for the response, then parses it. deliver_async_with_logging() does NOT apply here (it backgrounds). Instead, call write_hook_event_record() directly after the synchronous response:

```bash
if [ "$HOOK_MODE" = "bidirectional" ]; then
  RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" \
    --message "$WAKE_MESSAGE" --json 2>&1 || echo "")
  debug_log "RESPONSE: ${RESPONSE:0:200}"

  # Write JSONL record for bidirectional delivery
  local outcome="delivered"
  [ -z "$RESPONSE" ] && outcome="no_response"
  write_hook_event_record \
    "$JSONL_FILE" "$HOOK_ENTRY_MS" "$HOOK_SCRIPT_NAME" "$SESSION_NAME" \
    "$AGENT_ID" "$OPENCLAW_SESSION_ID" "$TRIGGER" "$STATE" \
    "$CONTENT_SOURCE" "$WAKE_MESSAGE" "$RESPONSE" "sync_delivered"

  # Parse response for decision injection (existing logic)
  if [ -n "$RESPONSE" ]; then
    DECISION=$(echo "$RESPONSE" | jq -r '.decision // ""' 2>/dev/null || echo "")
    REASON=$(echo "$RESPONSE" | jq -r '.reason // ""' 2>/dev/null || echo "")
    if [ "$DECISION" = "block" ] && [ -n "$REASON" ]; then
      echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
    fi
  fi
  exit 0
```

**outcome value:** Use `"sync_delivered"` (not `"delivered"`) for bidirectional paths — this distinguishes synchronous from async delivery in queries.

### Pattern 6: stop-hook.sh Content Source Variable

stop-hook.sh dynamically determines content_source based on whether transcript extraction succeeded. The CONTENT_SOURCE variable must be set in the content selection block:

```bash
if [ -n "$EXTRACTED_RESPONSE" ]; then
  CONTENT_SECTION="$EXTRACTED_RESPONSE"
  CONTENT_SOURCE="transcript"
  debug_log "content source: transcript"
else
  # Fallback: pane diff
  PANE_FOR_DIFF=$(printf '%s\n' "$PANE_CONTENT" | tail -40)
  if type extract_pane_diff &>/dev/null; then
    CONTENT_SECTION=$(extract_pane_diff "$SESSION_NAME" "$PANE_FOR_DIFF")
    CONTENT_SOURCE="pane_diff"
    debug_log "content source: pane_diff ..."
  else
    CONTENT_SECTION=$(printf '%s\n' "$PANE_CONTENT" | tail -40)
    CONTENT_SOURCE="raw_pane_tail"
    debug_log "content source: raw_pane_tail ..."
  fi
fi
```

### Pattern 7: ASK-04 — questions_forwarded in pre-tool-use-hook.sh

**The requirement:** The JSONL record must include `questions_forwarded` showing the questions, options, and headers sent to OpenClaw.

**The challenge:** The base JSONL schema (13 fields from write_hook_event_record()) has no `questions_forwarded` field.

**Option A — Extend write_hook_event_record() with 13th parameter:**
- Add `questions_forwarded` as 13th positional parameter to write_hook_event_record()
- All other 5 hooks pass empty string ""
- Breaks the established 12-parameter contract; all call sites must be updated
- Increases testing burden for all hooks

**Option B — Use wake_message field as questions_forwarded vehicle:**
- The wake_message already contains the complete `[ASK USER QUESTION]` section with formatted questions, options, headers
- Set content_source="questions" (already the plan per field values table)
- The wake_message IS the questions_forwarded data — machine-queryable via `jq '.wake_message'`
- No function signature change required
- No new parameter to all 6 hooks

**Recommended: Option B.** The requirement says "JSONL record includes questions_forwarded field showing what questions, options, and headers were sent to OpenClaw agent." The wake_message already contains exactly this data in structured format. The wake_message field IS functionally equivalent to questions_forwarded for pre-tool-use-hook.sh invocations.

**However,** if the planner determines a distinct `questions_forwarded` field is needed for query clarity (e.g., jq `.questions_forwarded` vs parsing wake_message), Option A requires minimal surgery:
- Add 13th `questions_forwarded` parameter to write_hook_event_record()
- Default value "" for all other hooks
- Only pre-tool-use-hook.sh passes a non-empty value (the formatted TOOL_INPUT as JSON string)

**Decision point for planner:** Choose Option A or Option B. Both are implementable. This research recommends Option B (no function change) but flags this as the one non-trivial design decision in Phase 9.

### Pattern 8: session-end-hook.sh Special Case

session-end-hook.sh differs from other hooks in two ways:
1. It does NOT extract hook_settings — no HOOK_MODE, PANE_CAPTURE_LINES, etc.
2. It always delivers async (bidirectional mode is meaningless on session termination)
3. It has minimal wake message (identity + trigger only, no pane content)

For JSONL purposes:
- STATE should be "terminated" (matches the wake message: `state: terminated`)
- CONTENT_SOURCE should be "none" (no content section)
- TRIGGER should be "session_end"
- Always use deliver_async_with_logging() — no bidirectional branch to handle

### Anti-Patterns to Avoid

- **Emitting JSONL on guard exits:** Guard exits (no TMUX, no SESSION_NAME, no registry, no agent match) must NOT call write_hook_event_record(). The function is only called from deliver_async_with_logging() or the bidirectional path, both of which only execute AFTER all guards have passed and AGENT_ID/OPENCLAW_SESSION_ID are confirmed non-empty.
- **Double-sourcing lib/hook-utils.sh:** Moving the source call to the top means the existing mid-script source block must be deleted. Double-sourcing is harmless (functions redefine themselves) but is wasteful and confusing.
- **Forgetting to set TRIGGER and CONTENT_SOURCE before calling deliver_async_with_logging():** Both are required parameters. Without them, the JSONL record has empty trigger and content_source fields. Set them as named variables for clarity.
- **Using debug_log inside write_hook_event_record():** Phase 8 confirmed write_hook_event_record() is a pure function with no side effects. Do not add debug_log calls inside it. Debug the hook from outside (debug_log before/after the deliver_async_with_logging call).
- **Removing existing debug_log calls:** Success criteria #5 — ".log files continue in parallel for backward compatibility during transition." Keep ALL debug_log calls exactly as they are. Phase 9 adds JSONL in parallel, it does not replace debug_log.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSONL record construction | printf-based JSON assembly | write_hook_event_record() from lib/hook-utils.sh | Already shipped, tested (21 assertions), handles all escaping edge cases |
| Async openclaw with logging | Custom background subshell | deliver_async_with_logging() from lib/hook-utils.sh | Already shipped, tested (23 assertions), handles response capture, outcome, </dev/null |
| questions_forwarded field | New jq-based JSON object | Pass via wake_message (Option B) or add 13th param (Option A) | Simpler than building a parallel JSON object; wake_message already carries the data |
| Per-hook JSONL file path | Custom path logic | `"${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"` — same pattern as .log | Consistent with established Quick-5 decision; follow the same convention |

---

## Common Pitfalls

### Pitfall 1: Sourcing lib Before SCRIPT_DIR is Set

**What goes wrong:** The current hook scripts set `SCRIPT_DIR` midway through execution (in the registry lookup block). Moving the source call to the top requires moving `SCRIPT_DIR` calculation to the top as well.

**How to avoid:** Add `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` at the very top alongside SKILL_LOG_DIR, before the source call. Check that SCRIPT_DIR is not set again later (some hooks have it; some have `SCRIPT_DIR` inside the registry block). The existing redundant SCRIPT_DIR assignment in the registry block can be removed.

**Warning signs:** `source "$LIB_PATH"` fails because LIB_PATH uses an unset SCRIPT_DIR.

### Pitfall 2: Removing the Wrong Registry Path Block

**What goes wrong:** Each hook has TWO related blocks: (1) the LIB_PATH + source block (moves to top), and (2) the REGISTRY_PATH check + guard exit block (stays where it is). The REGISTRY_PATH block must NOT move — it is a guard exit that prevents JSONL emission for sessions with no registry.

**How to avoid:** Move only the LIB_PATH + source + guard-exit-on-missing-lib block to the top. Leave the REGISTRY_PATH check and lookup_agent_in_registry() call exactly where they are.

### Pitfall 3: JSONL_FILE Undefined When Called

**What goes wrong:** JSONL_FILE is assigned after SESSION_NAME is known (Phase 2 redirect block). deliver_async_with_logging() is called after registry match. If JSONL_FILE is not assigned before the registry lookup (i.e., the script exits before getting to the redirect block), the variable is undefined. This happens only on guard exits, which must not call deliver_async_with_logging() anyway — so this is not an actual bug, but the code reads poorly if JSONL_FILE appears undefined in fallback paths.

**How to avoid:** Initialize `JSONL_FILE=""` at the top of the script (near HOOK_ENTRY_MS and GSD_HOOK_LOG). This prevents shell unbound variable errors under `set -euo pipefail`.

### Pitfall 4: stop-hook.sh — CONTENT_SOURCE Not Set Before WAKE_MESSAGE Build

**What goes wrong:** stop-hook.sh builds WAKE_MESSAGE in step 10. CONTENT_SOURCE is determined in step 9b. If CONTENT_SOURCE is not set before the WAKE_MESSAGE build, it will be empty or undefined when passed to deliver_async_with_logging().

**How to avoid:** Confirm CONTENT_SOURCE is set in the content selection block (step 9b) before WAKE_MESSAGE is constructed (step 10). The variable assignment should be:
- After transcript extraction succeeds: `CONTENT_SOURCE="transcript"`
- After pane_diff fallback: `CONTENT_SOURCE="pane_diff"`
- After raw_pane_tail fallback: `CONTENT_SOURCE="raw_pane_tail"`

### Pitfall 5: pre-compact-hook.sh Uses -t Flag (Not -pt)

**What goes wrong:** pre-compact-hook.sh uses `tmux capture-pane -t "$SESSION_NAME:0.0" -p -S ...` while other hooks use `tmux capture-pane -pt`. The `-p` flag prints to stdout (needed when not using `-t` pane reference). This is a pre-existing difference — do not change it during Phase 9 migration, only add JSONL alongside.

**How to avoid:** When modifying pre-compact-hook.sh, do not touch the pane capture command. Only add HOOK_ENTRY_MS, JSONL_FILE, TRIGGER, CONTENT_SOURCE variables, move the source block, and replace the openclaw delivery call.

---

## Code Examples

### Minimal Hook Migration — notification-idle-hook.sh

This is the simplest case (no transcript extraction, no bidirectional branch). Shows complete diff:

**Lines to add at top (after debug_log definition, before first guard):**
```bash
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

**After STDIN_JSON=$(cat):**
```bash
STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)
```

**In Phase 2 redirect block:**
```bash
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
```

**Set TRIGGER and CONTENT_SOURCE before wake message (or before delivery):**
```bash
TRIGGER="idle_prompt"
CONTENT_SOURCE="pane"
```

**Replace delivery block:**
```bash
# Before:
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >> "$GSD_HOOK_LOG" 2>&1 &
debug_log "DELIVERED (async, bg PID=$!)"

# After:
deliver_async_with_logging \
  "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" "$JSONL_FILE" "$HOOK_ENTRY_MS" \
  "$HOOK_SCRIPT_NAME" "$SESSION_NAME" "$AGENT_ID" \
  "$TRIGGER" "$STATE" "$CONTENT_SOURCE"
debug_log "DELIVERED (async with JSONL logging)"
```

**Delete the existing middle LIB_PATH source block** (currently after registry check — now redundant).

### stop-hook.sh — Both Paths With JSONL

```bash
# After WAKE_MESSAGE is built, before delivery:
if [ "$HOOK_MODE" = "bidirectional" ]; then
  RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" \
    --message "$WAKE_MESSAGE" --json 2>&1 || echo "")
  debug_log "RESPONSE: ${RESPONSE:0:200}"

  write_hook_event_record \
    "$JSONL_FILE" "$HOOK_ENTRY_MS" "$HOOK_SCRIPT_NAME" "$SESSION_NAME" \
    "$AGENT_ID" "$OPENCLAW_SESSION_ID" "$TRIGGER" "$STATE" \
    "$CONTENT_SOURCE" "$WAKE_MESSAGE" "$RESPONSE" "sync_delivered"

  if [ -n "$RESPONSE" ]; then
    DECISION=$(echo "$RESPONSE" | jq -r '.decision // ""' 2>/dev/null || echo "")
    REASON=$(echo "$RESPONSE" | jq -r '.reason // ""' 2>/dev/null || echo "")
    if [ "$DECISION" = "block" ] && [ -n "$REASON" ]; then
      echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
    fi
  fi
  exit 0
else
  deliver_async_with_logging \
    "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" "$JSONL_FILE" "$HOOK_ENTRY_MS" \
    "$HOOK_SCRIPT_NAME" "$SESSION_NAME" "$AGENT_ID" \
    "$TRIGGER" "$STATE" "$CONTENT_SOURCE"
  debug_log "DELIVERED (async with JSONL logging)"
  exit 0
fi
```

### Expected JSONL Record Per Hook

```json
// stop-hook.sh — async path, transcript content
{
  "timestamp": "2026-02-18T12:00:00Z",
  "hook_script": "stop-hook.sh",
  "session_name": "warden-main",
  "agent_id": "warden",
  "openclaw_session_id": "abc-123",
  "trigger": "response_complete",
  "state": "working",
  "content_source": "transcript",
  "wake_message": "[SESSION IDENTITY]\nagent_id: warden\n...",
  "response": "{\"status\":\"ok\"}",
  "outcome": "delivered",
  "duration_ms": 312
}

// session-end-hook.sh — always async, no content
{
  "timestamp": "2026-02-18T12:01:00Z",
  "hook_script": "session-end-hook.sh",
  "session_name": "warden-main",
  "agent_id": "warden",
  "openclaw_session_id": "abc-123",
  "trigger": "session_end",
  "state": "terminated",
  "content_source": "none",
  "wake_message": "[SESSION IDENTITY]\nagent_id: warden\n...",
  "response": "",
  "outcome": "no_response",
  "duration_ms": 45
}
```

---

## Script-by-Script Migration Summary

| Script | Complexity | Special Cases |
|--------|-----------|---------------|
| notification-idle-hook.sh | Low | Standard async-only pattern |
| notification-permission-hook.sh | Low | Standard async-only pattern |
| session-end-hook.sh | Low | No hook_settings block; always async; STATE="terminated"; CONTENT_SOURCE="none" |
| pre-tool-use-hook.sh | Medium | Async-only; ASK-04 questions_forwarded via wake_message; CONTENT_SOURCE="questions" |
| pre-compact-hook.sh | Medium | Has bidirectional branch needing inline write_hook_event_record(); different tmux capture flag |
| stop-hook.sh | High | Has bidirectional branch; dynamic CONTENT_SOURCE (transcript/pane_diff/raw_pane_tail); two-phase content selection |

**Recommended execution order:** Simple hooks first (notification-idle, notification-permission, session-end), then pre-tool-use, then pre-compact, then stop-hook. This validates the pattern on easy cases before tackling the complex ones.

---

## Plan Structure Recommendation

This phase is 6 file modifications with a shared pattern. The planner should consider:

**Option 1: One plan per hook (6 plans)**
- Each plan is small and independently verifiable
- Clear commit history per hook
- Easy to stop and resume

**Option 2: Group by complexity (2-3 plans)**
- Plan A: notification-idle, notification-permission, session-end (3 simple hooks)
- Plan B: pre-tool-use, pre-compact (2 medium hooks)
- Plan C: stop-hook (1 complex hook)
- Each plan is self-contained

**Option 3: One plan for all (1 plan)**
- Fastest to plan
- Harder to verify in pieces
- All-or-nothing commit

**Recommendation:** Option 2 (3 plans grouped by complexity). Each plan is independently testable and committable. Failure in one group does not block others. Aligns with Phase 8's 2-plan approach (foundation → async wrapper).

---

## Open Questions

1. **ASK-04: Option A vs Option B for questions_forwarded field**
   - What we know: wake_message already contains full question data in [ASK USER QUESTION] section; write_hook_event_record() has 12 parameters (established in Phase 8)
   - What's unclear: Does "questions_forwarded field" mean a dedicated JSON key, or is wake_message sufficient?
   - Recommendation: Use Option B (wake_message carries questions data). If planner disagrees, Option A adds a 13th parameter to write_hook_event_record() and all 6 call sites.

2. **TRIGGER variable naming convention**
   - What we know: trigger values defined in Phase 8 RESEARCH.md field-values table
   - What's unclear: Should trigger values be stored in a variable named `TRIGGER` (uppercase constant) before being passed?
   - Recommendation: Yes, set `TRIGGER="idle_prompt"` etc. as named variables for readability and to match the existing HOOK_MODE, STATE pattern.

3. **Should session-end-hook.sh also write a JSONL record for the pane-state file cleanup step?**
   - What we know: session-end-hook.sh cleans up pane state files; this happens after the openclaw delivery; the JSONL record should capture delivery outcome
   - What's unclear: Should the cleanup be noted in the JSONL record?
   - Recommendation: No. The JSONL record captures the hook invocation lifecycle (trigger, delivery, outcome). Cleanup is implementation detail. One record per invocation is the design decision (Phase 8).

---

## Sources

### Primary (HIGH confidence — live codebase)

- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/lib/hook-utils.sh` — confirmed 6 functions, write_hook_event_record signature (12 params), deliver_async_with_logging signature (10 params)
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/stop-hook.sh` — full current script read; bidirectional branch confirmed
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/pre-tool-use-hook.sh` — full current script read; async-only; AskUserQuestion forwarding
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-idle-hook.sh` — full current script read
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-permission-hook.sh` — full current script read
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/session-end-hook.sh` — full current script read; always-async; pane cleanup
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/pre-compact-hook.sh` — full current script read; bidirectional branch; different tmux capture flag
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/tests/test-deliver-async-with-logging.sh` — confirmed test pattern; export -f for subshell mocking
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/tests/test-write-hook-event-record.sh` — confirmed test pattern; assert_jq helper

### Primary (HIGH confidence — planning artifacts)

- `.planning/phases/08-jsonl-logging-foundation/08-RESEARCH.md` — field values table per hook, placement recommendations for HOOK_ENTRY_MS and JSONL_FILE, open questions resolved (bidirectional path = inline write_hook_event_record)
- `.planning/phases/08-jsonl-logging-foundation/08-VERIFICATION.md` — confirmed Phase 8 PASSED with all 8 criteria; 44 test assertions passing
- `.planning/REQUIREMENTS.md` v3 section — HOOK-12..17, ASK-04 exact wording, "Guard exits do NOT emit JSONL" is explicit out-of-scope
- `.planning/STATE.md` — Phase 8 decisions confirmed and shipped

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; all tools confirmed present and version-verified
- Architecture patterns: HIGH — all patterns derived directly from shipped Phase 8 code and existing hook scripts
- Migration steps: HIGH — derived from reading all 6 scripts in full; no guesswork
- ASK-04 decision: MEDIUM — Option B is recommended but the planner must decide on the named field vs wake_message tradeoff

**Research date:** 2026-02-18
**Valid until:** Stable — no external dependencies; hook scripts are the primary artifact
