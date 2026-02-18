# Phase 6: Core Extraction and Delivery Engine - Research

**Researched:** 2026-02-18
**Domain:** Bash hook script modification — transcript JSONL extraction, pane diff fallback, PreToolUse AskUserQuestion forwarding, shared library creation, v2 wake format
**Confidence:** HIGH — all findings verified against existing codebase, prior project research (SUMMARY.md, ARCHITECTURE.md, FEATURES.md, PITFALLS.md, STACK.md), official Claude Code documentation, and live transcript inspection on host

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LIB-01 | lib/hook-utils.sh contains shared extraction and diff functions (DRY — sourced by stop-hook.sh and pre-tool-use-hook.sh only) | Shared library pattern confirmed; ARCHITECTURE.md specifies exact 4-function API; source path pattern verified from existing scripts |
| LIB-02 | Each function in lib has single responsibility — extract response, compute diff, format questions are separate functions | SRP mapping confirmed: extract_last_assistant_response, extract_pane_diff, format_ask_user_questions each do one thing; ARCHITECTURE.md documents this boundary |
| EXTRACT-01 | Stop hook extracts last assistant response from transcript_path JSONL using type-filtered content parsing (`content[]? | select(.type == "text")`) | Transcript JSONL structure confirmed from live inspection; type-filtering requirement documented (pitfall 1 in PITFALLS.md); jq pattern verified |
| EXTRACT-02 | When transcript extraction fails (file missing, empty, parse error), fall back to pane diff (only new/added lines from last 40 pane lines) | Fallback chain design confirmed; diff flag `--new-line-format='%L'` verified on GNU diff 3.10; 40 lines from last commit decision |
| EXTRACT-03 | Per-session previous pane state stored in /tmp for diff fallback calculation | /tmp file pattern `/tmp/gsd-pane-prev-${SESSION_NAME}.txt` confirmed; flock requirement for concurrent access documented |
| ASK-01 | PreToolUse hook fires on AskUserQuestion tool calls only (matcher: `"AskUserQuestion"`) | Matcher-scoped PreToolUse confirmed in Claude Code hooks docs; AskUserQuestion as only valid matcher confirmed |
| ASK-02 | PreToolUse hook extracts structured question data (questions, options, header, multiSelect) from tool_input in stdin | AskUserQuestion tool_input schema confirmed from official docs and live transcript; field paths `.tool_input.questions[].{question,header,options,multiSelect}` verified |
| ASK-03 | PreToolUse hook sends question data to OpenClaw agent asynchronously (background, never blocks Claude Code UI) | Async background pattern (</dev/null >/dev/null 2>&1 &) confirmed; pitfall 6 in PITFALLS.md documents the blocking risk |
| WAKE-07 | Wake messages use v2 structured format: [SESSION IDENTITY], [TRIGGER], [CONTENT] (transcript or pane diff), [STATE HINT], [CONTEXT PRESSURE], [AVAILABLE ACTIONS] | V2 format specified; [CONTENT] replaces [PANE CONTENT]; section ordering confirmed from requirements |
| WAKE-08 | v1 wake format code removed entirely — clean break, no backward compatibility layer | Decision confirmed in STATE.md; v1 [PANE CONTENT] section removed, no transition layer per user decision 2026-02-18 |
| WAKE-09 | AskUserQuestion forwarding uses dedicated [ASK USER QUESTION] section with structured question/options data | [ASK USER QUESTION] section format documented in ARCHITECTURE.md; jq formatting function specified |
</phase_requirements>

---

## Summary

Phase 6 is a well-researched bash implementation task. All technical patterns are fully specified in the existing project research documents (ARCHITECTURE.md, FEATURES.md, PITFALLS.md, STACK.md, SUMMARY.md) from 2026-02-17. The key simplification from the most recent commit (2026-02-18) is that v2.0 delivers content as ONE source per message: transcript JSONL (primary) OR pane diff (fallback), never both. This is cleaner than the original dual-section design.

The implementation consists of three deliverables with a clear dependency chain: (1) create `lib/hook-utils.sh` with three extraction functions, (2) create `scripts/pre-tool-use-hook.sh` as the new AskUserQuestion forwarder, and (3) modify `scripts/stop-hook.sh` to use lib functions and emit v2 wake format. The other four hook scripts are untouched. Zero new dependencies are introduced — jq 1.7, bash 5.x, GNU diff 3.10, md5sum, and flock are all confirmed present on the production host.

