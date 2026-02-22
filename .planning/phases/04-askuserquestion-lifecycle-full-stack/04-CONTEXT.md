# Phase 4: AskUserQuestion Lifecycle (Full Stack) - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

<domain>
## Phase Boundary

The full PreToolUse → PostToolUse verification loop for AskUserQuestion tool calls. When Claude Code asks the user a question (via AskUserQuestion), the OpenClaw agent automatically reads the question, decides the answer based on project context, submits it via TUI driver, and verifies the answer went through correctly. This enables fully autonomous GSD workflow execution without human intervention.

**AskUserQuestion is blocking** — Claude Code waits for the answer before continuing. No concurrent question handling needed. The next AskUserQuestion cannot fire until the current one is answered.

</domain>

<prerequisites>
## Prerequisites

Phase 3.1 refactor must be complete before Phase 4 implementation:

- **`wakeAgentWithRetry` helper** — wraps `wakeAgentViaGateway` + `retryWithBackoff` with `{ maxAttempts: 3, initialDelayMilliseconds: 2000 }`. All Phase 4 handlers use this instead of raw `wakeAgentViaGateway`.
- **`readHookContext` shared boilerplate** — extracts the 15-line stdin read → JSON.parse guard → tmux session resolve → agent resolve pattern shared across all handlers. Phase 4 adds 2 more handlers — without extraction, the boilerplate is duplicated 5 times.
- **Guard-failure debug logging** — all guard clause exits log a `debug`-level JSONL entry with exit reason. Without this, Phase 4 handler debugging is guesswork.

</prerequisites>

<decisions>
## Implementation Decisions

### Answer Strategy

- **Context-aware answering** — OpenClaw agent classifies question type and uses project context to decide, not "always first option"
- **OpenClaw agent is the decision-maker, not a rubber stamp** — verify Claude Code's recommended option against ROADMAP.md, STATE.md, and CONTEXT.md before accepting. Claude Code can hallucinate — the OpenClaw agent is the quality gate.
- **6 question categories** with distinct strategies:

| Category | Signal | Strategy |
|----------|--------|----------|
| Confirmation | 1-2 options, one is "yes/proceed" | Pick the affirmative. GSD doesn't hesitate. |
| Style preference | Equivalent alternatives | Check existing codebase conventions. If uncertain, pick "You decide". |
| Scope selection | Multi-select, asking what to include | Select ALL relevant to current phase. Add annotations if project context exceeds options. |
| Architecture decision | Options have different consequences | Cross-reference ROADMAP.md, STATE.md, CONTEXT.md. Pick what aligns with project direction. |
| Open floor | Has "Something else" / "Type something" | Pick option if it matches. Type specific requirements if not. |
| Delegation | Has "You decide" option | Pick "You decide" ONLY when all options equally valid AND agent has no project-specific reason to prefer one. |

- **GSD phase-aware answering** — response depth varies by which GSD command is running:

| GSD Phase | Question Pattern | OpenClaw Agent Approach |
|-----------|-----------------|------------------------|
| `/gsd:discuss-phase` | Heavy (5-10 questions). Architecture, scope, preferences. This IS the decision phase. | **Full reasoning.** Read ROADMAP.md, STATE.md, prior CONTEXT.md. Type nuanced answers. Add annotations. The OpenClaw agent's answer quality here directly determines what goes into CONTEXT.md, which feeds everything downstream. |
| `/gsd:plan-phase` | Light. "Discuss incomplete, proceed?" | **Confirm and proceed.** OpenClaw agent deliberately moved to plan — unblock quickly. |
| `/gsd:execute-phase` | Rare. Procedural confirmations. | **Confirm and continue.** Decisions are locked in CONTEXT.md. If real design question appears, answer but log warning — plan phase missed something. |
| `/gsd:verify-work` | Interactive. "Does this work?" | **Report honestly.** Test/check and report pass/fail with specifics. Feeds back into fix plans. |
| Fallback | Can't classify | **Type something** — explain reasoning with project context. OpenClaw agent is an AI, it can always articulate its thinking. |

- **Fallback strategy**: always "Type something" with reasoning. The OpenClaw agent always has STATE.md, ROADMAP.md, CONTEXT.md in its own conversation context. It can always explain its thinking. A typed reasoning is a decision — a blind first-option pick is a guess.

