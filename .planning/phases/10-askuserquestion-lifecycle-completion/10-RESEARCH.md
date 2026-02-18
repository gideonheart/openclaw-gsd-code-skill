# Phase 10: AskUserQuestion Lifecycle Completion - Research

**Researched:** 2026-02-18
**Domain:** Bash hook script authoring — PostToolUse hook creation, PreToolUse tool_use_id extraction, hook registration, empirical stdin schema validation
**Confidence:** HIGH for implementation patterns (derived from shipped Phase 9 code); MEDIUM for PostToolUse stdin field names (documented in official Claude Code hooks reference but empirical validation required for AskUserQuestion-specific tool_response structure)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ASK-05 | PostToolUse hook (`post-tool-use-hook.sh`) emits JSONL record showing which answer OpenClaw agent selected and how TUI was controlled to achieve that decision | New script following established hook script pattern; `deliver_async_with_logging()` for delivery + JSONL; `answer_selected` field via extra_fields_json 13th param; PostToolUse stdin includes `tool_response` with answer; hook is notification-only (no blocking, always exits 0) |
| ASK-06 | PreToolUse and PostToolUse records share `tool_use_id` field enabling question-to-answer lifecycle linking | PreToolUse stdin already carries `tool_use_id` field (confirmed in Claude Code hooks reference); extract it in pre-tool-use-hook.sh and add to JSONL via extra_fields_json; PostToolUse stdin also carries `tool_use_id` (same invocation identifier); both hooks extract it from `.tool_use_id` in their stdin JSON |

</phase_requirements>

---

## Summary

Phase 10 closes the AskUserQuestion lifecycle audit trail that Phase 9 began. Phase 9 shipped the PreToolUse JSONL record with `questions_forwarded` but does not yet include `tool_use_id` and has no PostToolUse counterpart. Phase 10 delivers two things: (1) adding `tool_use_id` to the PreToolUse JSONL record (modifying `pre-tool-use-hook.sh` and its extra_fields_json), and (2) creating a new `post-tool-use-hook.sh` that fires after AskUserQuestion completes and emits an `answer_selected` JSONL record including the chosen option and the menu-driver command used to achieve it.

The PostToolUse hook pattern is identical to the PreToolUse hook pattern in all structural respects: source lib/hook-utils.sh at top, consume stdin, TMUX guard, session name extraction, registry lookup, JSONL_FILE assignment, extract fields from stdin JSON, deliver_async_with_logging(). The only new concern is empirical validation of the `tool_response` field structure in PostToolUse stdin for AskUserQuestion, which the official hooks reference documents as `tool_response: { filePath, success }` for Write — the AskUserQuestion equivalent must be verified in a live session before the field names are committed.

The hook registration work (register-hooks.sh + settings.json) follows the exact pattern used for the existing PreToolUse hook — add a `PostToolUse` section with an `AskUserQuestion` matcher alongside the existing `PreToolUse` section.

**Primary recommendation:** Build in two steps. Step 1: add `tool_use_id` to pre-tool-use-hook.sh's extra_fields_json and update the PostToolUse hook's log script to capture raw stdin. Step 2: after empirical validation of PostToolUse stdin fields for AskUserQuestion, add the typed `answer_selected` extra fields.

---

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| lib/hook-utils.sh | Phase 9 — 6 functions | `deliver_async_with_logging()`, `write_hook_event_record()`, `lookup_agent_in_registry()`, `format_ask_user_questions()` | All Phase 9 hooks use this; no new library needed |
| jq | 1.7 (on host) | Extract `tool_use_id` and `tool_response` from stdin JSON; build extra_fields_json objects | Already present in all hook scripts; confirmed version working |
| bash | 5.2.21 (on host) | Script execution, sourcing, subshell backgrounding | Existing stack; no change |
| flock | util-linux (installed) | Atomic JSONL append inside write_hook_event_record() | Already inside the shared library; no new dependency |

### No New Dependencies

Phase 10 introduces zero new tools or libraries. All required components are present and confirmed working from Phase 9.

---

## Architecture Patterns

### Pattern 1: PostToolUse Hook Structure (New Script)

