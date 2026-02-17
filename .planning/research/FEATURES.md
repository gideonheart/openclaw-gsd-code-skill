# Feature Research

**Domain:** Hook-driven autonomous agent control for Claude Code sessions — v2.0 Smart Hook Delivery
**Researched:** 2026-02-17
**Confidence:** HIGH (transcript/PreToolUse from official docs; diff/dedup from standard bash patterns)

---

## Context: What v1.0 Built (Already Shipped)

This is a subsequent milestone research file. v1.0 shipped the complete hook system:
- Stop hook fires on response complete, captures 120-line pane dump, sends structured wake message
- Notification hooks for idle_prompt and permission_prompt events
- SessionEnd and PreCompact hooks
- Three-tier hook_settings (per-agent > global > hardcoded)
- Hybrid hook mode (async background / bidirectional with decision injection)
- menu-driver.sh with type action, snapshot, choose, enter, esc, clear_then, submit
- Per-agent system prompts via recovery registry

**v2.0 problem statement:** The wake messages are noisy and redundant. 120 lines of raw tmux pane content contains ANSI escape codes, rendering artifacts, statusline noise, and large blocks of content identical to the previous hook fire. Claude's actual response text is buried in this rendering noise. AskUserQuestion menus fire via pattern-matching imprecision — the exact question text and option labels are not forwarded structurally.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that must exist for v2.0 to be considered functional. Missing any of these means the milestone fails its stated goal.

| Feature | Why Expected | Complexity | Dependencies on v1.0 |
|---------|--------------|------------|----------------------|
| Transcript-based response extraction | Hook stdin already provides `transcript_path` JSONL — reading it is the obvious, correct way to get Claude's exact response text (no ANSI codes, no tmux artifacts) | LOW | stop-hook.sh (has transcript_path in stdin), existing guard and registry lookup logic |
| AskUserQuestion forwarding via PreToolUse | PreToolUse hook fires before `AskUserQuestion` executes, stdin contains structured `tool_input` with `questions` array, `options`, `header`, `multiSelect` — this is the only reliable way to get exact question text and option labels without tmux scraping | MEDIUM | Existing notification-permission-hook.sh as structural reference; settings.json hook registration pattern |
| Deduplication: skip wake when pane content is identical | Same pane content across consecutive hook fires means agent receives no new information — sending it wastes tokens and creates noise | LOW | stop-hook.sh (add state file per session in /tmp) |
| Minimum context guarantee (always include at least 10 lines) | Orchestrator agent must have enough baseline context to act, even when diff is empty or small | LOW | stop-hook.sh pane capture logic |
| Structured wake message v2 format | v1.0 format embeds raw 120-line pane in `[PANE CONTENT]` — v2.0 must replace this with extracted response text + optional compact delta | MEDIUM | Existing wake message builder in all 5 hook scripts |

### Differentiators (Competitive Advantage)

Features that make the system meaningfully better than the current v1.0 behavior. Not required for correctness, but high value for token efficiency and orchestrator signal quality.