The most important planning decisions: (a) lib functions are stateless bash functions, each doing exactly one thing; (b) the fallback chain in stop-hook.sh is `transcript success → use transcript text`, `transcript failure → compute pane diff from last 40 lines`; (c) pre-tool-use-hook.sh must always exit 0 and always background the openclaw call; (d) v1 [PANE CONTENT] code is removed entirely, not wrapped or conditionally preserved.

**Primary recommendation:** Build lib/hook-utils.sh first (no dependencies), then pre-tool-use-hook.sh and the stop-hook.sh modification in parallel (both depend only on lib). The planner should create 3 plans: one for lib, one for pre-tool-use-hook.sh, one for stop-hook.sh modifications.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.x (Ubuntu 24) | All hook scripts and lib functions | Existing stack; no new dependency |
| jq | 1.7 | JSONL parsing, stdin JSON extraction, question formatting | Existing stack; supports select(), streaming |
| tail | coreutils | Constant-time JSONL tail read (avoids full-file reads) | Existing stack; 2ms vs 100ms+ for large files |
| diff (GNU) | 3.10 | Pane delta extraction with `--new-line-format` flags | Confirmed available; produces clean new-lines-only output |
| md5sum | coreutils | Pane content hashing for diff state tracking | Confirmed available; non-cryptographic, speed is the requirement |
| flock | util-linux | Per-session lock on /tmp state files | Confirmed available; prevents concurrent write corruption |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| source (bash builtin) | n/a | Shared library loading | In stop-hook.sh and pre-tool-use-hook.sh only |
| tmux capture-pane | 3.4 | Pane content for fallback diff | Fallback path only; pane capture already in stop-hook.sh |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| tail + jq | cat + jq | cat reads full transcript (100ms+ on large files); tail -40 is constant-time; use tail always |
| diff --new-line-format | diff -u then grep '^+' | Unified diff includes header lines and @@ markers; --new-line-format gives clean output directly |
| md5sum | sha256sum | sha256sum is slower; collision resistance irrelevant for pane dedup; use md5sum |
| /tmp state files | Registry JSON | Registry writes require atomic flock+mv pattern; /tmp is faster and self-cleaning on reboot |

**Installation:** No installation needed. All tools are present on the production Ubuntu 24 host.

---

## Architecture Patterns

### Recommended Project Structure

```
gsd-code-skill/
├── lib/
│   └── hook-utils.sh          # NEW: shared extraction functions (LIB-01, LIB-02)
├── scripts/
│   ├── stop-hook.sh           # MODIFIED: source lib, transcript extraction, diff fallback, v2 format
│   ├── pre-tool-use-hook.sh   # NEW: AskUserQuestion forwarder (ASK-01, ASK-02, ASK-03)
│   ├── notification-idle-hook.sh      # UNCHANGED
│   ├── notification-permission-hook.sh # UNCHANGED
│   ├── session-end-hook.sh    # UNCHANGED (cleanup is Phase 7)
│   └── pre-compact-hook.sh    # UNCHANGED
└── /tmp/ (runtime)
    ├── gsd-pane-prev-{SESSION_NAME}.txt   # per-session previous pane for diff (EXTRACT-03)
    └── gsd-pane-lock-{SESSION_NAME}       # flock file for concurrent access protection
```

### Pattern 1: Source-Based Shared Library

**What:** `lib/hook-utils.sh` provides bash functions that hook entry points source via `. "$SCRIPT_DIR/../lib/hook-utils.sh"` (or `source`). The lib file contains only function definitions — no side effects on source.

**When to use:** When 2+ hook scripts need the same logic. In v2.0, only stop-hook.sh and pre-tool-use-hook.sh source the lib. Notification/session-end/pre-compact hooks remain untouched.

**Example:**
```bash
# In stop-hook.sh, after section 6 (hook_settings extract):
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/hook-utils.sh"
```

**SRP preserved:** Each hook script is one entry point for one hook event type. The lib function calls are orchestration, not business logic in the entry point.

**What NOT to put in lib:** Guards (stop_hook_active, TMUX check), registry lookup, hook_settings extraction, delivery logic — these stay in each hook script because they may diverge per event type.

### Pattern 2: Transcript Extraction with Fallback

**What:** Primary path reads transcript JSONL; fallback path computes pane diff. Only ONE path fires per hook invocation, never both.

