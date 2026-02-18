# Milestones: gsd-code-skill

## v3.1 Hook Refactoring & Migration Completion (In Progress)

**Goal:** Extract shared code from duplicated hook preambles, unify divergent patterns, and complete the v2.0 [CONTENT] migration left incomplete in v3.0.

**Started:** 2026-02-18
**Phases:** TBD (defining roadmap)
**Requirements:** 12 total (5 refactoring, 3 migration, 3 diagnostic fixes, 1 code quality)

**Target:**
- hook-preamble.sh replacing 27-line preamble duplicated across 7 hooks
- extract_hook_settings() and detect_session_state() shared functions in lib/hook-utils.sh
- [CONTENT] migration completed for notification-idle, notification-permission, pre-compact
- diagnose-hooks.sh prefix-match fix and complete script list
- echo to printf '%s' sweep for escape sequence safety

## v3.0 Structured Hook Observability (Shipped)

**Goal:** Replace plain-text debug_log with structured JSONL event logging — one complete record per hook invocation with full lifecycle data.

**Started:** 2026-02-18
**Completed:** 2026-02-18
**Phases:** 4 (Phase 8: JSONL Foundation, Phase 9: Hook Script Migration, Phase 10: AskUserQuestion Lifecycle, Phase 11: Operational Hardening)
**Requirements:** 17 total (see REQUIREMENTS.md)

**What shipped:**
- write_hook_event_record() and deliver_async_with_logging() in lib/hook-utils.sh
- All 7 hooks emit structured JSONL records with full lifecycle data
- PostToolUse hook for AskUserQuestion answer logging with tool_use_id lifecycle linking
- diagnose-hooks.sh JSONL log analysis (Step 10)
- Per-session .jsonl log files in logs/ directory

## v2.0 Smart Hook Delivery (Shipped)

**Goal:** Replace blunt 120-line pane scraping with precise content extraction — transcript-based responses, AskUserQuestion forwarding via PreToolUse, diff-based delivery.

**Started:** 2026-02-17
**Completed:** 2026-02-18
**Phases:** 2 (Phase 6: Core Extraction and Delivery Engine, Phase 7: Registration and Documentation)
**Requirements:** 14 total (see REQUIREMENTS.md)

**What shipped:**
- lib/hook-utils.sh with transcript extraction, pane diff, question formatting functions
- PreToolUse hook for AskUserQuestion forwarding
- v2 wake format with [CONTENT] section (transcript primary, pane diff fallback)
- Clean break from v1 wake format — all v1 code removed

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
*Last updated: 2026-02-18 after v3.1 milestone start*