| Feature | Value Proposition | Complexity | Dependencies on v1.0 |
|---------|-------------------|------------|----------------------|
| Diff-based pane delivery (send only changed lines) | When pane content changes between hook fires, send a compact line-level delta (new lines only, or `diff --unified` output) instead of full 120-line dump — dramatically reduces per-wake message size during long active sessions | MEDIUM | stop-hook.sh pane capture; /tmp state file per session for previous-capture storage |
| AskUserQuestion structured forwarding (questions + options as JSON-like section) | Orchestrator receives `[ASK USER QUESTION]` section with structured data: question text, option labels, option descriptions, header — no tmux pattern-matching required, exact phrasing preserved | MEDIUM | pre-tool-use-hook.sh (NEW); existing hook registration pattern |
| Last assistant message extraction from transcript | From transcript JSONL, find the most recent `message.role == "assistant"` entry and extract `message.content[].text` — gives clean response text without tmux rendering noise, ANSI codes, statusline garbage | LOW | transcript_path available in all hook stdin payloads since v1.0 |
| Per-session previous-pane state storage in /tmp | Store `pane_capture_hash` and `pane_capture_raw` per session in `/tmp/gsd-hook-state-${SESSION_NAME}.json` — enables both deduplication (hash comparison) and diff delivery (raw comparison) in a single read | LOW | stop-hook.sh state file pattern |
| Compact pane delta section `[PANE DELTA]` | When pane changed but transcript extraction succeeded, include only the new/changed lines (not full dump) as a smaller `[PANE DELTA]` section — orchestrator gets both clean response + what changed on screen | MEDIUM | Diff-based delivery feature |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Parse tmux pane content for AskUserQuestion question text | Seems simpler than adding a new hook — just grep "?" patterns in pane | Brittle: question text can span multiple lines, wrap, contain special chars; ANSI codes corrupt grep output; menu borders interfere; breaks on any UI change | Use PreToolUse hook — fires before tool executes, stdin contains exact `tool_input.questions` from Claude's tool call, zero ambiguity |
| Send full transcript content in wake message | Complete conversation history seems useful for agent context | Transcripts grow to hundreds of KB; single JSONL line for last assistant message is sufficient; orchestrator has its own conversation memory | Extract only last assistant `message.content[].text` block — precise and bounded in size |
| Global PreToolUse hook (no matcher) that fires for all tools | Seems easy to configure — one hook handles everything | Global PreToolUse fires before every single Bash, Read, Write, Edit, Glob, Grep, WebFetch, WebSearch, Task call — extreme overhead for every tool use; known bug (fixed in 2.0.76) caused AskUserQuestion to return empty responses when PreToolUse global hook was active | Use matcher `"AskUserQuestion"` — fires only when Claude calls that specific tool, zero overhead for all other tool uses |
| diff output with full context lines (unified diff format) | Familiar format from git, easy to read | Unified diff with surrounding context lines still sends most of the unchanged content; for the orchestrator, added lines are sufficient | Send only the added/new lines using `comm` or `grep` against stored previous capture, or `diff --new-line-format` with no context |
| Re-implement previous-pane storage in registry JSON | Registry already exists — seems natural to store state there | Registry is read-only in hooks (atomic writes via flock + mv only in spawn/recover); hooks run concurrently and frequently; adding write operations to every hook fire risks corruption | Use per-session files in /tmp — ephemeral, no locking required, natural cleanup on reboot |
| Blocking PreToolUse hook that intercepts AskUserQuestion and waits for orchestrator decision | Bidirectional mode already works for Stop hook — seems consistent | AskUserQuestion is specifically designed for interactive user input; blocking it while waiting for OpenClaw adds latency to the user-facing TUI; the hook should forward the question, not intercept the answer | Forward question data in async mode — orchestrator receives the question before it appears in TUI, can prepare context, but user interaction proceeds normally via Claude Code's native UI |

---

## Feature Dependencies

```
Transcript-based response extraction
    └──requires──> transcript_path in hook stdin (v1.0, available in all hooks)
    └──requires──> last assistant message JSONL parsing (tail + jq)
    └──enhances──> Structured wake message v2 format ([RESPONSE] section replaces [PANE CONTENT])

Deduplication (skip identical pane content)
    └──requires──> Per-session previous-pane state storage in /tmp
    └──provides──> hash(pane_content) == hash(previous_pane) → skip wake or send lightweight signal

Diff-based pane delivery
    └──requires──> Per-session previous-pane state storage in /tmp (same state file as deduplication)
    └──enhances──> Structured wake message v2 format ([PANE DELTA] instead of [PANE CONTENT])
    └──conflicts──> Full 120-line pane dump (replaced, not combined)

AskUserQuestion forwarding via PreToolUse
    └──requires──> pre-tool-use-hook.sh (NEW script)
    └──requires──> PreToolUse hook registered in ~/.claude/settings.json with matcher "AskUserQuestion"
    └──uses──> tool_input.questions[] from PreToolUse stdin (NOT tmux pane scraping)
    └──provides──> [ASK USER QUESTION] section in wake message with structured question + options

Structured wake message v2 format
    └──requires──> Transcript-based response extraction (to replace [PANE CONTENT] with [RESPONSE])
    └──requires──> Diff-based pane delivery (to add [PANE DELTA] section)
    └──requires──> Minimum context guarantee (10-line baseline when diff is small)
    └──modifies──> stop-hook.sh wake message builder (existing, v1.0)
    └──modifies──> notification-idle-hook.sh wake message builder (existing, v1.0)

Minimum context guarantee
    └──requires──> Diff-based pane delivery (guard: if delta < 10 lines, include 10 lines from bottom)
    └──modifies──> Pane delta calculation logic in stop-hook.sh
```

