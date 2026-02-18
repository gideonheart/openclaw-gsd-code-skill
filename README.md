# gsd-code-skill

Event-driven agent session lifecycle management for OpenClaw + Claude Code. This document is for administrators setting up and operating the hook-driven infrastructure that enables autonomous agent recovery after reboot/OOM, intelligent session monitoring, and automated lifecycle management.

Agents use SKILL.md; admins use this README.

## Pre-Flight Checklist

Complete these steps once before spawning your first agent session.

### 1. Configure registry

Create `config/recovery-registry.json` from the example template:

```bash
cp config/recovery-registry.example.json config/recovery-registry.json
```

Edit the registry to set your agent entries. At minimum, configure:
- `agent_id` (required): unique identifier
- `enabled` (required): set to `true` to include in recovery
- `auto_wake` (required): set to `true` to wake agent after reboot
- `openclaw_session_id` (required): OpenClaw session UUID for wake instructions
- `working_directory` (required): absolute path to agent workspace
- `tmux_session_name` (required): tmux session name (convention: `{agent_id}-main`)

Optional but recommended:
- `system_prompt`: per-agent personality/instructions (replaces default)
- `claude_resume_target`: hint for which session to resume
- `hook_settings`: per-agent overrides for hook behavior

The sync script (`scripts/sync-recovery-registry-session-ids.sh`) can auto-populate `openclaw_session_id` from OpenClaw's session data. Run it before manual edits:

```bash
scripts/sync-recovery-registry-session-ids.sh --dry-run
scripts/sync-recovery-registry-session-ids.sh
```

### 2. Register hooks

Run the hook registration script to configure Claude Code's event hooks:

```bash
scripts/register-hooks.sh
```

