# Milestones: gsd-code-skill

## v2.0 Smart Hook Delivery (In Progress)

**Goal:** Replace blunt 120-line pane scraping with precise content extraction — transcript-based responses, AskUserQuestion forwarding via PreToolUse, diff-based delivery.

**Started:** 2026-02-17
**Phases:** TBD (defining requirements)

## v1.0 Hook-Driven Agent Control (Shipped)

**Goal:** Replace polling-based menu handling with Claude Code's native hook system for event-driven, agent-intelligent control.

**Started:** 2026-02-17
**Completed:** 2026-02-17
**Phases:** 5 (Additive Changes, Hook Wiring, Launcher Updates, Cleanup, Documentation)
**Requirements:** 38 total (see REQUIREMENTS.md)
**Tech stack:** Bash + jq only (no Python dependency)

**What shipped:**
- 5 hook scripts (stop, notification-idle, notification-permission, session-end, pre-compact)
- Per-agent system prompts via recovery registry
- hook_settings with three-tier fallback (per-agent > global > hardcoded)
- Hybrid hook mode (async + bidirectional)
- menu-driver.sh type action for freeform text
- Deleted autoresponder.sh and hook-watcher.sh (polling replaced)
- Updated SKILL.md and docs/hooks.md

---
*Last updated: 2026-02-17 after v2.0 milestone start*