---

## MVP Definition

### Launch With (v2.0 — all six stated milestone features)

These are the six explicitly named v2.0 features. All must ship together since the wake message v2 format depends on the others.

- [ ] **Transcript-based extraction** — Read `transcript_path` JSONL from hook stdin, extract last `message.role == "assistant"` entry, pull `message.content[].text`, add as `[RESPONSE]` section in wake message. Replaces tmux scraping as the source of Claude's last response text.
- [ ] **PreToolUse hook for AskUserQuestion** — New `pre-tool-use-hook.sh` script. Registered in settings.json with matcher `"AskUserQuestion"`. Receives `tool_input.questions[]` (each with `question`, `header`, `options[].label`, `options[].description`, `multiSelect`). Sends structured wake with `[ASK USER QUESTION]` section to orchestrator. Async mode only (no bidirectional — forwarding only, not intercepting).
- [ ] **Diff-based pane delivery** — Store previous pane capture per session in `/tmp/gsd-hook-state-${SESSION_NAME}`. On each hook fire, compare with current capture. Send only new/changed lines as `[PANE DELTA]` section instead of full `[PANE CONTENT]` dump.
- [ ] **Structured wake message v2** — Compact format: `[SESSION IDENTITY]`, `[TRIGGER]`, `[STATE HINT]`, `[RESPONSE]` (from transcript), `[PANE DELTA]` (changed lines only), `[CONTEXT PRESSURE]`, `[AVAILABLE ACTIONS]`. Removes raw 120-line `[PANE CONTENT]` dump.
- [ ] **Deduplication** — Hash pane content (md5sum or sha1sum). If hash matches previous, skip wake entirely OR send lightweight `[NO CHANGE]` signal. Configurable via hook_settings (`dedup_mode: "skip" | "lightweight"`).
- [ ] **Minimum context guarantee** — When pane delta is fewer than 10 lines (e.g., only a statusline change), pad to always include at least 10 lines from pane bottom so orchestrator has baseline context.

### Add After Validation (v2.x)

Features to add once v2.0 core delivery is working and token reduction is measurable.

- [ ] **Per-hook dedup mode settings** — Add `dedup_mode` to hook_settings with per-hook override (same three-tier fallback as existing hook_settings). Trigger after measuring actual dedup rates.
- [ ] **AskUserQuestion async pre-notification** — When PreToolUse hook fires for AskUserQuestion, orchestrator receives the question 50-200ms before Claude Code renders the TUI menu. Add a brief delay in the hook before exiting to give orchestrator time to prepare context (e.g., look up session state). Only useful if orchestrator response latency is measurable and matters.

### Future Consideration (v3+)

- [ ] **Transcript diff (conversation delta)** — Instead of pane delta, send only the new conversation turns since last wake (diff of transcript JSONL). Requires tracking last-read transcript position per session. Higher complexity, potentially higher value for long sessions.
- [ ] **Selective hook muting** — Allow orchestrator to instruct hook to be silent for N turns ("I'm handling this, don't wake me again until next Stop"). Requires two-way state channel between hook and orchestrator.
- [ ] **PostToolUse hook for AskUserQuestion** — After AskUserQuestion tool executes, forward what answer was selected back to orchestrator as confirmation. Enables orchestrator to build a record of user preferences without polling.

---

## Feature Prioritization Matrix

| Feature | Orchestrator Value | Implementation Cost | Priority |
|---------|-------------------|---------------------|----------|
| Transcript-based response extraction | HIGH — eliminates ANSI noise from response text | LOW — tail JSONL + jq, 5 lines of bash | P1 |
| Deduplication (hash comparison + skip) | HIGH — eliminates duplicate wakes entirely | LOW — md5sum comparison + /tmp state file | P1 |
| Structured wake message v2 format | HIGH — orchestrator reads cleaner signal | MEDIUM — modify wake builder in 2 hook scripts (stop, notification-idle) | P1 |
| Diff-based pane delivery | MEDIUM — reduces delta size during active work | MEDIUM — diff calculation + /tmp state file (shares with dedup) | P2 |
| Minimum context guarantee | LOW — safety net for edge cases | LOW — guard in delta calculation | P2 |
| AskUserQuestion forwarding via PreToolUse | HIGH — exact question/options without pattern matching | MEDIUM — new pre-tool-use-hook.sh + settings.json registration | P1 |

