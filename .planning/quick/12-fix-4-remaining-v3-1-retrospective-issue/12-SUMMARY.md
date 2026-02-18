---
phase: quick-12
plan: 01
subsystem: hook-utils
tags: [refactor, dry, security, hooks, delivery]
dependency_graph:
  requires: [lib/hook-utils.sh, scripts/notification-idle-hook.sh, scripts/notification-permission-hook.sh, scripts/stop-hook.sh]
  provides: [deliver_with_mode() function, single jq template in write_hook_event_record]
  affects: [all bidirectional and async delivery paths, JSONL record writing]
tech_stack:
  added: []
  patterns: [bash array conditional args, jq -cn --arg for safe JSON construction]
key_files:
  modified:
    - lib/hook-utils.sh
    - scripts/notification-idle-hook.sh
    - scripts/notification-permission-hook.sh
    - scripts/stop-hook.sh
decisions:
  - deliver_with_mode() takes hook_mode as first parameter — function handles both bidirectional and async branches, hook scripts pass all parameters and rely on deliver_with_mode() to exit 0
  - extra_args bash array pattern for conditional jq --argjson — empty array expands to nothing, avoids if/else duplication while preserving identical runtime behavior
  - stale comment deleted entirely — no replacement note needed since Phase 13 fully migrated pre-compact to detect_session_state()
metrics:
  duration: 157 seconds
  completed: 2026-02-18
  tasks_completed: 2
  files_modified: 4
---

# Phase quick-12 Plan 01: Fix 4 Remaining v3.1 Retrospective Issues Summary

**One-liner:** Extracted deliver_with_mode() eliminating ~90 lines of triplicated delivery code, fixed JSON injection with jq --arg, deduped write_hook_event_record jq template, and deleted stale pre-compact comment.

## What Was Built

Four issues identified in Quick Tasks 10-11 were fixed in 2 tasks:

**Issue 1 (Delivery triplication):** ~35-line if/else delivery block existed identically in notification-idle-hook.sh, notification-permission-hook.sh, and stop-hook.sh. Extracted to `deliver_with_mode()` in lib/hook-utils.sh. Each hook now calls one function instead of containing duplicate logic.

**Issue 2 (JSON injection):** Bidirectional delivery responses used bare string interpolation: `echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"`. This allowed injection via `$REASON` containing quotes, backslashes, or newlines. Fixed by using `jq -cn --arg reason "$reason"` inside `deliver_with_mode()`. The fix lives in exactly one place.

**Issue 3 (write_hook_event_record duplication):** Two identical 28-line jq blocks existed — one for when `extra_fields_json` was non-empty and one for empty. Only difference was the `--argjson extra_fields` flag and `+ $extra_fields` merge. Replaced with a single jq invocation using a bash array (`extra_args`) for conditional flag passing and a string variable (`extra_merge`) for the conditional filter suffix.

**Issue 4 (Stale comment):** `detect_session_state()` docstring contained a "Note:" paragraph claiming pre-compact-hook.sh uses different patterns and may not use this function. Phase 13 fully migrated pre-compact-hook.sh to use `detect_session_state()`, making this comment false. Deleted.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Extract deliver_with_mode() and fix JSON injection | d8dd202 | lib/hook-utils.sh, notification-idle-hook.sh, notification-permission-hook.sh, stop-hook.sh |
| 2 | Deduplicate write_hook_event_record jq blocks and remove stale comment | 741e48c | lib/hook-utils.sh |

## Verification Results

1. All 4 files pass `bash -n` syntax check: PASS
2. Zero JSON injection vectors (`grep -rn 'echo.*{.*decision.*reason.*}'`): PASS — 0 matches
3. Zero delivery triplication (`grep -rn 'openclaw agent --session-id' scripts/notification-*.sh scripts/stop-hook.sh`): PASS — 0 matches
4. Zero stale pre-compact comments: PASS — 0 matches
5. Single jq template in write_hook_event_record: PASS — exactly 1 occurrence of `timestamp: \$timestamp`

## Deviations from Plan

None — plan executed exactly as written.

## Metrics

- Duration: ~3 minutes
- Tasks completed: 2/2
- Files modified: 4 (lib/hook-utils.sh, 3 hook scripts)
- Lines removed: ~117 (87 from hook scripts + 30 from write_hook_event_record if/else)
- Lines added: ~67 (deliver_with_mode function + extra_args pattern)
- Net reduction: ~50 lines

## Self-Check: PASSED

- lib/hook-utils.sh: FOUND
- scripts/notification-idle-hook.sh: FOUND
- scripts/notification-permission-hook.sh: FOUND
- scripts/stop-hook.sh: FOUND
- Commit d8dd202: FOUND
- Commit 741e48c: FOUND
