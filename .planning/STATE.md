# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-19)

**Core value:** When Claude Code fires any hook event, the right agent wakes up with the right context and knows exactly which GSD slash command to type next
**Current focus:** v4.0 Event-Driven Hook Architecture

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-02-19 — Milestone v4.0 started

## Accumulated Context

### Decisions

- v4.0 is a clean rewrite — all v1.0-v3.2 hook code will be deleted
- `agent-registry.json` replaces `recovery-registry.json`
- Event-folder architecture: `events/{event_name}/` with handler + prompt per event
- `last_assistant_message` from JSON replaces pane scraping, transcript parsing, and state regex
- PreToolUse → PostToolUse verification loop for AskUserQuestion
- Cross-platform using only OpenClaw dependencies

### What Stays (from v1.0-v3.2)

- spawn.sh, recover-openclaw-agents.sh, menu-driver.sh, sync-recovery-registry-session-ids.sh
- systemd timer for auto-recovery
- install.sh (will be updated for new structure)
- hook-event-logger.sh (debugging tool)
- diagnose-hooks.sh (will be updated)

### What Gets Deleted

- All 7 hook scripts (stop-hook.sh, notification-idle-hook.sh, etc.)
- lib/hook-preamble.sh, lib/hook-utils.sh (rewrite)
- scripts/prompts/*.md (replaced by events/*/prompt_*.md)
- PRD.md (outdated, v4.0 scope is in PROJECT.md)
- docs/v3-retrospective.md (historical, not needed)
- register-hooks.sh (rewrite for new structure)
- test-hook-prompts.sh (rewrite for new structure)
- tests/ (rewrite for new structure)

---
*Last updated: 2026-02-19 after v4.0 milestone start*
