---
phase: 14-test-hooks
plan: 01
subsystem: testing
tags: [hooks, jsonl, tmux, prompts, v3.2]

requires:
  - phase: 16-hook-migration
    provides: v3.2 per-hook prompt templates and [ACTION REQUIRED] sections
  - phase: 15-prompt-templates
    provides: load_hook_prompt(), response-complete.md, idle-prompt.md templates

provides:
  - Automated end-to-end test script for v3.2 hook prompt verification
  - Registry pointing at correct running tmux session warden-main-4

affects:
  - Future hook changes (use test-hook-prompts.sh to verify correctness)
  - Registry maintenance (tmux_session_name must match actual running session)

tech-stack:
  added: []
  patterns:
    - "JSONL record polling: poll wc -l every 2s to detect new records without tail -f"
    - "Wake message string checks: grep -qF for literal string presence/absence in JSONL .wake_message"
    - "Idle hook detection: secondary JSONL poll loop, not a failure if timeout"

key-files:
  created:
    - scripts/test-hook-prompts.sh
  modified:
    - config/recovery-registry.json (gitignored — on disk only)

key-decisions:
  - "Registry file is gitignored (contains session IDs) — disk change confirmed but not committed to git"
  - "Idle hook step is INFO-only on timeout, not a FAIL — depends on Claude Code state"
  - "Test script polls wc -l every 2s (stop hook) and every 5s (idle hook) — avoids tail -f complexity"

patterns-established:
  - "Pattern: test script structure mirrors diagnose-hooks.sh (pass/fail/info helpers, step headers, summary block)"

requirements-completed: [QUICK-14]

duration: ~10min
completed: 2026-02-19
---

# Quick Task 14: Test Hooks Send Correct Prompts Summary

**Automated v3.2 hook prompt test script that triggers stop hook via /help, polls JSONL log for records, and validates [ACTION REQUIRED] sections and wake message structure**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-02-19T13:00:00Z
- **Completed:** 2026-02-19T13:10:18Z
- **Tasks:** 2 automated + 1 human-verify checkpoint
- **Files modified:** 2 (1 created, 1 disk-only)

## Accomplishments

- Updated registry `tmux_session_name` from `warden-main-3` to `warden-main-4` to match the running tmux session
- Cleared stale JSONL and log files for a clean test baseline
- Created `scripts/test-hook-prompts.sh` — 6-step end-to-end test covering: pre-flight, stop hook trigger, JSONL field validation, `[ACTION REQUIRED]` check, wake message structure, and idle hook (60s optional)

## Task Commits

1. **Task 1: Update registry and clear stale logs** - `e944f04` (chore — disk-only change, gitignored file)
2. **Task 2: Create automated hook prompt test script** - `0f28797` (feat)

## Files Created/Modified

- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/test-hook-prompts.sh` - 6-step automated end-to-end test for v3.2 hook prompts
- `config/recovery-registry.json` - warden tmux_session_name updated to warden-main-4 (disk only, gitignored)

## Decisions Made

- Registry file is gitignored because it contains `openclaw_session_id` secrets — disk change applied but no git commit for this file; used empty commit to record intent
- Idle hook verification is `INFO` on timeout, not a `FAIL` — the idle hook only fires when Claude Code enters an idle state, which cannot be forced reliably in a test
- Poll-based JSONL detection (every 2s for stop hook, every 5s for idle) avoids `tail -f` complexity and works well within the 30s / 60s timeout windows

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Empty commit for gitignored registry file**
- **Found during:** Task 1 (Update registry and clear stale logs)
- **Issue:** `config/recovery-registry.json` is gitignored (contains session IDs/secrets). `git add` failed with "ignored by .gitignore"
- **Fix:** Used `git commit --allow-empty` to record the intent and disk change. The file is correctly updated on disk and functions as expected.
- **Files modified:** config/recovery-registry.json (disk only)
- **Verification:** `jq '.agents[] | select(.agent_id == "warden") | .tmux_session_name'` returns `"warden-main-4"`

---

**Total deviations:** 1 auto-handled (gitignore constraint)
**Impact on plan:** No scope creep. Registry correctly points at warden-main-4 on disk.

## Issues Encountered

- `config/recovery-registry.json` is gitignored — the file was correctly updated on disk but could not be git-committed. This is by design (secrets). Empty commit used to mark task completion in git history.

## User Setup Required

Task 3 is a `checkpoint:human-verify` — run the test script to confirm all checks pass:

```bash
scripts/test-hook-prompts.sh
# or to skip the 60s idle wait:
scripts/test-hook-prompts.sh --skip-idle
```

Expected: all PASS checks green, zero FAIL, `ALL CRITICAL CHECKS PASSED` printed.

## Next Phase Readiness

- Test script exists at `scripts/test-hook-prompts.sh` and is executable
- Registry correctly points at `warden-main-4`
- Run `scripts/test-hook-prompts.sh` to confirm v3.2 prompt delivery end-to-end

---

## Self-Check

**Created files exist:**
- `scripts/test-hook-prompts.sh` — FOUND
- `config/recovery-registry.json` — FOUND (disk, gitignored)

**Commits exist:**
- `e944f04` — FOUND (empty commit for Task 1)
- `0f28797` — FOUND (Task 2 script creation)

## Self-Check: PASSED

---
*Phase: 14-test-hooks*
*Completed: 2026-02-19*