This registers 7 hook events in `~/.claude/settings.json`:
- Stop (agent stopped work)
- Notification with idle_prompt matcher (agent waiting for input)
- Notification with permission_prompt matcher (agent requesting permission)
- SessionEnd (Claude Code session exited)
- PreCompact (context approaching token limit)
- PreToolUse with AskUserQuestion matcher (agent about to ask user a question)
- PostToolUse with AskUserQuestion matcher (user answered agent's question)

Verify registration succeeded:

```bash
jq '.hooks' ~/.claude/settings.json
```

You should see all 7 hook events with absolute paths to hook scripts in this skill directory.

Important: Restart all Claude Code sessions after registration. Existing sessions use old configuration until restarted.

### 3. Install systemd timer

Two installation paths:

#### Option A: Via Laravel Forge UI (Recommended)

Laravel Forge provides a web UI for daemon and scheduled job management. Use this if your server is managed by Forge.

**Add Daemon:**
1. Navigate to your server in Forge UI
2. Go to Daemons section
3. Add new daemon with:
   - Name: `recover-openclaw-agents`
   - Command: `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/recover-openclaw-agents.sh --registry /home/forge/.openclaw/workspace/skills/gsd-code-skill/config/recovery-registry.json`
   - User: `forge`
   - Directory: `/home/forge/.openclaw/workspace`
   - Processes: 1
4. Save and start the daemon

**Add Scheduled Job (Reboot Trigger):**
1. Go to Scheduled Jobs section
2. Add new job with:
   - Command: `systemctl restart recover-openclaw-agents`
   - User: `forge`
   - Frequency: `@reboot`
3. Save

This approach gives you web-based control over daemon lifecycle without SSH access.

#### Option B: Manual systemd install (Fallback)

If not using Laravel Forge, install systemd units directly:

```bash
sudo install -m 0644 systemd/recover-openclaw-agents.service /etc/systemd/system/recover-openclaw-agents.service
sudo install -m 0644 systemd/recover-openclaw-agents.timer /etc/systemd/system/recover-openclaw-agents.timer
sudo systemctl daemon-reload
sudo systemctl enable --now recover-openclaw-agents.timer
```

The timer runs the recovery service 45 seconds after each boot.

### 4. Verify daemon

Check timer status:

```bash
systemctl status recover-openclaw-agents.timer
```

Expected output: `active (waiting)` with next trigger time.

Check service status:

```bash
systemctl status recover-openclaw-agents.service
```

After first boot trigger, you should see successful execution logs.

### 5. Test spawn

Spawn a test agent to verify the full stack:

```bash
scripts/spawn.sh test-agent /tmp/test-dir
```

Verify tmux session created:

```bash
tmux ls
```

You should see `test-agent-main` in the list. Attach to verify Claude Code launched:

```bash
tmux attach -t test-agent-main
```

If everything works, the registry will auto-update with the test agent entry. Kill the test session when done:

```bash
tmux kill-session -t test-agent-main
```

## Registry Schema

The recovery registry uses JSON with per-agent configuration and global defaults. All hook-related settings support **three-tier fallback**: per-agent > global > hardcoded defaults.

### Annotated JSON Example

Based on `config/recovery-registry.example.json`:

```json
{
  "global_status_openclaw_session_id": "20dd98b6-45e0-41b1-b799-6f8089051a87",
  "_comment_global_status_openclaw_session_id": "Optional. OpenClaw session that receives global recovery summary. Recommended for centralized monitoring.",

  "global_status_openclaw_session_key": "agent:gideon:telegram:group:-1003874762204:topic:1",
  "_comment_global_status_openclaw_session_key": "Optional. Session key used to auto-refresh global_status_openclaw_session_id from OpenClaw session data. Recommended for stability across session rotations.",

  "hook_settings": {
    "_comment_hook_settings_defaults": "Global defaults for all hook events. New agent entries should use empty object {} to inherit all defaults via three-tier fallback: per-agent > global > hardcoded.",

    "pane_capture_lines": 100,
    "_comment_pane_capture_lines": "Required integer. Number of tmux pane lines to capture for context. Default: 100.",

    "context_pressure_threshold": 50,
    "_comment_context_pressure_threshold": "Required integer. Percentage of max context at which to trigger pressure warnings. Default: 50.",

    "autocompact_pct": 80,
    "_comment_autocompact_pct": "Required integer. Percentage of max context at which to trigger automatic compaction. Default: 80.",

    "hook_mode": "async",
    "_comment_hook_mode": "Required string. Hook execution mode: 'async' (fire and forget) or 'bidirectional' (can inject instructions into Claude session). Default: 'async'."
  },

  "agents": [
    {
      "agent_id": "gideon",
      "_comment_agent_id": "Required string. Unique agent identifier. Primary key for registry lookups.",

      "enabled": true,
      "_comment_enabled": "Required boolean. If false, agent is excluded from all operations (recovery, hooks, sync).",

      "auto_wake": true,
      "_comment_auto_wake": "Required boolean. If true, agent is awakened after reboot via recovery script. If false, agent entry is kept but skipped during auto-recovery.",

      "topic_id": 1,
      "_comment_topic_id": "Required integer if auto_wake=true. Telegram topic ID for status updates. Ignored if auto_wake=false.",

      "openclaw_session_id": "20dd98b6-45e0-41b1-b799-6f8089051a87",
      "_comment_openclaw_session_id": "Required string (UUID). OpenClaw session that receives wake instructions. Auto-refreshed by sync script from sessions/sessions.json (latest agent:{agent_id}:openai:* entry).",

      "working_directory": "/home/forge/.openclaw/workspace",
      "_comment_working_directory": "Required string (absolute path). Working directory for tmux session and Claude Code.",

      "tmux_session_name": "gideon-main",
      "_comment_tmux_session_name": "Required string. Tmux session name. Convention: {agent_id}-main. If conflict detected at spawn, -2 suffix auto-applied.",

      "claude_resume_target": "",
      "_comment_claude_resume_target": "Optional string. Hint for which Claude session to resume (e.g., 'Phase 3 execution'). Passed to agent in wake instruction. Empty string = no hint.",

      "claude_launch_command": "claude --dangerously-skip-permissions",
      "_comment_claude_launch_command": "Optional string. Command to launch Claude Code in tmux. Default: 'claude --dangerously-skip-permissions'.",

      "claude_post_launch_mode": "resume_then_agent_pick",
      "_comment_claude_post_launch_mode": "Optional string. Post-launch behavior: 'resume_then_agent_pick' (send /resume, wait for agent to pick session) or 'gsd_resume_work' (send /gsd:resume-work directly). Default: 'resume_then_agent_pick'.",

      "system_prompt": "You are Gideon, the orchestrator agent. You delegate development tasks to Warden and infrastructure tasks to Forge. You communicate with Rolands via Telegram.",
      "_comment_system_prompt": "Optional string. Per-agent system prompt. REPLACEMENT MODEL: if present, this prompt replaces config/default-system-prompt.txt entirely (does NOT append). Empty string = use default-system-prompt.txt only. Omitted field = use default-system-prompt.txt only.",

      "hook_settings": {}
      "_comment_hook_settings": "Optional object. Per-agent hook setting overrides. Merged per-field with global hook_settings via three-tier fallback. Empty object {} = inherit all global defaults. Omitted fields inherit from global. Example: {\"pane_capture_lines\": 150, \"hook_mode\": \"bidirectional\"} overrides only those two fields."
    },
    {
      "agent_id": "warden",
      "enabled": true,
      "auto_wake": true,
      "topic_id": 1,
      "openclaw_session_id": "d52a3453-3ac6-464b-9533-681560695394",
      "working_directory": "/home/forge/warden.kingdom.lv",
      "tmux_session_name": "warden-main",
      "claude_resume_target": "",
      "claude_launch_command": "claude --dangerously-skip-permissions",
      "claude_post_launch_mode": "resume_then_agent_pick",
      "system_prompt": "You are Warden, the development specialist. You handle coding tasks delegated by Gideon. Focus on code quality, testing, and best practices.",
      "hook_settings": {
        "pane_capture_lines": 150,
        "hook_mode": "bidirectional"
      }
    },
    {
      "agent_id": "forge",
      "enabled": true,
      "auto_wake": true,
      "topic_id": 1,
      "openclaw_session_id": "4ffd03a4-a8f5-40de-a17d-bcec595535aa",
      "working_directory": "/home/forge",
      "tmux_session_name": "forge-main",
      "claude_resume_target": "",
      "claude_launch_command": "ls",
      "claude_post_launch_mode": "resume_then_agent_pick",
      "system_prompt": "You are Forge, the infrastructure specialist. You handle server management, deployment, and infrastructure tasks delegated by Gideon.",
      "hook_settings": {
        "context_pressure_threshold": 60
      }
    }
  ]
}
```

### Three-Tier Fallback Mechanism

Hook settings use per-field merge, not all-or-nothing replacement. Priority order:

1. **Per-agent** (`agents[].hook_settings`)
2. **Global** (top-level `hook_settings`)
3. **Hardcoded defaults** (in hook scripts)

**Concrete example:**

Global settings:
```json
"hook_settings": {
  "pane_capture_lines": 100,
  "context_pressure_threshold": 50,
  "autocompact_pct": 80,
  "hook_mode": "async"
}
```

Agent "warden" overrides:
```json
"hook_settings": {
  "pane_capture_lines": 150,
  "hook_mode": "bidirectional"
}
```

**Effective settings for warden:**
- `pane_capture_lines`: 150 (per-agent override)
- `hook_mode`: bidirectional (per-agent override)
- `context_pressure_threshold`: 50 (inherited from global)
- `autocompact_pct`: 80 (inherited from global)

Agent "forge" overrides:
```json
"hook_settings": {
  "context_pressure_threshold": 60
}
```

**Effective settings for forge:**
- `context_pressure_threshold`: 60 (per-agent override)
- `pane_capture_lines`: 100 (inherited from global)
- `autocompact_pct`: 80 (inherited from global)
- `hook_mode`: async (inherited from global)

Agent with empty `hook_settings: {}` inherits all global defaults.

### System Prompt Field

The `system_prompt` field uses a **replacement model**, not append:

- **Present and non-empty**: Replaces `config/default-system-prompt.txt` entirely. The default prompt is NOT used.
- **Empty string `""`**: Uses `config/default-system-prompt.txt` only.
- **Omitted field**: Uses `config/default-system-prompt.txt` only.

This allows per-agent personality/constraints without mixing default GSD workflow instructions with agent-specific role definitions.

### Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `global_status_openclaw_session_id` | string (UUID) | Optional, recommended | OpenClaw session receiving global recovery summary. Useful for centralized monitoring in a single Telegram topic. |
| `global_status_openclaw_session_key` | string | Optional, recommended | Session key for auto-refresh of `global_status_openclaw_session_id`. Format: `agent:{agent_id}:{channel}:{destination}:topic:{topic_id}`. Enables stable session ID across rotations. |
| `hook_settings` | object | Optional | Global defaults for all hook events. See Hook Settings Fields below. |
| `agents` | array of objects | Required | Agent entries. Each object describes one agent's recovery configuration. |

### Per-Agent Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | Required | Unique agent identifier. Primary key for lookups. |
| `enabled` | boolean | Required | If `false`, agent excluded from all operations. |
| `auto_wake` | boolean | Required | If `true`, agent awakened after reboot. If `false`, registry entry kept but skipped. |
| `topic_id` | integer | Required if `auto_wake=true` | Telegram topic ID for status updates. |
| `openclaw_session_id` | string (UUID) | Required | OpenClaw session for wake instructions. Auto-synced from sessions data. |
| `working_directory` | string (absolute path) | Required | Working directory for tmux + Claude Code. |
| `tmux_session_name` | string | Required | Tmux session name. Conflicts resolved with `-2` suffix. |
| `claude_resume_target` | string | Optional | Hint for which Claude session to resume. Passed to agent in wake instruction. |
| `claude_launch_command` | string | Optional | Command to launch Claude Code. Default: `claude --dangerously-skip-permissions`. |
| `claude_post_launch_mode` | string | Optional | Post-launch behavior: `resume_then_agent_pick` or `gsd_resume_work`. Default: `resume_then_agent_pick`. |
| `system_prompt` | string | Optional | Per-agent system prompt. Replaces default entirely if non-empty. Empty/omitted = use default only. |
| `hook_settings` | object | Optional | Per-agent hook overrides. Per-field merge with global. Empty object = inherit all. |

### Hook Settings Fields

These fields can appear in global `hook_settings` or per-agent `hook_settings`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `pane_capture_lines` | integer | 100 | Number of tmux pane lines captured for hook context. |
| `context_pressure_threshold` | integer | 50 | Percentage of max context triggering pressure warnings. |
| `autocompact_pct` | integer | 80 | Percentage of max context triggering auto-compaction. |
| `hook_mode` | string | "async" | Hook execution mode: `async` (fire and forget) or `bidirectional` (can inject instructions). |

## Recovery Flow

The deterministic recovery sequence runs automatically on reboot (via systemd timer) or manually via `scripts/recover-openclaw-agents.sh`:

1. **Auto-sync session IDs**: Refresh `openclaw_session_id` values from OpenClaw session data (`/home/forge/.openclaw/agents/{agent_id}/sessions/sessions.json`). Selects most recently updated session matching pattern `agent:{agent_id}:openai:*`.

2. **Load registry**: Parse `config/recovery-registry.json` and validate JSON structure.

3. **Filter agents**: Select agents where `enabled=true` AND `auto_wake=true`. Skip disabled or non-auto-wake agents.

4. **Ensure tmux session exists**: Check if tmux session with `tmux_session_name` exists. If not, create it in `working_directory`. If name conflict detected, resolve with `-2` suffix.

5. **Launch Claude Code if not running**: Inspect tmux pane for Claude Code TUI signatures (`Resume Session`, `/gsd:`, `Type to Search`, etc.). If not detected, run `claude_launch_command` with system prompt (per-agent or default). Wait 2 seconds and verify launch succeeded.

6. **Apply system prompt**: System prompt composition follows replacement model:
   - Per-agent `system_prompt` (if non-empty) replaces default entirely
   - Empty or omitted `system_prompt` uses `config/default-system-prompt.txt`

7. **Send wake instruction to OpenClaw session**: Use `openclaw agent --session-id {openclaw_session_id}` to send deterministic recovery instruction. Instruction includes:
   - Agent ID, topic ID, tmux session name
   - Steps: snapshot TUI, pick resume target, wait for load, read last GSD response, send status

8. **Wait for resume menu to clear**: Monitor tmux pane for up to 45 seconds. If resume menu still visible after timeout, inject fallback `/gsd:resume-work` command automatically.

9. **Send per-agent status and global summary**: Each agent receives wake instruction in its own OpenClaw session. One global summary sent to `global_status_openclaw_session_id` with counts: restored, skipped, failed.

Hooks fire automatically once session is running:
- **Stop**: Agent stops work (waiting for user or finished task)
- **Notification (idle_prompt)**: Agent idle, awaiting input
- **Notification (permission_prompt)**: Agent requesting permission
- **SessionEnd**: Claude Code session exited (crash, user exit, OOM)
- **PreCompact**: Context approaching token limit (auto or manual compact triggered)
- **PreToolUse (AskUserQuestion)**: Agent about to ask user a question (forwards question data)
- **PostToolUse (AskUserQuestion)**: User answered agent's question (logs answer for lifecycle correlation)

## Operational Runbook

### Manual Runs

Test recovery flow without waiting for reboot:

**Dry-run** (shows what would happen, no changes):
```bash
scripts/recover-openclaw-agents.sh --dry-run
```

**Live run** (executes full recovery):
```bash
scripts/recover-openclaw-agents.sh
```

**Custom registry path**:
```bash
scripts/recover-openclaw-agents.sh --registry /path/to/custom-registry.json
```

**Skip session ID sync** (use existing session IDs in registry):
```bash
scripts/recover-openclaw-agents.sh --skip-session-id-sync
```

**Standalone session ID sync** (update session IDs without recovery):
```bash
scripts/sync-recovery-registry-session-ids.sh --dry-run
scripts/sync-recovery-registry-session-ids.sh
```

### Verification Commands

**Check hooks registered in Claude Code settings**:
```bash
jq '.hooks' ~/.claude/settings.json
```

Expected output: Objects for Stop, Notification, SessionEnd, PreCompact with absolute paths to hook scripts.

**Check daemon status** (systemd timer):
```bash
systemctl status recover-openclaw-agents.timer
systemctl status recover-openclaw-agents.service
```

**Check tmux sessions**:
```bash
tmux ls
```

**Check registry agent status**:
```bash
jq '.agents[] | {agent_id, enabled, auto_wake, openclaw_session_id}' config/recovery-registry.json
```

**Check hook JSONL logs for a session**:
```bash
scripts/diagnose-hooks.sh <agent-name>
```

Runs 11-step diagnostic including JSONL log analysis (recent events, outcome distribution, non-delivered detection, duration stats).

**Re-register hooks after script updates**:
```bash
scripts/register-hooks.sh
```

Creates timestamped backup of `~/.claude/settings.json` before modifying.

**View recent recovery logs** (if using systemd):
```bash
journalctl -u recover-openclaw-agents.service -n 50 --no-pager
```

### Troubleshooting

**Wrong tmux session created**:
- Verify `tmux_session_name` in registry matches expected value
- Check for session name conflicts (script auto-resolves with `-2` suffix)
- Manually kill conflicting session: `tmux kill-session -t {name}`

**Wrong OpenClaw session awakened**:
- Verify `openclaw_session_id` in registry matches intended session UUID
- Run session ID sync to refresh from OpenClaw data: `scripts/sync-recovery-registry-session-ids.sh`
- Manually inspect OpenClaw session data: `jq '.' /home/forge/.openclaw/agents/{agent_id}/sessions/sessions.json`

**Agent not recovering on reboot**:
- Verify systemd timer enabled: `systemctl is-enabled recover-openclaw-agents.timer`
- Check timer logs: `journalctl -u recover-openclaw-agents.timer -n 20`
- Verify `auto_wake=true` in registry for that agent
- Verify `enabled=true` in registry for that agent

**Hooks not firing**:
- Run `scripts/register-hooks.sh` to re-register
- Verify with `jq '.hooks' ~/.claude/settings.json`
- Restart Claude Code sessions (existing sessions use old config)
- Check hook script permissions: `ls -l scripts/*-hook.sh` (should be executable)

**Recovery script reports "corrupt registry"**:
- Script auto-backups corrupt file with timestamp: `config/recovery-registry.json.corrupt-{timestamp}`
- Script creates fresh skeleton registry
- Restore from backup or rebuild from example: `cp config/recovery-registry.example.json config/recovery-registry.json`

**Non-destructive guarantees**:
- Recovery script skips disabled agents (`enabled=false`)
- Recovery script skips non-auto-wake agents (`auto_wake=false`)
- Recovery script logs and continues on missing required fields
- Recovery script never deletes files or tmux sessions
- Registry corruption auto-backed up before recreation

## Files

### Scripts

| File | Description |
|------|-------------|
| `scripts/spawn.sh` | Spawn new agent session. Auto-creates/updates registry entry. |
| `scripts/recover-openclaw-agents.sh` | Deterministic multi-agent recovery after reboot/OOM. |
| `scripts/sync-recovery-registry-session-ids.sh` | Sync `openclaw_session_id` values from OpenClaw session data. |
| `scripts/register-hooks.sh` | Idempotent hook registration for Claude Code. Registers all 7 hook events. |
| `scripts/stop-hook.sh` | Hook: fires when agent stops work. |
| `scripts/notification-idle-hook.sh` | Hook: fires when agent idle (waiting for input). |
| `scripts/notification-permission-hook.sh` | Hook: fires when agent requests permission. |
| `scripts/session-end-hook.sh` | Hook: fires when Claude Code session exits. |
| `scripts/pre-compact-hook.sh` | Hook: fires when context approaches token limit. |
| `scripts/pre-tool-use-hook.sh` | Hook: fires when agent calls AskUserQuestion (forwards question data). |
| `scripts/post-tool-use-hook.sh` | Hook: fires after AskUserQuestion completes (logs selected answer). |
| `scripts/diagnose-hooks.sh` | End-to-end 11-step hook chain diagnostic with JSONL analysis. |
| `scripts/menu-driver.sh` | TUI helper for tmux pane inspection and resume menu navigation. |

### Config Files

| File | Description |
|------|-------------|
| `config/recovery-registry.json` | Live registry (gitignored, contains session UUIDs). |
| `config/recovery-registry.example.json` | Template registry with annotated schema. |
| `config/default-system-prompt.txt` | Default system prompt for all agents. Minimal GSD workflow guidance. |

### Shared Libraries

| File | Description |
|------|-------------|
| `lib/hook-utils.sh` | Shared library (6 functions) sourced by all hook scripts. No side effects on source. |

### systemd Units

| File | Description |
|------|-------------|
| `systemd/recover-openclaw-agents.service` | Oneshot service executing recovery script. |
| `systemd/recover-openclaw-agents.timer` | Timer triggering service 45 seconds after boot. |

### Documentation

| File | Description |
|------|-------------|
| `README.md` | This file. Admin-facing setup, registry schema, operational runbook. |
| `SKILL.md` | Agent-facing instructions for using GSD workflow (not for admins). |
| `docs/hooks.md` | Deep-dive into hook architecture, event types, and implementation details. |