**When to use:** Every Stop hook invocation. The transcript path is attempted first; if it returns empty (file missing, parse error, no assistant messages yet), the diff path runs.

**Implementation (in lib/hook-utils.sh):**
```bash
extract_last_assistant_response() {
  local transcript_path="$1"

  if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
    echo ""
    return
  fi

  # tail -40: constant-time read; type-filtering: handles thinking/tool_use blocks before text
  tail -40 "$transcript_path" 2>/dev/null | \
    jq -r 'select(.type == "assistant") |
      (.message.content // [])[] |
      select(.type == "text") | .text' 2>/dev/null | \
    tail -1
}
```

**Critical:** `content[]? | select(.type == "text")` not `content[0].text`. Using positional indexing fails silently when thinking blocks or tool_use blocks precede the text block. Always type-filter.

**Critical:** `tail -40` not `cat`. Transcripts grow unbounded with session age; cat causes hook latency to grow from 2ms to 100ms+.

**Critical:** `2>/dev/null` on both tail and jq. Claude Code may be mid-write when the hook fires; a partial JSON line at tail output causes jq to emit a parse error. Suppress errors; the empty result triggers fallback.

### Pattern 3: Pane Diff Fallback

**What:** When transcript extraction returns empty, compute a line-level diff of the last 40 pane lines against the stored previous pane state for this session. Send only new/added lines.

**When to use:** Only when `extract_last_assistant_response()` returns empty string.

**Implementation (in lib/hook-utils.sh):**
```bash
extract_pane_diff() {
  local session_name="$1"
  local current_pane="$2"
  local previous_file="/tmp/gsd-pane-prev-${session_name}.txt"
  local lock_file="/tmp/gsd-pane-lock-${session_name}"
  local pane_delta=""

  (
    flock -x -w 2 200 || { return; }

    if [ -f "$previous_file" ]; then
      pane_delta=$(diff \
        --new-line-format='%L' \
        --old-line-format='' \
        --unchanged-line-format='' \
        "$previous_file" \
        <(echo "$current_pane") 2>/dev/null || echo "")
    fi

    echo "$current_pane" > "$previous_file" 2>/dev/null || true

  ) 200>"$lock_file"

  # If no delta (first fire or no change), fall back to tail of current pane
  if [ -z "$pane_delta" ]; then
    pane_delta=$(echo "$current_pane" | tail -10)
  fi

  echo "$pane_delta"
}
```

**Key decisions:**
- `--new-line-format='%L'` prints only added lines without diff markup (no +, -, @@ noise)
- `flock -x -w 2` prevents concurrent Stop + Notification hook races on the same state file
- When no previous file exists (first fire), returns tail -10 of current pane as baseline
- Pane is captured as last 40 lines (`tail -40` of tmux capture-pane output) per requirements

**Why tail -40 for pane capture in fallback:** The requirements specify "only new/added lines from last 40 pane lines". The existing stop-hook.sh captures `PANE_CAPTURE_LINES` (default 100) lines for state detection. For the diff fallback, only 40 lines are needed; store 40 lines as the previous state.

### Pattern 4: AskUserQuestion Question Formatting

**What:** Format the structured `tool_input.questions` array from PreToolUse stdin into readable text for the [ASK USER QUESTION] wake section.

**When to use:** Only in pre-tool-use-hook.sh, called once per AskUserQuestion hook fire.

**Implementation (in lib/hook-utils.sh):**
```bash
format_ask_user_questions() {
  local tool_input_json="$1"

  echo "$tool_input_json" | jq -r '
    .questions[] |
    "Question: \(.question)\n" +
    (if .header then "Header: \(.header)\n" else "" end) +
    (if .multiSelect then "Multi-select: yes\n" else "Multi-select: no\n" end) +
    "Options:\n" +
    (.options // [] | to_entries[] |
      "  \(.key + 1). \(.value.label)" +
      (if .value.description and .value.description != "" then ": \(.value.description)" else "" end)
    ) + "\n"
  ' 2>/dev/null || echo "(could not parse questions)"
}
```

**AskUserQuestion tool_input schema (confirmed from live transcripts and official docs):**
```json
{
  "questions": [
    {
      "question": "Which approach should I use?",
      "header": "Approach",
      "options": [
        { "label": "Option A", "description": "Use existing pattern" },
        { "label": "Option B", "description": "Create new pattern" }
      ],
      "multiSelect": false
    }
  ]
}
```

Constraints: 1-4 questions per call; 2-4 options per question; header max 12 chars.