### TUI Interaction Patterns

- **Claude Code AskUserQuestion TUI layout per question:**
  ```
  ❯ 1. Option A          ← options from payload (0-indexed)
    2. Option B
    3. Option C
    4. Type something.   ← ALWAYS present, not in payload options
  ──────────────────────
    5. Chat about this   ← ALWAYS present, below separator
  ```

- **Multi-question forms use a tabbed layout:**
  ```
  ←  ☐ Question 1  ☐ Question 2  ✔ Submit  →
  ```

- **4 TUI driver actions:**

| Action | Payload | TUI Keystrokes |
|--------|---------|----------------|
| `select` | `{ "action": "select", "optionIndex": N }` | Down ×N → Enter |
| `type` | `{ "action": "type", "text": "..." }` | Down × options.length → Enter → type text → Enter |
| `multi-select` | `{ "action": "multi-select", "selectedIndices": [...] }` | Down/Space to toggle each selected index → navigate to submit → Enter |
| `chat` | `{ "action": "chat", "text": "..." }` | Down × (options.length + 2?) → Enter → type text → Enter |

- **Default assumptions (build + test live):**
  - Cursor starts on option 0
  - Tab auto-advances after answering each question in multi-question forms
  - "Type something" Enter submits that question only, not the whole form
  - Annotation in multi-select: **skip for Phase 4 v1**, add after live testing reveals mechanics

### Escalation Policy

- **OpenClaw agent ALWAYS answers. No exceptions.** The OpenClaw agent IS the human. It reads project context, understands the question, makes a decision, and types the answer — exactly like you would if you were sitting at the keyboard. The difference is it does it at 3am when you're asleep. Deferring blocks the session and stops the autonomous loop.
- **Permission questions never appear** — GSD runs with `--dangerously-skip-permissions`. Only GSD workflow questions reach the OpenClaw agent.
- **Three-tier answer strategy:**

| Situation | Action |
|-----------|--------|
| Question makes sense, options cover it | Select the right option |
| Question makes sense, options don't fully capture it | Type something with nuanced answer |
| Question is wrong — contradicts project state, wrong phase, hallucinated requirement | Chat about this — redirect Claude Code back on track |

- **"Chat about this" does NOT break out of the AskUserQuestion flow.** It loops back with a new set of options or a follow-up question. The hook sequence stays the same — PreToolUse(AskUserQuestion) keeps firing. No special queue logic needed. Whatever fires next, the existing handlers handle it.

### Verification System

- **File-based programmatic verification** — no OpenClaw agent wake on match (95% case, zero tokens burned)
- **PreToolUse handler** saves question metadata to `logs/queues/question-{session}.json`
- **TUI driver** reads question file + saves intent to `logs/queues/pending-answer-{session}.json` (includes `tool_use_id`)
- **PostToolUse handler** reads pending answer, compares with `tool_response.answers`:
  - **Match (95%):** log "verified" + delete both files + exit 0 — zero tokens burned, OpenClaw agent never woken
  - **Mismatch (5%):** wake OpenClaw agent with specific details + delete both files + exit 0
  - **Missing/stale file:** log warning + exit 0 — self-healing, no crash, no block
- **Comparison logic per action type:**

| Action | Intent Field | Compare Against |
|--------|-------------|-----------------|
| `select` | `optionIndex: N` | `answers["question"] === options[N].label` |
| `type` | `text: "..."` | `answers["question"]` contains the typed text |
| `multi-select` | `selectedIndices: [0, 2]` | `answers["question"]` contains all selected option labels |
| `chat` | `text: "..."` | Skip verification — breaks normal answer flow, next event handles outcome |

- **Immediate OpenClaw agent notification on mismatch** — agent corrects on NEXT AskUserQuestion via "Chat about this" or "Type something". Don't wait for Stop — errors compound across remaining questions in a discuss phase.
- **Two causes of mismatch, both fixed by informing the agent:**
  1. TUI driver bug (cursor position, timing) — agent corrects now, mismatch log tells you to fix the driver
  2. OpenClaw agent sent wrong parameters (miscounted options, wrong action) — agent learns and adjusts next call

### Handler Architecture