The new `post-tool-use-hook.sh` follows the same skeleton as all other hook scripts in this codebase. The differences from `pre-tool-use-hook.sh` are:

1. It sources from `PostToolUse` event (no structural change — hook script doesn't know event type from its structure; it reads from stdin `hook_event_name`)
2. It extracts `tool_response` from stdin instead of `tool_input` for its primary data
3. It also extracts `tool_use_id` from stdin (shared field between PreToolUse and PostToolUse)
4. The JSONL extra_fields_json contains `answer_selected` and `tool_use_id` instead of `questions_forwarded`
5. No bidirectional branch — PostToolUse hook is always async and notification-only

Skeleton:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve skill-local log directory
SKILL_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$SKILL_LOG_DIR"

GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" >> "$GSD_HOOK_LOG" 2>/dev/null || true
}

debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"

# Source shared library BEFORE any guard exits
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"
if [ -f "$LIB_PATH" ]; then
  source "$LIB_PATH"
  debug_log "sourced lib/hook-utils.sh"
else
  debug_log "FATAL: hook-utils.sh not found at $LIB_PATH"
  exit 0
fi

# 1. CONSUME STDIN IMMEDIATELY (prevent pipe blocking)
STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)
debug_log "stdin: ${#STDIN_JSON} bytes"

# 2. GUARD: $TMUX environment check
if [ -z "${TMUX:-}" ]; then
  debug_log "EXIT: TMUX env var is unset"
  exit 0
fi

# 3. EXTRACT tmux session name
SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
if [ -z "$SESSION_NAME" ]; then
  debug_log "EXIT: could not extract tmux session name"
  exit 0
fi
debug_log "tmux_session=$SESSION_NAME"
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
debug_log "=== log redirected to per-session file ==="

# 4. REGISTRY LOOKUP
REGISTRY_PATH="${SCRIPT_DIR}/../config/recovery-registry.json"
if [ ! -f "$REGISTRY_PATH" ]; then
  debug_log "EXIT: registry not found"
  exit 0
fi
AGENT_DATA=$(lookup_agent_in_registry "$REGISTRY_PATH" "$SESSION_NAME")
if [ -z "$AGENT_DATA" ] || [ "$AGENT_DATA" = "null" ]; then
  debug_log "EXIT: no agent matched session=$SESSION_NAME"
  exit 0
fi
AGENT_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.agent_id' 2>/dev/null || echo "")
OPENCLAW_SESSION_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.openclaw_session_id' 2>/dev/null || echo "")
if [ -z "$AGENT_ID" ] || [ -z "$OPENCLAW_SESSION_ID" ]; then
  debug_log "EXIT: agent_id or openclaw_session_id is empty"
  exit 0
fi

# 5. EXTRACT tool_use_id AND tool_response FROM STDIN
TOOL_USE_ID=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_use_id // ""' 2>/dev/null || echo "")
TOOL_RESPONSE=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_response // ""' 2>/dev/null || echo "")
debug_log "tool_use_id=$TOOL_USE_ID tool_response_length=${#TOOL_RESPONSE}"

# 6. EXTRACT answer_selected FROM tool_response
# CRITICAL: field names below are TENTATIVE until empirical validation confirms them
# The raw stdin must be logged first; validate field names from real session before finalizing
ANSWER_SELECTED=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_response // "" | if type == "object" then (.content // "") elif type == "string" then . else "" end' 2>/dev/null || echo "")
debug_log "answer_selected_length=${#ANSWER_SELECTED}"

# 7. BUILD WAKE MESSAGE (notification to OpenClaw that answer was selected)
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}
timestamp: ${TIMESTAMP}

[TRIGGER]
type: ask_user_question_answered

[ANSWER SELECTED]
tool_use_id: ${TOOL_USE_ID}
answer: ${ANSWER_SELECTED}

[STATE HINT]
state: answer_submitted"