### Pattern 5: PreToolUse Hook Structure

**What:** pre-tool-use-hook.sh follows the same guard pattern as other hooks (stdin consume, TMUX check, session name, registry lookup) but has simpler delivery: always async, always exit 0.

**When to use:** This script is the entry point for every AskUserQuestion tool call in managed sessions.

**Full data flow:**
```
PreToolUse event fires (matcher: "AskUserQuestion")
    |
1. STDIN_JSON = cat (stdin)
    |
2. TMUX guard → exit 0 if not in tmux
    |
3. SESSION_NAME from tmux display-message
    |
4. Registry lookup → exit 0 if no match
    |
5. OPENCLAW_SESSION_ID extraction
    |
6. TOOL_INPUT = echo "$STDIN_JSON" | jq '.tool_input'
    |
7. source lib/hook-utils.sh
   FORMATTED_QUESTIONS = format_ask_user_questions("$TOOL_INPUT")
    |
8. Build [ASK USER QUESTION] wake message
    |
9. openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" \
   </dev/null >/dev/null 2>&1 &
    |
exit 0  (ALWAYS — never deny/block AskUserQuestion)
```

**Critical: exit 0 always.** If the hook returns non-zero or outputs a JSON decision, AskUserQuestion is blocked and the TUI never shows the question. The hook is notification-only.

**Critical: background the openclaw call.** `</dev/null >/dev/null 2>&1 &` is mandatory. Foreground openclaw calls block Claude Code's UI for 200ms-2s before the question renders.

### Pattern 6: V2 Wake Format for Stop Hook

**What:** The stop-hook.sh wake message changes from v1 [PANE CONTENT] to v2 [CONTENT] section containing either extracted transcript text (primary) or pane diff (fallback).

**V1 wake format (current stop-hook.sh, lines 142-166):**
```
[SESSION IDENTITY]
agent_id: X
tmux_session_name: Y
timestamp: Z

[TRIGGER]
type: response_complete

[STATE HINT]
state: working

[PANE CONTENT]
<100-150 lines raw tmux pane>

[CONTEXT PRESSURE]
47% [OK]

[AVAILABLE ACTIONS]
...
```

**V2 wake format (after Phase 6):**
```
[SESSION IDENTITY]
agent_id: X
tmux_session_name: Y
timestamp: Z

[TRIGGER]
type: response_complete

[CONTENT]
<extracted transcript text OR pane diff — never both>

[STATE HINT]
state: working

[CONTEXT PRESSURE]
47% [OK]

[AVAILABLE ACTIONS]
...
```

**V2 AskUserQuestion wake format (pre-tool-use-hook.sh):**
```
[SESSION IDENTITY]
agent_id: X
tmux_session_name: Y
timestamp: Z

[TRIGGER]
type: ask_user_question

[ASK USER QUESTION]
Question: Which approach should I use?
Header: Approach
Multi-select: no
Options:
  1. Option A: Use existing pattern
  2. Option B: Create new pattern

[STATE HINT]
state: awaiting_user_input

[AVAILABLE ACTIONS]
menu-driver.sh Y choose <n>
menu-driver.sh Y type <text>
...
```

**V1 code removal (WAKE-08):** The existing `WAKE_MESSAGE` heredoc in stop-hook.sh (lines 142-166) is replaced entirely. No conditional v1/v2 toggle. No backward compatibility layer. The prior research SUMMARY.md noted a deployment concern about Gideon's parsing — this has been decided: clean break, Gideon parsing update is a Phase 7 deployment concern, not Phase 6.

### Pattern 7: Stop Hook Integration Points

**What:** The exact locations in stop-hook.sh where new code is inserted/replaced.

**Current stop-hook.sh structure (196 lines):**

| Section | Lines | Change in Phase 6 |
|---------|-------|-------------------|
| 1. stdin consume | 20-21 | Unchanged |
| 2. stop_hook_active guard | 26-30 | Unchanged |
| 3. TMUX guard | 35-38 | Unchanged |
| 4. session extraction | 43-48 | Unchanged |
| 5. registry lookup | 53-79 | Unchanged |
| 6. hook_settings extract | 84-96 | Unchanged |
| 7. pane capture | 101 | Unchanged (still needed for state detection + fallback diff) |
| **7b. lib source + transcript extraction** | **after 101** | **NEW: source lib; TRANSCRIPT_PATH from STDIN_JSON; extract_last_assistant_response()** |
| 8. state detection | 106-116 | Unchanged |
| 9. context pressure | 123-135 | Unchanged |
| **9b. pane diff fallback** | **after 135** | **NEW: if EXTRACTED_RESPONSE empty, call extract_pane_diff(); set CONTENT_SOURCE label** |
| 10. build wake message | 140-166 | **REPLACED: v2 format with [CONTENT] section** |
| 11. delivery | 171-195 | Unchanged |

