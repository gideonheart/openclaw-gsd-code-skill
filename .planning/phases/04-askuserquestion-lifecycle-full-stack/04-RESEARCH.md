# Phase 4: AskUserQuestion Lifecycle (Full Stack) - Research

**Researched:** 2026-02-22
**Domain:** Claude Code hooks (PreToolUse/PostToolUse) + AskUserQuestion tool payload + tmux TUI navigation
**Confidence:** MEDIUM-HIGH (payload schema verified via official docs + community bug reports; TUI navigation details LOW confidence — must verify live)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Answer Strategy**
- Context-aware answering — classify question type and use project context, not "always first option"
- OpenClaw agent is the decision-maker, not a rubber stamp — verify Claude Code's recommendation against ROADMAP.md, STATE.md, CONTEXT.md before accepting
- 6 question categories with distinct strategies: Confirmation, Style preference, Scope selection, Architecture decision, Open floor, Delegation
- GSD phase-aware answering — response depth varies by which GSD command is running (/gsd:discuss-phase = full reasoning, /gsd:plan-phase = confirm and proceed, /gsd:execute-phase = confirm and continue)
- Fallback strategy: always "Type something" with reasoning

**TUI Interaction Patterns**
- Claude Code AskUserQuestion TUI layout per question:
  ```
  ❯ 1. Option A          ← options from payload (0-indexed)
    2. Option B
    3. Option C
    4. Type something.   ← ALWAYS present, not in payload options
  ──────────────────────
    5. Chat about this   ← ALWAYS present, below separator
  ```
- Multi-question forms use a tabbed layout
- 4 TUI driver actions: select, type, multi-select, chat
- Default assumptions (build + test live): cursor starts on option 0, Tab auto-advances after answering each question in multi-question forms, "Type something" Enter submits that question only, annotation in multi-select skip for Phase 4 v1

**Escalation Policy**
- OpenClaw agent ALWAYS answers. No exceptions.
- Permission questions never appear — GSD runs with --dangerously-skip-permissions
- Three-tier answer strategy: select right option / type nuanced answer / chat to redirect

**Verification System**
- File-based programmatic verification — no OpenClaw agent wake on match (95% case, zero tokens)
- PreToolUse handler saves question metadata to logs/queues/question-{session}.json
- TUI driver reads question file + saves intent to logs/queues/pending-answer-{session}.json (includes tool_use_id)
- PostToolUse handler reads pending answer, compares with tool_response.answers:
  - Match (95%): log "verified" + delete both files + exit 0
  - Mismatch (5%): wake OpenClaw agent with specific details + delete both files + exit 0
  - Missing/stale file: log warning + exit 0

**Handler Architecture**
- Router pattern: one registered handler per event type (PreToolUse, PostToolUse), dispatches by tool_name
- event_pre_tool_use.mjs — shared boilerplate (readHookContext), reads tool_name, routes to ask_user_question/handle_ask_user_question.mjs
- event_post_tool_use.mjs — shared boilerplate (readHookContext), reads tool_name, routes to ask_user_question/handle_post_ask_user_question.mjs
- Same guard pattern as all handlers: resolve session → resolve agent → if managed, proceed
- No re-entrancy guard needed — each AskUserQuestion is independent and sequential
- Handlers are fire-and-forget — wake OpenClaw agent via gateway, exit 0 immediately
- Handlers are thin plumbing (~5-10 lines of logic each). Domain knowledge lives in lib/ask-user-question.mjs

**Driver Architecture**
- bin/tui-driver-ask.mjs — separate from bin/tui-driver.mjs (SRP)
- Shares lib/tui-common.mjs for sendKeysToTmux / sendSpecialKeyToTmux (DRY at tmux layer)
- TUI driver reads question metadata from file — logs/queues/question-{session}.json
- OpenClaw agent passes only its decision — minimal CLI payload
- TUI driver saves pending answer BEFORE typing

**Shared Library Module**
- lib/ask-user-question.mjs — owns ALL AskUserQuestion domain knowledge
- Functions: formatQuestionsForAgent, saveQuestionMetadata, readQuestionMetadata, deleteQuestionMetadata, savePendingAnswer, readPendingAnswer, deletePendingAnswer, compareAnswerWithIntent