# 8. ASYNC DELIVERY (ALWAYS background, ALWAYS exit 0)
TRIGGER="ask_user_question_answered"
STATE="answer_submitted"
CONTENT_SOURCE="tool_response"
EXTRA_FIELDS_JSON=$(jq -cn \
  --arg tool_use_id "$TOOL_USE_ID" \
  --arg answer_selected "$ANSWER_SELECTED" \
  '{"tool_use_id": $tool_use_id, "answer_selected": $answer_selected}')
deliver_async_with_logging \
  "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" "$JSONL_FILE" "$HOOK_ENTRY_MS" \
  "$HOOK_SCRIPT_NAME" "$SESSION_NAME" "$AGENT_ID" \
  "$TRIGGER" "$STATE" "$CONTENT_SOURCE" \
  "$EXTRA_FIELDS_JSON"
debug_log "DELIVERED (async PostToolUse AskUserQuestion answer with JSONL logging)"
exit 0
```

### Pattern 2: Adding tool_use_id to PreToolUse JSONL Record (Modify Existing Script)

The existing `pre-tool-use-hook.sh` already extracts from stdin but does not extract `tool_use_id`. The official Claude Code hooks reference confirms `tool_use_id` is present in PreToolUse stdin. Add extraction alongside the existing `TOOL_INPUT` extraction and merge it into `EXTRA_FIELDS_JSON`:

```bash
# EXISTING:
TOOL_INPUT=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_input // ""' 2>/dev/null || echo "")

# ADD after TOOL_INPUT extraction:
TOOL_USE_ID=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_use_id // ""' 2>/dev/null || echo "")
debug_log "tool_use_id=$TOOL_USE_ID"

# CHANGE the EXTRA_FIELDS_JSON construction to include tool_use_id:
# BEFORE:
EXTRA_FIELDS_JSON=$(jq -cn --arg questions_forwarded "$FORMATTED_QUESTIONS" '{"questions_forwarded": $questions_forwarded}')

# AFTER:
EXTRA_FIELDS_JSON=$(jq -cn \
  --arg questions_forwarded "$FORMATTED_QUESTIONS" \
  --arg tool_use_id "$TOOL_USE_ID" \
  '{"questions_forwarded": $questions_forwarded, "tool_use_id": $tool_use_id}')
