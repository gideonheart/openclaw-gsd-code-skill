# Phase 3: Launcher Updates - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Update spawn.sh and recover-openclaw-agents.sh to use per-agent system prompts from registry with jq-only operations. Remove legacy autoresponder/polling logic. Scripts become registry-driven with minimal CLI arguments.

</domain>

<decisions>
## Implementation Decisions

### Prompt composition
- Two-tier model: default-system-prompt.txt is base, agent's registry `system_prompt` replaces it entirely if present
- No concatenation — agent override wins completely over default
- `--system-prompt` CLI flag overrides everything (both default and registry)
- `--system-prompt` auto-detects: if value is a file path that exists, read it; otherwise treat as inline text
- Silent fallback when agent has no system_prompt field — use default without logging
- Prompts only matter at launch time (spawn/recovery), never during hooks

### Spawn CLI design
- Registry-driven: `spawn.sh <agent-name> <workdir> [first-command]`
- Agent name is the primary key — reads workdir, system_prompt, all config from registry
- Workdir required for new/unknown agents; for registered agents, registry value is used (CLI arg overrides)
- First command defaults to `claude` if not provided
- Auto-create registry entry for unknown agents with defaults
- Maximum simplicity: DRY, SRP, lean — OpenClaw agents must be able to execute it
- Remove all autoresponder flags, hardcoded strict_prompt, and legacy polling logic
- No Python dependency — jq only for all registry operations

### Recovery reporting
- Stdout + Telegram notification on failures only (silent when all agents recover successfully)
- Diagnostic detail per agent: name + status + failure reason + session ID
- One retry with short delay before reporting failure
- Re-spawn immediately when agent marked 'running' but tmux session is gone (no intermediate state)
- No --dry-run mode — keep recovery simple

### Failure handling
- Missing/corrupt registry: back up corrupt file (timestamped, keep all), create fresh, notify via Telegram
- Tmux session name conflict: append `-2` suffix to new session (don't kill existing)
- Tmux server not running: start it automatically
- jq check at startup: verify jq exists before doing anything, clear error if missing
- No flock for registry writes — concurrent access unlikely, add later if needed

### Claude's Discretion
- Default system prompt content scope (GSD workflow only vs including minimal agent identity)
- System prompt format in registry (inline string vs file path)
- Exact retry delay for recovery (within "short delay" guidance)
- Registry auto-create entry schema (what defaults to populate)

</decisions>

<specifics>
## Specific Ideas

- "I want predictable code — code to run at all we need defaults, but we can override"
- "All I want is Claude Code to be run by external OpenClaw agent always forever until whole project is complete"
- warden.kingdom.lv dashboard watches all tmux sessions — session naming matters for visibility
- Registry global fields (`global_status_openclaw_session_id`, `global_status_openclaw_session_key`) are for the main agent; subagents have separate entries

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-launcher-updates*
*Context gathered: 2026-02-17*