**File Structure**
```
bin/
  tui-driver.mjs                                ← existing Phase 3
  tui-driver-ask.mjs                            ← NEW

events/
  pre_tool_use/
    event_pre_tool_use.mjs                      ← NEW: router
    ask_user_question/
      handle_ask_user_question.mjs              ← NEW
      prompt_ask_user_question.md               ← NEW
  post_tool_use/
    event_post_tool_use.mjs                     ← NEW: router
    ask_user_question/
      handle_post_ask_user_question.mjs         ← NEW
      prompt_post_ask_mismatch.md               ← NEW

lib/
  ask-user-question.mjs                         ← NEW
  hook-context.mjs                              ← NEW (prerequisite, already implemented)
  gateway.mjs                                   ← MODIFIED: add wakeAgentWithRetry (already done)
  tui-common.mjs                                ← existing (shared)
  index.mjs                                     ← MODIFIED: re-export new modules
```

### Claude's Discretion

- Exact error handling in question/pending-answer file read/write/delete operations
- Comparison logic edge cases (partial text matches, whitespace normalization)
- `action: chat` exact Down count to reach "Chat about this" — test live

### Deferred Ideas (OUT OF SCOPE)

- Annotation text entry in multi-select — skip for Phase 4 v1
- SubagentStart/SubagentStop hooks — future phase
- Notification handlers — future phases
- Error/failure status in queue — keep plumbing dumb for now
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ASK-01 | PreToolUse(AskUserQuestion) handler extracts tool_input.questions array with question text, options, and multiSelect flag | Confirmed: PreToolUse fires for AskUserQuestion with tool_name="AskUserQuestion", tool_input.questions array. Schema documented below. |
| ASK-02 | PreToolUse(AskUserQuestion) prompt template instructs agent to read the question, decide the answer, and call the AskUserQuestion TUI driver with the chosen option | Handled by prompt_ask_user_question.md — format follows existing prompt_stop.md pattern. |
| ASK-03 | PostToolUse(AskUserQuestion) handler extracts tool_response.answers object and the original tool_input.questions | Confirmed: PostToolUse fires after user answers. tool_response.answers is Record<string, string>. Pending-answer file provides the tool_use_id linkage needed. |
| ASK-04 | PostToolUse(AskUserQuestion) prompt template instructs agent to verify submitted answer matches what agent decided, and report any mismatch | Handled by prompt_post_ask_mismatch.md — only fires on mismatch (5% case). |
| TUI-03 | AskUserQuestion TUI driver knows how to navigate options (arrow keys), select (space for multiSelect, enter for single-select), and submit | Verified via tui-common.mjs patterns. Exact key counts need live testing (LOW confidence). |
| TUI-04 | TUI drivers replace monolithic menu-driver.sh for hook-driven interactions | bin/tui-driver-ask.mjs is the AskUserQuestion-specific driver, reusing lib/tui-common.mjs. |
</phase_requirements>

---

## Summary

Phase 4 implements a fully autonomous AskUserQuestion answering loop. When Claude Code presents multiple-choice questions to the user, the OpenClaw agent intercepts via PreToolUse, reads the questions, decides answers using project context, drives the TUI via tmux send-keys to select and submit, then PostToolUse verifies the answer was recorded correctly. The whole loop is closed programmatically with zero human intervention.

The domain breaks cleanly into three parts: (1) hook-level payload extraction — well-understood from existing Phase 3 patterns and the Claude Code hooks docs; (2) TUI navigation mechanics — requires live testing to confirm exact key counts; (3) verification file I/O — straightforward atomic file operations following the queue-processor.mjs pattern already in the codebase.

