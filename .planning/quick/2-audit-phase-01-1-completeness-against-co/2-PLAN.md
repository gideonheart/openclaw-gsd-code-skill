---
phase: quick-2
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/quick/2-audit-phase-01-1-completeness-against-co/AUDIT.md
  - .planning/REQUIREMENTS.md
  - .planning/ROADMAP.md
  - .planning/PROJECT.md
autonomous: true
requirements: []
must_haves:
  truths:
    - "AUDIT.md documents completeness status of all 11 REV-3.x findings with evidence"
    - "AUDIT.md lists non-REV-3.x items and their resolution status"
    - "AUDIT.md lists all drifted files with specific line-level corrections needed"
    - "REQUIREMENTS.md traceability table shows REG-01 as Complete in Phase 1"
    - "ROADMAP.md Phase 2 success criterion uses ESM import pattern instead of require()"
    - "PROJECT.md handler script references say .js not .sh"
    - "PROJECT.md Key Decisions outcomes reflect implemented decisions"
    - "PROJECT.md cross-platform claim is annotated with Linux-only reality"
  artifacts:
    - path: ".planning/quick/2-audit-phase-01-1-completeness-against-co/AUDIT.md"
      provides: "Completeness audit of Phase 01.1 against code review"
    - path: ".planning/REQUIREMENTS.md"
      provides: "Corrected traceability table"
    - path: ".planning/ROADMAP.md"
      provides: "Corrected Phase 2 success criteria"
    - path: ".planning/PROJECT.md"
      provides: "Corrected project documentation"
  key_links:
    - from: "AUDIT.md"
      to: "REVIEW.md"
      via: "references each REV-3.x finding by ID"
      pattern: "REV-3\\."
---

<objective>
Audit Phase 01.1 completeness against the code review, write the audit document, and fix drifted tracking documents so Phase 2 planning starts from an accurate state.

Purpose: Phase 2 planning will reference REQUIREMENTS.md, ROADMAP.md, and PROJECT.md. If these contain stale data (wrong statuses, impossible test commands, outdated terminology), Phase 2 plans will inherit those errors. Fix now, once, before planning begins.

Output: AUDIT.md (completeness report) + corrected REQUIREMENTS.md, ROADMAP.md, PROJECT.md
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/STATE.md
@.planning/quick/1-analyse-phase-1-implementation-code-revi/REVIEW.md
@.planning/phases/01.1-refactor-phase-1-code-based-on-code-review-findings/01.1-VERIFICATION.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Write AUDIT.md completeness report</name>
  <files>.planning/quick/2-audit-phase-01-1-completeness-against-co/AUDIT.md</files>
  <action>
Create AUDIT.md in the quick task directory with the following structure:

**Section 1: REV-3.x Findings Status (all 11)**

A table with columns: Finding ID | Description | Status | Evidence. Use the orchestrator's analysis as the source of truth (all 11 are DONE). For each finding, include a one-line evidence note referencing the specific code change (e.g., "LOG_BLOCK_TIMESTAMP captures once, reused 5 times" for REV-3.1). The VERIFICATION.md from Phase 01.1 has detailed evidence for each.

**Section 2: Non-REV-3.x Items From Review**

Three items noted in the review but not assigned REV-3.x IDs:

1. **jq -cn DRY violation** (hook-event-logger.sh lines 62-78): Near-identical blocks for valid/invalid JSON. Status: NOT ADDRESSED (out of scope for 01.1, minor). Recommendation: address opportunistically if touching the logger in a future phase, or leave as-is since the logger may be replaced by a Node.js logger in Phase 2.

2. **Cross-platform tension**: PROJECT.md claims cross-platform but code is Linux-only (flock, tmux, bash). Status: KNOWN TENSION. Recommendation: resolve in PROJECT.md (Task 2 of this plan fixes this).

3. **default-system-prompt.md is a stub**: Status: DEFERRED BY DESIGN to Phase 2/3. No action needed.

**Section 3: Drifted Tracking Documents**

List each drift item with: File, What's Wrong, What It Should Say, and Which Task in This Plan Fixes It. Four items:

1. REQUIREMENTS.md: REG-01 listed as "Phase 5 Pending" but was completed in Phase 1.
2. ROADMAP.md: Phase 2 success criterion #1 uses `node -e "require('./lib')"` but package.json has `"type": "module"` making require() fail. Should use ESM: `node -e "import('./lib/index.mjs')"` or `node --input-type=module -e "import { resolveAgentFromSession } from './lib/index.mjs'"`.
3. PROJECT.md: Multiple stale references (see Task 2 for full list).
4. ROADMAP.md: Phase 01.1 plan checkboxes still show `[ ]` but both plans are complete.

**Section 4: Conclusion**

Phase 01.1 is COMPLETE. All 11 REV-3.x findings resolved. Three non-REV items have clear dispositions. Four document drift items identified and corrected in Task 2.
  </action>
  <verify>
File exists at `.planning/quick/2-audit-phase-01-1-completeness-against-co/AUDIT.md`. Contains all 11 REV-3.x finding IDs. Contains sections for non-REV items and drifted documents.
  </verify>
  <done>AUDIT.md documents all 11 REV-3.x findings as complete with evidence, lists 3 non-REV items with dispositions, and catalogs 4 document drift items with corrections.</done>
</task>

