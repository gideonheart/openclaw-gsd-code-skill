# Phase 03 Plan 01: Registry-Driven Launcher Summary

**One-liner:** Replaced Python-dependent spawn.sh with jq-only registry-driven launcher accepting agent-name as primary key with automatic entry creation and replacement-model system prompt composition

---

## Frontmatter

```yaml
phase: 03-launcher-updates
plan: 01
subsystem: session-launcher
tags: [refactor, jq, registry, launcher, system-prompt]

dependency_graph:
  requires:
    - Phase 01 (recovery-registry.json schema with system_prompt field)
    - Phase 01 (default-system-prompt.txt)
  provides:
    - Registry-driven spawn.sh with jq-only operations
    - Agent-name as primary key with auto-create behavior
    - System prompt composition (CLI > registry > default)
  affects:
    - All scripts that launch Claude Code sessions
    - recover-openclaw-agents.sh (will need similar jq conversion in Phase 03 Plan 02)

tech_stack:
  added:
    - jq 1.7 for JSON manipulation (replaced Python)
  patterns:
    - Atomic registry writes (.tmp + mv)
    - Three-tier system prompt fallback (CLI > agent > default)
    - Tmux session name conflict resolution (-2 suffix)

key_files:
  created: []
  modified:
    - scripts/spawn.sh (complete rewrite: 273 lines changed, 231 removed)

decisions:
  - System prompt replacement model (agent overrides default entirely, not append) per CONTEXT.md locked decision
  - Auto-create registry entries for unknown agents with sensible defaults (enabled=true, auto_wake=true, topic_id=1)
  - Session name conflict resolution: append -2 suffix instead of failing
  - Inline system_prompt only in registry (no file path references) for simplicity

metrics:
  duration_seconds: 100
  duration_display: "1 min 40 sec"
  tasks_completed: 1
  commits: 1
  files_modified: 1
  lines_changed: 504
  completed_at: "2026-02-17T14:45:52Z"
```

---

## Overview

### What Was Built

Completely rewrote `scripts/spawn.sh` to eliminate Python dependency and simplify CLI interface. The new launcher:

1. **Registry-driven with agent-name as primary key**: Single positional argument replaces 5 optional flags
2. **jq-only JSON operations**: Replaced 75 lines of Python upsert logic with functional jq patterns
3. **Three-tier system prompt composition**: CLI override > registry agent prompt > default file (replacement model per CONTEXT.md)
4. **Auto-create unknown agents**: New agents get sensible defaults in registry automatically
5. **Removed all legacy code**: strict_prompt() function, autoresponder logic, --prd/--agent-id/--topic-id/--auto-wake flags deleted

### Why It Matters

- **Zero Python dependency**: OpenClaw agents can execute spawn.sh directly without Python interpreter
- **Simplified interface**: 7 CLI flags reduced to 3 positional args + 1 optional flag
- **Registry-driven config**: All agent settings centralized in recovery-registry.json
- **Per-agent customization**: Different agents can have different system prompts, working directories, launch commands
- **Predictable failure handling**: Session name conflicts resolved gracefully with -2 suffix

---

## Tasks Completed

### Task 1: Rewrite spawn.sh as registry-driven jq-only launcher

**Commit:** 72f3672

**Changes:**
- Complete script rewrite (273 lines added, 231 removed)
- Replaced Python `upsert_recovery_registry_entry()` function with jq functional operations
- New CLI interface: `<agent-name> <workdir> [first-command] [--system-prompt <value>]`
- Implemented registry lookup by agent_id with auto-create for unknown agents
- System prompt composition with three-tier fallback (CLI > registry > default file)
- Auto-detection for --system-prompt: file path vs inline text
- Atomic registry writes via .tmp + mv pattern
- Tmux session name conflict resolution with -2 suffix
- Deleted legacy code:
  - `strict_prompt()` function (content moved to default-system-prompt.txt in Phase 1)
  - `derive_agent_id_from_session_name()` function (agent-name now explicit CLI arg)
  - `upsert_recovery_registry_entry()` Python function
  - All autoresponder launch logic and --autoresponder flag
  - --prd flag and PRD resolution logic
  - --agent-id, --topic-id, --auto-wake flags

**Verification Results:**
- Syntax validation: PASS
- No Python references: PASS (0 matches)
- No autoresponder: PASS (0 matches)
- No strict_prompt: PASS (0 matches)
- jq is used: PASS (7 matches)
- --append-system-prompt: PASS (1 match)
- default-system-prompt referenced: PASS (1 match)
- No --prd flag: PASS (0 matches)
- No --agent-id flag: PASS (0 matches)
- No --topic-id flag: PASS (0 matches)
- Atomic write pattern: PASS (.tmp file present)