**Priority key:**
- P1: Must have for v2.0 launch (all stated milestone features)
- P2: Should have for completeness, add in same milestone
- P3: Nice to have, defer

---

## Behavior Descriptions (Orchestrator Perspective)

### Before v2.0 (current v1.0 behavior)

Orchestrator receives a wake message like:

```
[SESSION IDENTITY]
agent_id: warden
tmux_session_name: warden-main
timestamp: 2026-02-17T10:00:00Z

[TRIGGER]
type: response_complete

[STATE HINT]
state: menu

[PANE CONTENT]
[full 120 lines of raw tmux pane content including ANSI codes, statusline,
 previous responses, menu borders, rendering artifacts, and identical content
 from the previous hook fire — 3000-8000 characters]

[CONTEXT PRESSURE]
72% [WARNING]

[AVAILABLE ACTIONS]
menu-driver.sh warden-main choose <n>
...
```

Orchestrator must: parse ANSI codes mentally, find Claude's actual response buried in the pane dump, identify what changed since last wake, distinguish menu options from surrounding noise, and handle repeated sends of identical content.

### After v2.0

Orchestrator receives:

```
[SESSION IDENTITY]
agent_id: warden
tmux_session_name: warden-main
timestamp: 2026-02-17T10:00:00Z

[TRIGGER]
type: response_complete

[STATE HINT]
state: menu

[RESPONSE]
I've analyzed the codebase and found 3 issues to address. Which approach would
you like me to take?

[PANE DELTA]
  > 1. Fix all issues in a single commit
  > 2. Fix each issue separately with individual commits
  > 3. Show me the issues first before deciding

[CONTEXT PRESSURE]
72% [WARNING]

[AVAILABLE ACTIONS]
menu-driver.sh warden-main choose <n>
...
```

Orchestrator gets: exact response text (no ANSI codes), only the changed lines (not 120-line dump), clean signal-to-noise ratio. If pane was identical to previous fire, wake is skipped entirely.

### AskUserQuestion wake (new in v2.0)

When Claude calls `AskUserQuestion`, orchestrator receives a separate wake before the TUI menu renders:

```
[SESSION IDENTITY]
agent_id: warden
tmux_session_name: warden-main
timestamp: 2026-02-17T10:00:01Z

[TRIGGER]
type: ask_user_question

[STATE HINT]
state: menu

[ASK USER QUESTION]
questions:
  - header: "Approach"
    question: "Which approach should I use for the authentication fix?"
    multiSelect: false
    options:
      1. OAuth (Recommended) — Use OAuth 2.0 with PKCE for third-party integrations
      2. JWT — Lightweight stateless tokens, good for internal services
      3. Session-based — Traditional server-side sessions, simplest to implement

[AVAILABLE ACTIONS]
menu-driver.sh warden-main choose <n>
menu-driver.sh warden-main type <text>
...
```

No pattern matching, no ANSI parsing. The question text and option labels are taken directly from `tool_input.questions` in the PreToolUse hook stdin.

---

## AskUserQuestion Tool Input Schema (CONFIRMED — official docs)

