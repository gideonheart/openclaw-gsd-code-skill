# Plan 14-01 Summary: Fix diagnose-hooks.sh prefix-match and script list

**Phase:** 14-diagnostic-fixes
**Plan:** 01
**Status:** Complete
**Duration:** ~1 min

## What was built

Fixed two diagnostic accuracy bugs in diagnose-hooks.sh:

Step 7 (Registry Lookup):
- Replaced exact-match jq query (`.tmux_session_name == $session`) with prefix-match (`$session | startswith($agent.agent_id + "-")`)
- Pattern now identical to `lookup_agent_in_registry()` in lib/hook-utils.sh
- Sessions like "gideon-2" correctly resolve to agent "gideon" instead of false FAIL
- Also switched echo-to-jq to printf '%s' for consistency with Phase 13 cleanup

Step 2 (Hook Script Files):
- Added pre-tool-use-hook.sh and post-tool-use-hook.sh to HOOK_SCRIPTS array (5 -> 7 scripts)
- Missing tool-use hooks are now flagged as FAIL instead of silently ignored

## Key files

### Modified
- `scripts/diagnose-hooks.sh` — Step 7 prefix-match fix + Step 2 complete 7-script list

## Verification

All checks passed:
- `bash -n` syntax validation: PASS
- `startswith` present in Step 7 jq query
- Zero `tmux_session_name ==` exact-match patterns remain
- Both pre-tool-use-hook.sh and post-tool-use-hook.sh in HOOK_SCRIPTS array

## Requirements addressed

- FIX-01: diagnose-hooks.sh Step 7 uses startswith prefix-match (complete)
- FIX-02: diagnose-hooks.sh Step 2 checks all 7 hook scripts (complete)

## Self-Check: PASSED
