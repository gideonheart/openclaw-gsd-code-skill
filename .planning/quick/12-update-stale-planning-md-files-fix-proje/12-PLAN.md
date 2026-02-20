---
phase: quick-12
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/PROJECT.md
  - .planning/REQUIREMENTS.md
autonomous: true
requirements: [CLEAN-07]
must_haves:
  truths:
    - "PROJECT.md accurately reflects current state — no stale references to flock, .js extensions, or pending outcomes that are actually implemented"
    - "REQUIREMENTS.md checkboxes match traceability table status — no contradictions between checkbox and table"
    - "Both files show correct last-updated date"
  artifacts:
    - path: ".planning/PROJECT.md"
      provides: "Accurate project description with current architecture decisions"
      contains: ".mjs"
    - path: ".planning/REQUIREMENTS.md"
      provides: "Consistent requirement tracking"
      contains: "[x] **REG-01**"
  key_links:
    - from: ".planning/PROJECT.md"
      to: ".planning/ROADMAP.md"
      via: "Key Decisions outcomes match roadmap phase completion"
      pattern: "Implemented"
---

<objective>
Fix 6 stale issues in PROJECT.md and 1 inconsistency in REQUIREMENTS.md so both files accurately reflect the current state after Phase 03 completion.

Purpose: Planning docs that contradict reality cause confusion in future phases. Phase 04 planning will reference these files.
Output: Updated PROJECT.md and REQUIREMENTS.md with all corrections applied.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/REQUIREMENTS.md
@.planning/ROADMAP.md
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix all 6 PROJECT.md issues</name>
  <files>.planning/PROJECT.md</files>
  <action>
Read `.planning/PROJECT.md` and apply these 6 targeted fixes:

1. **Line 17 — .js to .mjs extension**: Change `event_{descriptive_name}.js` to `event_{descriptive_name}.mjs`. This is in the "Target features" bullet list.

2. **Lines 26, 73, 81 — Remove flock references**: flock was replaced by O_APPEND atomic writes in Phase 02 (decision 02-01 in STATE.md). Three locations:
   - Line 26: "Linux-targeted (Ubuntu 24 — tmux, flock, bash are Linux-only dependencies...)" — remove "flock, " from the parenthetical, keeping tmux and bash
   - Line 73: "Linux-targeted: Runs on Ubuntu 24 under the forge user. tmux and flock are Linux-only dependencies." — remove "and flock" from the sentence
   - Line 81: "Linux-targeted: The runtime depends on tmux, flock, and bash." — change to "The runtime depends on tmux and bash."

3. **Lines 88-93 — Key Decisions table "Pending" outcomes**: Update three rows that say "Pending" but are now implemented:
   - `events/{event_name}/` folder structure: Change "— Pending" to "Implemented — Phase 3 created events/stop/, events/session_start/, events/user_prompt_submit/"
   - Full-stack delivery per event: Change "— Pending" to "Implemented — Phase 3 delivered handler + prompt + TUI driver for Stop"
   - Node.js for all handlers: Change "— Pending" to "Adopted — all event handlers are .mjs (Phase 1-3)" (note: this row might already partially say Adopted, update the outcome to reflect full implementation)

4. **Lines 44-53 — Active requirements checkboxes**: Check off items that are done:
   - `[ ] Event-folder architecture with handler + prompt per event` -> `[x]` (Phase 3)
   - `[ ] Agent resolution from structured JSON session field via agent-registry.json` -> `[x]` (Phase 2)
   - `[ ] OpenClaw gateway delivery with last_assistant_message + prompt` -> `[x]` (Phase 2)
   - `[ ] Stop event handler: wake agent with response content, agent picks GSD command` -> `[x]` (Phase 3)
   - `[ ] Shared lib for agent resolution, gateway delivery, JSON field extraction` -> `[x]` (Phase 2)
   - `[ ] Delete all v1.0-v3.2 hook scripts, prompts, and dead code` -> `[x]` (Phase 1)

5. **Line 97 — Last updated date**: Change "Last updated: 2026-02-19" to "Last updated: 2026-02-20"

6. **Also update line 97 context**: Change "after v4.0 milestone start" to "after Phase 03 completion" to reflect actual state.

Do NOT change any other content. Preserve all formatting, spacing, and markdown structure.
  </action>
  <verify>
Verify all 6 fixes applied:
- `grep -c '.mjs' .planning/PROJECT.md` shows handler extension is .mjs
- `grep -c 'flock' .planning/PROJECT.md` returns 0 (no flock references remain)
- `grep -c 'Pending' .planning/PROJECT.md` returns 0 in Key Decisions table (only "Pending" should be in Active requirements for items still undone)
- `grep -c '\[x\]' .planning/PROJECT.md` shows the correct number of checked items
- `grep '2026-02-20' .planning/PROJECT.md` shows updated date
  </verify>
  <done>All 6 PROJECT.md issues are fixed: .mjs extension, no flock references, Key Decisions outcomes updated, active requirements checked off, date updated</done>
</task>

<task type="auto">
  <name>Task 2: Fix REQUIREMENTS.md REG-01 checkbox inconsistency</name>
  <files>.planning/REQUIREMENTS.md</files>
  <action>
Read `.planning/REQUIREMENTS.md` and apply this single fix:

1. **Line 42 — REG-01 checkbox**: Change `- [ ] **REG-01**:` to `- [x] **REG-01**:` — the traceability table at line 108 already says "Complete" for REG-01, so the checkbox must match.

Also update the "Last updated" line at the bottom to "2026-02-20" with note "REG-01 checkbox fixed to match traceability table".

Do NOT change any other content.
  </action>
  <verify>
- `grep 'REG-01' .planning/REQUIREMENTS.md` shows `[x]` checkbox
- `grep '2026-02-20' .planning/REQUIREMENTS.md` shows updated date
- Confirm traceability table still says "Complete" for REG-01 (no regression)
  </verify>
  <done>REG-01 checkbox is [x] matching the "Complete" status in the traceability table, last-updated date reflects the change</done>
</task>

</tasks>

<verification>
- PROJECT.md: zero occurrences of "flock", zero "Pending" in Key Decisions table, .mjs extension for handlers, 6 checked active requirements, date is 2026-02-20
- REQUIREMENTS.md: REG-01 has [x] checkbox, traceability table unchanged, date is 2026-02-20
- Both files have no unintended changes (diff should show only the targeted lines)
</verification>

<success_criteria>
Both .planning/PROJECT.md and .planning/REQUIREMENTS.md accurately reflect post-Phase-03 reality with no internal contradictions. All 7 issues (6 + 1) resolved.
</success_criteria>

<output>
After completion, create `.planning/quick/12-update-stale-planning-md-files-fix-proje/12-SUMMARY.md`
</output>