**lib sourcing placement:** Source lib/hook-utils.sh at step 7b (after pane capture, before state detection). This ensures pane content is already captured (needed for fallback diff), and transcript extraction runs before the wake message build.

### Anti-Patterns to Avoid

- **Positional content indexing:** `content[0].text` fails when thinking blocks precede text. Always use `content[]? | select(.type == "text") | .text`.
- **Reading full transcript:** `cat "$TRANSCRIPT_PATH" | jq` grows from 2ms to 100ms+ on long sessions. Always `tail -40`.
- **Synchronous openclaw in PreToolUse:** Blocks Claude Code UI before AskUserQuestion renders. Always background.
- **Sending both transcript and pane diff:** The v2 design is OR not AND. Pick one source per message.
- **Sourcing lib in notification/session-end/pre-compact hooks:** These scripts are untouched in Phase 6. Only stop-hook.sh and pre-tool-use-hook.sh source lib.
- **Using diff -u or grep '^>':** Unified diff includes headers and markers. Use `--new-line-format='%L'` flags.
- **Skipping flock on /tmp state files:** Stop hook and Notification hooks can fire concurrently. Without flock, concurrent reads/writes corrupt state and produce duplicate wakes.
- **Returning non-zero exit from pre-tool-use-hook.sh:** Blocks AskUserQuestion. Always exit 0.
- **Dedup exit path with zero context:** Not applicable for Phase 6 — deduplication (hash-based skip) was in prior research but is NOT in Phase 6 requirements. Phase 6 requirements are transcript OR pane diff, not the full dedup-skip path. Do not add dedup unless it appears in LIB-01/02, EXTRACT-01/02/03, ASK-01/02/03, WAKE-07/08/09.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON field extraction from stdin | Custom string parsing | jq with 2>/dev/null | jq handles all JSON edge cases; 2>/dev/null handles partial writes |
| JSONL line filtering | Python/Node.js parser | tail + jq streaming | 2ms vs 50ms; no new dependencies |
| Line-level diff | Custom diff implementation | GNU diff with --new-line-format | diff handles all edge cases (empty files, identical files, binary); custom diffs miss order-sensitive changes |
| Per-session mutex | Application-level lock | flock on /tmp file | flock is atomic; application locks fail on concurrent processes |
| Wake message assembly | printf with complex escaping | Bash heredoc or multiline variable | Heredoc handles newlines and special chars safely |

**Key insight:** This phase is adding bash function implementations to existing, working infrastructure. The complexity is in getting the jq filters, diff flags, and exit behaviors exactly right — not in building new systems.

---

## Common Pitfalls

### Pitfall 1: Content Block Type Indexing (CRITICAL)

**What goes wrong:** Using `content[0].text` to extract the assistant response. Fails silently when Claude uses extended thinking or tool calls before the text response — `content[0]` is a thinking or tool_use block, not a text block. Returns null or empty with no error.

**Why it happens:** The JSONL `message.content` is an array of typed objects. Claude's responses with extended thinking always have a thinking block first. Sessions with tool use have tool_result blocks in content.

**How to avoid:**
```bash
# WRONG
jq -r 'select(.type == "assistant") | .message.content[0].text'

# CORRECT
jq -r 'select(.type == "assistant") | (.message.content // [])[] | select(.type == "text") | .text'
```

**Warning signs:** CONTENT section empty in sessions with extended thinking. Works in simple test sessions, fails in production sessions.

### Pitfall 2: Partial JSONL Write at Hook Fire Time

**What goes wrong:** Claude Code may be mid-write to the transcript file when the Stop hook fires. The last line of the JSONL file may be partial JSON. jq fails to parse the truncated line and emits an error on stderr; the pipeline returns empty.

**How to avoid:** Always add `2>/dev/null` to jq calls against transcript files. Empty result triggers the pane diff fallback, which is correct behavior.

**Warning signs:** Intermittent empty CONTENT sections on first hook fires. jq parse errors in hook log.

### Pitfall 3: Blocking openclaw Call in PreToolUse

