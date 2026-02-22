---
phase: quick-14
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md
autonomous: true
requirements: []

must_haves:
  truths:
    - "PreToolUse Prompt Format section lists session name, questions, answer format examples, TUI driver syntax — no queue or project context references"
    - "All function list comments use actual handler filenames consistently"
    - "A concrete example of formatQuestionsForAgent output exists in the document"
    - "Escalation Policy section states AskUserQuestion is blocking"
    - "A Prerequisites section references Phase 3.1 refactor deliverables"
    - "Claude's Discretion is split into implementation details vs TUI unknowns"
    - "wakeAgentWithRetry appears in Shared Library function list and Deferred section"
    - "Data Flow section has no 'project context' injection reference"
  artifacts:
    - path: ".planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md"
      provides: "Corrected Phase 4 context document"
      contains: "wakeAgentWithRetry"
  key_links: []
---

<objective>
Apply 7 targeted fixes to the Phase 04 CONTEXT.md document: remove queue/project-context references from PreToolUse prompt format, fix naming consistency in function comments, add gateway message example, add blocking note, add Phase 3.1 prerequisites, split Claude's Discretion into two sections, and add wakeAgentWithRetry references.

Purpose: Ensure the Phase 4 planning document accurately reflects the actual architecture (no stale queue references, correct filenames, prerequisite awareness) before plan-phase begins.
Output: Corrected `.planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md`
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Apply all 7 fixes to 04-CONTEXT.md</name>
  <files>.planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md</files>
  <action>
Read the file fully, then apply these 7 edits in a single Write:

**Fix 1 — PreToolUse Prompt Format (lines 133-141):**
Replace the current bullet list under "Agent receives:" with:
- Session name
- All questions with 0-indexed options, descriptions, multiSelect flags
- Answer format examples per action type (select, type, multi-select, chat)
- TUI driver call syntax: `node bin/tui-driver-ask.mjs --session <name> '<decisions JSON>'`

Remove these three lines entirely:
- "Active queue command (read from queue file...)"
- "GSD phase type (discuss/plan/execute/verify)"
- "Project context: STATE.md, ROADMAP.md, prior CONTEXT.md references"

The OpenClaw agent already has project context in its session — the handler should NOT inject it.

**Fix 2 — Naming consistency (line 125 area):**
In the Shared Library functions list, each function comment says which file uses it. Ensure all comments use actual filenames:
- `saveQuestionMetadata` — used by `handle_ask_user_question.mjs` (not "PreToolUse handler")
- `readQuestionMetadata` — used by `bin/tui-driver-ask.mjs` (not "TUI driver")
- `deleteQuestionMetadata` — used by `handle_post_ask_user_question.mjs` (not "PostToolUse handler")
- `savePendingAnswer` — used by `bin/tui-driver-ask.mjs`
- `readPendingAnswer` — used by `handle_post_ask_user_question.mjs`
- `deletePendingAnswer` — used by `handle_post_ask_user_question.mjs`
- `compareAnswerWithIntent` — used by `handle_post_ask_user_question.mjs`
- `formatQuestionsForAgent` — used by `handle_ask_user_question.mjs` + `handle_post_ask_user_question.mjs` (mismatch prompt)

**Fix 3 — Add explicit gateway message example:**
After the Shared Library section (or within Data Flow), add a concrete example showing what `formatQuestionsForAgent(toolInput)` produces. Example:

```
Input toolInput:
{
  "questions": [
    { "question": "How should we handle auth?", "options": ["JWT tokens", "Session cookies", "You decide"], "multiSelect": false },
    { "question": "Which features to include?", "options": ["Login", "Register", "Password reset"], "multiSelect": true }
  ]
}

formatQuestionsForAgent output:
Question 0: How should we handle auth?
  [0] JWT tokens
  [1] Session cookies
  [2] You decide
  multiSelect: false

Question 1: Which features to include?
  [0] Login
  [1] Register
  [2] Password reset
  multiSelect: true
```