**Critical discovery:** PreToolUse DOES fire for AskUserQuestion, with `tool_name: "AskUserQuestion"`. This was confirmed broken (issue #12031, #13439) and fixed in Claude Code v2.0.76. The fix is live as of January 2026. The hook system works as expected for this tool — the router pattern is the correct approach.

**Primary recommendation:** Follow the locked CONTEXT.md decisions exactly. The router pattern, file-based verification, and tui-driver-ask.mjs separation are all well-reasoned. The only unknowns are TUI navigation key counts — build a test harness and verify live before writing production navigation logic.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Node.js built-ins | 22+ | fs, path, util, child_process | No new dependencies needed — follows Phase 3 pattern |
| execFileSync | node:child_process | tmux send-keys for TUI navigation | Already used in tui-common.mjs, no shell injection risk |
| writeFileSync + renameSync | node:fs | Atomic file writes for question/pending-answer files | Same pattern as queue-processor.mjs |
| readFileSync | node:fs | Read question metadata and pending-answer files | Synchronous for simplicity, files are small |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| lib/tui-common.mjs | internal | sendKeysToTmux / sendSpecialKeyToTmux | All tmux key sends in tui-driver-ask.mjs |
| lib/hook-context.mjs | internal | readHookContext() boilerplate | Both event router handlers |
| lib/gateway.mjs | internal | wakeAgentWithRetry() | PostToolUse mismatch wake only |
| lib/logger.mjs | internal | appendJsonlEntry() | All logging throughout |
| lib/paths.mjs | internal | SKILL_ROOT constant | Absolute path resolution |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Atomic tmp+rename for question files | flock -x | flock requires bash; tmp+rename is POSIX-atomic and matches existing queue-processor.mjs pattern |
| Separate tui-driver-ask.mjs | Extending tui-driver.mjs | SRP: existing driver is for slash commands, new one is for TUI menu navigation — different problem |
| File-based verification (question + pending-answer) | In-memory state | Hook processes are separate OS processes — must use filesystem for cross-process state |

**Installation:** No new npm packages. Pure Node.js built-ins.

---

## Architecture Patterns

### Recommended Project Structure

```
events/
├── pre_tool_use/
│   ├── event_pre_tool_use.mjs        # Router: readHookContext → dispatch by tool_name
│   └── ask_user_question/
│       ├── handle_ask_user_question.mjs      # Domain handler (thin)
│       └── prompt_ask_user_question.md       # Agent prompt template
├── post_tool_use/
│   ├── event_post_tool_use.mjs       # Router: readHookContext → dispatch by tool_name
│   └── ask_user_question/
│       ├── handle_post_ask_user_question.mjs # Domain handler (thin)
│       └── prompt_post_ask_mismatch.md       # Mismatch prompt template

bin/
└── tui-driver-ask.mjs                # AskUserQuestion TUI navigator

lib/
└── ask-user-question.mjs             # All domain knowledge

logs/queues/
├── question-{session}.json           # PreToolUse saves here
└── pending-answer-{session}.json     # TUI driver saves here before typing
```

### Pattern 1: Router Handler (event_pre_tool_use.mjs)

**What:** A thin router that reads tool_name from the hook payload and delegates to the per-tool handler. Follows the same guard structure as all existing handlers.

**When to use:** Any time a single hook event type handles multiple tool names. For Phase 4, only AskUserQuestion is handled — but the pattern allows future tools to be added without touching the router.

**Example:**
```javascript
// Source: follows event_stop.mjs pattern from existing codebase
async function main() {
  const hookContext = readHookContext('event_pre_tool_use');
  if (!hookContext) process.exit(0);
  const { hookPayload, sessionName, resolvedAgent } = hookContext;

  const toolName = hookPayload.tool_name;

  if (toolName === 'AskUserQuestion') {
    await handleAskUserQuestion({ hookPayload, sessionName, resolvedAgent });
    process.exit(0);
  }

  // Unknown tool — no handler registered, exit cleanly
  appendJsonlEntry({ level: 'debug', source: 'event_pre_tool_use', message: `No handler for tool_name: ${toolName}`, session: sessionName }, sessionName);
  process.exit(0);
}
```

### Pattern 2: Question Metadata File (question-{session}.json)

**What:** PreToolUse handler saves question metadata before waking agent. TUI driver reads it to know what to navigate. PostToolUse reads tool_use_id from pending-answer to match with tool_response.

**When to use:** Cross-process communication between hook handler (PreToolUse process), agent-called TUI driver process, and verification handler (PostToolUse process).

**Example schema:**
```json
{
  "tool_use_id": "toolu_01ABC123...",
  "saved_at": "2026-02-22T10:00:00.000Z",
  "session": "warden-main",
  "questions": [
    {
      "question": "Which approach should we use?",
      "header": "Implementation",
      "multiSelect": false,
      "options": [
        { "label": "Option A", "description": "Use existing pattern" },
        { "label": "Option B", "description": "Create new pattern" }
      ]
    }
  ]
}
```

### Pattern 3: Pending Answer File (pending-answer-{session}.json)

**What:** TUI driver saves intent BEFORE typing keys. PostToolUse reads this to compare with what Claude Code recorded in tool_response.answers.

**Example schema:**
```json
{
  "tool_use_id": "toolu_01ABC123...",
  "saved_at": "2026-02-22T10:00:01.000Z",
  "session": "warden-main",
  "answers": {
    "0": "Option A"
  },
  "action": "select"
}
```

### Pattern 4: tui-driver-ask.mjs CLI Interface

**What:** CLI tool called by OpenClaw agent with the decision payload. Reads question metadata from file, navigates TUI, saves pending answer.

**When to use:** OpenClaw agent calls this after deciding the answer.

**Example CLI:**
```bash
node bin/tui-driver-ask.mjs \
  --session warden-main \
  --action select \
  --answers '{"0": "Option A"}'
```

**Example for multi-select:**
```bash
node bin/tui-driver-ask.mjs \
  --session warden-main \
  --action multi-select \
  --answers '{"0": ["Option A", "Option C"]}'
```

**Example for typing custom text:**
```bash
node bin/tui-driver-ask.mjs \
  --session warden-main \
  --action type \
  --text "Use the existing pattern but add error handling"
```

### Pattern 5: Comparison Logic (compareAnswerWithIntent)

**What:** PostToolUse reads pending-answer, reads tool_response.answers, compares them.

**Exact tool_response.answers format (HIGH confidence):** Claude Code records answers as a plain string in the format used by the selected option label. The comparison must normalize whitespace and handle case-insensitivity.

**Example:**
```javascript
// Source: derived from community bug reports showing response format
function compareAnswerWithIntent(pendingAnswers, actualAnswers) {
  // pendingAnswers: { "0": "Option A" }  (from pending-answer file)
  // actualAnswers: { "0": "Option A" }   (from tool_response.answers)
  // Both are Record<string, string>
  // Normalize: trim whitespace, lowercase for comparison
  for (const [questionIndex, intendedAnswer] of Object.entries(pendingAnswers)) {
    const actualAnswer = actualAnswers[questionIndex];
    if (!actualAnswer) return { matched: false, reason: `No answer for question ${questionIndex}` };
    if (actualAnswer.trim().toLowerCase() !== intendedAnswer.trim().toLowerCase()) {
      return { matched: false, reason: `Q${questionIndex}: expected "${intendedAnswer}", got "${actualAnswer}"` };
    }
  }
  return { matched: true };
}
```

### Anti-Patterns to Avoid

- **Caching question files across sessions:** Each AskUserQuestion call is independent. Always write fresh, always delete after verification.
- **Adding delay between tmux key sends:** execFileSync blocks until tmux returns. No artificial delays needed (same as tui-common.mjs).
- **Using shell string interpolation for send-keys:** Always use argument arrays. `execFileSync('tmux', ['send-keys', '-t', sessionName, text, ''])` — never string concatenation.
- **Waking agent on every PostToolUse:** Only wake on mismatch. 95% of cases are match — zero tokens burned.
- **Storing state in module-level variables:** Hook processes are ephemeral OS processes. All state must be in files.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic file writes | Custom locking logic | writeFileSync to .tmp + renameSync | POSIX rename is atomic. Already proven in queue-processor.mjs. |
| Session resolution | Parsing hook payload JSON | execFileSync('tmux', ['display-message', '-p', '#S']) | hook JSON has session_id UUID, not tmux session name. Confirmed in BUG 1 fix. |
| Gateway delivery | Custom HTTP client | wakeAgentWithRetry() from lib/gateway.mjs | Already built with retry, logging, prompt-file pattern. |
| tmux key sends | Shell string building | sendKeysToTmux() from lib/tui-common.mjs | No injection risk. Trailing empty string handles tmux key-name disambiguation. |
| Hook context boilerplate | Duplicating 15-line pattern | readHookContext() from lib/hook-context.mjs | Phase 3.1 prerequisite — already implemented. |

**Key insight:** Every infrastructure problem in Phase 4 is already solved. The only new code is domain logic (question parsing, comparison, TUI navigation) and file I/O (question/pending-answer files).

---

## Common Pitfalls

### Pitfall 1: PreToolUse Was Broken for AskUserQuestion (Fixed in v2.0.76)

**What goes wrong:** PreToolUse hooks fired but stripped the answer data from AskUserQuestion responses, making verification impossible and breaking the question flow.

**Why it happened:** Claude Code internal hook result processing did not preserve tool response data for UI tools when PreToolUse hooks were active.

**How to avoid:** Verify Claude Code version is >= 2.0.76 before testing. Confirmed fixed as of January 2026. Current gsd-code-skill targets this version range.

**Warning signs:** PostToolUse tool_response.answers is empty string or null when it should contain user selection.

### Pitfall 2: AskUserQuestion May Fire PermissionRequest Instead of PreToolUse

**What goes wrong:** In some configurations, AskUserQuestion triggers a PermissionRequest hook event instead of PreToolUse. A PermissionRequest deny hook automatically dismisses the question without showing it.

**Why it happens:** Routing ambiguity in Claude Code's hook dispatch for UI tools (reported in issue #15400, v2.0.76).

**How to avoid:** The project runs with `--dangerously-skip-permissions`, so PermissionRequest hooks never fire. This pitfall does not apply to the GSD setup. (Confirmed in CONTEXT.md: "Permission questions never appear — GSD runs with `--dangerously-skip-permissions`.")

**Warning signs:** AskUserQuestion dismissed immediately with empty answers.

### Pitfall 3: TUI Cursor Position Assumptions

**What goes wrong:** Assuming cursor starts on option 0 and requires N Down-arrow presses to reach option N is correct in most cases, but may break if the TUI renders differently in tmux vs. direct terminal.

**Why it happens:** The AskUserQuestion TUI is a React Ink component — its rendering in a tmux pane may differ from interactive testing. The "Type something" and "Chat about this" extra options add to the count unpredictably if their positions shift.

**How to avoid:** Build a test harness that actually invokes AskUserQuestion and observes the result. Don't ship production navigation logic without live verification. Lock down exact key counts through testing before Phase 4 ships.

**Warning signs:** Selected option does not match intended option. tool_response.answers shows wrong selection.

### Pitfall 4: tool_use_id Linkage Between PreToolUse and PostToolUse

**What goes wrong:** PostToolUse needs to match the verification file to the right AskUserQuestion call. Without tool_use_id linkage, multiple concurrent tool calls (not an AskUserQuestion concern, but defensive coding) would mix up files.

**Why it happens:** AskUserQuestion is blocking so this is not a live risk, but the file naming by session alone is sufficient for the sequential case.

**How to avoid:** Use session name for file naming (as decided in CONTEXT.md). The blocking nature of AskUserQuestion guarantees one-at-a-time calls per session. Include tool_use_id in both files for debugging traceability even if not strictly needed for matching.

**Warning signs:** N/A for sequential case. If tool_use_id in pending-answer does not match PostToolUse payload's tool_use_id, log a warning but proceed.

### Pitfall 5: "Type something" vs "Chat about this" TUI Position

**What goes wrong:** The "Type something" and "Chat about this" options are always present but not in tool_input.questions.options. Their position in the TUI menu is implementation-defined.

**Why it happens:** These are Claude Code-injected UI elements, not schema fields. Their position relative to the payload options (before or after separator, above or below "Chat about this") must be verified live.

**How to avoid:** Per CONTEXT.md decisions — build and test live. The separator position and key counts for reaching "Chat about this" are LOW confidence until verified.

**Warning signs:** Typing something when intending to select an option, or vice versa.

### Pitfall 6: Multi-Question Form Tab Advancement

**What goes wrong:** In multi-question forms, Tab auto-advances to the next question after answering. If the TUI driver sends Enter for a single-select answer, it may advance incorrectly or skip the tab sequence.

**Why it happens:** CONTEXT.md states Tab auto-advances after answering — but the exact trigger (does Enter on single-select also advance? Does Space on multiSelect advance?) needs live verification.

**How to avoid:** Test multi-question forms specifically. Verify Tab behavior and Enter behavior per question type before shipping.

**Warning signs:** Only first question answered, rest skipped. Or all questions answered with wrong selections due to unexpected advancement.

---

## Code Examples

Verified patterns from official sources and existing codebase:

### AskUserQuestion PreToolUse Payload

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../transcript.jsonl",
  "cwd": "/Users/...",
  "permission_mode": "bypassPermissions",
  "hook_event_name": "PreToolUse",
  "tool_name": "AskUserQuestion",
  "tool_use_id": "toolu_01ABC123...",
  "tool_input": {
    "questions": [
      {
        "question": "Which approach should we use?",
        "header": "Implementation",
        "multiSelect": false,
        "options": [
          { "label": "Option A", "description": "Use existing pattern" },
          { "label": "Option B", "description": "Create new pattern" }
        ]
      }
    ]
  }
}
```

Source: Claude Code hooks reference + issue #12605 proposed payload (verified against schema gist)
Confidence: HIGH for field names (confirmed via official schema); MEDIUM for exact response wire format

### AskUserQuestion PostToolUse Payload

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../transcript.jsonl",
  "cwd": "/Users/...",
  "permission_mode": "bypassPermissions",
  "hook_event_name": "PostToolUse",
  "tool_name": "AskUserQuestion",
  "tool_use_id": "toolu_01ABC123...",
  "tool_input": {
    "questions": [...]
  },
  "tool_response": {
    "answers": {
      "0": "Option A"
    }
  }
}
```

