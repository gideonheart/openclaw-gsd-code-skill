# Architecture Research: v2.0 Smart Hook Delivery

**Domain:** Hook-driven OpenClaw agent control for Claude Code sessions
**Researched:** 2026-02-17
**Confidence:** HIGH

## Executive Summary

v2.0 adds four precision-extraction features to the existing 5-hook architecture:
transcript-based response extraction, PreToolUse hook for AskUserQuestion forwarding,
diff-based pane delivery, and deduplication. Each feature is additive. The existing
5 hook scripts continue working unchanged. New features are implemented as new shared
library functions plus targeted modifications to stop-hook.sh (the primary delivery
script) and a new pre-tool-use-hook.sh.

**Critical discovery:** The PreToolUse hook for AskUserQuestion had a known bug
causing empty responses (issue #13439). This was fixed in Claude Code 2.0.76.
Current production version is 2.1.45. The fix is in place — PreToolUse hook for
AskUserQuestion is safe to implement.

**Critical discovery:** AskUserQuestion `tool_input` structure confirmed from live
transcripts. The field path is `.tool_input.questions[].{question, header, options, multiSelect}`.
Options are `.options[].{label, description}`.

**Architecture decision:** All four features integrate through a single shared library
script (`lib/hook-utils.sh`) that stop-hook.sh and pre-tool-use-hook.sh both source.
This avoids code duplication across the 5 existing hooks while keeping each hook script
as the SRP entry point.

---

## System Overview

### Current Architecture (v1.0)

```
Claude Code Session (tmux pane)
         |
         | hook event fires
         v
┌──────────────────────────────────────────────────┐
│              Hook Scripts (~/.claude/settings.json)│
│                                                    │
│  stop-hook.sh          (Stop event)               │
│  notification-idle-hook.sh   (Notification/idle)  │
│  notification-permission-hook.sh (Notification/perm)│
│  session-end-hook.sh   (SessionEnd event)         │
│  pre-compact-hook.sh   (PreCompact event)         │
└──────────────┬───────────────────────────────────┘
               |
               | guards: tmux check → registry lookup
               v
┌──────────────────────────────────────────────────┐
│          Shared Logic (duplicated across scripts) │
│                                                    │
│  stdin consume → TMUX guard → session extract    │
│  registry lookup → hook_settings extract         │
│  pane capture → state detection → context pct    │
│  wake message build → openclaw deliver           │
└──────────────┬───────────────────────────────────┘
               |
               | openclaw agent --session-id UUID
               v
┌──────────────────────────────────────────────────┐
│    Wake Message v1 (raw pane dump)               │
│                                                    │
│  [SESSION IDENTITY]                               │
│  [TRIGGER]                                        │
│  [STATE HINT]                                     │
│  [PANE CONTENT] ← 100-150 lines raw tmux output  │
│  [CONTEXT PRESSURE]                               │
│  [AVAILABLE ACTIONS]                              │
└──────────────────────────────────────────────────┘
```

### Target Architecture (v2.0)

```
Claude Code Session (tmux pane)
         |
         | hook event fires (Stop, PreToolUse, Notification, etc.)
         v
┌──────────────────────────────────────────────────┐
│              Hook Entry Points                    │
│                                                    │
│  stop-hook.sh          (Stop event)   ← MODIFIED │
│  pre-tool-use-hook.sh  (PreToolUse)   ← NEW      │
│  notification-idle-hook.sh            unchanged   │
│  notification-permission-hook.sh      unchanged   │
│  session-end-hook.sh                  unchanged   │
│  pre-compact-hook.sh                  unchanged   │
└──────────────┬───────────────────────────────────┘
               |
               | source lib/hook-utils.sh
               v
┌──────────────────────────────────────────────────┐
│          lib/hook-utils.sh (NEW shared library)  │
│                                                    │
│  extract_last_assistant_response()               │
│    tail -50 transcript JSONL                     │
│    jq: select type==assistant, content[].text    │
│    Returns: last text block from assistant       │
│                                                    │
│  compute_pane_hash()                             │
│    md5sum of pane content                        │
│    Returns: hex hash string                      │
│                                                    │
│  load_previous_pane_hash()                       │
│    reads /tmp/gsd-pane-hash-SESSION.txt          │
│    Returns: previous hash or ""                  │
│                                                    │
│  save_pane_hash()                                │
│    writes hash to /tmp/gsd-pane-hash-SESSION.txt │
│                                                    │
│  extract_pane_diff()                             │
│    compare PANE_CONTENT vs /tmp/gsd-pane-prev-SESSION.txt │
│    save current as new previous                  │
│    Returns: diff lines (new lines only)          │
│                                                    │
│  build_wake_message_v2()                         │
│    assembles structured v2 format                │
│    inputs: response, pane_delta, state, context  │
└──────────────┬───────────────────────────────────┘
               |
               | targeted delivery
               v
┌──────────────────────────────────────────────────┐
│    Wake Message v2 (extracted content)           │
│                                                    │
│  [SESSION IDENTITY]                               │
│  [TRIGGER]                                        │
│  [CLAUDE RESPONSE]      ← extracted from JSONL   │
│  [STATE HINT]                                     │
│  [PANE DELTA]           ← diff since last wake   │
│  [CONTEXT PRESSURE]                               │
│  [AVAILABLE ACTIONS]                              │
└──────────────────────────────────────────────────┘

─ ─ ─ separate path for AskUserQuestion ─ ─ ─

Claude calls AskUserQuestion tool
         |
         | PreToolUse event fires (BEFORE tool executes)
         v
┌──────────────────────────────────────────────────┐
│    pre-tool-use-hook.sh                          │
│                                                    │
│  stdin JSON:                                     │
│    hook_event_name: "PreToolUse"                 │
│    tool_name: "AskUserQuestion"                  │
│    tool_input.questions[]:                       │
│      { question, header, options[], multiSelect } │
│                                                    │
│  matcher: "AskUserQuestion"                      │
│  (only fires for AskUserQuestion, fast exit       │
│   for any other tool_name)                       │
│                                                    │
│  → extract questions from tool_input             │
│  → build forwarding wake message                 │
│  → openclaw agent --session-id UUID --message    │
│  → exit 0 (let AskUserQuestion proceed normally) │
└──────────────────────────────────────────────────┘
```

---

## Component Boundaries

| Component | Status | Responsibility | v2.0 Changes |
|-----------|--------|----------------|--------------|
| `stop-hook.sh` | MODIFIED | Stop event entry point | Add transcript extraction, diff delivery, deduplication |
| `pre-tool-use-hook.sh` | NEW | PreToolUse entry point for AskUserQuestion | Full new script |
| `lib/hook-utils.sh` | NEW | Shared extraction functions | All new v2.0 logic lives here |
| `notification-idle-hook.sh` | UNCHANGED | Notification/idle_prompt entry | No changes in v2.0 |
| `notification-permission-hook.sh` | UNCHANGED | Notification/permission_prompt entry | No changes in v2.0 |
| `session-end-hook.sh` | UNCHANGED | SessionEnd entry point | No changes in v2.0 |
| `pre-compact-hook.sh` | UNCHANGED | PreCompact entry point | No changes in v2.0 |
| `register-hooks.sh` | MODIFIED | Idempotent hook registration | Add PreToolUse registration |
| `config/recovery-registry.json` | MODIFIED | Agent metadata + hook settings | Add v2 hook_settings fields |
| `/tmp/gsd-pane-hash-SESSION.txt` | NEW (runtime) | Per-session pane hash store | Created/read at hook runtime |
| `/tmp/gsd-pane-prev-SESSION.txt` | NEW (runtime) | Per-session previous pane content | Created/read for diff |

---

## Feature Integration Points

### Feature 1: Transcript-Based Response Extraction

**What it replaces:** The `[PANE CONTENT]` section in wake messages v1 used raw tmux pane capture. This produces 100-150 lines of mixed noise (ANSI codes, status bars, previous output). The transcript JSONL contains the exact assistant response text.

**Integration point:** `stop-hook.sh`, section 7 (CAPTURE PANE CONTENT), currently line 101.

**New behavior:** After pane capture (still needed for state detection), add a separate transcript read step that extracts the last assistant text message.

**Data flow:**

```
stdin JSON  →  TRANSCRIPT_PATH=$(echo "$STDIN_JSON" | jq -r '.transcript_path')
                    |
                    | tail -50 "$TRANSCRIPT_PATH"
                    |
                    | jq -r 'select(.type == "assistant") |
                    |   (.message.content // [])[] |
                    |   select(.type == "text") | .text'
                    |
                    v
            EXTRACTED_RESPONSE (last 2000 chars)
```

**Bash implementation pattern (hook-utils.sh):**

```bash
extract_last_assistant_response() {
  local transcript_path="$1"
  local max_chars="${2:-2000}"

  if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
    echo ""
    return
  fi

  # tail -50: only look at recent entries (performance + we want last response)
  # jq: select assistant type, extract all text content blocks
  # Last text block from last assistant entry = Claude's final output
  local response
  response=$(tail -50 "$transcript_path" 2>/dev/null | \
    jq -r 'select(.type == "assistant") |
      (.message.content // [])[] |
      select(.type == "text") | .text' 2>/dev/null | \
    tail -c "$max_chars")

  echo "$response"
}
```

**Wake message v2 change:** Replaces raw `[PANE CONTENT]` with `[CLAUDE RESPONSE]` section containing the extracted text. Falls back to pane content if transcript_path is empty or file unreadable.

**Confidence:** HIGH. Verified against live transcript files. JSONL structure confirmed: `type == "assistant"`, `message.content[].type == "text"`, `message.content[].text`.

---

### Feature 2: PreToolUse Hook for AskUserQuestion

**What it does:** When Claude calls `AskUserQuestion`, the PreToolUse event fires BEFORE the tool executes. The hook receives `.tool_input.questions` containing the exact question text, header, options, and multiSelect flag. The hook forwards this structured data to the OpenClaw agent so the orchestrator sees the question immediately — without waiting for pane scraping.

**Why PreToolUse not Notification:** The `elicitation_dialog` Notification fires but does NOT include question data. PreToolUse fires with `tool_input` containing the full question payload.

**Known bug (resolved):** PreToolUse hook caused `AskUserQuestion` to return empty responses (GitHub issue #13439). Fixed in Claude Code 2.0.76. Current production: 2.1.45. Safe to implement.

**New file:** `scripts/pre-tool-use-hook.sh`

**Registration:** `register-hooks.sh` must add to `~/.claude/settings.json`:

```json
"PreToolUse": [
  {
    "matcher": "AskUserQuestion",
    "hooks": [
      {
        "type": "command",
        "command": "/path/to/pre-tool-use-hook.sh",
        "timeout": 30
      }
    ]
  }
]
```

**Note:** `matcher: "AskUserQuestion"` means this hook only fires for AskUserQuestion calls. No fast-path guard needed for other tools.

**stdin JSON received by pre-tool-use-hook.sh:**

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/working/dir",
  "permission_mode": "dontAsk",
  "hook_event_name": "PreToolUse",
  "tool_name": "AskUserQuestion",
  "tool_use_id": "toolu_01ABC123",
  "tool_input": {
    "questions": [
      {
        "question": "Which approach should we use?",
        "header": "Implementation choice",
        "options": [
          { "label": "Option A", "description": "Use existing pattern" },
          { "label": "Option B", "description": "Create new pattern" }
        ],
        "multiSelect": false
      }
    ]
  }
}
```

**Confirmed from live transcript analysis:** Field path `.tool_input.questions[].options[].{label,description}` and `.tool_input.questions[].multiSelect`. The `input` field in transcript becomes `tool_input` in PreToolUse hook stdin.

**Data flow:**

```
stdin JSON
    |
    | jq: extract tool_input.questions
    v
QUESTIONS_JSON  →  format as readable text
    |
    | build wake message with [ASKUSERQUESTION] section
    v
openclaw agent --session-id UUID --message MSG (async, background)
    |
exit 0  ←  let AskUserQuestion execute normally
```

**Wake message format for AskUserQuestion forwarding:**

```
[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: ask_user_question

[ASK USER QUESTION]
${FORMATTED_QUESTIONS}

[STATE HINT]
state: awaiting_user_input

[AVAILABLE ACTIONS]
menu-driver.sh ${SESSION_NAME} choose <n>
menu-driver.sh ${SESSION_NAME} type <text>
```

**Formatting questions in bash (hook-utils.sh):**

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
      (if .value.description != "" then ": \(.value.description)" else "" end)
    ) + "\n"
  ' 2>/dev/null || echo "(could not parse questions)"
}
```

**Exit behavior:** Always exits 0. Never blocks AskUserQuestion. The hook's purpose is notification only — the OpenClaw agent observes the question but the actual UI interaction is Claude Code's responsibility.

**Confidence:** HIGH for field structure (confirmed from live transcripts). MEDIUM for bug-fix behavior (confirmed from GitHub issue, Claude Code 2.1.45 > 2.0.76 fix threshold).

---

### Feature 3: Diff-Based Pane Delivery

**What it replaces:** `[PANE CONTENT]` sends 100-150 lines of raw tmux output on every hook fire. Most of this is repeated content from the previous delivery. The OpenClaw agent sees mostly duplicate content, increasing token waste and reducing signal clarity.

**What diff delivery does:** Store the previous pane capture in `/tmp/gsd-pane-prev-SESSION.txt`. On each hook fire, compare the new capture to the previous. Send only the new lines (the delta). Always include a minimum of 10 lines as context guarantee.

**Persistent state location:** `/tmp/gsd-pane-prev-SESSION.txt` (per session, session name in filename). This is ephemeral (lost on reboot), which is acceptable — a reboot triggers recovery flow which resets session state.

**Data flow:**

```
PANE_CONTENT (current capture)
    |
    | load_previous_pane_content(SESSION_NAME)
    v
PREVIOUS_CONTENT (from /tmp or empty string)
    |
    | diff --new-line-format='%L' --old-line-format='' \
    |      --unchanged-line-format=''
    | (GNU diff: only print added lines)
    v
PANE_DELTA (new lines only)
    |
    | if len(PANE_DELTA) < MIN_CONTEXT_LINES (10):
    |   PANE_DELTA = tail -10 PANE_CONTENT (minimum guarantee)
    v
DELIVERY_CONTENT
    |
    | save_current_pane_content(SESSION_NAME, PANE_CONTENT)
    v
wake message [PANE DELTA] section
```

**Bash implementation pattern (hook-utils.sh):**

```bash
MIN_CONTEXT_LINES=10

extract_pane_diff() {
  local session_name="$1"
  local current_pane="$2"
  local previous_file="/tmp/gsd-pane-prev-${session_name}.txt"

  local pane_delta=""

  if [ -f "$previous_file" ]; then
    # diff: print only lines added in current vs previous
    # Using comm -23 after sorting doesn't preserve order.
    # Use diff with format flags to get only new lines in order.
    pane_delta=$(diff \
      --new-line-format='%L' \
      --old-line-format='' \
      --unchanged-line-format='' \
      "$previous_file" \
      <(echo "$current_pane") 2>/dev/null || echo "")
  fi

  # Save current as new previous (always, even if diff failed)
  echo "$current_pane" > "$previous_file" 2>/dev/null || true

  # Minimum context guarantee: always send at least MIN_CONTEXT_LINES
  local delta_line_count
  delta_line_count=$(echo "$pane_delta" | wc -l 2>/dev/null || echo "0")

  if [ "$delta_line_count" -lt "$MIN_CONTEXT_LINES" ]; then
    # Supplement with recent tail of current pane
    pane_delta=$(echo "$current_pane" | tail -"$MIN_CONTEXT_LINES")
  fi

  echo "$pane_delta"
}
```

**Note on diff approach:** GNU `diff` with `--new-line-format` flags prints only added lines while preserving their original order. This is the correct approach over `comm` (which requires sorted input and loses order).

**Integration point in stop-hook.sh:** After section 7 (CAPTURE PANE CONTENT, line 101), before section 10 (BUILD WAKE MESSAGE, line 142). The `PANE_CONTENT` variable is still needed for state detection (section 8) and context pressure extraction (section 9). The diff runs after state detection and replaces the delivery content.

**Wake message change:** Section label changes from `[PANE CONTENT]` to `[PANE DELTA]`. Content is the diff output instead of full pane. The v2 format uses `[CLAUDE RESPONSE]` (from transcript) as the primary content and `[PANE DELTA]` as supplementary context.

**Confidence:** HIGH. GNU diff available on Ubuntu 24. `/tmp` writable confirmed. File naming pattern `/tmp/gsd-pane-prev-SESSION.txt` does not conflict with existing `/tmp/gsd-hooks.log`.

---

### Feature 4: Deduplication

**What it solves:** The Stop hook fires every time Claude finishes responding, including after trivial tool completions mid-task. Some hook fires produce no meaningful change in pane content. Without deduplication, the OpenClaw agent receives repeated near-identical wake messages, wasting tokens and attention.

**Mechanism:** md5sum hash of the pane content stored in `/tmp/gsd-pane-hash-SESSION.txt`. Before delivering, compare current hash to stored. If identical: skip full delivery, optionally send a lightweight signal.

**Data flow:**

```
PANE_CONTENT
    |
    | md5sum → CURRENT_HASH
    v
load /tmp/gsd-pane-hash-SESSION.txt → PREVIOUS_HASH
    |
    | if CURRENT_HASH == PREVIOUS_HASH:
    |   debug_log "dedup: pane unchanged, skipping delivery"
    |   exit 0  (or send lightweight pulse signal)
    |
    | if CURRENT_HASH != PREVIOUS_HASH:
    |   save CURRENT_HASH to /tmp/gsd-pane-hash-SESSION.txt
    |   proceed to full delivery
    v
(continue with transcript extraction + diff delivery)
```

**Bash implementation pattern (hook-utils.sh):**

```bash
is_pane_duplicate() {
  local session_name="$1"
  local pane_content="$2"
  local hash_file="/tmp/gsd-pane-hash-${session_name}.txt"

  local current_hash
  current_hash=$(echo "$pane_content" | md5sum | cut -d' ' -f1)

  local previous_hash=""
  if [ -f "$hash_file" ]; then
    previous_hash=$(cat "$hash_file" 2>/dev/null || echo "")
  fi

  # Save current hash (regardless of match, update for next comparison)
  echo "$current_hash" > "$hash_file" 2>/dev/null || true

  if [ "$current_hash" = "$previous_hash" ]; then
    echo "true"
  else
    echo "false"
  fi
}
```

**Integration point in stop-hook.sh:** After section 7 (CAPTURE PANE CONTENT) and section 8 (DETECT STATE), immediately before section 10 (BUILD WAKE MESSAGE). Specifically: compute hash, compare to stored, if duplicate then `debug_log "dedup: unchanged"` and `exit 0`.

**Deduplication scope:** Hash is based on full pane content. This means if any visible change occurred (new output line, cursor movement, status bar update), the delivery proceeds. This is intentionally conservative — false negatives (delivering when unchanged) are acceptable; false positives (skipping when changed) are not.

**Interaction with diff delivery:** Deduplication runs FIRST. If hash matches, skip entirely. If hash differs, run diff extraction. The two features are complementary: dedup prevents delivery on zero-change events; diff reduces payload size when content changed but mostly repeated.

**Confidence:** HIGH. md5sum confirmed available. `/tmp` writeable confirmed.

---

## Structured Wake Message v2 Format

The four features above combine to produce a new wake message format. This replaces the v1 format used in all 5 existing scripts (for stop-hook.sh only — other scripts keep v1 for now).

**v1 format (current):**

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
menu-driver.sh Y choose <n>
...
```

**v2 format (target for stop-hook.sh):**

```
[SESSION IDENTITY]
agent_id: X
tmux_session_name: Y
timestamp: Z

[TRIGGER]
type: response_complete

[CLAUDE RESPONSE]
<extracted text from transcript JSONL, last 2000 chars>

[STATE HINT]
state: working

[PANE DELTA]
<new lines since last delivery, min 10 lines>

[CONTEXT PRESSURE]
47% [OK]

[AVAILABLE ACTIONS]
menu-driver.sh Y choose <n>
menu-driver.sh Y type <text>
menu-driver.sh Y clear_then <command>
menu-driver.sh Y enter
menu-driver.sh Y esc
menu-driver.sh Y submit
menu-driver.sh Y snapshot
```

**Fallback handling:**
- If `transcript_path` empty or file missing: omit `[CLAUDE RESPONSE]` section, fall back to `[PANE CONTENT]` (full pane, v1 behavior)
- If diff fails or previous pane file missing: use `[PANE CONTENT]` (full pane, first delivery after restart always full)
- If dedup skip: no message sent (exit 0)

---

## Project Structure After v2.0

```
gsd-code-skill/
├── scripts/
│   ├── stop-hook.sh           # MODIFIED: transcript, diff, dedup, v2 format
│   ├── pre-tool-use-hook.sh   # NEW: AskUserQuestion forwarding
│   ├── notification-idle-hook.sh      # unchanged
│   ├── notification-permission-hook.sh # unchanged
│   ├── session-end-hook.sh    # unchanged
│   ├── pre-compact-hook.sh    # unchanged
│   ├── register-hooks.sh      # MODIFIED: add PreToolUse registration
│   ├── spawn.sh               # unchanged (v1.0 already correct)
│   ├── menu-driver.sh         # unchanged (v1.0 already correct)
│   ├── recover-openclaw-agents.sh    # unchanged
│   ├── sync-recovery-registry-session-ids.sh # unchanged
│   └── diagnose-hooks.sh      # unchanged
├── lib/
│   └── hook-utils.sh          # NEW: shared extraction functions
├── config/
│   ├── recovery-registry.json         # MODIFIED: v2 hook_settings fields
│   ├── recovery-registry.example.json # MODIFIED: document v2 fields
│   └── default-system-prompt.txt      # unchanged
└── .planning/
    └── research/
        └── ARCHITECTURE.md    # this file
```

**Why `lib/` directory:** The 5 existing scripts all duplicate the same guard + registry lookup + hook_settings extraction + pane capture + state detection + delivery logic. This was acceptable for v1.0 (additive creation). For v2.0, new shared logic (transcript extraction, diff, dedup) would need to be duplicated across all 5 scripts if kept inline. A shared library prevents that duplication while keeping each hook as the SRP entry point.

**SRP preserved:** Each hook script remains one entry point for one hook event. The lib function calls are orchestration, not business logic in the entry point.

---

## Integration Points Summary (Script + Line References)

### stop-hook.sh modifications

| Step | Current lines | Change |
|------|--------------|--------|
| 1. stdin consume | lines 19-21 | Unchanged |
| 2. stop_hook_active guard | lines 26-30 | Unchanged |
| 3. TMUX guard | lines 35-38 | Unchanged |
| 4. session extraction | lines 43-48 | Unchanged |
| 5. registry lookup | lines 53-79 | Unchanged |
| 6. hook_settings extract | lines 84-96 | Unchanged |
| 7. pane capture | line 101 | Unchanged (still needed for state detection) |
| **7b. transcript extraction** | **after line 101** | **NEW: source lib/hook-utils.sh, call extract_last_assistant_response()** |
| 8. state detection | lines 106-116 | Unchanged |
| 9. context pressure | lines 123-135 | Unchanged |
| **9b. deduplication check** | **after line 135** | **NEW: call is_pane_duplicate(); if true, exit 0** |
| **9c. diff extraction** | **after dedup check** | **NEW: call extract_pane_diff(); store PANE_DELTA** |
| 10. build wake message | lines 140-166 | **MODIFIED: use v2 format with [CLAUDE RESPONSE] + [PANE DELTA]** |
| 11. delivery | lines 171-195 | Unchanged |

### register-hooks.sh modifications

**Location:** The `HOOKS_CONFIG` heredoc, lines 77-135.

**Change:** Add `PreToolUse` block to the JSON configuration:

```json
"PreToolUse": [
  {
    "matcher": "AskUserQuestion",
    "hooks": [
      {
        "type": "command",
        "command": "${SKILL_ROOT}/scripts/pre-tool-use-hook.sh",
        "timeout": 30
      }
    ]
  }
]
```

**Also add:** `pre-tool-use-hook.sh` to the `HOOK_SCRIPTS` array (lines 46-52) for pre-flight verification.

**Also add:** `.hooks.PreToolUse = $new.PreToolUse` to the jq merge expression (lines 145-163).

**Also add:** Verification output for PreToolUse hook (lines 195-211 pattern).

### recovery-registry.json (optional v2 additions)

If new `hook_settings` fields are needed for v2.0 behavior (e.g., `transcript_extract_chars`, `min_context_lines`, `dedup_enabled`), they follow the existing three-tier fallback pattern. Not required for MVP — hardcoded defaults are acceptable for v2.0.

---

## Data Flow Diagrams

### Stop Hook v2.0 Complete Flow

```
Claude Code finishes responding
         |
         | Stop event fires
         v
stop-hook.sh starts
         |
1. STDIN_JSON = cat (stdin)
         |
2. stop_hook_active == true? → exit 0
         |
3. TMUX env unset? → exit 0
         |
4. SESSION_NAME = tmux display-message -p '#S'
         |
5. AGENT_DATA = jq registry lookup by SESSION_NAME
   no match? → exit 0
         |
6. extract hook_settings (pane_capture_lines, hook_mode, etc.)
         |
7. PANE_CONTENT = tmux capture-pane (still needed for state/pressure)
         |
7b. TRANSCRIPT_PATH = echo STDIN_JSON | jq '.transcript_path'
    EXTRACTED_RESPONSE = extract_last_assistant_response(TRANSCRIPT_PATH)
         |
8. STATE = detect_state(PANE_CONTENT)
         |
9. CONTEXT_PRESSURE = extract_context_pressure(PANE_CONTENT)
         |
9b. CURRENT_HASH = md5sum(PANE_CONTENT)
    PREV_HASH = load_previous_pane_hash(SESSION_NAME)
    if CURRENT_HASH == PREV_HASH:
      debug_log "dedup: skip"
      exit 0    ←─────────────────────────── EARLY EXIT (no delivery)
    save CURRENT_HASH
         |
9c. PANE_DELTA = extract_pane_diff(SESSION_NAME, PANE_CONTENT)
         |
10. WAKE_MESSAGE = build_wake_message_v2(
       EXTRACTED_RESPONSE, STATE, PANE_DELTA, CONTEXT_PRESSURE)
         |
11. if hook_mode == "bidirectional":
      RESPONSE = openclaw agent --session-id UUID --message MSG --json
      if RESPONSE.decision == "block":
        echo decision:block
    else:
      openclaw agent --session-id UUID --message MSG &
    exit 0
```

### PreToolUse Hook AskUserQuestion Flow

```
Claude calls AskUserQuestion tool
         |
         | PreToolUse event fires (matcher: "AskUserQuestion")
         v
pre-tool-use-hook.sh starts
         |
1. STDIN_JSON = cat
         |
2. TMUX guard → exit 0 if not in tmux
         |
3. SESSION_NAME extraction
         |
4. AGENT_DATA = registry lookup
   no match → exit 0
         |
5. OPENCLAW_SESSION_ID extraction
         |
6. TOOL_INPUT = echo STDIN_JSON | jq '.tool_input'
         |
7. FORMATTED_QUESTIONS = format_ask_user_questions(TOOL_INPUT)
         |
8. WAKE_MESSAGE = build ask_user_question message with
   [ASK USER QUESTION] section
         |
9. openclaw agent --session-id UUID --message MSG &
   (always async: AskUserQuestion blocks UI, must not block hook)
         |
exit 0  ← ALWAYS. Never deny/block AskUserQuestion.
         |
AskUserQuestion executes normally
(user interaction in Claude Code TUI proceeds)
```

---

## Architectural Patterns

### Pattern 1: Source-Based Shared Library

**What:** `lib/hook-utils.sh` provides bash functions that hook entry points source via `. "$SCRIPT_DIR/../lib/hook-utils.sh"`.

**When to use:** When 2+ hook scripts need the same logic. v2.0 transcript extraction, diff, and dedup all belong here.

**Trade-offs:**
- Pro: DRY, single fix point for bugs
- Pro: hook entry points stay thin (SRP)
- Con: lib must be robust (hook depends on it)
- Con: sourcing adds ~1ms overhead (acceptable)

**Do NOT put in lib:** Guards (stop_hook_active, TMUX check), registry lookup, hook_settings extraction, delivery — these stay in each hook script for clarity and because they may diverge per event type.

**Example:**

```bash
# In stop-hook.sh, after existing section 6:
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/hook-utils.sh"

EXTRACTED_RESPONSE=$(extract_last_assistant_response "$TRANSCRIPT_PATH" 2000)
```

### Pattern 2: Fail-Safe Fallback Chain

**What:** Every new v2.0 extraction attempts clean extraction, falls back to v1 behavior on failure. Never causes hook to error out.

**Implementation:**

```bash
# Transcript extraction with fallback
EXTRACTED_RESPONSE=$(extract_last_assistant_response "$TRANSCRIPT_PATH" 2000)
if [ -z "$EXTRACTED_RESPONSE" ]; then
  # Fallback: include pane content as before
  RESPONSE_SECTION="[PANE CONTENT]\n${PANE_CONTENT}"
else
  RESPONSE_SECTION="[CLAUDE RESPONSE]\n${EXTRACTED_RESPONSE}"
fi
```

**Why:** Hooks must never break Claude Code operation. Partial degradation (v1 behavior) is better than delivery failure.

### Pattern 3: Per-Session State Files in /tmp

**What:** `/tmp/gsd-pane-prev-SESSION.txt` and `/tmp/gsd-pane-hash-SESSION.txt` store transient per-session state.

**File naming:** `gsd-pane-{type}-{session_name}.txt` where session_name is the tmux session name (e.g., `gsd-pane-hash-warden-main.txt`).

**Why /tmp:** Ephemeral by design. Lost on reboot (acceptable: recovery flow resets state). No persistent storage needed. No cleanup scripts needed.

**Collision risk:** tmux session names are unique on a host. File names derive from session names. No collision possible between sessions.

**Write pattern:** Always `> file 2>/dev/null || true`. Never fail the hook on write error.

### Pattern 4: Matcher-Scoped PreToolUse

**What:** `pre-tool-use-hook.sh` is registered with `matcher: "AskUserQuestion"` so it only fires for that specific tool.

**Why:** Without a matcher, PreToolUse fires for EVERY tool call (Bash, Read, Write, Edit, Glob, Grep, etc.). With matcher, zero overhead for the vast majority of tool calls.

**Trade-off:** If other tools need PreToolUse interception in future, they need separate registrations. This is correct — each tool with different forwarding logic gets its own handler.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Sourcing lib in All 5 Hook Scripts

**What people might do:** Add `source lib/hook-utils.sh` to all 5 existing hook scripts to prepare for future use.

**Why it's wrong:** notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh, and pre-compact-hook.sh don't use transcript extraction or diff. Sourcing adds overhead and coupling without benefit.

**Do this instead:** Only stop-hook.sh and pre-tool-use-hook.sh source lib/hook-utils.sh in v2.0. Other scripts get lib sourcing only if/when they adopt v2 features.

### Anti-Pattern 2: Blocking PreToolUse on AskUserQuestion

**What people might do:** Return `permissionDecision: "deny"` from pre-tool-use-hook.sh to intercept the AskUserQuestion entirely.

**Why it's wrong:** Denying AskUserQuestion prevents the TUI from showing the question to the user. The OpenClaw agent receives the question but has no mechanism to inject an answer back into Claude Code's tool response. The session hangs or auto-selects.

**Do this instead:** Always exit 0 (allow). The hook is notification-only. The OpenClaw agent observes the question, the TUI interaction proceeds normally, and the agent can influence Claude's behavior through other means if needed.

### Anti-Pattern 3: Storing Previous Pane in Memory (Variable)

**What people might do:** Store PANE_CONTENT in a bash variable or subshell variable between hook invocations.

**Why it's wrong:** Each hook invocation is a separate process. Variables don't persist between invocations.

**Do this instead:** Use `/tmp/gsd-pane-prev-SESSION.txt` file per session. File system is the correct IPC mechanism between separate hook process invocations.

### Anti-Pattern 4: Using diff -u (Unified Format) for Pane Delta

**What people might do:** `diff -u prev curr` produces unified diff format (--- /++ headers, @@ lines, +/- prefixes).

**Why it's wrong:** Unified diff includes context lines, headers, and +/- markers that create noise in the wake message. The OpenClaw agent needs clean new content, not a programmer diff.

**Do this instead:** Use `diff --new-line-format='%L' --old-line-format='' --unchanged-line-format=''`. This produces only the truly new lines in their original order, with no diff markup.

### Anti-Pattern 5: Deduplication Before State Detection

**What people might do:** Run hash check first (before pane capture), exit early to save time.

**Why it's wrong:** State detection and context pressure extraction run on `PANE_CONTENT`. If you exit before capturing the pane, you skip the state detection that determines `STATE`. Even if deduplication exits, the state/context info was needed to log or update internal state.

**Do this instead:** Capture pane first (section 7), detect state (section 8), extract pressure (section 9), THEN run deduplication check. The pane capture + state detection is cheap (~5ms). The delivery to OpenClaw is the expensive part that dedup prevents.

---

## Build Order and Dependencies

v2.0 has a clear dependency chain. Each step must complete before the next begins.

```
Step 1: Create lib/hook-utils.sh (NEW)
  - No dependencies
  - Provides: extract_last_assistant_response, extract_pane_diff,
              is_pane_duplicate, format_ask_user_questions
  - Test: source it in bash, call each function with test data

Step 2: Create pre-tool-use-hook.sh (NEW)
  - Depends on: lib/hook-utils.sh (format_ask_user_questions)
  - Provides: AskUserQuestion forwarding
  - Test: echo mock stdin | bash pre-tool-use-hook.sh

Step 3: Modify stop-hook.sh (MODIFIED)
  - Depends on: lib/hook-utils.sh (extract_last_assistant_response,
                extract_pane_diff, is_pane_duplicate)
  - Changes: sections 7b, 9b, 9c, 10
  - Test: run in managed tmux session, verify v2 wake message format

Step 4: Modify register-hooks.sh (MODIFIED)
  - Depends on: pre-tool-use-hook.sh exists and is executable
  - Changes: HOOK_SCRIPTS array, HOOKS_CONFIG JSON, merge jq, verification
  - Test: bash register-hooks.sh, verify ~/.claude/settings.json

Step 5: Update recovery-registry (OPTIONAL)
  - Depends on: nothing (additive fields)
  - Changes: add v2 hook_settings fields if needed
  - May defer to later phase
```

**Parallelizable:** Steps 1+2 can be done in parallel (both create new files with no mutual dependency). Steps 3+4 depend on Step 1 completing. Step 5 is independent.

**Migration safety:** Steps 1-2 create new files, no existing behavior changes. Step 3 modifies stop-hook.sh but keeps all guards intact. Worst case: lib fails to source → stop-hook.sh catches the error with `|| true` → falls back to v1 delivery. Step 4 adds a new hook event registration — existing hooks in settings.json are not removed.

---

## Edge Cases

### transcript_path Points to Non-Existent File

**When:** First hook fire of a new session before JSONL file is created.

**Behavior:** `[ ! -f "$transcript_path" ]` check in `extract_last_assistant_response()` returns empty string. Wake message falls back to `[PANE CONTENT]` section (v1 behavior).

**Safety:** Fallback chain handles gracefully.

### First Hook Fire (No Previous Pane State)

**When:** First Stop hook fire after session start or after /tmp cleared.

**Behavior for diff:** `/tmp/gsd-pane-prev-SESSION.txt` does not exist. `extract_pane_diff()` skips diff, saves current pane as new previous, returns `tail -10 PANE_CONTENT` (minimum context guarantee). Wake message has 10 lines.

**Behavior for dedup:** `/tmp/gsd-pane-hash-SESSION.txt` does not exist. `is_pane_duplicate()` returns "false" (no previous to compare to), saves current hash. Full delivery proceeds.

**Safety:** First fire always delivers full signal, subsequent fires use diff.

### Session Name Contains Spaces or Special Characters

**When:** Tmux session name set to something like `warden main` or `forge-dev/test`.

**Behavior:** `/tmp/gsd-pane-hash-warden main.txt` — space in filename is technically valid but risky. Session names with `/` would create subdirectories.

**Mitigation:** Current sessions use names like `warden-main`, `forge-main` — no spaces or slashes. If future sessions use unusual names, sanitize: `SAFE_NAME=$(echo "$SESSION_NAME" | tr ' /' '__')`.

**Recommendation:** Document in PITFALLS.md. Not a code change for now.

### AskUserQuestion with Empty options Array

**When:** Claude calls AskUserQuestion with a question that has no predefined options (open-ended text input).

**Behavior:** `format_ask_user_questions()` jq expression iterates `.options // []`. Empty array produces no option lines. Message shows question + header only.

**Safety:** Graceful degradation. OpenClaw agent receives question text and knows it's open-ended.

### Stop Hook Fires During AskUserQuestion Interaction

**When:** Claude Code fires Stop hook while waiting for AskUserQuestion response.

**Behavior:** `stop_hook_active` may be true in this context (Claude is mid-interaction). Guard at line 27-30 exits 0 immediately. No interference with the AskUserQuestion flow.

**Separate from:** `pre-tool-use-hook.sh` which fires BEFORE AskUserQuestion executes. Stop hook fires AFTER Claude's response turn.

---

## Sources

**HIGH confidence (direct verification):**
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — complete PreToolUse stdin JSON schema, AskUserQuestion tool_input fields, hook event lifecycle, matcher patterns
- Live transcript file analysis (`~/.claude/projects/*/`) — confirmed JSONL structure: `type`, `message.role`, `message.content[].type`, `message.content[].text`
- Live AskUserQuestion transcript entry — confirmed `tool_input.questions[].{question, header, options, multiSelect}` field paths
- `stop-hook.sh` source (196 lines) — exact line numbers for integration points
- `register-hooks.sh` source (240 lines) — hook registration pattern for new PreToolUse addition
- GNU diff man page — `--new-line-format` / `--old-line-format` / `--unchanged-line-format` flags
- md5sum, sha256sum confirmed available on host

**MEDIUM confidence:**
- [GitHub Issue #13439](https://github.com/anthropics/claude-code/issues/13439) — PreToolUse + AskUserQuestion bug fixed in 2.0.76, current version 2.1.45 is safe
- [GitHub Issue #12605](https://github.com/anthropics/claude-code/issues/12605) — AskUserQuestion hook forwarding design patterns, confirmed `tool_input.questions` field path

---
*Architecture research for: gsd-code-skill v2.0 Smart Hook Delivery*
*Researched: 2026-02-17*
*Confidence: HIGH — all source files read, live transcript verified, official docs fetched, integration points mapped to exact line numbers*
