---
phase: quick-21
plan: 01
subsystem: lib
tags: [dry, refactor, paths, queue-processor, ask-user-question, hook-context]
dependency_graph:
  requires: []
  provides: [canonical-path-helpers-in-paths-mjs, tmux-guard-in-hook-context]
  affects: [lib/paths.mjs, lib/queue-processor.mjs, lib/ask-user-question.mjs, lib/hook-context.mjs]
tech_stack:
  added: []
  patterns: [single-source-of-truth-for-path-helpers, guard-clause-first]
key_files:
  created: []
  modified:
    - lib/paths.mjs
    - lib/queue-processor.mjs
    - lib/ask-user-question.mjs
    - lib/hook-context.mjs
decisions:
  - "QUEUES_DIRECTORY and resolvePendingAnswerFilePath now defined exactly once in lib/paths.mjs — canonical home for all path constants"
  - "TMUX guard committed to hook-context.mjs — was in working tree but uncommitted; correct position as first check before tmux display-message"
metrics:
  duration: "1 min"
  completed_date: "2026-02-23"
  tasks_completed: 2
  files_modified: 4
---

# Quick Task 21: DRY Refactor — Move resolvePendingAnswerFilePath and QUEUES_DIRECTORY to paths.mjs

**One-liner:** Eliminated DRY violations by consolidating QUEUES_DIRECTORY and resolvePendingAnswerFilePath into lib/paths.mjs, and committed the pre-existing TMUX guard fix to hook-context.mjs.

## What Was Done

### Task 1: Move QUEUES_DIRECTORY and resolvePendingAnswerFilePath to paths.mjs

Both `lib/queue-processor.mjs` and `lib/ask-user-question.mjs` had identical local definitions of `QUEUES_DIRECTORY` and `resolvePendingAnswerFilePath`. The comment in queue-processor.mjs claimed this duplication was intentional to avoid a circular dependency — but that was incorrect: `paths.mjs` has no circular dependency with either module.

Changes made:

**lib/paths.mjs:**
- Added `resolve` to the `node:path` import
- Added `export const QUEUES_DIRECTORY = resolve(SKILL_ROOT, 'logs', 'queues')`
- Added `export function resolvePendingAnswerFilePath(sessionName)` with JSDoc
- Updated module-level JSDoc to document the new exports

**lib/queue-processor.mjs:**
- Changed import from `{ SKILL_ROOT }` to `{ QUEUES_DIRECTORY, resolvePendingAnswerFilePath }` from `./paths.mjs`
- Removed local `QUEUES_DIRECTORY` const (was line 21)
- Removed local `resolvePendingAnswerFilePath` function + misleading "duplicated intentionally" JSDoc (was lines 23-35)
- Removed `resolve` from `node:path` import (no longer needed locally); kept `dirname` (used by `writeQueueFileAtomically`)
- Removed `SKILL_ROOT` import (no longer needed)

**lib/ask-user-question.mjs:**
- Changed import to `{ SKILL_ROOT, QUEUES_DIRECTORY, resolvePendingAnswerFilePath }` from `./paths.mjs`
- Removed local `QUEUES_DIRECTORY` const (was line 27)
- Removed local `resolvePendingAnswerFilePath` function + JSDoc (was lines 39-47)
- Kept `resolve` and `dirname` in `node:path` import (both still used by remaining functions)
- Kept `SKILL_ROOT` import (used by `formatQuestionsForAgent` for `tui-driver-ask.mjs` path)

### Task 2: Confirm TMUX guard in hook-context.mjs

The TMUX guard (`if (!process.env.TMUX) return null;`) was present in the working tree but had not been committed to git. The committed HEAD was missing the guard.

The guard is correct:
- Position: line 31, first check inside `readHookContext`
- Purpose: prevents calling `tmux display-message` outside a tmux session (which would fail/crash)
- Order matches module JSDoc: "1. Check tmux (cheap, no stdin) -- bail if not in tmux"

The working tree fix was committed as part of this task (Rule 2: missing critical functionality).

## Verification Results

All verification checks passed:

```
paths OK: true
QUEUES_DIR OK: true
queue-processor OK: true
ask-user-question OK: true
barrel OK: true
hook-context loads OK: true
```

Definition count checks (only one definition of each):
- `resolvePendingAnswerFilePath`: defined once — `lib/paths.mjs:25`
- `QUEUES_DIRECTORY`: defined once — `lib/paths.mjs:17`
- TMUX guard: `lib/hook-context.mjs:31` as first check in `readHookContext`

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 2d8b4c3 | refactor(quick-21): move QUEUES_DIRECTORY + resolvePendingAnswerFilePath to paths.mjs |
| 2 | 9447c87 | fix(quick-21): add TMUX guard to readHookContext before tmux display-message call |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] TMUX guard was in working tree but uncommitted**
- **Found during:** Task 2 — verifying TMUX guard presence
- **Issue:** `git diff lib/hook-context.mjs` showed the guard was a working tree change not yet committed to git. The committed HEAD lacked the guard entirely, meaning `tmux display-message` would be called without checking `$TMUX` first.
- **Fix:** Committed the working tree fix as part of Task 2. The code was already correct — it just needed to be committed.
- **Files modified:** `lib/hook-context.mjs`
- **Commit:** 9447c87

## Self-Check: PASSED

- `lib/paths.mjs` exists and exports SKILL_ROOT, QUEUES_DIRECTORY, resolvePendingAnswerFilePath
- `lib/queue-processor.mjs` imports from paths.mjs, no local duplicates
- `lib/ask-user-question.mjs` imports from paths.mjs, no local duplicates
- `lib/hook-context.mjs` has TMUX guard committed
- Commits 2d8b4c3 and 9447c87 exist in git log
