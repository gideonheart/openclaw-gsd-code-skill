# Phase 4: AskUserQuestion Lifecycle (Full Stack) - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

The full PreToolUse → PostToolUse verification loop for AskUserQuestion tool calls. When Claude Code asks the user a question (via AskUserQuestion), the OpenClaw agent automatically reads the question, decides the answer based on project context, submits it via TUI driver, and verifies the answer went through correctly. This enables fully autonomous GSD workflow execution without human intervention.

</domain>

<decisions>
## Implementation Decisions

### Answer Strategy

- **Context-aware answering** — agent classifies question type and uses project context to decide, not "always first option"
- **6 question categories** with distinct strategies:

| Category | Signal | Strategy |
|----------|--------|----------|
| Confirmation | 1-2 options, one is "yes/proceed" | Pick the affirmative. GSD doesn't hesitate. |
| Style preference | Equivalent alternatives | Check existing codebase conventions. If uncertain, pick "You decide". |
| Scope selection | Multi-select, asking what to include | Select ALL relevant to current phase. Add annotations if project context exceeds options. |
| Architecture decision | Options have different consequences | Cross-reference ROADMAP.md, STATE.md, CONTEXT.md. Pick what aligns with project direction. |
| Open floor | Has "Something else" / "Type something" | Pick option if it matches. Type specific requirements if not. |
| Delegation | Has "You decide" option | Pick "You decide" ONLY when all options equally valid AND agent has no project-specific reason to prefer one. |

- **Phase-aware answering** — response depth varies by GSD command:

| GSD Phase | Question Pattern | Approach |
|-----------|-----------------|----------|
| `/gsd:discuss-phase` | Heavy (5-10 questions). Architecture, scope, preferences. | **Full reasoning.** Read ROADMAP.md, STATE.md, prior CONTEXT.md. Type nuanced answers. Add annotations. |
| `/gsd:plan-phase` | Light. "Discuss incomplete, proceed?" | **Confirm and proceed.** Agent deliberately moved to plan — unblock quickly. |
| `/gsd:execute-phase` | Rare. Procedural confirmations. | **Confirm and continue.** If real design question appears, answer but log warning — plan phase missed something. |
| `/gsd:verify-work` | Interactive. "Does this work?" | **Report honestly.** Test/check and report pass/fail with specifics. |
| Fallback | Can't classify | **Type something** — explain reasoning with project context. |

- **Agent is decision-maker, not rubber stamp** — verify Claude Code's recommendation against ROADMAP.md and STATE.md before accepting. Claude Code can hallucinate — the OpenClaw agent is the quality gate.
- **Fallback strategy**: always "Type something" with reasoning. Agent always has STATE.md, ROADMAP.md, CONTEXT.md. It can always articulate its thinking.

### TUI Interaction Patterns

- **Claude Code AskUserQuestion UI per question:**
  - Options 0..N (from payload, 0-indexed)
  - "Type something" (always at index = options.length, not in payload)
  - Separator line
  - "Chat about this" (always below separator)
  - Multi-question forms: tabbed layout with Submit tab

- **4 TUI driver actions:**

| Action | Payload | TUI Keystrokes |
|--------|---------|----------------|
| `select` | `{ "action": "select", "optionIndex": N }` | Down ×N → Enter |
| `type` | `{ "action": "type", "text": "..." }` | Down × options.length → Enter → type text → Enter |
| `multi-select` | `{ "action": "multi-select", "selectedIndices": [...] }` | Space (select 0) → Down → Space (select next) → ... → navigate to submit → Enter |
| `chat` | `{ "action": "chat", "text": "..." }` | Down × (options.length + 2?) → Enter → type text → Enter |

- **Default assumptions (build + test live):**
  - Cursor starts on option 0
  - Tab auto-advances after answering each question in multi-question forms
  - "Type something" Enter submits that question only, not the whole form
  - Annotation in multi-select: **skip for Phase 4 v1**, add after live testing reveals mechanics

### Escalation Policy

- **Agent ALWAYS answers. No exceptions.** The OpenClaw agent IS the human. Deferring blocks the session and stops the autonomous loop.
- **"Chat about this"** reserved for when the **question is WRONG** — contradicts project state, wrong phase, hallucinated requirement. Agent redirects Claude Code.
- **Three-tier answer strategy:**

