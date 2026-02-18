# Plan 13-02 Summary: Migrate Pre-Compact and Session-End Hooks

**Phase:** 13-coordinated-hook-migration
**Plan:** 02
**Status:** Complete
**Duration:** ~2 min

## What was built

Migrated pre-compact-hook.sh and session-end-hook.sh to use the shared library chain.

Pre-compact-hook.sh:
- Source hook-preamble.sh instead of duplicated preamble
- Call extract_hook_settings() instead of inline settings (which also lacked 2>/dev/null)
- Call detect_session_state() replacing divergent case-sensitive patterns — state names normalized: idle_prompt -> idle, active -> working
- Use [CONTENT] label instead of [PANE CONTENT]
- Use printf '%s' for all jq and pipe operations
- Added 2>/dev/null error guards to bare jq calls

Session-end-hook.sh:
- Source hook-preamble.sh instead of duplicated preamble
- Added 2>/dev/null error guards to all jq calls (FIX-03)
- Use printf '%s' for all jq piping

## Key files

### Modified
- `scripts/pre-compact-hook.sh` — migrated with state detection normalization
- `scripts/session-end-hook.sh` — migrated with jq error guards (FIX-03)

## Verification

All checks passed:
- Both source hook-preamble.sh
- Neither sources hook-utils.sh directly
- pre-compact uses [CONTENT] not [PANE CONTENT]
- pre-compact uses detect_session_state() with standard state names
- session-end has 0 unguarded jq calls
- Zero echo-to-jq patterns
- Both pass bash -n syntax validation

## Requirements addressed

- MIGR-03: pre-compact-hook.sh uses [CONTENT]
- FIX-03: session-end-hook.sh jq calls have 2>/dev/null error guards
- REFAC-03: Both hooks source hook-preamble.sh (partial — 4/7 hooks)
- QUAL-01: Both hooks use printf for jq piping (partial — 4/7 hooks)
