---
phase: quick-27
status: complete
commit: 1c881da
date: 2026-03-05
---

# Quick Task 27: Add Per-Session Auto-Drive Hooks Toggle

## What Was Done

Added a per-session pause flag that disables auto-drive behavior (TUI typing and gateway wakes) while keeping hook event logging intact.

### Files Created

- **`lib/pause-state.mjs`** — Core library with `isSessionPaused()`, `setSessionPauseState()`, and `PAUSE_STATE_FILE_PATH` exports. File-backed state in `logs/pause-state.json`. Fail-open reads (missing/corrupt = unpaused). Atomic writes (tmp+rename).

- **`bin/pause-session.mjs`** — Executable CLI: `pause-session.mjs <session> <on|off|status>`

### Files Modified

- **`lib/hook-context.mjs`** — Added pause gate at step 2.5 (after agent resolution, before stdin read). When paused, logs one entry and returns `null` — all 5 event handlers get pause behavior with zero handler file changes.

- **`lib/index.mjs`** — Added re-exports for `isSessionPaused` and `setSessionPauseState`.

### Key Design Decisions

- **DRY**: Pause gate lives in ONE place (`readHookContext`) — zero handler duplication
- **Fail-open**: Corrupt or missing state file = unpaused (never blocks hooks)
- **Atomic writes**: tmp+rename pattern (same as `writeQueueFileAtomically`)
- **Zero-noise reads**: `isSessionPaused` does not log (runs every hook invocation)
- **Warden integration path**: Documented in plan with concrete API endpoint, React hook, and UI toggle examples

## Verification

```
$ node bin/pause-session.mjs test-session on
Session 'test-session' paused.
$ node bin/pause-session.mjs test-session status
Session 'test-session' is paused.
$ node bin/pause-session.mjs test-session off
Session 'test-session' unpaused.
$ node bin/pause-session.mjs test-session status
Session 'test-session' is not paused.
$ node --check lib/pause-state.mjs && node --check lib/hook-context.mjs && node --check bin/pause-session.mjs
(all pass)
```
