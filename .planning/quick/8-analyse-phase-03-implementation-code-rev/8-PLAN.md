---
phase: quick-8
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/quick/8-analyse-phase-03-implementation-code-rev/REVIEW.md
autonomous: true
requirements: [REVIEW-03]

must_haves:
  truths:
    - "REVIEW.md contains a thorough code review of all 6 Phase 03 files (tui-common.mjs, queue-processor.mjs, event_stop.mjs, event_session_start.mjs, event_user_prompt_submit.mjs, tui-driver.mjs) plus prompt_stop.md"
    - "Review identifies what was done well with specific code references"
    - "Review identifies concrete improvement opportunities and refactoring candidates"
    - "Review evaluates progress toward the autonomous TUI driving goal"
    - "Review includes scores consistent with Phase 01 and Phase 02 review format"
  artifacts:
    - path: ".planning/quick/8-analyse-phase-03-implementation-code-rev/REVIEW.md"
      provides: "Complete Phase 03 code review document"
      min_lines: 200
  key_links: []
---

<objective>
Produce a comprehensive code review of all Phase 03 implementation files, following the same format and depth established by the Phase 01 review (quick task 1) and Phase 02 review (quick task 3).

Purpose: Identify strengths, weaknesses, DRY/SRP compliance, naming conventions, security posture, error handling patterns, and refactoring opportunities in Phase 03 code before proceeding to Phase 04. This review may trigger an inserted Phase 03.1 refactor (as happened after Phase 01 and Phase 02).

Output: REVIEW.md in the quick task directory.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/ROADMAP.md

Phase 03 source files to review:
@lib/tui-common.mjs
@lib/queue-processor.mjs
@bin/tui-driver.mjs
@events/stop/event_stop.mjs
@events/stop/prompt_stop.md
@events/session_start/event_session_start.mjs
@events/user_prompt_submit/event_user_prompt_submit.mjs

Supporting files (already reviewed in Phase 02, context for Phase 03 usage):
@lib/index.mjs
@lib/gateway.mjs

Prior reviews (for format and pattern reference):
@.planning/quick/1-analyse-phase-1-implementation-code-revi/REVIEW.md
@.planning/quick/3-reflect-on-phase-02-implementation-dry-s/REVIEW.md

Phase 03 summaries (for decisions and patterns context):
@.planning/phases/03-stop-event-full-stack/03-01-SUMMARY.md
@.planning/phases/03-stop-event-full-stack/03-02-SUMMARY.md
@.planning/phases/03-stop-event-full-stack/03-03-SUMMARY.md

Quick task 7 fixes (already applied, do not re-flag):
@.planning/quick/7-fix-phase-03-code-issues-before-phase-04/7-SUMMARY.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Write comprehensive Phase 03 code review to REVIEW.md</name>
  <files>.planning/quick/8-analyse-phase-03-implementation-code-rev/REVIEW.md</files>
  <action>
Read all 7 Phase 03 files (listed in context above) and write a comprehensive code review following the exact structure established by Phase 01 and Phase 02 reviews. The review MUST include these sections:

1. **Executive Summary** — Overall assessment of Phase 03 quality, key strengths, key concerns. Mention the 3 plans that delivered Phase 03 and the quick task 7 fixes already applied.

2. **What Was Done Well** — With specific code line references and snippets:
   - Guard clause pattern consistency across all 3 event handlers
   - Discriminated action return objects in processQueueForHook (no-queue, no-active-command, awaits-mismatch, advanced, queue-complete)
   - Handler = dumb plumbing, lib = brain architecture (thin handlers, fat lib)
   - Self-explanatory naming compliance (CLAUDE.md)
   - DRY: shared typeCommandIntoTmuxSession, shared processQueueForHook, shared prompt_stop.md reuse
   - SRP: each file has a single clear responsibility
   - Atomic queue writes (writeFileSync .tmp + renameSync)
   - Tab completion logic for /gsd:* commands
   - Queue lifecycle completeness (create, advance, cancel, stale cleanup)
   - Session resolution via tmux display-message (not hook payload UUID)
   - Proper error boundaries (main().catch for all handlers)