<task type="auto">
  <name>Task 2: Fix drifted tracking documents</name>
  <files>
    .planning/REQUIREMENTS.md
    .planning/ROADMAP.md
    .planning/PROJECT.md
  </files>
  <action>
**REQUIREMENTS.md — 1 fix:**

In the Traceability table, change the REG-01 row from:
```
| REG-01 | Phase 5 | Pending |
```
to:
```
| REG-01 | Phase 1 | Complete |
```
REG-01 says "agent-registry.json replaces recovery-registry.json" — this was done in Phase 1 plan 01-02 (registry renamed, .gitignore updated, example created).

**ROADMAP.md — 2 fixes:**

1. Phase 2 success criterion #1: Replace `node -e "require('./lib')"` with an ESM-compatible check. The project uses `"type": "module"` so require() will throw ERR_REQUIRE_ESM. Use: `node --input-type=module -e "import('./lib/index.mjs').then(() => console.log('ok'))"` or simply `node -e "await import('./lib/index.mjs')"` (Node 22+ supports top-level await in -e with --input-type=module). The simplest correct form: `node -e "import('./lib/index.mjs')"` (dynamic import works in both CJS and ESM contexts).

2. Phase 01.1 plan checkboxes: Change both `- [ ]` to `- [x]` for the two plan entries (01.1-01-PLAN.md and 01.1-02-PLAN.md) since both plans are complete per STATE.md and VERIFICATION.md.

**PROJECT.md — 4 fixes:**

1. Target features bullet: Change `event_{descriptive_name}.sh handler scripts` to `event_{descriptive_name}.js handler scripts` — the Node.js decision was made (STATE.md: "Node.js for all event handlers").

2. Key Decisions table: Update outcomes for decisions that are now implemented:
   - "Rewrite from scratch (v4.0)" outcome: change "— Pending" to "Implemented — Phase 1 deleted all v1-v3 artifacts"
   - "agent-registry.json replaces recovery-registry.json" outcome: change "— Pending" to "Implemented — Phase 1 plan 01-02"
   - "last_assistant_message as primary content source" outcome: change "— Pending" to "Adopted — old pane scraping code deleted in Phase 1"
   - "Node.js for all handlers and TUI drivers" outcome: change "— Pending" to "Adopted — launch-session.mjs is ESM, package.json type: module"
   - Leave the remaining decisions (event folder structure, tool-specific PreToolUse, verification loop, full-stack delivery) as "— Pending" since they are Phase 2+ work.

3. Cross-platform claim: Change the target features bullet from "Cross-platform: works on Windows, macOS, Linux using only OpenClaw dependencies (no additional)" to "Linux-targeted (Ubuntu 24 — tmux, flock, bash are Linux-only dependencies; SKILL.md os: linux)". Also update the Constraints section: change "Cross-platform: No GNU-only flags, no Linux-specific paths. POSIX-compatible where possible." to "Linux-targeted: The runtime depends on tmux, flock, and bash. SKILL.md declares os: linux. If cross-platform becomes a goal, these dependencies would need abstraction."

4. Context section: The bullet "Cross-platform: Must work wherever OpenClaw runs (Windows, macOS, Linux) using only OpenClaw dependencies" should be changed to "Linux-targeted: Runs on Ubuntu 24 under the forge user. tmux and flock are Linux-only dependencies."
  </action>
  <verify>
Run these checks:
- `grep 'REG-01' .planning/REQUIREMENTS.md` shows "Complete" not "Pending"
- `grep 'require(' .planning/ROADMAP.md` returns no matches (the old require() pattern is gone)
- `grep '\.sh handler' .planning/PROJECT.md` returns no matches (changed to .js)
- `grep 'Pending' .planning/PROJECT.md` returns only the 4 genuinely pending decisions (event folder, PreToolUse, verification loop, full-stack delivery)
- `grep -c 'Cross-platform' .planning/PROJECT.md` returns 0 (replaced with Linux-targeted)
- `grep '\- \[x\] 01.1-01' .planning/ROADMAP.md` returns a match (checkbox checked)
  </verify>
  <done>REQUIREMENTS.md shows REG-01 as Complete/Phase 1. ROADMAP.md uses ESM import pattern and has checked plan boxes. PROJECT.md reflects .js handlers, implemented decisions, and Linux-targeted platform scope. All four drifted documents are accurate for Phase 2 planning.</done>
</task>

</tasks>

<verification>
1. AUDIT.md exists and contains all 11 REV-3.x finding IDs
2. REQUIREMENTS.md REG-01 row says "Complete" and "Phase 1"
3. ROADMAP.md Phase 2 criterion #1 uses `import()` not `require()`
4. ROADMAP.md Phase 01.1 plan checkboxes are `[x]`
5. PROJECT.md has no `.sh handler` references in target features
6. PROJECT.md Key Decisions has 4 implemented outcomes and 4 pending
7. PROJECT.md says "Linux-targeted" not "Cross-platform"
</verification>

<success_criteria>
- AUDIT.md is a complete, self-contained record of Phase 01.1 completeness
- All four tracking documents are accurate for Phase 2 planning
- No stale require() patterns, no stale .sh handler references, no stale Pending statuses for completed work
</success_criteria>

<output>
After completion, create `.planning/quick/2-audit-phase-01-1-completeness-against-co/2-SUMMARY.md`
</output>