Source: Community bug reports showing "User has answered your questions: Option A" text + schema gist answers field
Confidence: MEDIUM — exact answers key format (string index "0" vs question text as key) needs live verification

### Handler Registration in settings.json

The router handlers must be added to `~/.claude/settings.json` using the nested format:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "node /home/forge/.openclaw/workspace/skills/gsd-code-skill/events/pre_tool_use/event_pre_tool_use.mjs",
            "timeout": 30
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "node /home/forge/.openclaw/workspace/skills/gsd-code-skill/events/post_tool_use/event_post_tool_use.mjs",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

Source: Confirmed from existing settings.json + BUG 6 fix notes (nested format, seconds-based timeouts)
Confidence: HIGH — same format as Stop/SessionStart hooks already verified in production

### Saving Question Metadata (Atomic Write Pattern)

```javascript
// Source: follows queue-processor.mjs writeQueueFileAtomically pattern
import { writeFileSync, renameSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { SKILL_ROOT } from './paths.mjs';

const QUEUES_DIRECTORY = resolve(SKILL_ROOT, 'logs', 'queues');

export function saveQuestionMetadata(sessionName, toolUseId, questions) {
  const questionFilePath = resolveQuestionFilePath(sessionName);
  mkdirSync(dirname(questionFilePath), { recursive: true });
  const temporaryFilePath = questionFilePath + '.tmp';
  const data = {
    tool_use_id: toolUseId,
    saved_at: new Date().toISOString(),
    session: sessionName,
    questions,
  };
  writeFileSync(temporaryFilePath, JSON.stringify(data, null, 2), 'utf8');
  renameSync(temporaryFilePath, questionFilePath);
}

export function resolveQuestionFilePath(sessionName) {
  return resolve(QUEUES_DIRECTORY, `question-${sessionName}.json`);
}
```