3. **What Could Be Improved** — Concrete issues with code references, alternatives, pros/cons, and verdicts:
   - Evaluate whether handlers have any remaining DRY violations (repeated boilerplate: stdin read, JSON.parse guard, tmux session resolution, agent resolution — same 15 lines in all 3 handlers)
   - Evaluate error handling: handlers exit(0) on all guard failures silently — no logging of WHY a handler exited early (makes debugging hard in production)
   - Evaluate promptFilePath resolution: each handler resolves it differently (event_stop uses __dirname, session_start and user_prompt_submit navigate to ../stop/) — fragile if directory structure changes
   - Evaluate whether queue-processor.mjs processQueueForHook mutates its input data (activeCommand.status = 'done' mutates the parsed JSON object before writing) — is this safe?
   - Evaluate tui-common.mjs sendKeysToTmux third argument pattern (empty string as "literal flag") — is this documented in tmux? Is it portable?
   - Evaluate whether tui-driver.mjs handles the case where a queue file already exists (overwrite without warning?)
   - Evaluate whether cancelQueueForSession and cleanupStaleQueueForSession could collide (what if both fire within milliseconds?)
   - Evaluate the suggested commands regex in event_stop.mjs — does it handle edge cases (e.g., /gsd:plan-phase inside a code block, /clear in a URL)?
   - Evaluate whether event_stop.mjs wakeAgentViaGateway is called without retryWithBackoff (unlike what Phase 02 review Section 5.3 hypothesized)

4. **Phase 01 and Phase 02 Review Alignment** — Table mapping prior review findings to Phase 03 outcomes (was each lesson applied?)

5. **Progress Toward Autonomous Driving Goal** — Evaluate how close the system is to the goal: "When Claude Code fires any hook event, the right agent wakes up with the right context and knows exactly which GSD slash command to type next."
   - What pieces are now in place?
   - What is still missing for Phase 04?
   - Risk assessment for Phase 04

6. **Scores** — Using the same dimensions as Phase 01 and Phase 02 reviews:
   - Code Quality (x/5)
   - DRY/SRP (x/5)
   - Naming Conventions (x/5)
   - Error Handling (x/5)
   - Security (x/5)
   - Future-Proofing (x/5)

7. **Summary Table** — One row per file: key strength, key concern, recommendation.

IMPORTANT: Do NOT re-flag issues already fixed in quick task 7 (DRY writeQueueFileAtomically, JSON.parse guards, absolute path in prompt_stop.md). Acknowledge these as fixed. Focus on issues that REMAIN in the current code.

IMPORTANT: Be honest and critical. Prior reviews gave 2/5 for security (Phase 01), 4/5 for error handling (Phase 02). Do not inflate scores. If the code is genuinely excellent, say so with evidence. If it has weaknesses, name them with line numbers.
  </action>
  <verify>
1. File exists: `ls -la .planning/quick/8-analyse-phase-03-implementation-code-rev/REVIEW.md`
2. File has substantial content: `wc -l .planning/quick/8-analyse-phase-03-implementation-code-rev/REVIEW.md` shows 200+ lines
3. File contains all required sections: grep for "Executive Summary", "What Was Done Well", "What Could Be Improved", "Alignment", "Autonomous Driving", "Scores", "Summary Table"
4. File contains specific code references: grep for line numbers or code snippets
  </verify>
  <done>REVIEW.md exists with 200+ lines covering all 7 Phase 03 files, all 7 required sections present, scores assigned with evidence, specific code line references throughout, and no re-flagging of quick task 7 fixes.</done>
</task>

</tasks>

<verification>
- REVIEW.md exists in the quick task directory
- All 7 Phase 03 source files are analyzed (not just summarized)
- Review follows Phase 01/02 review format exactly
- Scores are justified with evidence
- Actionable findings are identified for potential Phase 03.1 refactor
</verification>

<success_criteria>
- REVIEW.md is written with the same depth and format as the Phase 01 and Phase 02 reviews
- Every Phase 03 file has at least one "done well" and one "could improve" observation
- Findings are specific enough to drive a refactoring plan if needed
- No quick task 7 fixes are re-flagged as issues
</success_criteria>

<output>
After completion, create `.planning/quick/8-analyse-phase-03-implementation-code-rev/8-SUMMARY.md`
</output>