**What goes wrong:** Calling `openclaw agent --session-id ... --message ...` in the foreground in pre-tool-use-hook.sh. The hook blocks until openclaw returns (200ms-2s), delaying the AskUserQuestion TUI from rendering. Users see a freeze before the question appears.

**How to avoid:**
```bash
# WRONG
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE"

# CORRECT
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" \
  </dev/null >/dev/null 2>&1 &
```

**Warning signs:** AskUserQuestion prompts render with a 0.5-2s delay after Claude finishes its turn.

### Pitfall 4: Non-Zero Exit from PreToolUse

**What goes wrong:** Any non-zero exit code from pre-tool-use-hook.sh, or any JSON output to stdout with a "decision: block" field, causes Claude Code to block or deny the AskUserQuestion. The TUI never shows the question.

**How to avoid:** Always end pre-tool-use-hook.sh with `exit 0`. Never echo JSON to stdout. The hook is notification-only.

### Pitfall 5: Missing flock on Pane State Files

**What goes wrong:** Stop hook and Notification hooks fire concurrently for the same session. Both read `/tmp/gsd-pane-prev-SESSION.txt`, both compute a diff against the same baseline, both write the new state. The writes race; one write may truncate mid-read; both hooks deliver identical delta content.

**How to avoid:** Wrap the read-diff-write cycle in `flock -x -w 2` on a per-session lock file. 2-second timeout prevents deadlock.

### Pitfall 6: session_name Containing Special Characters

**What goes wrong:** If a tmux session name contains spaces or slashes, `/tmp/gsd-pane-prev-${SESSION_NAME}.txt` becomes a path with spaces or directory separators. Space: technically valid but risky in bash. Slash: creates subdirectory, write fails.

**How to avoid:** Current production sessions (`warden-main`, `forge-main`) are safe. If session names ever use unusual chars, sanitize: `SESSION_SAFE_NAME=$(echo "$SESSION_NAME" | tr ' /' '__')`. Not a code change for now — document as a known edge case.

---

## Code Examples

Verified patterns for implementation:

### Transcript Extraction Function (lib/hook-utils.sh)

```bash
# Source: ARCHITECTURE.md, verified against live transcripts on host
extract_last_assistant_response() {
  local transcript_path="$1"

  if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
    echo ""
    return
  fi

  tail -40 "$transcript_path" 2>/dev/null | \
    jq -r 'select(.type == "assistant") |
      (.message.content // [])[] |
      select(.type == "text") | .text' 2>/dev/null | \
    tail -1
}
```

### Pane Diff Function (lib/hook-utils.sh)

```bash
# Source: ARCHITECTURE.md, GNU diff --new-line-format pattern
extract_pane_diff() {
  local session_name="$1"
  local current_pane="$2"
  local previous_file="/tmp/gsd-pane-prev-${session_name}.txt"
  local lock_file="/tmp/gsd-pane-lock-${session_name}"
  local pane_delta=""

  (
    flock -x -w 2 200 || { echo ""; return; }

    if [ -f "$previous_file" ]; then
      pane_delta=$(diff \
        --new-line-format='%L' \
        --old-line-format='' \
        --unchanged-line-format='' \
        "$previous_file" \
        <(echo "$current_pane") 2>/dev/null || echo "")
    fi

    echo "$current_pane" > "$previous_file" 2>/dev/null || true
    echo "$pane_delta"

  ) 200>"$lock_file"
}
```

**Note:** The function as written above has a subshell variable scoping issue — `pane_delta` set inside the subshell is not visible outside. The actual implementation needs to capture the subshell output. Correct pattern:

```bash
extract_pane_diff() {
  local session_name="$1"
  local current_pane="$2"
  local previous_file="/tmp/gsd-pane-prev-${session_name}.txt"
  local lock_file="/tmp/gsd-pane-lock-${session_name}"

  local pane_delta
  pane_delta=$(
    flock -x -w 2 "/tmp/gsd-pane-lock-${session_name}" sh -c "
      if [ -f '${previous_file}' ]; then
        diff --new-line-format='%L' --old-line-format='' --unchanged-line-format='' \
          '${previous_file}' - 2>/dev/null
      fi
      cat > '${previous_file}'
    " <<< "$current_pane" 2>/dev/null || echo ""
  )

  if [ -z "$pane_delta" ]; then
    pane_delta=$(echo "$current_pane" | tail -10)
  fi

  echo "$pane_delta"
}
```