- **Router pattern**: one registered handler per event type (`PreToolUse`, `PostToolUse`), dispatches by `tool_name`
  - `event_pre_tool_use.mjs` — shared boilerplate (readHookContext), reads `tool_name`, routes to `ask_user_question/handle_ask_user_question.mjs`
  - `event_post_tool_use.mjs` — shared boilerplate (readHookContext), reads `tool_name`, routes to `ask_user_question/handle_post_ask_user_question.mjs`
  - Claude Code registers ONE handler per hook event type in `settings.json`. Cannot register separate handlers per `tool_name`. Router pattern solves this.
  - Extensible: future tools add a folder + one `if` branch. No existing code changes.
- **Same guard pattern as all handlers**: resolve session → resolve agent → if managed, proceed. If session not found or agent disabled → exit 0 silently (human is at the keyboard, handler stays out of the way).
- **No re-entrancy guard needed** — each AskUserQuestion is independent and sequential. Unlike Stop which can trigger itself (agent sends command → Claude runs → Stop fires → agent sends command → infinite loop), AskUserQuestion is blocking: Claude Code waits for the answer, then either continues or asks a new (different) question.
- **Handlers are fire-and-forget** — wake OpenClaw agent via gateway, exit 0 immediately. Same pattern as Stop handler. Claude Code hooks have a timeout (30s), OpenClaw agent may need longer to think.
- **Handlers are thin plumbing** (~5-10 lines of logic each). Domain knowledge lives in `lib/ask-user-question.mjs`.

### Driver Architecture

- **`bin/tui-driver-ask.mjs`** — separate from `bin/tui-driver.mjs` (SRP: different inputs, different TUI patterns, different purposes)
- **Shares `lib/tui-common.mjs`** for `sendKeysToTmux` / `sendSpecialKeyToTmux` (DRY at tmux layer)
- **4 action types in one driver**: select, type, multi-select, chat — "Chat about this" is just more Downs, not architecturally different from "Type something"
- **TUI driver reads question metadata from file** — `logs/queues/question-{session}.json` saved by PreToolUse handler provides option counts, multiSelect flags, option labels. Driver calculates all navigation from this.
- **OpenClaw agent passes only its decision** — minimal CLI payload:
  ```bash
  node bin/tui-driver-ask.mjs --session warden-main-4 '[
    { "action": "select", "optionIndex": 1 }
  ]'
  ```
  Or for multi-question tabbed form:
  ```bash
  node bin/tui-driver-ask.mjs --session warden-main-4 '[
    { "action": "type", "text": "events/ folder with bin/ alias" },
    { "action": "select", "optionIndex": 0 }
  ]'
  ```
  Array index matches question tab index. One action per question.
- **TUI driver saves pending answer BEFORE typing** — `logs/queues/pending-answer-{session}.json` with intent + `tool_use_id` for PostToolUse verification.

### Shared Library Module

- **`lib/ask-user-question.mjs`** — owns ALL AskUserQuestion domain knowledge. Handlers and TUI driver import from here.
- Functions:

| Function | Used By |
|----------|---------|
| `formatQuestionsForAgent(toolInput)` | PreToolUse handler + PostToolUse mismatch prompt |
| `saveQuestionMetadata(sessionName, toolInput, toolUseId)` | `handle_ask_user_question.mjs` (PreToolUse) |
| `readQuestionMetadata(sessionName)` | `bin/tui-driver-ask.mjs` |
| `deleteQuestionMetadata(sessionName)` | `handle_post_ask_user_question.mjs` (PostToolUse) |
| `savePendingAnswer(sessionName, intent, toolUseId)` | `bin/tui-driver-ask.mjs` |
| `readPendingAnswer(sessionName)` | `handle_post_ask_user_question.mjs` (PostToolUse) |
| `deletePendingAnswer(sessionName)` | `handle_post_ask_user_question.mjs` (PostToolUse) |
| `compareAnswerWithIntent(toolResponse, pendingAnswer, toolInput)` | `handle_post_ask_user_question.mjs` (PostToolUse) |

### Gateway Message Format

What `formatQuestionsForAgent(toolInput)` produces — the actual message the OpenClaw agent receives:

