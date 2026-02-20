# Quick Task 5: Update ROADMAP.md — fix stale .js extensions to .mjs

## What Changed

### ROADMAP.md — Phase 3 Success Criteria (5 lines)
1. `event_stop.js` → `event_stop.mjs`
2. `tui_driver_stop.js` → `bin/tui-driver.mjs` (generic driver, per CONTEXT.md locked decision)
3. Updated criteria #4 to describe queue-based TUI driver architecture instead of per-event driver

### ROADMAP.md — Phase 4 Success Criteria (4 lines)
1. `event_ask_user_question.js` → `event_ask_user_question.mjs`
2. `tui_driver_ask_user_question.js` → `tui_driver_ask_user_question.mjs`
3. `event_post_ask_user_question.js` → `event_post_ask_user_question.mjs`

### REQUIREMENTS.md (2 lines)
1. **ARCH-04**: `event_{name}.js` → `event_{name}.mjs`
2. **TUI-01**: Rewritten from per-event `tui_driver_{event_name}.js` to generic `bin/tui-driver.mjs` architecture

## Why

Phase 3 plan checker identified these as blockers: ROADMAP.md was written before the discuss-phase session that locked the `.mjs` extension convention and generic TUI driver architecture. Plans correctly implemented CONTEXT.md decisions, but ROADMAP/REQUIREMENTS text was stale.

## Files Modified
- `.planning/ROADMAP.md`
- `.planning/REQUIREMENTS.md`