```

This adds `tool_use_id` to the PreToolUse JSONL record without any changes to write_hook_event_record() or deliver_async_with_logging() — it's purely extra_fields_json content.

### Pattern 3: Hook Registration — PostToolUse in settings.json

The existing `register-hooks.sh` builds a `HOOKS_CONFIG` JSON object and merges it via `jq` into `~/.claude/settings.json`. Add a `PostToolUse` section alongside the existing `PreToolUse` section:

```json
"PostToolUse": [
  {
    "matcher": "AskUserQuestion",
    "hooks": [
      {
        "type": "command",
        "command": "${SKILL_ROOT}/scripts/post-tool-use-hook.sh",
        "timeout": 10
      }
    ]
  }
]
```

The jq merge in register-hooks.sh must be extended to also write `.hooks.PostToolUse = $new.PostToolUse`.

Verification output (add alongside existing verification lines):
```bash
POST_TOOL_USE=$(jq -r '.hooks.PostToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[0].command // "NOT REGISTERED"' "$SETTINGS_FILE")
log_message "PostToolUse (AskUserQuestion): $POST_TOOL_USE"
```

### Pattern 4: Empirical Validation of PostToolUse stdin Schema

**The critical unknown:** The official Claude Code hooks reference documents PostToolUse stdin as:

```json
{
  "session_id": "abc123",
  "transcript_path": "...",
  "cwd": "...",
  "permission_mode": "default",
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_input": { "file_path": "...", "content": "..." },
  "tool_response": { "filePath": "...", "success": true },
  "tool_use_id": "toolu_01ABC123..."
}
```

For the `Write` tool, `tool_response` is `{ filePath, success }`. For `AskUserQuestion`, the `tool_response` structure is not separately documented. Prior research (FEATURES.md) estimated it as `{ "type": "tool_result", "content": "JWT" }` at MEDIUM confidence.

**Empirical validation approach:**
1. Add a raw stdin dump to the new `post-tool-use-hook.sh` before any field extraction:
   ```bash
   debug_log "raw_stdin: $(printf '%s' "$STDIN_JSON" | jq -c '.' 2>/dev/null || echo "$STDIN_JSON")"
   ```
2. Trigger an AskUserQuestion call in a live managed session
3. Read the per-session `.log` file to see the actual `tool_response` structure
4. Finalize the `ANSWER_SELECTED` extraction jq expression based on confirmed field names
5. Commit the schema as confirmed

**What we know with HIGH confidence from official docs:**
- `tool_use_id` is present in PostToolUse stdin: `"tool_use_id": "toolu_01ABC123..."` — explicitly documented
- `tool_name` will be `"AskUserQuestion"` — matches the matcher
- `tool_input` will contain the same questions JSON as PreToolUse

**What is MEDIUM confidence (inferred, needs validation):**
- `tool_response` structure for AskUserQuestion: the top-level key `tool_response` is confirmed present; the nested structure (whether it's `{ "content": "selected answer text" }` or a different shape) requires empirical confirmation

### Pattern 5: JSONL Record Structure for PostToolUse

The PostToolUse JSONL record will use the same base schema as all other records (13 fields from write_hook_event_record(), called via deliver_async_with_logging()), plus the extra_fields_json merge:

```json
{
  "timestamp": "2026-02-18T12:05:00Z",
  "hook_script": "post-tool-use-hook.sh",
  "session_name": "warden-main",
  "agent_id": "warden",
  "openclaw_session_id": "abc-123",
  "trigger": "ask_user_question_answered",
  "state": "answer_submitted",
  "content_source": "tool_response",
  "wake_message": "[SESSION IDENTITY]\nagent_id: warden\n...",
  "response": "",
  "outcome": "no_response",
  "duration_ms": 45,
  "tool_use_id": "toolu_01XYZ...",
  "answer_selected": "Option 2: Use JWT tokens"
}
```

And the PreToolUse record (after Phase 10 modification):
```json
{
  "timestamp": "2026-02-18T12:04:55Z",
  "hook_script": "pre-tool-use-hook.sh",
  "session_name": "warden-main",
  "agent_id": "warden",
  "openclaw_session_id": "abc-123",
  "trigger": "ask_user_question",
  "state": "awaiting_user_input",
  "content_source": "questions",
  "wake_message": "...",
  "response": "{\"status\":\"ok\"}",
  "outcome": "delivered",
  "duration_ms": 312,
  "questions_forwarded": "Question: Which auth...\nOptions:\n  1. JWT...",
  "tool_use_id": "toolu_01XYZ..."
}
```

Lifecycle linkage query:
```bash
# Find PreToolUse and PostToolUse records for same tool invocation:
jq --arg id "toolu_01XYZ..." 'select(.tool_use_id == $id)' logs/warden-main.jsonl
```

### Pattern 6: PostToolUse Hook Async-Only — No Bidirectional Mode

PostToolUse fires AFTER the tool has already completed. Per the official docs: "PostToolUse — No — Shows stderr to Claude (tool already ran)". The tool cannot be blocked. The hook is purely notification/logging. Therefore:

- No `HOOK_MODE` check needed
- No `hook_settings` extraction needed
- Always use `deliver_async_with_logging()` — no bidirectional branch
- Always exit 0

This is simpler than stop-hook.sh and pre-compact-hook.sh. It is structurally identical to session-end-hook.sh in complexity level.

### Anti-Patterns to Avoid

- **Blocking on PostToolUse:** The tool has already run. Do not attempt to use exit code 2 or `{"decision": "block"}` to prevent anything — the action already happened. The hook is notification-only.
- **Skipping empirical validation:** Do not commit to field names for `tool_response.content` based solely on inference. The raw stdin dump must be read from a real AskUserQuestion session before the final extraction jq expression is committed.
- **Stdout output from post-tool-use-hook.sh:** Like pre-tool-use-hook.sh, the PostToolUse hook should not echo JSON to stdout unless intentionally providing feedback to Claude. For this notification-only use case, always exit 0 with no stdout output.
- **Forgetting to update register-hooks.sh HOOK_SCRIPTS array:** The array validates script existence before registration. Add `"post-tool-use-hook.sh"` to the array or it will fail with "script not found" before writing settings.json.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSONL record construction | printf-based JSON assembly | `write_hook_event_record()` via `deliver_async_with_logging()` | Phase 9 shipped, tested, handles all escaping edge cases — 54 test assertions passing |
| Async openclaw with JSONL logging | Custom background subshell | `deliver_async_with_logging()` from lib/hook-utils.sh | Already handles response capture, outcome determination, `</dev/null` redirect |
| answer_selected JSON building | Custom string concatenation | `jq -cn --arg answer_selected ... '{"answer_selected": $answer_selected, "tool_use_id": $tool_use_id}'` | Handles embedded quotes/newlines in answer text safely |
| settings.json PostToolUse registration | Direct file manipulation | Extend existing `HOOKS_CONFIG` heredoc in register-hooks.sh | Atomic backup-validate-replace pattern already present; add PostToolUse to the same JSON blob |

---

## Common Pitfalls

### Pitfall 1: tool_response Field Structure Unknown Until Empirical Validation

**What goes wrong:** Committing to `.tool_response.content` as the answer field name before seeing real PostToolUse stdin for AskUserQuestion. If the actual field is `.tool_response.text` or simply `.tool_response` as a string, the extraction silently returns empty string and the JSONL record has `"answer_selected": ""` for every invocation.

**Why it happens:** The official docs document PostToolUse stdin structure for the `Write` tool but not for AskUserQuestion specifically. The shape of `tool_response` is tool-specific.

**How to avoid:** Two-step implementation — Step 1: log `raw_stdin` via debug_log before field extraction; Step 2: trigger a real AskUserQuestion, read the session log, confirm field names; Step 3: finalize extraction. Both steps can be in a single plan if they are sequential tasks.

**Warning signs:** `answer_selected` field is empty in JSONL records for every PostToolUse invocation.

### Pitfall 2: register-hooks.sh HOOK_SCRIPTS Array Not Updated

**What goes wrong:** `register-hooks.sh` validates each hook script exists before modifying settings.json. If `post-tool-use-hook.sh` is added to `HOOKS_CONFIG` but NOT added to the `HOOK_SCRIPTS` array, the script runs validation on the array (which passes since the new script is not listed), then writes a `PostToolUse` entry pointing to a path that the validation never checked. If the file does not exist, sessions that fire PostToolUse will get a command-not-found error.

**How to avoid:** Update the `HOOK_SCRIPTS` array in register-hooks.sh to include `"post-tool-use-hook.sh"` at the same time as creating the script and adding it to `HOOKS_CONFIG`.

### Pitfall 3: PreToolUse jq for extra_fields_json Must Include Both Fields

**What goes wrong:** If the EXTRA_FIELDS_JSON construction in pre-tool-use-hook.sh only adds `tool_use_id` and drops `questions_forwarded`, ASK-04 (Phase 9 requirement, already completed) is regressed. The modification must extend, not replace, the existing `questions_forwarded` field.

**How to avoid:** The extra_fields_json construction uses `jq -cn --arg questions_forwarded ... --arg tool_use_id ... '{"questions_forwarded": ..., "tool_use_id": ...}'` — both fields in one jq object literal.

### Pitfall 4: PostToolUse Timeout Too Long

**What goes wrong:** Setting a long timeout on the PostToolUse hook when it does not need it. The pre-tool-use-hook.sh uses timeout=10 in settings.json because AskUserQuestion TUI rendering is time-sensitive. PostToolUse fires after the answer is submitted, so there is no TUI blocking concern, but an excessively long timeout still holds the hook process slot open.

**How to avoid:** Use timeout=10 (same as PreToolUse) since the hook script backgrounds openclaw immediately and exits. The 10 second window covers the hook script execution itself, not the async openclaw call.

### Pitfall 5: No TMUX Check Makes Debug Log Difficult to Find

**What goes wrong:** If a developer runs `post-tool-use-hook.sh` manually outside tmux (e.g., to test), the TMUX guard exits cleanly but the log goes to the shared `hooks.log` not a per-session file. This makes the raw_stdin validation output hard to locate.

**How to avoid:** When performing empirical validation, run from inside the managed tmux session (the normal operating context). The per-session log file will contain the `raw_stdin` debug_log line. Alternatively, temporarily override `GSD_HOOK_LOG` to stdout before sourcing lib: `GSD_HOOK_LOG=/dev/stderr`.

---

## Code Examples

### Extracting tool_use_id in PreToolUse (Verified Pattern)

```bash
# Source: official Claude Code hooks reference
# PreToolUse stdin includes tool_use_id alongside tool_name and tool_input
TOOL_USE_ID=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_use_id // ""' 2>/dev/null || echo "")
debug_log "tool_use_id=$TOOL_USE_ID"
```

This pattern is identical to how AGENT_ID is extracted from jq output. The `// ""` handles the case where the field is absent (silent empty string, never crashes the hook).