```markdown
## AskUserQuestion from Claude Code

**Session:** warden-main-4

### Question 1: Driver path (single-select)
  0. bin/tui-driver-ask.mjs — Alongside generic tui-driver.mjs. Consistent with bin/ convention.
  1. events/ folder — Inside events/pre_tool_use/. Event-specific driver lives with its event.
  2. You decide — Claude's discretion based on DRY/SRP analysis.

## How to answer
Read each question. Read the option descriptions. Cross-reference with your project context
(STATE.md, ROADMAP.md, CONTEXT.md — already in your conversation).

For EVERY question, decide:
- Does one option clearly align with project direction? → select it
- Is an option close but missing nuance? → use "Type something" to give the right answer
  with your reasoning
- Does Claude Code's recommended option (first) actually make sense? → verify against
  ROADMAP.md and STATE.md before accepting. Claude Code can hallucinate.
- Is the question itself wrong (contradicts project state, wrong phase)? → use "Chat about
  this" to redirect Claude Code
- For multi-select: which items are relevant to current phase? Select only what matters.

Answer format per question:
  Pick option:    { "action": "select", "optionIndex": N }
  Type answer:    { "action": "type", "text": "your reasoned answer" }
  Multi-select:   { "action": "multi-select", "selectedIndices": [0, 2] }
  Redirect:       { "action": "chat", "text": "explanation of what's wrong" }

Call:
  node /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver-ask.mjs --session warden-main-4 '<json array>'
```

### Mismatch Correction Prompt

What the OpenClaw agent receives when PostToolUse detects a mismatch:

```markdown
## AskUserQuestion Verification — MISMATCH

**Question:** Naming convention for .mjs files?
**You intended:** option 1 (snake_case)
**Claude Code received:** kebab-case
**tool_use_id:** toolu_01AJk2sUZouyXiPUTjXvyjJx

Your answer was not submitted correctly. On the next AskUserQuestion, use "Chat about
this" or "Type something" to correct this with Claude Code before answering the new question.
```

### Implementation Details (Claude's Discretion)

- Exact error handling in question/pending-answer file read/write/delete operations
- Comparison logic edge cases (partial text matches, whitespace normalization)
- `action: chat` exact Down count to reach "Chat about this" — test live (does separator count as navigable element?)

</decisions>

<specifics>
## Specific Ideas

- "The OpenClaw agent IS the human. It reads project context, understands the question, makes a decision, and types the answer — exactly like you would if you were sitting at the keyboard. The difference is it does it at 3am when you're asleep."
- During `/gsd:discuss-phase`, the OpenClaw agent's answer quality directly determines what goes into CONTEXT.md, which feeds everything downstream. This is where autonomous driving earns its value.
- PostToolUse verification exists as the feedback loop — if TUI assumptions are wrong, the mismatch logs show exactly which assumption failed. The system self-corrects over time from real data.
- "Build with sensible defaults, test live" philosophy for all TUI unknowns. Research won't answer keystroke questions — only real Claude Code sessions will.
- The GSD workflow cycle that the OpenClaw agent drives: discuss → plan → execute → verify → next phase. GSD itself suggests the next command in `last_assistant_message` (e.g., "Next: /clear then /gsd:plan-phase 3"). The OpenClaw agent reads the suggestion at Stop, decides whether to follow or override, and sends the next command via TUI driver.
- The PostToolUse payload structure (from real logs):
  ```json
  {
    "tool_input": {
      "questions": [{ "question": "...", "options": [...], "multiSelect": false }]
    },
    "tool_response": {
      "questions": [{ "question": "...", "options": [...] }],
      "answers": { "question text": "selected answer" },
      "annotations": { "question text": { "notes": "typed text" } }
    }
  }
  ```
- Real AskUserQuestion examples from logs:
  - Multi-select with annotations: "Which areas do you want to discuss?" → user selected all 4 options AND typed "DRY, SRP, Best OpenClaw and Claude Code practices"
  - Single-select with delegation: "Naming convention for .mjs files?" → user picked "You decide"
  - Single-select with escape hatch: "What else to discuss?" → options include "Something else" with "I'll type what I want to discuss"
  - Multi-question tabbed form: two questions with separate tabs + Submit tab

</specifics>

<deferred>
## Deferred Ideas

