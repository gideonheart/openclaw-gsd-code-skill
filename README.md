# gsd-code-skill recovery and operations

This README documents deterministic multi-agent recovery for OpenClaw + Claude Code after reboot or gateway OOM.

## What this subsystem does

The recovery flow is intentionally two-layered:

1. Restore the **OpenClaw agent session** first (`openclaw_session_id`).
2. Then that restored OpenClaw session drives Claude Code TUI and runs deterministic `/resume` selection.

This avoids layer mixing and keeps continuity anchored to the correct OpenClaw transcript.

## Files

- Script: `skills/gsd-code-skill/scripts/recover-openclaw-agents.sh`
- Script: `skills/gsd-code-skill/scripts/sync-recovery-registry-session-ids.sh`
- Script: `skills/gsd-code-skill/scripts/spawn.sh` (auto-upserts recovery registry entry on start)
- Registry (real): `skills/gsd-code-skill/config/recovery-registry.json`
- Registry (example): `skills/gsd-code-skill/config/recovery-registry.example.json`
- systemd service: `skills/gsd-code-skill/systemd/recover-openclaw-agents.service`
- systemd timer: `skills/gsd-code-skill/systemd/recover-openclaw-agents.timer`
- TUI helper reused by recovery instructions: `skills/gsd-code-skill/scripts/menu-driver.sh`

## Registry schema

Top-level:

- `global_status_openclaw_session_id` (optional, recommended): OpenClaw session that receives one global summary.
- `global_status_openclaw_session_key` (optional, recommended): stable session key used to auto-refresh `global_status_openclaw_session_id` on each run.
- `agents` (required): array of agent entries.

Per-agent entry:

- `agent_id` (required)
- `enabled` (required)
- `auto_wake` (required)
- `topic_id` (required if `auto_wake=true`)
- `openclaw_session_id` (required)
- `working_directory` (required)
- `tmux_session_name` (required)
- `claude_resume_target` (optional but recommended)
- `claude_launch_command` (optional, default `claude --dangerously-skip-permissions`)
- `claude_post_launch_mode` (optional, default `resume_then_agent_pick`; options: `resume_then_agent_pick` or `gsd_resume_work`)

## Deterministic recovery flow

0. Auto-sync OpenClaw session ids in registry from `/home/forge/.openclaw/agents/<agent_id>/sessions/sessions.json` by choosing latest `agent:<agent_id>:openai:*` entry.
1. Load registry.
2. Filter agents by `enabled=true && auto_wake=true`.
3. Ensure tmux session exists in correct working directory.
4. Launch Claude Code if not already running in that tmux pane.
5. Send deterministic wake instruction to the exact OpenClaw session id.
6. OpenClaw agent checks resume menu and restores Claude session target.
7. Recovery script waits for resume menu to clear (up to 45s); if still stuck, it injects fallback `/gsd:resume-work` automatically.
8. Send per-agent status to topic and one global summary to `global_status_openclaw_session_id`.

## What the timer is

`recover-openclaw-agents.timer` is a systemd timer unit.

Current template behavior:

- `OnBootSec=45s`
- Runs recovery service once shortly after boot.

This is an automatic reboot recovery trigger.

## Install and enable (run as separate commands)

```bash
sudo install -m 0644 /home/forge/.openclaw/workspace/skills/gsd-code-skill/systemd/recover-openclaw-agents.service /etc/systemd/system/recover-openclaw-agents.service
sudo install -m 0644 /home/forge/.openclaw/workspace/skills/gsd-code-skill/systemd/recover-openclaw-agents.timer /etc/systemd/system/recover-openclaw-agents.timer
sudo systemctl daemon-reload
sudo systemctl enable --now recover-openclaw-agents.timer
sudo systemctl status --no-pager recover-openclaw-agents.timer
```

## Manual runs

Dry-run first:

Note: if `recovery-registry.json` is missing, it is auto-created on first run as an empty registry and then bootstrapped from live agent/session data (agent ids + latest session ids). Default bootstrap values use `auto_wake=false`, `working_directory=/home/forge`, and `<agent>-main` tmux names; adjust these once per agent.

```bash
/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/recover-openclaw-agents.sh --dry-run
```

Optional standalone sync run:

```bash
/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/sync-recovery-registry-session-ids.sh --dry-run
/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/sync-recovery-registry-session-ids.sh
```

Live run:

```bash
/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/recover-openclaw-agents.sh
```

Custom registry:

```bash
/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/recover-openclaw-agents.sh --registry /path/to/recovery-registry.json
```

## If config is wrong, what happens?

Current behavior is non-destructive:

- Skips agents with `enabled=false` or `auto_wake=false`.
- Fails and logs on missing required fields.
- Fails and logs if working directory is missing.
- Does not delete files or remove sessions.

Potential bad outcomes from bad config:

- Wrong tmux session may be created.
- Wrong OpenClaw session may be awakened.
- Agent may resume wrong Claude thread.

You can disable automatic session id refresh with:

```bash
/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/recover-openclaw-agents.sh --skip-session-id-sync
```

Mitigation:

- Always run `--dry-run` after registry edits.
- Keep `claude_resume_target` explicit.
- Keep one stable `openclaw_session_id` per agent role.

## Operations tips

- Use `enabled=false` to disable agent entirely.
- Use `auto_wake=false` to keep config but skip auto-recovery.
- Keep session ids updated when you intentionally rotate sessions.
- Keep names self-explanatory and stable for long-lived automation.
