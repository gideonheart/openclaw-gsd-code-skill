# Quick Task 15 — Summary

## Task
Investigate and fix AskUserQuestion PreToolUse not triggering TUI control and cross-session log bleeding

## Root Causes Found

| # | Issue | Component | Root Cause |
|---|-------|-----------|------------|
| 1 | PreToolUse handler never invoked | `~/.claude/settings.json` | Only `hook-event-logger.sh` registered — no entry for `event_pre_tool_use.mjs` |
| 2 | PostToolUse handler never invoked | `~/.claude/settings.json` | Same — only logger, no `event_post_tool_use.mjs` |
| 3 | Placeholder openclaw_session_id | `config/agent-registry.json` | `"TODO-fill-in-real-session-id"` — gateway delivery would fail even if handler ran |
| 4 | Logger tmux dependency fragile | `bin/hook-event-logger.sh` | Called `tmux display-message` without checking `$TMUX` env var first |

## Changes Made

### New Files
- **`config/hooks.json`** — Canonical source of truth for all 14 hook event registrations. Uses `{{SKILL_ROOT}}` placeholder for portability. Includes logger for all events + handlers for SessionStart, UserPromptSubmit, Stop, PreToolUse(AskUserQuestion), PostToolUse(AskUserQuestion).
- **`bin/install-hooks.mjs`** — Hook installer/uninstaller script. Reads `config/hooks.json`, resolves `{{SKILL_ROOT}}` to actual path, merges into `~/.claude/settings.json` (preserves statusLine, enabledPlugins, etc.). Supports `--remove` and `--dry-run` flags.

### Modified Files
- **`bin/hook-event-logger.sh`** — Session resolution now checks `$TMUX` env var before forking `tmux display-message`. Eliminates unnecessary process spawn when hooks run outside tmux.

### Not Changed (Human Action Required)
- **`config/agent-registry.json`** — Still has `"openclaw_session_id": "TODO-fill-in-real-session-id"`. OpenClaw sessions list shows no warden-specific session. User needs to provide the correct OpenClaw session ID for the warden agent.

## Verification

| Check | Result |
|-------|--------|
| settings.json PreToolUse has AskUserQuestion matcher entry | PASS |
| settings.json PostToolUse has AskUserQuestion matcher entry | PASS |
| settings.json preserves statusLine and enabledPlugins | PASS |
| 14 hook events installed (5 handlers) | PASS |
| hook-event-logger.sh syntax valid | PASS |
| install-hooks.mjs --dry-run shows correct output | PASS |

## Usage

```bash
# Install/update all hooks
node bin/install-hooks.mjs

# Preview what would change
node bin/install-hooks.mjs --dry-run

# Remove all hooks
node bin/install-hooks.mjs --remove
```

## Remaining Work
- Fill in `config/agent-registry.json` `openclaw_session_id` with real warden session UUID
- Live test: trigger AskUserQuestion in a warden session and verify the full lifecycle fires