**Planner note:** The subshell/flock pattern needs care. The simplest correct approach uses a temp file for flock + process substitution. Recommend the planner specify the exact flock pattern and test it explicitly. See Open Questions #1.

### Question Formatting Function (lib/hook-utils.sh)

```bash
# Source: ARCHITECTURE.md, official AskUserQuestion tool_input schema
format_ask_user_questions() {
  local tool_input_json="$1"

  echo "$tool_input_json" | jq -r '
    .questions[] |
    "Question: \(.question)\n" +
    (if .header then "Header: \(.header)\n" else "" end) +
    (if .multiSelect then "Multi-select: yes\n" else "Multi-select: no\n" end) +
    "Options:\n" +
    (.options // [] | to_entries[] |
      "  \(.key + 1). \(.value.label)" +
      (if .value.description and .value.description != "" then ": \(.value.description)" else "" end)
    ) + "\n"
  ' 2>/dev/null || echo "(could not parse questions)"
}
```

### Transcript Path Extraction from stdin (in stop-hook.sh)

```bash
# After section 6 (hook_settings), source lib then extract transcript path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/hook-utils.sh"

TRANSCRIPT_PATH=$(echo "$STDIN_JSON" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
EXTRACTED_RESPONSE=$(extract_last_assistant_response "$TRANSCRIPT_PATH")
```

### Content Section Assembly (in stop-hook.sh, replaces section 10)

```bash
# Determine content source: transcript (primary) or pane diff (fallback)
if [ -n "$EXTRACTED_RESPONSE" ]; then
  CONTENT_SECTION="[CONTENT]
${EXTRACTED_RESPONSE}"
else
  # Fallback: pane diff from last 40 lines
  PANE_FOR_DIFF=$(echo "$PANE_CONTENT" | tail -40)
  PANE_DELTA=$(extract_pane_diff "$SESSION_NAME" "$PANE_FOR_DIFF")
  CONTENT_SECTION="[CONTENT]
${PANE_DELTA}"
fi

WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: response_complete

${CONTENT_SECTION}

[STATE HINT]
state: ${STATE}

[CONTEXT PRESSURE]
${CONTEXT_PRESSURE}

[AVAILABLE ACTIONS]
menu-driver.sh ${SESSION_NAME} choose <n>
menu-driver.sh ${SESSION_NAME} type <text>
menu-driver.sh ${SESSION_NAME} clear_then <command>
menu-driver.sh ${SESSION_NAME} enter
menu-driver.sh ${SESSION_NAME} esc
menu-driver.sh ${SESSION_NAME} submit
menu-driver.sh ${SESSION_NAME} snapshot"
```

### Async Delivery in pre-tool-use-hook.sh

