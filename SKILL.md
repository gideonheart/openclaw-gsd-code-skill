---
name: gsd-code-skill
description: Launch a strict GSD-only Claude Code session (slash-commands only) with deterministic git preflight + first-command selection.
metadata: {"openclaw":{"emoji":"🧭","os":["linux"],"requires":{"bins":["tmux","git","claude"]}}}
---

# gsd-code-skill

Deterministically start a **Claude Code** session where the agent is constrained to output **only slash commands**, primarily `/gsd:*` from **get-shit-done**.

This is designed to be used from OpenClaw as a “coding skill” launcher.

## What it does

- Creates a tmux session in the target repo directory
- Runs `claude --dangerously-skip-permissions` with a strict `--append-system-prompt`
- Runs a lightweight git preflight (no network)
- Chooses the first slash-command to send:
  - If repo is **non-empty** and `CLAUDE.md` missing → `/init`
  - Else if `.planning/` exists → `/gsd:resume-work`
  - Else if a PRD file exists → `/gsd:new-project @PRD.md`
  - Else → `/gsd:help`

## Scripts

### `scripts/spawn.sh <session-name> <workdir> [--prd <path>]`

Examples:

```bash
# Start a strict GSD Claude session in a repo
skills/gsd-code-skill/scripts/spawn.sh warden-gsd /home/forge/warden.kingdom.lv --prd PRD.md

# Start in an arbitrary directory (no PRD)
skills/gsd-code-skill/scripts/spawn.sh gideon-gsd /tmp/some-repo
```

Output:
- prints a short summary including the chosen first command
- tmux session is running in background; attach with:
  - `tmux attach -t <session-name>`
- Hook-driven event system handles agent control; use `scripts/menu-driver.sh` as deterministic TUI helper for agent-driven menu navigation

### `scripts/menu-driver.sh <session> <action> [args]`

Deterministic tmux helper for agent-driven menu navigation.

Examples:

```bash
# show latest pane content
skills/gsd-code-skill/scripts/menu-driver.sh warden-mc-gsd snapshot

# atomically clear context then start next command
skills/gsd-code-skill/scripts/menu-driver.sh warden-mc-gsd clear_then "/gsd:plan-phase 9"

# choose option 1 in a numbered menu
skills/gsd-code-skill/scripts/menu-driver.sh warden-mc-gsd choose 1
```

### `scripts/recover-openclaw-agents.sh [--registry <path>] [--dry-run] [--skip-session-id-sync]`

Deterministic reboot/OOM recovery orchestrator for many agents.

What it does:

1. Reads a per-agent registry JSON (`config/recovery-registry.json`)
2. Filters `enabled=true && auto_wake=true`
3. Ensures tmux session exists for each agent in the correct workdir
4. Launches Claude Code in tmux if not already running
5. Wakes the exact OpenClaw session id (`openclaw_session_id`) with deterministic instructions
6. Sends one global summary to `global_status_openclaw_session_id`

Includes:

- Example registry: `config/recovery-registry.example.json`
- Session id sync helper: `scripts/sync-recovery-registry-session-ids.sh`
- systemd unit template: `systemd/recover-openclaw-agents.service`
- systemd timer template: `systemd/recover-openclaw-agents.timer`

## Notes

- Recovery runbook and systemd setup are documented in `README.md` in this skill directory.
- This does **not** disable or modify global GSD command installation.
- It enforces behavior by starting Claude with a strict system prompt.
