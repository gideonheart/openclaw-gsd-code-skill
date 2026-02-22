---
phase: quick-14
plan: 01
subsystem: docs
tags: [planning, context, phase-04, ask-user-question, full-rewrite]

# Dependency graph
requires:
  - phase: quick-13
    provides: Phase 3.1 refactor context (wakeAgentWithRetry, hook-context.mjs established)
  - discuss: Phase 4 discuss session (2026-02-22)
    provides: All architecture decisions for AskUserQuestion lifecycle
provides:
  - Corrected Phase 4 CONTEXT.md — full rewrite (354 lines) incorporating all discuss session decisions
  - No stale queue/project-context references in PreToolUse prompt
  - Concrete Gateway Message Format example showing formatQuestionsForAgent output
  - Concrete Mismatch Correction Prompt example showing PostToolUse agent notification
  - Prerequisites section referencing Phase 3.1 deliverables
  - Implementation Details separated from Items Needing Live Testing
  - File Structure with NEW/MODIFIED/existing markers
  - wakeAgentWithRetry referenced in Prerequisites and Data Flow
affects: [phase-04-planning, plan-phase-04]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - .planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md

key-decisions:
  - "Full rewrite instead of 7 targeted edits — original had too many structural gaps (missing sections) for incremental fixes to produce a coherent document"
  - "PreToolUse prompt does NOT inject queue command or project context — OpenClaw agent already has project context in its own session"
  - "Gateway Message Format section added — concrete example of what formatQuestionsForAgent produces, including answer format syntax and TUI driver call"
  - "Mismatch Correction Prompt section added — concrete example of what OpenClaw agent receives when PostToolUse detects wrong answer"
  - "Prerequisites section added — Phase 3.1 refactor (wakeAgentWithRetry, readHookContext, guard-failure logging) must be complete before Phase 4"
  - "AskUserQuestion is blocking — stated in Phase Boundary section, no concurrent handling needed"
  - "formatQuestionsForAgent used by both handle_ask_user_question.mjs and handle_post_ask_user_question.mjs (mismatch prompt)"
  - "Phase 4 handlers MUST use wakeAgentWithRetry from lib/gateway.mjs (established quick-10), not raw retry+gateway calls"
  - "File Structure section marks each file as existing / NEW / MODIFIED for planning clarity"
  - "TUI unknowns (5 items) separated into dedicated Items Needing Live Testing section at document end"

patterns-established:
  - "Full rewrite over incremental edits when structural gaps exceed content fixes"
  - "Concrete prompt examples (gateway message, mismatch notification) in CONTEXT.md for implementation reference"

requirements-completed: []

# Metrics
duration: 2min
completed: 2026-02-22
---

# Quick Task 14: Fix Phase 04 CONTEXT.md — Full Rewrite Summary

**Full rewrite of Phase 04 CONTEXT.md (354 lines) incorporating all discuss session decisions: removed stale queue/project-context references, added gateway message example, mismatch prompt example, prerequisites section, and separated TUI unknowns**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-22T11:00:18Z
- **Completed:** 2026-02-22T11:02:15Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

### Structural additions (4 new sections):
- **Prerequisites section** — references Phase 3.1 refactor deliverables (`wakeAgentWithRetry`, `readHookContext`, guard-failure debug logging) as hard prerequisites for Phase 4
- **Gateway Message Format section** — concrete example showing what `formatQuestionsForAgent(toolInput)` produces, including the full prompt with answer format examples (`select`, `type`, `multi-select`, `chat`) and TUI driver call syntax
- **Mismatch Correction Prompt section** — concrete example showing what the OpenClaw agent receives when PostToolUse detects a verification mismatch (question, intended answer, received answer, tool_use_id, correction guidance)
- **Items Needing Live Testing section** — 5 TUI unknowns extracted from the original Claude's Discretion section (annotation entry, tab auto-advance, cursor position, type-something scope, chat navigation)