```bash
# Step 9: always async, always exit 0
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" \
  >> "$GSD_HOOK_LOG" 2>&1 &
debug_log "DELIVERED (async AskUserQuestion forward, bg PID=$!)"
exit 0
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Raw 120-line pane dump in [PANE CONTENT] | Transcript text OR pane diff in [CONTENT] | Phase 6 (this phase) | Gideon receives clean response text instead of tmux rendering noise |
| No AskUserQuestion forwarding | PreToolUse hook forwards structured questions before TUI renders | Phase 6 (this phase) | Gideon sees exact question text and options before user interaction |
| Extraction logic inline in hook scripts | Shared lib/hook-utils.sh functions | Phase 6 (this phase) | DRY: one fix point for extraction bugs |
| v1 format: [PANE CONTENT] | v2 format: [CONTENT] (one source, clean) | Phase 6 (this phase) | No ANSI codes, no rendering artifacts, no duplicate content |

**Deprecated/outdated:**
- `[PANE CONTENT]` section: removed entirely in this phase (WAKE-08). No backward compat layer.
- Dual-section design (transcript + pane delta both): simplified to OR in commit eadb686. The prior research SUMMARY.md described both sections in v2 — this has been superseded. Phase 6 uses one [CONTENT] section only.

---

## Open Questions

1. **flock subshell variable scoping in extract_pane_diff**
   - What we know: flock with a subshell `( ... ) 200>lockfile` pattern prevents pane_delta from being visible in the outer scope
   - What's unclear: best bash pattern for flock + variable capture without a temp file
   - Recommendation: Use `flock lockfile command` inline form with process substitution, or write pane_delta to a temp file inside the flock block and read it outside. The planner should specify the exact implementation pattern and include a test step.

2. **pane content variable for fallback diff (40 vs PANE_CAPTURE_LINES)**
   - What we know: stop-hook.sh captures PANE_CAPTURE_LINES (default 100) lines for state detection. Requirements say "last 40 pane lines" for diff fallback.
   - What's unclear: should stop-hook.sh capture 40 lines separately for diff, or tail the existing PANE_CONTENT capture?
   - Recommendation: Use `echo "$PANE_CONTENT" | tail -40` on the existing capture — this avoids a second tmux capture-pane call and is simpler. The stored previous state is 40 lines, matching what was sent to Gideon.

3. **lib/hook-utils.sh error handling for missing lib file**
   - What we know: if lib/hook-utils.sh is missing or unreadable, `source` in stop-hook.sh will fail, causing the hook to exit with an error
   - What's unclear: whether to use `source ... || { debug_log ...; fallback; }` or `set -e` behavior
   - Recommendation: Use `source "${LIB_PATH}" 2>/dev/null || { debug_log "ERROR: lib not found, falling back to v1 behavior"; use v1 pane content; }`. The hook must never error out and break Claude Code operation.

---

## Sources

### Primary (HIGH confidence — existing project research)
- `.planning/research/SUMMARY.md` — complete v2.0 research synthesis; all key decisions
- `.planning/research/ARCHITECTURE.md` — exact integration points, line numbers, function implementations, data flow diagrams
- `.planning/research/FEATURES.md` — feature specifications, AskUserQuestion schema, transcript JSONL structure, behavior descriptions
- `.planning/research/PITFALLS.md` — 11 documented pitfalls with prevention strategies and verification checklist
- `.planning/research/STACK.md` — all tool versions confirmed on production host
- `.planning/REQUIREMENTS.md` — v2.0 requirements as simplified in commit eadb686 (2026-02-18)
- `.planning/STATE.md` — current decisions including "transcript OR pane diff, not both" (2026-02-18)

### Primary (HIGH confidence — local codebase)
- `scripts/stop-hook.sh` (196 lines) — exact line numbers for all integration points verified by reading the file
- `scripts/notification-idle-hook.sh` — structural reference for pre-tool-use-hook.sh guard patterns
- `scripts/register-hooks.sh` — PreToolUse registration pattern reference (Phase 7 concern, not Phase 6)

### Primary (HIGH confidence — official documentation, from prior research)
- Claude Code Hooks Reference (code.claude.com/docs/en/hooks) — PreToolUse stdin schema, AskUserQuestion matcher, transcript_path field
- Claude Agent SDK / Handle approvals (platform.claude.com/docs/en/agent-sdk/user-input) — AskUserQuestion tool_input.questions structure
- GitHub Issue #13439 — PreToolUse + AskUserQuestion bug fixed in Claude Code 2.0.76; current version 2.1.45 is safe

### Secondary (MEDIUM confidence — community, from prior research)
- claude-code-log (github.com/daaain/claude-code-log) — JSONL content type enumeration confirming text/tool_use/thinking blocks
- Simon Willison JSONL analysis — confirms JSONL format and session structure

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies, all tools version-checked on production host in prior research
- Architecture: HIGH — integration points mapped to exact line numbers; all function signatures specified; prior research verified against live transcripts
- Pitfalls: HIGH — based on official docs, confirmed GitHub issues, and analysis of existing v1.0 codebase
- Phase 6 scope: HIGH — requirements are clear; simplification decision (transcript OR pane diff) is documented and confirmed

**Research date:** 2026-02-18
**Valid until:** Stable (no external dependencies; Claude Code API and bash utilities are stable)

**Key simplification since prior research:** The SUMMARY.md and ARCHITECTURE.md describe a v2 format with both `[CLAUDE RESPONSE]` and `[PANE DELTA]` as separate sections. This was superseded by commit eadb686 on 2026-02-18. Phase 6 uses a single `[CONTENT]` section: transcript text if available, pane diff if not. The planner must use `[CONTENT]` not `[CLAUDE RESPONSE]` + `[PANE DELTA]`. Requirements are authoritative.

**Build order for planner:**
1. `lib/hook-utils.sh` — no dependencies (Plan 1)
2. `scripts/pre-tool-use-hook.sh` — depends on lib (Plan 2, parallel with Plan 3)
3. `scripts/stop-hook.sh` modifications — depends on lib (Plan 3, parallel with Plan 2)
