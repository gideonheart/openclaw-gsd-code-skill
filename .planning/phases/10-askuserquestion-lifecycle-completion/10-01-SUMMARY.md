---
phase: 10-askuserquestion-lifecycle-completion
plan: 01
subsystem: infra
tags: [bash, hooks, jsonl, claude-code-hooks, posttooluse, pretooluse, askuserquestion]

# Dependency graph
requires:
  - phase: 09-hook-script-migration
    provides: deliver_async_with_logging, write_hook_event_record, extra_fields_json 13th param, JSONL skeleton for all 6 hook scripts
provides:
  - post-tool-use-hook.sh: PostToolUse hook that fires after AskUserQuestion completes and logs answer_selected + tool_use_id
  - pre-tool-use-hook.sh: extended with tool_use_id field in EXTRA_FIELDS_JSON (alongside existing questions_forwarded)
  - register-hooks.sh: PostToolUse AskUserQuestion registration alongside PreToolUse
  - settings.json: PostToolUse hook registered via register-hooks.sh
affects:
  - 11-phase (any future phases using AskUserQuestion lifecycle JSONL data)
  - gideon-agent (receives ask_user_question_answered wake messages after answer submitted)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PostToolUse hook follows identical 7-section skeleton as all other hook scripts"
    - "Defensive multi-shape jq extractor for tool_response handles object or string shapes pending empirical validation"
    - "Lifecycle linking via shared tool_use_id field in both PreToolUse and PostToolUse JSONL records"

key-files:
  created:
    - scripts/post-tool-use-hook.sh
  modified:
    - scripts/pre-tool-use-hook.sh
    - scripts/register-hooks.sh

key-decisions:
  - "Defensive multi-shape tool_response extractor used (handles object .content/.text and plain string) pending empirical validation of AskUserQuestion PostToolUse stdin schema"
  - "Raw stdin logged via debug_log raw_stdin for ASK-05 empirical validation requirement — intentionally verbose in Phase 10, can be reduced in future phase once schema confirmed"
  - "PostToolUse wake message to OpenClaw included for symmetry and audit completeness despite firing after answer already submitted"
  - "PostToolUse timeout=10 (same as PreToolUse) since hook backgrounds immediately; 10s covers script execution, not the async openclaw call"
  - "HOOK_SCRIPTS array comment changed from stale 5 count to generic all hook scripts to avoid future staleness"

patterns-established:
  - "Pattern: All new hook scripts source lib/hook-utils.sh before guard exits"
  - "Pattern: tool_use_id extracted via jq -r '.tool_use_id // \"\"' 2>/dev/null || echo \"\" in both Pre and PostToolUse hooks"
  - "Pattern: EXTRA_FIELDS_JSON extended with --arg chaining in jq -cn for multi-field extra data"

requirements-completed: [ASK-05, ASK-06]

# Metrics
duration: 3min
completed: 2026-02-18
---

# Phase 10 Plan 01: AskUserQuestion Lifecycle Completion Summary

**AskUserQuestion lifecycle audit trail completed with PostToolUse hook logging answer_selected via shared tool_use_id for question-to-answer JSONL correlation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-18T13:21:38Z
- **Completed:** 2026-02-18T13:24:30Z
- **Tasks:** 3
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments

- Extended `pre-tool-use-hook.sh` to extract and include `tool_use_id` in PreToolUse JSONL records alongside existing `questions_forwarded` (ASK-06 PreToolUse side, ASK-04 preserved)
- Created `post-tool-use-hook.sh` following the established 7-section hook skeleton — fires after AskUserQuestion completes, logs `answer_selected` and `tool_use_id`, logs raw stdin for empirical validation of tool_response schema (ASK-05)
- Registered PostToolUse hook in `register-hooks.sh` alongside PreToolUse with AskUserQuestion matcher, verified live registration produces correct settings.json entry

## Task Commits

Each task was committed atomically:

1. **Task 1: Add tool_use_id extraction to pre-tool-use-hook.sh JSONL record** - `aab8677` (feat)
2. **Task 2: Create post-tool-use-hook.sh for AskUserQuestion answer logging** - `8ac4aaf` (feat)
3. **Task 3: Register PostToolUse hook in register-hooks.sh** - `e49166a` (feat)

## Files Created/Modified

- `scripts/post-tool-use-hook.sh` - New PostToolUse hook: extracts tool_use_id and answer_selected from stdin, logs raw stdin for schema validation, delivers async via deliver_async_with_logging with JSONL record
- `scripts/pre-tool-use-hook.sh` - Extended EXTRA_FIELDS_JSON with tool_use_id field alongside existing questions_forwarded; adds extraction line and debug_log
- `scripts/register-hooks.sh` - Added post-tool-use-hook.sh to HOOK_SCRIPTS array; added PostToolUse section to HOOKS_CONFIG heredoc; added .hooks.PostToolUse to jq merge; added PostToolUse verification output; updated top comment to list all 7 hook events

## Decisions Made

- Defensive multi-shape `tool_response` extractor chosen for `ANSWER_SELECTED`: handles both `object` (`.content // .text // tostring`) and `string` shapes — AskUserQuestion PostToolUse stdin schema is MEDIUM confidence pending empirical validation from a live session log
- Raw stdin logging via `debug_log "raw_stdin: ..."` included intentionally for ASK-05 empirical validation requirement — can be reduced to byte count in a future phase once schema confirmed
- PostToolUse wake message to OpenClaw included (not JSONL-only) for symmetry with PreToolUse pattern and for audit completeness in Gideon's conversation history
- `HOOK_SCRIPTS` array comment updated from stale "5 hook scripts" to "all hook scripts" to prevent future staleness as hook count grows

## Deviations from Plan

None — plan executed exactly as written. All four register-hooks.sh changes (HOOK_SCRIPTS array, HOOKS_CONFIG heredoc, jq merge, verification output) applied as specified.

## Issues Encountered

None.

## User Setup Required

None — `register-hooks.sh` was run during Task 3 verification and automatically updated `~/.claude/settings.json` with the PostToolUse hook. Existing Claude Code sessions must be restarted to activate the new hook.

## Next Phase Readiness

- PostToolUse hook is registered and will fire on next Claude Code AskUserQuestion invocation in a managed session
- Raw stdin logging is in place — read `logs/{session-name}.log` after triggering an AskUserQuestion to see actual `tool_response` structure for AskUserQuestion (empirical validation of ASK-05 schema)
- Once `tool_response` schema is confirmed from a live session log, the defensive multi-shape extractor in `post-tool-use-hook.sh` section 5 can be narrowed to the specific field path
- Phase 10 requirements ASK-05 and ASK-06 are fully satisfied; lifecycle linking query works: `jq --arg id "toolu_..." 'select(.tool_use_id == $id)' logs/session.jsonl`

---
*Phase: 10-askuserquestion-lifecycle-completion*
*Completed: 2026-02-18*

## Self-Check: PASSED

- FOUND: scripts/post-tool-use-hook.sh
- FOUND: scripts/pre-tool-use-hook.sh
- FOUND: scripts/register-hooks.sh
- FOUND: .planning/phases/10-askuserquestion-lifecycle-completion/10-01-SUMMARY.md
- FOUND commit: aab8677 (Task 1)
- FOUND commit: 8ac4aaf (Task 2)
- FOUND commit: e49166a (Task 3)