### Extending extra_fields_json With Multiple Fields

```bash
# Source: shipped pre-tool-use-hook.sh (Phase 9) + extension for tool_use_id
EXTRA_FIELDS_JSON=$(jq -cn \
  --arg questions_forwarded "$FORMATTED_QUESTIONS" \
  --arg tool_use_id "$TOOL_USE_ID" \
  '{"questions_forwarded": $questions_forwarded, "tool_use_id": $tool_use_id}')
```

The jq `--arg` chain safely handles all content: newlines in FORMATTED_QUESTIONS, special characters in TOOL_USE_ID. Object merge happens at write_hook_event_record() via `+ $extra_fields`.

### PostToolUse tool_response Extraction (Validated Field Names Pending)

The two most likely shapes, based on official docs and AskUserQuestion behavior:

**Shape A — object with content field (MEDIUM confidence):**
```bash
# If tool_response is { "type": "tool_result", "content": "selected text" }
ANSWER_SELECTED=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_response.content // ""' 2>/dev/null || echo "")
```

**Shape B — string directly (MEDIUM confidence):**
```bash
# If tool_response is a plain string
ANSWER_SELECTED=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_response // ""' 2>/dev/null || echo "")
```

**Defensive extraction (use during empirical validation phase):**
```bash
# Handles both shapes without knowing which is correct
ANSWER_SELECTED=$(printf '%s' "$STDIN_JSON" | \
  jq -r '.tool_response | if type == "object" then (.content // .text // (. | tostring)) elif type == "string" then . else "" end' \
  2>/dev/null || echo "")
```

