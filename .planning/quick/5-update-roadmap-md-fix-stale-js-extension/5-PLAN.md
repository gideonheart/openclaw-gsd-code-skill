---
phase: quick-5
plan: "5"
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/ROADMAP.md
  - .planning/REQUIREMENTS.md
autonomous: true
requirements: []
---

<objective>
Update ROADMAP.md and REQUIREMENTS.md to fix stale references identified during Phase 3 plan verification. All `.js` handler extensions become `.mjs` (locked project convention), and Phase 3 success criteria reflect the generic `bin/tui-driver.mjs` architecture (locked CONTEXT.md decision).
</objective>

<tasks>

<task type="auto">
  <name>Task 1: Fix stale references in ROADMAP.md and REQUIREMENTS.md</name>
  <files>.planning/ROADMAP.md, .planning/REQUIREMENTS.md</files>
  <action>
ROADMAP.md Phase 3 success criteria:
- event_stop.js → event_stop.mjs
- tui_driver_stop.js → bin/tui-driver.mjs (generic driver)
- Update criteria text to reflect queue-based architecture

ROADMAP.md Phase 4 success criteria:
- All .js → .mjs extensions

REQUIREMENTS.md:
- ARCH-04: event_{name}.js → event_{name}.mjs
- TUI-01: per-event tui_driver → generic bin/tui-driver.mjs
  </action>
  <verify>grep -c "\.js" in success criteria sections should return 0 for handler files</verify>
  <done>All stale .js references updated to .mjs, tui_driver_stop.js replaced with bin/tui-driver.mjs throughout</done>
</task>

</tasks>
