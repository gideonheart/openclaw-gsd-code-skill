---
phase: quick-25
plan: 25
subsystem: tui-driver
tags: [bug-fix, tui, tmux, keystrokes, polling]
dependency_graph:
  requires: []
  provides: [captureTmuxPaneContent export, adaptive TUI polling in tui-driver-ask]
  affects: [lib/tui-common.mjs, bin/tui-driver-ask.mjs]
tech_stack:
  added: []
  patterns: [tmux pane polling for TUI readiness detection]
key_files:
  created: []
  modified:
    - lib/tui-common.mjs
    - bin/tui-driver-ask.mjs
decisions:
  - "captureTmuxPaneContent uses execFileSync tmux capture-pane -p — consistent with existing send-keys pattern, no additional deps"
  - "waitForTuiContentToAppear is async but uses synchronous sleepMilliseconds (Atomics.wait) — matches existing lib pattern, no need for async delay"
  - "On tmux capture failure in polling loop: return immediately and proceed — session-gone is unrecoverable, better to attempt keystrokes than hang"
  - "Search string = questionMetadata.questions[0].question — the question title text is always present in the TUI when rendered"
metrics:
  duration: "2 min"
  completed_date: "2026-02-23"
  tasks_completed: 2
  files_modified: 2
---

# Quick Task 25: Fix TUI Driver Queue Command Args Lost and AskUserQuestion Timing

**One-liner:** Fix double-space argument drop in Tab autocomplete and replace fixed 3s keystroke delay with adaptive tmux pane polling.

## What Was Built

Two targeted bug fixes to the TUI driver pipeline:

1. **lib/tui-common.mjs** — Removed the leading space before `commandArguments` in `typeGsdCommandWithTabCompletion`. Tab autocomplete already appends a trailing space to the command name, so the explicit `' ' + commandArguments` created a double-space that caused Claude Code to drop the argument entirely (e.g. `/gsd:research-phase 18` would arrive as `/gsd:research-phase  18`). Also added `captureTmuxPaneContent()` export for tmux pane content polling.

2. **bin/tui-driver-ask.mjs** — Replaced the unreliable `PRE_KEYSTROKE_DELAY_MILLISECONDS = 3000` fixed sleep with `waitForTuiContentToAppear()`. This function polls `captureTmuxPaneContent()` every 250ms until the first question's text appears in the pane, with a 15s maximum timeout and graceful warn+proceed fallback. Keystrokes now fire as soon as the TUI renders rather than waiting a fixed 3 seconds.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Fix double-space in typeGsdCommandWithTabCompletion; add captureTmuxPaneContent | 5606e24 | lib/tui-common.mjs |
| 2 | Replace fixed delay with tmux pane polling in tui-driver-ask.mjs | f7eb36a | bin/tui-driver-ask.mjs |

## Verification Results

- Both files pass `node --check` syntax validation
- No double-space pattern (`' ' + commandArguments`) in tui-common.mjs
- No stale `PRE_KEYSTROKE_DELAY_MILLISECONDS` constant in tui-driver-ask.mjs
- All 5 expected exports present in tui-common.mjs: `captureTmuxPaneContent, sendKeysToTmux, sendSpecialKeyToTmux, sleepMilliseconds, typeCommandIntoTmuxSession`

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- `lib/tui-common.mjs` — exists and exports verified
- `bin/tui-driver-ask.mjs` — exists and polling function verified
- Commit `5606e24` — verified in git log
- Commit `f7eb36a` — verified in git log