Once empirical validation confirms the shape, replace with the specific path.

### register-hooks.sh PostToolUse Registration

```bash
# In the HOOKS_CONFIG heredoc, add alongside PreToolUse:
"PostToolUse": [
  {
    "matcher": "AskUserQuestion",
    "hooks": [
      {
        "type": "command",
        "command": "${SKILL_ROOT}/scripts/post-tool-use-hook.sh",
        "timeout": 10
      }
    ]
  }
]

# In the jq merge, add:
.hooks.PostToolUse = $new.PostToolUse |

# In the HOOK_SCRIPTS array, add:
"post-tool-use-hook.sh"

# In verification output, add:
POST_TOOL_USE=$(jq -r '.hooks.PostToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[0].command // "NOT REGISTERED"' "$SETTINGS_FILE")
log_message "PostToolUse (AskUserQuestion): $POST_TOOL_USE"
```

---

## Open Questions

1. **Exact shape of tool_response for AskUserQuestion in PostToolUse stdin**
   - What we know: `tool_use_id` is confirmed present at top level; `tool_response` is a top-level field in PostToolUse stdin; for Write, it is `{ filePath, success }`
   - What's unclear: Whether AskUserQuestion returns `{ "content": "answer text" }`, `{ "type": "tool_result", "content": "..." }`, or a plain string
   - Recommendation: Log raw stdin first, read from a live session log before finalizing extraction jq expression. Use the defensive multi-shape extractor during the logging step.