### TUI Navigation Pattern (Single-Select)

```javascript
// Source: follows tui-common.mjs sendSpecialKeyToTmux pattern
// DOWN key count to reach option N (0-indexed): N presses from cursor-on-option-0
// LOW CONFIDENCE: verify live — these counts are assumptions

export function selectOptionByIndex(sessionName, optionIndex) {
  // Move cursor down by optionIndex steps from position 0
  for (let downPressCount = 0; downPressCount < optionIndex; downPressCount++) {
    sendSpecialKeyToTmux(sessionName, 'Down');
  }
  // Enter submits single-select
  sendSpecialKeyToTmux(sessionName, 'Enter');
}

export function typeCustomText(sessionName, text) {
  // Navigate to "Type something" option — its index depends on options count
  // "Type something" is always the last option before the separator
  // LOW CONFIDENCE: exact position needs live verification
  // ...navigate to Type something...
  sendSpecialKeyToTmux(sessionName, 'Enter'); // Select "Type something"
  sendKeysToTmux(sessionName, text);
  sendSpecialKeyToTmux(sessionName, 'Enter'); // Submit text
}
```

### Gateway Message Format for PreToolUse Wake

The PreToolUse handler wakes the agent with questions formatted for decision-making. `formatQuestionsForAgent` produces:

```markdown
## Event Metadata
- Event: PreToolUse
- Session: warden-main
- Timestamp: 2026-02-22T10:00:00.000Z

## Questions from Claude Code

**Question 1: Implementation**
Which approach should we use?

Options:
1. Option A — Use existing pattern
2. Option B — Create new pattern
3. Type something. (custom text)

MultiSelect: false

## Instructions
[contents of prompt_ask_user_question.md]
```

Source: CONTEXT.md Gateway Message Format decision, follows existing wakeAgentViaGateway pattern
Confidence: HIGH — pattern is locked in decisions

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| AskUserQuestion broken with PreToolUse hooks | Fixed in v2.0.76 (January 2026) | Jan 2026 | Phase 4 is now feasible |
| No hook support for AskUserQuestion | PreToolUse + PostToolUse fire normally | Fixed v2.0.76 | Full lifecycle hook support |
| PermissionRequest fires for AskUserQuestion | With --dangerously-skip-permissions, PermissionRequest never fires | bypassPermissions mode | Our setup is unaffected |

**Deprecated/outdated:**
- Pre-v2.0.76 workarounds for AskUserQuestion: not needed. The hook system works.
- PermissionRequest-based auto-answering (seen in community issue #15872): not applicable, not needed. PreToolUse + PostToolUse is the correct approach.

---

## Open Questions

1. **answers key format: string index "0" vs question text as key**
   - What we know: answers is Record<string, string>. Community shows `{"0": "Option A"}` but some sources suggest question text may be the key.
   - What's unclear: Is it always 0-indexed string ("0", "1", "2") or question-text-keyed?
   - Recommendation: Add logging to dump raw tool_response in PostToolUse during first test run. Design compareAnswerWithIntent to handle both formats.

2. **TUI cursor starting position**
   - What we know: CONTEXT.md states "cursor starts on option 0" as an assumption to build and test live.
   - What's unclear: Does the cursor wrap from last option back to first? Does it behave differently in tmux pane vs. direct terminal?
   - Recommendation: Write tui-driver-ask.mjs to send exactly N Down-presses for option N. Test with actual AskUserQuestion calls in the warden session. Log the result from PostToolUse to verify.

3. **Multi-question Tab advancement exact trigger**
   - What we know: CONTEXT.md states Tab auto-advances after answering each question. "Type something" Enter submits that question only.
   - What's unclear: Does Enter on a single-select option auto-advance or does Tab also need to be sent? What about Space on multiSelect?
   - Recommendation: Test multi-question form specifically. Try Enter-only first; if it doesn't advance, try Enter+Tab.

4. **"Chat about this" Down count**
   - What we know: It is below a separator, below the "Type something" option.
   - What's unclear: Exact number of Down presses from option 0 to reach "Chat about this" depends on option count + separator.
   - Recommendation: CONTEXT.md marks this as "test live". For Phase 4 v1, implement select and type only. Defer chat action until verified.

---

## Sources

### Primary (HIGH confidence)

- Claude Code Hooks Reference (code.claude.com/docs/en/hooks) — complete PreToolUse/PostToolUse payload schema, hook registration format, exit codes, decision control
- Existing codebase (lib/tui-common.mjs, lib/queue-processor.mjs, lib/hook-context.mjs, events/stop/event_stop.mjs) — confirmed patterns for tmux send-keys, atomic file I/O, handler structure
- ~/.claude/settings.json — confirmed hook registration format (nested, seconds-based timeouts)

### Secondary (MEDIUM confidence)

- AskUserQuestion schema gist (bgauryy/0cdb9aa337d01ae5bd0c803943aa36bd) — tool_input.questions schema with all required fields
- GitHub issue #12031 (PreToolUse strips AskUserQuestion results) — confirmed PreToolUse fires for AskUserQuestion; fix in v2.0.76
- GitHub issue #12605 (AskUserQuestion Hook Support, CLOSED) — proposed PreAskUserQuestion payload format with questions array structure
- GitHub issue #10400 (bypass permissions + AskUserQuestion) — confirmed fix in v2.0.67/v2.0.76; "User has answered your questions:" response text format

### Tertiary (LOW confidence)

- TUI navigation key counts (Down-arrow positions, Tab advancement) — derived from CONTEXT.md assumptions + general tmux TUI patterns; must verify live
- answers key format (string "0" vs question text) — inferred from community examples; wire format not officially documented
- "Chat about this" position (Down count from option 0) — not documented anywhere; must observe live

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies, all patterns from existing codebase
- Architecture: HIGH — locked decisions from CONTEXT.md, supported by PreToolUse/PostToolUse official docs
- Payload schema: MEDIUM — questions schema verified; answers response format needs live confirmation
- TUI navigation: LOW — key counts assumed, must verify live before shipping
- Pitfalls: HIGH — most pitfalls identified from real GitHub issues + existing codebase patterns

**Research date:** 2026-02-22
**Valid until:** 2026-03-22 (stable domain — Claude Code hook API is stable)