| Situation | Action |
|-----------|--------|
| Question makes sense, options cover it | Select the right option |
| Question makes sense, options don't fully capture | Type something with nuanced answer |
| Question is wrong — contradicts project state | Chat about this — redirect Claude Code |

- **Permission questions never appear** — GSD runs with `--dangerously-skip-permissions`. Only GSD workflow questions.
- **Same guard as all handlers**: resolve session → resolve agent → if managed, answer. Queue existence is irrelevant.
- **No re-entrancy guard needed** — each AskUserQuestion is independent and sequential (unlike Stop which can loop).

### Verification System

- **File-based programmatic verification** — no agent wake on match (95% case, zero tokens burned)
- **PreToolUse** saves question metadata to `logs/queues/question-{session}.json`
- **TUI driver** reads question file + saves intent to `logs/queues/pending-answer-{session}.json` (includes `tool_use_id`)
- **PostToolUse** reads pending answer, compares with `tool_response.answers`:
  - **Match:** log "verified" + delete both files + exit 0
  - **Mismatch:** wake OpenClaw agent with specific details + delete both files + exit 0
  - **Missing/stale file:** log warning + exit 0 — self-healing, no crash
- **Comparison logic per action type:**

| Action | Intent Field | Compare Against |
|--------|-------------|-----------------|
| `select` | `optionIndex: N` | `answers["question"] === options[N].label` |
| `type` | `text: "..."` | `answers["question"]` contains the typed text |
| `multi-select` | `selectedIndices: [0, 2]` | `answers["question"]` contains all selected option labels |
| `chat` | `text: "..."` | Skip verification — breaks normal answer flow |

- **Immediate agent notification on mismatch** — agent corrects on NEXT AskUserQuestion via "Chat about this" or "Type something". Don't wait for Stop — compounding errors across remaining questions.

### Handler Architecture

- **Router pattern**: one handler per event type, dispatches by `tool_name`
  - `event_pre_tool_use.mjs` — reads `tool_name`, routes to `ask_user_question/handle_ask_user_question.mjs`
  - `event_post_tool_use.mjs` — reads `tool_name`, routes to `ask_user_question/handle_post_ask_user_question.mjs`
  - Extensible: future tools add a folder + one `if` branch. No existing code changes.
- **Handlers are fire-and-forget** — wake agent, exit 0 immediately. Same pattern as Stop handler. Claude Code hooks have a timeout (30s), agent may need longer.
- **Handlers are thin plumbing** (~5-10 lines of logic each). Domain knowledge lives in `lib/ask-user-question.mjs`.

### Driver Architecture

- **`bin/tui-driver-ask.mjs`** — separate from `bin/tui-driver.mjs` (SRP: different inputs, different TUI patterns, different purposes)
- **Shares `lib/tui-common.mjs`** for `sendKeysToTmux` / `sendSpecialKeyToTmux` (DRY at tmux layer)
- **4 action types in one driver**: select, type, multi-select, chat (chat is just more Downs — not architecturally different)
- **TUI driver reads question metadata from file** (saved by PreToolUse), agent passes only its decision
- **Agent payload**: JSON array of per-question actions (matches tabbed form order)

### Shared Library Module

- **`lib/ask-user-question.mjs`** — owns ALL AskUserQuestion domain knowledge
- Functions:
  - `formatQuestionsForAgent(toolInput)` — used by PreToolUse handler + PostToolUse mismatch prompt
  - `saveQuestionMetadata(sessionName, toolInput, toolUseId)` — PreToolUse handler
  - `readQuestionMetadata(sessionName)` — TUI driver
  - `deleteQuestionMetadata(sessionName)` — PostToolUse handler
  - `savePendingAnswer(sessionName, intent, toolUseId)` — TUI driver
  - `readPendingAnswer(sessionName)` — PostToolUse handler
  - `deletePendingAnswer(sessionName)` — PostToolUse handler
  - `compareAnswerWithIntent(toolResponse, pendingAnswer, toolInput)` — PostToolUse handler

### PreToolUse Prompt Format

Agent receives:
- Session name
- Active queue command (read from queue file — e.g., "/gsd:discuss-phase 3")
- GSD phase type (discuss/plan/execute/verify)
- All questions with 0-indexed options, descriptions, multiSelect flags
- Project context: STATE.md, ROADMAP.md, prior CONTEXT.md references
- TUI driver call syntax with answer format examples

