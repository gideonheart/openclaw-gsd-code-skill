---
phase: 03-launcher-updates
plan: 02
subsystem: recovery
tags: [jq, registry, system-prompt, recovery, automation]
dependency_graph:
  requires:
    - RECOVER-01
    - RECOVER-02
  provides:
    - jq-only registry operations in recovery script
    - per-agent system prompt support via --append-system-prompt
    - failure-only Telegram notifications
    - retry-with-delay error handling
  affects:
    - scripts/recover-openclaw-agents.sh
tech_stack:
  added:
    - jq 1.7 for JSON manipulation (replacing Python)
    - printf %q for shell-safe prompt escaping
  patterns:
    - jq null coalescing with // operator
    - per-agent error handling without set -e
    - atomic registry validation
    - replacement-based system prompt composition
key_files:
  modified:
    - scripts/recover-openclaw-agents.sh
decisions:
  - "Use jq // \"\" null coalescing for all optional string fields"
  - "System prompt composition: agent prompt replaces default (not appends)"
  - "Retry delay set to 3 seconds for all recovery operations"
  - "Corrupt registry backed up with timestamp, fresh skeleton created"
  - "Telegram notifications backgrounded and async (fire-and-forget)"
metrics:
  duration: 2 minutes
  tasks_completed: 1
  files_modified: 1
  completed_date: 2026-02-17
---

# Phase 03 Plan 02: Registry-Driven Recovery with System Prompts Summary

Rewritten recover-openclaw-agents.sh to use pure jq for all registry operations, pass per-agent system prompts from registry to Claude via --append-system-prompt with fallback to default-system-prompt.txt, and implement failure-only Telegram reporting with retry logic.

## Execution Report

**Status:** Complete
**Duration:** 2 minutes
**Tasks Completed:** 1/1
**Commits:** 1

### Task Completion

| Task | Status | Files Modified | Commit |
|------|--------|----------------|--------|
| Task 1: Rewrite recover-openclaw-agents.sh with jq-only registry operations and system prompt support | Complete | scripts/recover-openclaw-agents.sh | ca07064 |

## Changes Summary

### Key Changes