- **Annotation text entry in multi-select** — skip for Phase 4 v1, add after live testing reveals the TUI mechanics
- **SubagentStart/SubagentStop hooks** — GSD spawns subagents during plan and execute phases. Future phase.
- **Notification(idle_prompt) handler** — from Phase 3 deferred items, evaluate after Phase 4 testing
- **Notification(permission_prompt) handler** — fires while AskUserQuestion waits for input. Currently ignored. May need handling if AskUserQuestion timing creates edge cases.
- **Error/failure status in queue** — from Phase 3 deferred, keep plumbing dumb for now

</deferred>

## File Structure

```
bin/
  tui-driver.mjs                                ← existing Phase 3: queue + type GSD commands
  tui-driver-ask.mjs                            ← NEW: 4 actions: select, type, multi-select, chat

events/
  pre_tool_use/
    event_pre_tool_use.mjs                      ← NEW: router — readHookContext, dispatch by tool_name
    ask_user_question/
      handle_ask_user_question.mjs              ← NEW: save question file, format prompt, wake OpenClaw agent
      prompt_ask_user_question.md               ← NEW: OpenClaw agent prompt for answering questions
  post_tool_use/
    event_post_tool_use.mjs                     ← NEW: router — readHookContext, dispatch by tool_name
    ask_user_question/
      handle_post_ask_user_question.mjs         ← NEW: verify answer, wake OpenClaw agent on mismatch only
      prompt_post_ask_mismatch.md               ← NEW: OpenClaw agent prompt for mismatch correction

lib/
  ask-user-question.mjs                         ← NEW: shared AskUserQuestion domain module
  hook-context.mjs                              ← NEW (Phase 3.1 prerequisite): shared handler boilerplate
  gateway.mjs                                   ← MODIFIED: add wakeAgentWithRetry helper
  tui-common.mjs                                ← existing: sendKeysToTmux, sendSpecialKeyToTmux (shared)
  index.mjs                                     ← MODIFIED: re-export new modules

logs/queues/                                    ← runtime, gitignored
  question-{session}.json                       ← PreToolUse creates, PostToolUse deletes
  pending-answer-{session}.json                 ← TUI driver creates, PostToolUse deletes
  queue-{session}.json                          ← existing Phase 3 (unrelated to AskUserQuestion)
```

## Data Flow

```
PreToolUse fires (tool_name === 'AskUserQuestion')
  → event_pre_tool_use.mjs: readHookContext (stdin, session, agent) → dispatch by tool_name
  → handle_ask_user_question.mjs:
    1. Save question metadata to logs/queues/question-{session}.json
    2. Format questions into readable prompt via formatQuestionsForAgent()
    3. Wake OpenClaw agent via wakeAgentWithRetry (fire-and-forget)
    4. Exit 0

OpenClaw agent (independently, in its own OpenClaw session)
  → Reads the question, all option descriptions
  → Classifies question type (confirmation, architecture, scope, etc.)
  → Cross-references project state (STATE.md, ROADMAP.md, CONTEXT.md — already in conversation)
  → Decides answer per question (select / type / multi-select / chat)
  → Calls: node bin/tui-driver-ask.mjs --session <name> '<decisions JSON>'

bin/tui-driver-ask.mjs
  → Reads logs/queues/question-{session}.json for option counts, labels, multiSelect flags
  → Saves logs/queues/pending-answer-{session}.json with intent + tool_use_id
  → Types keystrokes into tmux per action type
  → Exits

PostToolUse fires (tool_name === 'AskUserQuestion')
  → event_post_tool_use.mjs: readHookContext → dispatch by tool_name
  → handle_post_ask_user_question.mjs:
    1. Read pending-answer file
    2. Compare with tool_response.answers via compareAnswerWithIntent()
    3. Match: log "verified" + delete question + pending-answer files + exit 0
    4. Mismatch: wake OpenClaw agent with details + delete both files + exit 0
    5. Missing/stale file: log warning + exit 0
```

## Items Needing Live Testing

1. **Annotation text entry** — how does typed text get entered in multi-select TUI?
2. **Tab auto-advance** — does answering one question auto-advance to next tab, or manual Tab press needed?
3. **Cursor starting position** — always on option 0?
4. **"Type something" submission scope** — Enter submits that question only, or the whole form?
5. **"Chat about this" navigation** — does the separator line count as a navigable element? Exact Down count = `options.length + 1` or `options.length + 2`?

---

*Phase: 04-askuserquestion-lifecycle-full-stack*
*Context gathered: 2026-02-22*