### Claude's Discretion

- `action: chat` exact Down count to reach "Chat about this" — test live (does separator count as navigable?)
- Comparison logic implementation details per action type
- Error handling in question/pending-answer file operations
- Prompt wording for mismatch correction

</decisions>

<specifics>
## Specific Ideas

- "The OpenClaw agent IS the human. It reads project context, understands the question, makes a decision, and types the answer — exactly like you would if you were sitting at the keyboard. The difference is it does it at 3am when you're asleep."
- During `/gsd:discuss-phase`, the OpenClaw agent's answer quality directly determines what goes into CONTEXT.md, which feeds everything downstream. This is where it earns its keep.
- PostToolUse verification exists as the feedback loop — if TUI assumptions are wrong, the mismatch logs show exactly which assumption failed.
- "Build with sensible defaults, test live" philosophy for all TUI unknowns. Research won't answer keystroke questions — only real sessions will.
- The PostToolUse payload structure (from real logs):
  ```json
  {
    "tool_input": {
      "questions": [{ "question": "...", "options": [...], "multiSelect": false }]
    },
    "tool_response": {
      "answers": { "question text": "selected answer" },
      "annotations": { "question text": { "notes": "typed text" } }
    }
  }
  ```

</specifics>

<deferred>
## Deferred Ideas

- **Annotation text entry** in multi-select — test live, add after Phase 4 v1 reveals mechanics
- **SubagentStart/SubagentStop hooks** — mentioned in autonomous loop context, future phase
- **Notification/idle_prompt handler** — from Phase 3 deferred items, evaluate after Phase 4 testing
- **Error/failure status in queue** — from Phase 3 deferred, keep plumbing dumb for now

</deferred>

## File Structure

```
bin/
  tui-driver-ask.mjs                           ← 4 actions: select, type, multi-select, chat

events/
  pre_tool_use/
    event_pre_tool_use.mjs                      ← router: resolve session/agent, dispatch by tool_name
    ask_user_question/
      handle_ask_user_question.mjs              ← save question file, format prompt, wake agent
      prompt_ask_user_question.md               ← agent prompt for answering questions
  post_tool_use/
    event_post_tool_use.mjs                     ← router: resolve session/agent, dispatch by tool_name
    ask_user_question/
      handle_post_ask_user_question.mjs         ← verify answer, wake agent on mismatch
      prompt_post_ask_mismatch.md               ← agent prompt for mismatch correction (only used on mismatch)

lib/
  ask-user-question.mjs                         ← shared AskUserQuestion domain module

logs/queues/                                    ← runtime, gitignored
  question-{session}.json                       ← PreToolUse creates, PostToolUse deletes
  pending-answer-{session}.json                 ← TUI driver creates, PostToolUse deletes
```

## Data Flow

```
PreToolUse fires (AskUserQuestion)
  → Router dispatches to handle_ask_user_question.mjs
  → Save question metadata to logs/queues/question-{session}.json
  → Format questions for agent prompt (include active queue command + project context)
  → Wake OpenClaw agent via gateway (fire-and-forget)
  → Exit 0

OpenClaw agent (independently)
  → Reads question, classifies type, cross-references project state
  → Decides answer per question (select/type/multi-select/chat)
  → Calls: node bin/tui-driver-ask.mjs --session <name> '<decisions JSON>'

TUI driver
  → Reads logs/queues/question-{session}.json for option counts and metadata
  → Saves logs/queues/pending-answer-{session}.json with intent + tool_use_id
  → Types keystrokes into tmux per action type
  → Exits

PostToolUse fires (AskUserQuestion)
  → Router dispatches to handle_post_ask_user_question.mjs
  → Read pending-answer file, compare with tool_response.answers
  → Match (95%): log "verified", delete both files, exit 0
  → Mismatch (5%): wake agent with details, delete both files, exit 0
```

## Items Needing Live Testing

1. Annotation text entry mechanics in multi-select
2. Tab auto-advance between questions in tabbed forms
3. Cursor starting position (assumed: option 0)
4. "Type something" submission scope (assumed: that question only)
5. "Chat about this" Down count (does separator count as navigable element?)

---

*Phase: 04-askuserquestion-lifecycle-full-stack*
*Context gathered: 2026-02-22*