1. **Replaced Python with jq** - All registry parsing now uses pure jq operations with `// ""` null coalescing for optional fields
2. **System prompt support** - Reads per-agent `system_prompt` from registry, passes via `--append-system-prompt` to Claude CLI
3. **Fallback to default** - Uses `config/default-system-prompt.txt` when agent has no system_prompt field (silent, no logging per CONTEXT.md)
4. **Per-agent error handling** - Removed `set -e`, wrapped each recovery step in conditional with one retry and 3-second delay
5. **Failure-only notifications** - Sends Telegram message via `openclaw agent` only when failures occur (silent on full success per CONTEXT.md locked decision)
6. **Robust registry handling** - Validates JSON with `jq empty`, backs up corrupt files with timestamp, creates fresh skeleton
7. **Improved session management** - Auto-starts tmux server if not running, appends `-2` suffix on name conflicts (doesn't kill existing)

### Code Removals

- Entire `parse_registry_to_json_lines()` Python function (lines 63-106)
- All `python3 -c` inline calls in main loop (lines 366-399)
- `require_binary python3` check (line 339)
- `--dry-run` flag and all dry_run_enabled parameters throughout
- `dry_run_enabled` parameter from all functions

### Code Additions

- `validate_registry_or_recreate()` - Validates JSON and handles corruption with backup + notification
- `start_tmux_server_if_needed()` - Auto-starts tmux server if not running
- System prompt composition logic - Reads agent `system_prompt`, falls back to default file
- `printf %q` escaping for safe prompt passing to Claude CLI
- Retry logic with 3-second delays on all recovery operations
- Failure tracking with diagnostic detail per agent
- Backgrounded Telegram notification on failures only

## Technical Details

### System Prompt Composition Model

Per CONTEXT.md locked decision: **Replacement model** (not append)

```bash
# Agent has custom prompt → use it exclusively (replaces default)
if [[ -n "${agent_system_prompt}" ]]; then
  final_system_prompt="${agent_system_prompt}"
else
  # No agent prompt → use default
  final_system_prompt="${default_system_prompt}"
fi
```

### Registry Operations Pattern

All registry reads use jq with null coalescing:

```bash
agent_system_prompt="$(echo "${agent_entry}" | jq -r '.system_prompt // ""')"
working_directory="$(echo "${agent_entry}" | jq -r '.working_directory // ""')"
```

Filtering enabled agents:

```bash
while IFS= read -r agent_entry; do
  # Process each agent...
done < <(jq -c '.agents[]' "${registry_path}" 2>/dev/null || echo "")
```

### Error Handling Pattern

No `set -e` in script header - allows per-agent error handling:

```bash
if ! ensure_tmux_session_exists "${tmux_session_name}" "${working_directory}"; then
  log_info "failed to ensure tmux session for ${agent_id}; retrying after 3s"
  sleep 3
  if ! ensure_tmux_session_exists "${tmux_session_name}" "${working_directory}"; then
    recovery_failed_for_agent="1"
    failure_reason="tmux session creation failed (retry exhausted)"
    # Continue to next agent...
  fi
fi
```

### Telegram Notification Pattern

Failure-only reporting (silent success):

```bash
if [[ "${failed_agent_count}" -gt 0 ]]; then
  local failure_details="Recovery failures:\n"
  for failure in "${failed_agents[@]}"; do
    failure_details+="- ${failure}\n"
  done
  openclaw agent --session-id "${global_status_openclaw_session_id}" --message "${failure_details}" >/dev/null 2>&1 &
fi
```

## Verification Results

All 10 verification checks passed:

1. Bash syntax validation: PASSED
2. Python references: 0 (no Python dependency)
3. Dry-run references: 0 (no dry-run flag)
4. jq usage: 15 instances (used throughout)
5. append-system-prompt: 2 instances (Claude CLI integration)
6. default-system-prompt: 1 instance (fallback reference)
7. system_prompt field: 15 instances (registry field extraction)
8. openclaw agent: 3 instances (Telegram notifications)
9. set flags: `set -uo pipefail` (no -e for per-agent error handling)
10. Retry delays: 5 instances (3-second delays for retry logic)

## Deviations from Plan

None - plan executed exactly as written.

## Success Criteria Met

- recover-openclaw-agents.sh has no Python dependency (zero python3 references)
- Per-agent system_prompt from registry passed via --append-system-prompt to Claude
- Falls back to default-system-prompt.txt when agent has no system_prompt (silent, no logging)
- Per-agent error handling with one retry and 3-second delay
- Telegram notification on failures only; silent on full success
- No --dry-run flag
- Corrupt registry backed up with timestamp and fresh skeleton created
- Uses jq with `// ""` null coalescing for all optional fields

## Key Learnings

1. **jq null coalescing is critical** - Using `// ""` prevents "null" strings and script failures
2. **printf %q for shell safety** - Essential for passing arbitrary prompt text to Claude CLI without injection risks
3. **Backgrounded notifications** - Using `>/dev/null 2>&1 &` ensures recovery doesn't block on Telegram API
4. **Replacement vs append** - CONTEXT.md locked decision overrides ROADMAP.md when in conflict

## Next Steps

This plan completes Phase 03 registry-driven recovery updates. The recovery script now:
- Has zero Python dependencies (jq-only)
- Supports per-agent system prompts from registry
- Implements robust error handling with retries
- Reports failures only (silent on success)

Next phase should focus on updating spawn.sh to match the same registry-driven, jq-only pattern.

## Self-Check: PASSED

Verified all claims:

```bash
# File exists
$ [ -f "scripts/recover-openclaw-agents.sh" ] && echo "FOUND"
FOUND

# Commit exists
$ git log --oneline --all | grep -q "ca07064" && echo "FOUND"
FOUND

# No Python references
$ grep -c 'python' scripts/recover-openclaw-agents.sh
0

# jq used throughout
$ grep -c 'jq ' scripts/recover-openclaw-agents.sh
15

# System prompt support
$ grep -c 'append-system-prompt' scripts/recover-openclaw-agents.sh
2
```

All verification checks passed.