### Content fixes (stale references removed):
- Removed "active queue command (read from queue file)" from PreToolUse prompt — queue is irrelevant to AskUserQuestion
- Removed "GSD phase type (discuss/plan/execute/verify)" from PreToolUse prompt — OpenClaw agent knows this from its own context
- Removed "Project context: STATE.md, ROADMAP.md, prior CONTEXT.md references" from PreToolUse prompt — handler delivers only the question, OpenClaw agent already has project context in its session
- Fixed Data Flow step 2 from "include active queue command + project context" to "Format questions into readable prompt via formatQuestionsForAgent()"

### Consistency fixes:
- All 8 functions in Shared Library table use actual filenames (`handle_ask_user_question.mjs`, `handle_post_ask_user_question.mjs`, `bin/tui-driver-ask.mjs`) not generic handler names
- File Structure marks each file as existing / NEW / MODIFIED
- `wakeAgentWithRetry` appears in Prerequisites (as requirement) and Data Flow (as usage)
- Implementation Details (Claude's Discretion) now contains only implementation-level decisions, TUI unknowns moved to dedicated section

## Task Commits

1. **Task 1: Full rewrite of 04-CONTEXT.md** - `6bb9190` (fix)

## Files Created/Modified

- `.planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md` — Full rewrite, 354 lines. Corrected Phase 4 context document incorporating all discuss session decisions.

## Decisions Made

- **Full rewrite over incremental edits** — the original had 4 missing sections (Prerequisites, Gateway Message Format, Mismatch Correction Prompt, Items Needing Live Testing) plus 7 content fixes. Incremental editing would have been harder to verify than a clean rewrite.

## Deviations from Plan

- **Plan specified 7 targeted edits; execution was a full rewrite** — the plan described 7 individual fixes to apply. In practice, the document needed 4 new sections plus 7 content changes. A full rewrite produced a more coherent document than 11 individual edits applied sequentially.
- **Gateway message example format differs from plan** — plan specified a raw `formatQuestionsForAgent output:` code block. Actual implementation uses a full "Gateway Message Format" section with a complete markdown prompt example including the "How to answer" guidance the OpenClaw agent receives. This is more useful for implementation reference.
- **TUI Unknowns not a separate header inside decisions** — plan specified splitting Claude's Discretion into "Implementation Details" + "TUI Unknowns" as adjacent sections. Actual implementation keeps "Implementation Details" inside decisions and moves TUI unknowns to "Items Needing Live Testing" at document end, which is a better structure since they're action items, not decisions.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 4 CONTEXT.md is accurate and internally consistent (354 lines)
- No stale references remain (verified: no "active queue command", "GSD phase type", or "Project context:" injection)
- Prerequisites clearly state Phase 3.1 must be complete
- Concrete prompt examples (gateway message, mismatch notification) provide implementation reference
- 5 TUI unknowns documented for live testing
- Ready for `/gsd:plan-phase 4`

## Self-Check

**File exists:**
- `.planning/phases/04-askuserquestion-lifecycle-full-stack/04-CONTEXT.md`: FOUND (354 lines)

**Stale references removed:**
- Grep "active queue command": 0 matches ✓
- Grep "GSD phase type" (as bullet): 0 matches ✓
- Grep "Project context:" (as bullet under PreToolUse): 0 matches ✓

**New sections present:**
- "Prerequisites": FOUND ✓
- "Gateway Message Format": FOUND ✓
- "Mismatch Correction Prompt": FOUND ✓
- "Items Needing Live Testing": FOUND ✓
- "Implementation Details": FOUND ✓

**Consistency:**
- "handle_ask_user_question.mjs" in function table: FOUND ✓
- "handle_post_ask_user_question.mjs" in function table: FOUND ✓
- "bin/tui-driver-ask.mjs" in function table: FOUND ✓
- "wakeAgentWithRetry" in Prerequisites: FOUND ✓
- "wakeAgentWithRetry" in Data Flow: FOUND ✓
- "formatQuestionsForAgent" in Gateway Message Format: FOUND ✓
- "formatQuestionsForAgent" in Data Flow: FOUND ✓
- "NEW:" in File Structure: FOUND ✓

**Commits exist:**
- `6bb9190`: fix — FOUND

## Self-Check: PASSED

---
*Quick Task: 14-fix-7-bugs-in-phase-04-context-md-remove*
*Completed: 2026-02-22*