2. **Does the PostToolUse hook need to notify OpenClaw at all, or is logging-only sufficient?**
   - What we know: PreToolUse hook sends a wake message to OpenClaw so Gideon can select an answer. PostToolUse fires AFTER the answer is already submitted — Gideon's action has already happened.
   - What's unclear: Whether notifying OpenClaw of the answer completion is useful, or whether the JSONL record alone satisfies ASK-05
   - Recommendation: Include the notification (wake message to OpenClaw) for symmetry and audit completeness. The requirement says "emits JSONL record showing which answer OpenClaw agent selected and how TUI was controlled" — the wake message provides the human-readable summary and the JSONL provides the structured record. However, if the wake delivery adds noise to Gideon's inbox, the wake message can be omitted and only the JSONL written directly via write_hook_event_record(). This is a planning decision.

3. **Does the menu-driver command used appear in tool_response at all?**
   - What we know: The requirement (ASK-05) says the record should include "TUI control action taken (menu-driver command)." The menu-driver.sh command is run by Gideon (OpenClaw agent) externally — it is not inside Claude Code. Claude Code only knows the final selected answer, not which tmux key sequence achieved it.
   - What's unclear: Whether the menu-driver command can be inferred from the answer text, or whether it requires Gideon to log it separately
   - Recommendation: The PostToolUse hook can include `answer_selected` (the text/index) and `tool_use_id`. The menu-driver command itself is not in PostToolUse stdin — it is in Gideon's conversation history. The JSONL record satisfies ASK-05 by recording what was chosen; the "how TUI was controlled" aspect is an inference (choose N for option N). Document this constraint clearly in the plan.

---

## Sources

### Primary (HIGH confidence — official documentation verified 2026-02-18)

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — PostToolUse input schema confirmed: `tool_name`, `tool_input`, `tool_response`, `tool_use_id` all present; PreToolUse input schema confirmed: same fields including `tool_use_id`; matcher patterns for PostToolUse confirmed identical to PreToolUse (tool name regex)

### Primary (HIGH confidence — live codebase)

- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/lib/hook-utils.sh` — `deliver_async_with_logging()` (11 params including optional extra_fields_json), `write_hook_event_record()` (13 params including optional extra_fields_json), confirmed working with 54 test assertions
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/pre-tool-use-hook.sh` — current script read in full; extracts TOOL_INPUT and FORMATTED_QUESTIONS; builds EXTRA_FIELDS_JSON with `questions_forwarded` only; does NOT currently extract `tool_use_id`
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/register-hooks.sh` — read in full; HOOK_SCRIPTS array, HOOKS_CONFIG heredoc, jq merge, verification block — all patterns confirmed
- `.planning/phases/09-hook-script-migration/09-VERIFICATION.md` — Phase 9 PASSED with all 6 criteria; 54 assertions, 0 failures; confirmed extra_fields_json 13th param works
- `.planning/REQUIREMENTS.md` — ASK-05, ASK-06 exact wording confirmed; Phase 10 is the assigned phase

### Secondary (MEDIUM confidence — prior research, unverified PostToolUse field names)

- `.planning/research/FEATURES.md` — PostToolUse stdin structure inferred as `{ "tool_response": { "type": "tool_result", "content": "selected answer" } }`; explicitly flagged as MEDIUM confidence requiring empirical verification
- `.planning/research/SUMMARY.md` — "PostToolUse stdin schema needs empirical verification before schema is committed" — confirms empirical validation requirement

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; all tools confirmed present and working from Phase 9
- Architecture: HIGH — new script pattern derived directly from existing hook scripts; PostToolUse hook is structurally simpler than stop-hook.sh (no bidirectional branch, no pane capture)
- PreToolUse modification (tool_use_id addition): HIGH — `tool_use_id` field confirmed in official docs; extra_fields_json extension pattern confirmed in Phase 9
- PostToolUse stdin tool_response schema: MEDIUM — `tool_use_id` field at top level confirmed; `tool_response` nested structure for AskUserQuestion requires empirical validation
- Hook registration: HIGH — register-hooks.sh pattern read in full; PostToolUse registration follows identical jq merge pattern as PreToolUse

**Research date:** 2026-02-18
**Valid until:** Stable — no external framework dependencies. PostToolUse field name section valid until Claude Code changes its hook stdin schema.
