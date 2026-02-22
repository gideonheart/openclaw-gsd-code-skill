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
    - "No 'active queue command' or 'GSD phase type' references exist in PreToolUse Prompt Format or Handler Architecture sections"
    - "No 'Project context: STATE.md, ROADMAP.md' injection references exist — OpenClaw agent already has project context in its session"
    - "All function list entries use actual handler filenames (handle_ask_user_question.mjs, handle_post_ask_user_question.mjs, bin/tui-driver-ask.mjs)"
    - "A concrete Gateway Message Format section shows exactly what formatQuestionsForAgent produces for the OpenClaw agent"
    - "A Mismatch Correction Prompt section shows exactly what the OpenClaw agent receives on verification failure"
    - "AskUserQuestion is blocking statement appears in the document"
    - "A Prerequisites section references Phase 3.1 refactor deliverables (wakeAgentWithRetry, readHookContext, guard-failure logging)"
    - "Implementation Details (Claude's Discretion) section is separate from TUI testing items"
    - "Items Needing Live Testing section lists all 5 TUI unknowns"
    - "wakeAgentWithRetry appears in Prerequisites and Data Flow sections"
    - "Data Flow section uses formatQuestionsForAgent() — no stale project context injection"
    - "File Structure marks existing vs NEW vs MODIFIED files"
  artifacts:
    - path: ".planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md"
      provides: "Corrected Phase 4 context document — full rewrite incorporating all discussion decisions"
      contains: "wakeAgentWithRetry"
  key_links: []
---

<objective>
Full rewrite of Phase 04 CONTEXT.md incorporating all decisions from the discuss session. The original CONTEXT.md had 7 issues: stale queue/project-context references in PreToolUse prompt, inconsistent function comment naming, no gateway message example, no mismatch prompt example, missing blocking note, no Phase 3.1 prerequisites, and unsplit Claude's Discretion section.

Rather than applying 7 targeted edits to the existing file, produce a complete corrected document that reflects the full discussion output — including new sections (Gateway Message Format, Mismatch Correction Prompt, Prerequisites) and restructured content (TUI unknowns separated to Items Needing Live Testing).

Purpose: Ensure the Phase 4 planning document accurately reflects the actual architecture before plan-phase begins.
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
  <name>Task 1: Full rewrite of 04-CONTEXT.md with all corrections</name>
  <files>.planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md</files>
  <action>
Replace the entire file with the corrected version. Key changes from the original:

**Structural changes (new sections added):**
1. **Prerequisites section** (after domain, before decisions) — references Phase 3.1 refactor deliverables: `wakeAgentWithRetry`, `readHookContext`, guard-failure debug logging
2. **Gateway Message Format section** (inside decisions, after Shared Library) — concrete example showing what `formatQuestionsForAgent(toolInput)` produces, including the full prompt the OpenClaw agent receives with answer format examples and TUI driver call syntax
3. **Mismatch Correction Prompt section** (after Gateway Message Format) — concrete example showing what the OpenClaw agent receives when PostToolUse detects a verification mismatch
4. **Items Needing Live Testing section** (after Data Flow, end of document) — the 5 TUI unknowns extracted from the original Claude's Discretion section

**Content fixes (stale references removed):**
5. **PreToolUse prompt** — removed "active queue command", "GSD phase type", "project context injection". Handler delivers only the question. OpenClaw agent already has project context in its own session.
6. **Data Flow** — changed step 2 from "include active queue command + project context" to "Format questions into readable prompt via formatQuestionsForAgent()"
7. **Shared Library function table** — all 8 functions use actual filenames (`handle_ask_user_question.mjs`, `handle_post_ask_user_question.mjs`, `bin/tui-driver-ask.mjs`) not generic "PreToolUse handler" / "PostToolUse handler"
8. **File Structure** — marks each file as existing / NEW / MODIFIED for clarity
9. **Deferred section** — added `Notification(permission_prompt)` (fires while AskUserQuestion waits) and explicit note about SubagentStart/SubagentStop being GSD-related

**Restructured sections:**
10. **Implementation Details (Claude's Discretion)** — now contains only implementation-level decisions (error handling, comparison edge cases, chat Down count). TUI unknowns moved to dedicated "Items Needing Live Testing" section at document end.
  </action>
  <verify>
Verify all changes applied:
1. Grep for "active queue command" — should return 0 matches
2. Grep for "GSD phase type" as a bullet item — should return 0 matches
3. Grep for "Project context:" as a bullet item under PreToolUse Prompt — should return 0 matches
4. Grep for "handle_ask_user_question.mjs" — should appear in function table
5. Grep for "Gateway Message Format" — should appear as section header
6. Grep for "Mismatch Correction Prompt" — should appear as section header
7. Grep for "AskUserQuestion is blocking" — should appear
8. Grep for "Prerequisites" — should appear as section header
9. Grep for "Implementation Details" — should appear as section header
10. Grep for "Items Needing Live Testing" — should appear as section header
11. Grep for "wakeAgentWithRetry" — should appear in Prerequisites and Data Flow
12. Grep for "NEW:" — should appear in File Structure section
13. Grep for "formatQuestionsForAgent" — should appear in Gateway Message Format, Shared Library, and Data Flow
  </verify>
  <done>Full rewrite of 04-CONTEXT.md complete: stale queue/project-context references removed, gateway message and mismatch prompt examples added, prerequisites section added, TUI unknowns separated to Items Needing Live Testing, all function comments use actual filenames, file structure shows NEW/MODIFIED/existing markers</done>
</task>

</tasks>

<verification>
- No stale references to "active queue command", "GSD phase type", or "Project context:" injection remain
- Function table uses actual filenames throughout
- Gateway Message Format shows concrete formatQuestionsForAgent output with answer format examples
- Mismatch Correction Prompt shows concrete agent notification with question/intended/received details
- Escalation Policy or Phase Boundary includes blocking note
- Prerequisites section references all 3 Phase 3.1 deliverables
- Implementation Details is separate from Items Needing Live Testing
- wakeAgentWithRetry referenced in Prerequisites and Data Flow
- File Structure marks NEW/MODIFIED/existing files
- Data Flow has no project context injection — uses formatQuestionsForAgent()
</verification>

<success_criteria>
Complete rewrite produces an internally consistent document with no stale references. All new sections (Prerequisites, Gateway Message Format, Mismatch Correction Prompt, Items Needing Live Testing) exist and contain concrete examples. The document accurately reflects the architecture as discussed.
</success_criteria>

<output>
After completion, create `.planning/quick/14-fix-7-bugs-in-phase-04-context-md-remove/14-SUMMARY.md`
</output>