From [platform.claude.com/docs/en/agent-sdk/user-input](https://platform.claude.com/docs/en/agent-sdk/user-input):

```json
{
  "questions": [
    {
      "question": "Which approach should I use?",
      "header": "Approach",
      "options": [
        { "label": "OAuth (Recommended)", "description": "Use OAuth 2.0 with PKCE" },
        { "label": "JWT", "description": "Lightweight stateless tokens" }
      ],
      "multiSelect": false
    }
  ]
}
```

PreToolUse hook stdin for AskUserQuestion:

```json
{
  "session_id": "abc123",
  "transcript_path": "/home/forge/.claude/projects/.../transcript.jsonl",
  "cwd": "/path/to/project",
  "permission_mode": "bypassPermissions",
  "hook_event_name": "PreToolUse",
  "tool_name": "AskUserQuestion",
  "tool_use_id": "toolu_01ABC...",
  "tool_input": {
    "questions": [
      {
        "question": "Which approach should I use?",
        "header": "Approach",
        "options": [
          { "label": "OAuth (Recommended)", "description": "Use OAuth 2.0 with PKCE" },
          { "label": "JWT", "description": "Lightweight stateless tokens" }
        ],
        "multiSelect": false
      }
    ]
  }
}
```

Constraints (confirmed):
- 1–4 questions per AskUserQuestion call
- 2–4 options per question
- `multiSelect: true` allows multiple selections, joined with `", "` in answer
- `header` field is max 12 characters (short label for TUI display)
- AskUserQuestion is NOT available in subagents spawned via Task tool
- Bug fixed in Claude Code v2.0.76: PreToolUse hook with global matcher caused AskUserQuestion to return empty responses (stdin/stdout conflict) — fixed, safe to use with matcher `"AskUserQuestion"`

---

## Transcript JSONL: Last Assistant Message (CONFIRMED — official docs)

From hook stdin: `transcript_path` points to a JSONL file at `~/.claude/projects/<project-hash>/<session-id>.jsonl`.

Each line is a JSON object. Assistant message structure:

```json
{
  "parentUuid": "...",
  "isSidechain": false,
  "userType": "external",
  "sessionId": "...",
  "type": "assistant",
  "message": {
    "id": "msg_...",
    "type": "message",
    "role": "assistant",
    "model": "claude-sonnet-4-6",
    "content": [
      {
        "type": "text",
        "text": "Claude's actual response text here, clean, no ANSI codes"
      }
    ]
  },
  "uuid": "...",
  "timestamp": "2026-02-17T10:00:00.000Z"
}
```

Extraction pattern (bash + jq):

```bash
TRANSCRIPT_PATH=$(echo "$STDIN_JSON" | jq -r '.transcript_path // ""')
LAST_RESPONSE=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  LAST_RESPONSE=$(tail -50 "$TRANSCRIPT_PATH" | \
    jq -r 'select(.message.role == "assistant") | .message.content[] | select(.type == "text") | .text' 2>/dev/null | \
    tail -1 || echo "")
fi
```

Notes:
- `tail -50` scans last 50 lines (avoids reading entire large transcript)
- `select(.message.role == "assistant")` filters out user messages, tool calls, tool results
- `select(.type == "text")` filters out tool_use blocks inside assistant messages
- Transcript may have multiple assistant messages (multi-turn); `tail -1` gets the most recent text block
- If transcript_path is empty or file missing, fall back to pane content (graceful degradation)

---

## Diff-Based Pane Delivery Implementation Notes

State file location: `/tmp/gsd-hook-state-${SESSION_NAME}`

State file contents (plain text, two lines):
```
<hash>
<previous_pane_content_base64>
```

Or as two separate files:
```
/tmp/gsd-hook-state-${SESSION_NAME}.hash
/tmp/gsd-hook-state-${SESSION_NAME}.prev
```

Two separate files preferred (simpler to read/write independently).

Deduplication check (bash):
```bash
STATE_HASH_FILE="/tmp/gsd-hook-state-${SESSION_NAME}.hash"
CURRENT_HASH=$(echo "$PANE_CONTENT" | md5sum | cut -d' ' -f1)
PREV_HASH=$(cat "$STATE_HASH_FILE" 2>/dev/null || echo "")

if [ "$CURRENT_HASH" = "$PREV_HASH" ]; then
  debug_log "DEDUP: pane content identical to previous, skipping wake"
  exit 0
fi
echo "$CURRENT_HASH" > "$STATE_HASH_FILE"
```

Diff calculation (bash):
```bash
STATE_PREV_FILE="/tmp/gsd-hook-state-${SESSION_NAME}.prev"
PREV_PANE=$(cat "$STATE_PREV_FILE" 2>/dev/null || echo "")
echo "$PANE_CONTENT" > "$STATE_PREV_FILE"

if [ -n "$PREV_PANE" ]; then
  PANE_DELTA=$(diff <(echo "$PREV_PANE") <(echo "$PANE_CONTENT") | grep '^>' | sed 's/^> //' || echo "")
else
  PANE_DELTA=$(echo "$PANE_CONTENT" | tail -10)
fi

# Minimum context guarantee
DELTA_LINES=$(echo "$PANE_DELTA" | wc -l)
if [ "$DELTA_LINES" -lt 10 ]; then
  PANE_DELTA=$(echo "$PANE_CONTENT" | tail -10)
fi
```

State file cleanup: files in /tmp clean up on reboot. No explicit cleanup needed. Old files from dead sessions are harmless (small, ignored on next session start with different content).

---

## Edge Cases

| Scenario | Severity | Behavior |
|----------|----------|----------|
| transcript_path file does not exist yet | LOW | Fall back to pane delta only — no `[RESPONSE]` section, keep `[PANE DELTA]` |
| transcript_path has no assistant messages yet (session just started) | LOW | LAST_RESPONSE empty — omit `[RESPONSE]` section from wake |
| Pane content is empty (session just started) | LOW | PANE_DELTA is empty — apply minimum context guarantee, send last 10 lines |
| State file unreadable (/tmp full or permission error) | LOW | Treat as first fire — send full 10-line minimum, continue without dedup |
| AskUserQuestion called inside subagent (Task tool) | MEDIUM | PreToolUse fires for the subagent session — hook checks registry by tmux session name; if subagent is in different tmux session, no match found, hook exits 0 (non-managed session behavior). AskUserQuestion inside subagents is a known limitation per official docs. |
| PreToolUse global matcher bug (old Claude Code version) | HIGH | Verify Claude Code >= 2.0.76 before registering PreToolUse hook. Current version 2.1.44 is safe. Bug: empty AskUserQuestion responses when global PreToolUse hook active. Fix: use matcher `"AskUserQuestion"` not global matcher. |
| Multiple questions in single AskUserQuestion call (1-4 allowed) | LOW | Forward all questions in `[ASK USER QUESTION]` section, numbered sequentially |
| Wake skipped by dedup, but session state actually changed externally | LOW | Next genuine change triggers new wake with delta from the skipped-state base. Orchestrator may miss one update but will not miss all future updates. |
| Diff produces very large output (complete screen refresh) | LOW | Fall back to last 10 lines when delta is larger than original pane — minimum context guarantee handles this |

---

## Sources

**HIGH confidence (official documentation):**
- [Claude Code Hooks Reference — code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) — PreToolUse input schema, tool_input fields, AskUserQuestion matcher, hookSpecificOutput format
- [Handle approvals and user input — platform.claude.com/docs/en/agent-sdk/user-input](https://platform.claude.com/docs/en/agent-sdk/user-input) — AskUserQuestion tool_input.questions[] structure, `question`, `header`, `options`, `multiSelect` fields, response format with `answers`, 1-4 questions/2-4 options constraints
- [GitHub Issue #13439 — PreToolUse bug with AskUserQuestion](https://github.com/anthropics/claude-code/issues/13439) — Confirmed fixed in v2.0.76; current 2.1.44 is safe; use matcher "AskUserQuestion" not global matcher

**HIGH confidence (transcript format from community implementations):**
- [Analyzing Claude Code Interaction Logs with DuckDB — liambx.com](https://liambx.com/blog/claude-code-log-analysis-with-duckdb) — Real JSONL structure showing `message.role`, `message.content[]`, `type: "text"`, `text` fields
- [Claude Code conversation history — kentgigger.com](https://kentgigger.com/posts/claude-code-conversation-history) — Confirmed JSONL format with `parentUuid`, `sessionId`, `message.role`, `message.content`

**MEDIUM confidence (diff patterns — standard bash utilities):**
- Standard `diff` command: `diff <(echo "$OLD") <(echo "$NEW") | grep '^>' | sed 's/^> //'` — extracts only added lines; widely used for text delta extraction
- `md5sum` for hash comparison: standard Linux utility, available on all Ubuntu 24 systems

**LOCAL (existing implementation):**
- scripts/stop-hook.sh (v1.0) — guard patterns, registry lookup, pane capture, wake message builder
- scripts/notification-idle-hook.sh (v1.0) — duplicate of stop-hook patterns for reference
- PRD.md — v1.0 architecture and Structured Wake Message Format section
- config/recovery-registry.json — hook_settings schema for dedup_mode addition

---

*Feature research for: gsd-code-skill v2.0 Smart Hook Delivery*
*Researched: 2026-02-17*
