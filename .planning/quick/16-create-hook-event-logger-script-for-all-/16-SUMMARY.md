---
phase: quick-16
plan: 01
subsystem: hooks
tags: [bash, jq, hooks, logging, debug, claude-code, tmux, flock]

# Dependency graph
requires:
  - phase: quick-5
    provides: per-session log file pattern in logs/ directory
  - phase: quick-14
    provides: hook preamble and debug_log infrastructure
provides:
  - Universal hook event logger (hook-event-logger.sh) capturing raw stdin JSON for all 15 events
  - Registration script (register-all-hooks-logger.sh) adding logger to all 15 events additively
  - settings.json updated with logger registered for all 15 Claude Code hook events
affects: [hook-development, payload-inspection, warden-main-4]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "flock-based atomic append to .jsonl files (matches hook-utils.sh write_hook_event_record pattern)"
    - "trap 'exit 0' ERR — safety net for debug scripts that must never crash Claude Code"
    - "(.hooks.EventName // []) + [$new_rule] jq pattern for additive hook registration"
    - "per-session -raw-events.jsonl alongside -raw-events.lock for structured event inspection"

key-files:
  created:
    - scripts/hook-event-logger.sh
    - scripts/register-all-hooks-logger.sh
  modified:
    - ~/.claude/settings.json (19 logger entries added across 15 events)

key-decisions:
  - "Logger catch-all (no matcher) for PreToolUse and PostToolUse — fires for ALL tool uses alongside existing AskUserQuestion matcher"
  - "Notification event gets 5 logger entries: auth_success, permission_prompt, idle_prompt, elicitation_dialog matchers plus catch-all"
  - "flock for atomic JSONL append — same pattern as write_hook_event_record in hook-utils.sh"
  - "SESSION_NAME falls back to no-tmux when not in tmux — logger works in direct invocation too"
  - "trap 'exit 0' ERR wraps entire body — debug logger can never crash Claude Code sessions"

patterns-established:
  - "Debug logger pattern: source preamble, consume stdin, detect session, log to .log + append to .jsonl"
  - "Additive hook registration: (.hooks.X // []) + [$new_rule] never overwrites existing entries"

requirements-completed: [QUICK-16]

# Metrics
duration: 2min
completed: 2026-02-19
---

# Quick Task 16: Hook Event Logger Summary

**Universal raw stdin JSON logger registered for all 15 Claude Code hook events via additive jq merge, with per-session .log and .jsonl output files**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-02-19T16:24:44Z
- **Completed:** 2026-02-19T16:26:56Z
- **Tasks:** 2
- **Files modified:** 2 created, 1 modified (settings.json)

## Accomplishments

- Created `hook-event-logger.sh` — universal logger sourcing hook-preamble.sh, consuming stdin JSON, writing pretty-printed entry to per-session `.log` and compact JSONL record to per-session `-raw-events.jsonl`
- Created `register-all-hooks-logger.sh` — clears logs/, backups settings.json, appends logger rule for all 15 events using additive jq merge that preserves all existing GSD hooks
- All 15 hook events now registered in `~/.claude/settings.json`: 7 events with GSD+logger, 8 new events with logger only; Notification gets 5 logger entries (4 matchers + catch-all)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create universal hook event logger script** - `bb93ff9` (feat)
2. **Task 2: Create registration script and clear logs** - `df2a8b9` (feat)

**Plan metadata:** (included in this commit)

## Files Created/Modified

- `scripts/hook-event-logger.sh` — Sources preamble, reads stdin, extracts event name via jq, detects tmux session (falls back to "no-tmux"), logs structured entry to `{session}.log`, appends JSONL record to `{session}-raw-events.jsonl` via flock; trap ensures exit 0 always
- `scripts/register-all-hooks-logger.sh` — Clears `logs/*.{log,jsonl,lock,txt}`, backups settings.json, builds logger rule with jq, runs single jq merge adding logger to all 15 events preserving existing hooks, validates JSON, atomic mv replace, prints verification summary
- `~/.claude/settings.json` — 19 logger entries added across 15 events (15 unique events now registered)

## Decisions Made

- Logger uses catch-all (no matcher) for PreToolUse and PostToolUse so it fires for ALL tool uses, not just AskUserQuestion — complementary to existing GSD hooks
- Notification gets 5 logger entries: one for each known subtype matcher (auth_success, permission_prompt, idle_prompt, elicitation_dialog) plus one catch-all to capture any unknown subtypes
- `flock` for atomic JSONL append matches the existing `write_hook_event_record` pattern in `hook-utils.sh`
- `trap 'exit 0' ERR` wraps the full logger body — debug tools must never crash live Claude Code sessions
- SESSION_NAME falls back to "no-tmux" when tmux is unavailable — makes logger safe outside tmux

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. Both scripts created, verified, and registered successfully on first run.

## User Setup Required

None — settings.json already updated. Restart Claude Code sessions to activate the new hooks.

## Next Phase Readiness

- Ready: `warden-main-4` session can now trigger hooks and raw JSON payloads will be captured
- Inspect payloads with: `cat /home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/warden-main-4.log`
- Or structured JSONL: `cat /home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/warden-main-4-raw-events.jsonl | jq .`

---
*Phase: quick-16*
*Completed: 2026-02-19*