Also fix Data Flow line 216: change "Format questions for agent prompt (include active queue command + project context)" to "Format questions for agent prompt via formatQuestionsForAgent(toolInput)"

**Fix 4 — Add blocking note to Escalation Policy (after line 81):**
Add a bullet: "**AskUserQuestion is blocking** — Claude Code waits for the answer before continuing. No concurrent question handling needed. Each question is independent and sequential."

**Fix 5 — Add Prerequisites section:**
Add a `## Prerequisites` section before the File Structure section (before line 184):

```markdown
## Prerequisites

- **Phase 3.1 refactor complete** — the following shared utilities must exist:
  - `wakeAgentWithRetry` helper in `lib/gateway.mjs` (DRY wrapper for retry+gateway pattern)
  - `readHookContext` shared boilerplate in `lib/hook-context.mjs` (session/agent resolution)
  - Guard-failure debug logging via `lib/logger.mjs`
```

**Fix 6 — Split "Claude's Discretion" (lines 143-149):**
Replace the single section with two:

```markdown
### Implementation Details (Claude's Discretion)

- Comparison logic implementation details per action type
- Error handling in question/pending-answer file read/write/delete operations
- Prompt wording for mismatch correction notification

### TUI Unknowns (Resolve via Live Testing)

- `action: chat` exact Down count to reach "Chat about this" — does separator count as navigable element?
- Annotation text entry mechanics in multi-select (deferred to post-Phase 4 v1)
- Tab auto-advance behavior between questions in multi-question tabbed forms
- Cursor starting position (assumed: option 0)
- "Type something" submission scope — submits that question only, or entire form?
```

**Fix 7 — Add wakeAgentWithRetry references:**
In the Shared Library functions list, add a note after the function list:
"Handlers use `wakeAgentWithRetry` from `lib/gateway.mjs` for all gateway calls (established in Phase 3.1 refactor, quick-10)."

In the Deferred section, add:
"- **`wakeAgentWithRetry` as prerequisite** — Phase 3.1 refactor (quick-10) already extracted this helper to `lib/gateway.mjs`. Phase 4 handlers MUST use it, not raw retry+gateway calls."
  </action>
  <verify>
Verify all 7 fixes applied:
1. Grep for "active queue command" — should return 0 matches
2. Grep for "GSD phase type" — should return 0 matches
3. Grep for "Project context:" (as a bullet item) — should return 0 matches
4. Grep for "handle_ask_user_question.mjs" — should appear in function comments
5. Grep for "formatQuestionsForAgent output" — should appear (example section)
6. Grep for "AskUserQuestion is blocking" — should appear in Escalation Policy
7. Grep for "Prerequisites" — should appear as section header
8. Grep for "Implementation Details" and "TUI Unknowns" — both should appear
9. Grep for "wakeAgentWithRetry" — should appear in both Shared Library and Deferred sections
  </verify>
  <done>All 7 fixes applied to 04-CONTEXT.md: queue/project-context references removed from PreToolUse prompt, filenames consistent in function comments, gateway message example added, blocking note in Escalation Policy, Prerequisites section exists, Claude's Discretion split into two sections, wakeAgentWithRetry referenced in library and deferred sections</done>
</task>

</tasks>

<verification>
- No stale references to "active queue command", "GSD phase type", or "Project context:" injection remain
- Function comments use actual filenames (handle_ask_user_question.mjs, handle_post_ask_user_question.mjs, bin/tui-driver-ask.mjs)
- formatQuestionsForAgent example shows concrete input/output
- Escalation Policy includes the blocking note
- Prerequisites section references Phase 3.1 deliverables
- Two separate sections replace "Claude's Discretion"
- wakeAgentWithRetry appears in Shared Library and Deferred sections
</verification>

<success_criteria>
All 7 fixes applied in a single clean edit. The document is internally consistent — no stale references, all filenames match the File Structure section, and new sections are placed logically within the document flow.
</success_criteria>

<output>
After completion, create `.planning/quick/14-fix-7-bugs-in-phase-04-context-md-remove/14-SUMMARY.md`
</output>