**Key Functions Added:**
- `resolve_skill_root_directory()` - Get script base path
- `ensure_registry_exists()` - Create registry if missing
- `validate_registry_json()` - Backup corrupt registry, create fresh skeleton
- `read_agent_entry_from_registry()` - jq lookup by agent_id
- `upsert_agent_entry_in_registry()` - jq upsert with atomic write
- `compose_system_prompt()` - Three-tier fallback composition
- `resolve_tmux_session_name()` - Conflict resolution with -2 suffix
- `start_tmux_server_if_needed()` - Auto-start tmux server

---

## Deviations from Plan

None - plan executed exactly as written. All requirements from 03-CONTEXT.md and 03-RESEARCH.md were followed precisely.

---

## Technical Details

### System Prompt Composition (Replacement Model)

Per CONTEXT.md locked decision, agent prompts **replace** the default entirely (not append):

```bash
# Priority 1: CLI override (if --system-prompt provided)
if [ -n "$cli_override_prompt" ]; then
  final_prompt="$cli_override_prompt"

# Priority 2: Agent-specific prompt from registry
elif [ -n "$agent_prompt_from_registry" ]; then
  final_prompt="$agent_prompt_from_registry"

# Priority 3: Default prompt file
else
  final_prompt="$(cat default-system-prompt.txt)"
fi
```

This differs from ROADMAP.md which suggested append model. CONTEXT.md takes precedence as it captures locked user decisions from /gsd:discuss-phase.

### Registry Upsert (jq Functional Pattern)

```bash
jq --arg agent_id "$agent_name" \
   --arg workdir "$working_directory" \
   --arg session_name "$tmux_session_name" \
   '
if (.agents | map(.agent_id) | index($agent_id)) then
  # Update existing entry
  .agents |= map(
    if .agent_id == $agent_id then
      . + {
        "working_directory": $workdir,
        "tmux_session_name": $session_name
      }
    else . end
  )
else
  # Create new entry with defaults
  .agents += [{
    "agent_id": $agent_id,
    "enabled": true,
    "auto_wake": true,
    "topic_id": 1,
    "openclaw_session_id": "",
    "working_directory": $workdir,
    "tmux_session_name": $session_name,
    "claude_resume_target": "",
    "claude_launch_command": "claude --dangerously-skip-permissions",
    "claude_post_launch_mode": "resume_then_agent_pick",
    "system_prompt": "",
    "hook_settings": {}
  }]
end
' "$registry_file" > "$registry_file.tmp"

mv "$registry_file.tmp" "$registry_file"
```

### Atomic Write Pattern

All registry writes use atomic pattern to prevent corruption on SIGTERM/SIGKILL:
1. Write to `.tmp` suffix file
2. Atomically rename via `mv` (atomic on same filesystem)
3. No flock needed per CONTEXT.md (deferred for later if concurrent access becomes issue)

### Tmux Session Name Conflict Resolution

```bash
base_name="gideon-main"
session_name="$base_name"
counter=2

while tmux has-session -t "$session_name" 2>/dev/null; do
  session_name="${base_name}-${counter}"
  counter=$((counter + 1))
done

tmux new-session -d -s "$session_name" -c "$workdir"
```

Graceful handling: append -2, -3, etc. instead of failing.

---

## Usage Examples

### Basic agent launch
```bash
spawn.sh gideon /home/forge/.openclaw/workspace
# Uses registry config if exists, creates if not
# System prompt: registry agent prompt > default file
```

### New agent with custom workdir
```bash
spawn.sh warden /home/forge/project
# Auto-creates registry entry with defaults
# Session name: warden-main
```

### Explicit first command
```bash
spawn.sh test-agent /tmp/test "/gsd:resume-work"
# Skips auto-detection, runs specified command
```

### CLI system prompt override (inline)
```bash
spawn.sh gideon /workspace --system-prompt "Custom prompt text"
# Overrides both registry and default
```

### CLI system prompt override (file)
```bash
spawn.sh gideon /workspace --system-prompt /path/to/prompt.txt
# Auto-detects file, reads content
```

---

## Success Criteria

All plan success criteria met:

- [x] spawn.sh is single, self-contained bash script with no Python dependency
- [x] Agent-name is primary key; all config reads from registry via jq
- [x] System prompt follows replacement model: CLI override > registry agent prompt > default file
- [x] All 5 legacy flags removed (--prd, --autoresponder, --agent-id, --topic-id, --auto-wake)
- [x] strict_prompt() function deleted
- [x] Python upsert_recovery_registry_entry() function deleted
- [x] Registry auto-creates entries for unknown agents
- [x] Tmux session name conflict resolved with -2 suffix (not die/abort)

---

## Self-Check

### Created Files
None (all changes to existing files)

### Modified Files
```bash
[ -f "scripts/spawn.sh" ] && echo "FOUND: scripts/spawn.sh"
```
FOUND: scripts/spawn.sh

### Commits
```bash
git log --oneline --all | grep -q "72f3672" && echo "FOUND: 72f3672"
```
FOUND: 72f3672

## Self-Check: PASSED

All files exist, all commits present in git history.

---

## Next Steps

Phase 03 Plan 02 will apply similar jq conversion to `recover-openclaw-agents.sh`, completing the Python elimination from launcher scripts.
