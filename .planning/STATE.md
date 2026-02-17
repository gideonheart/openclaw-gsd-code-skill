# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-17)

**Core value:** Reliable, intelligent agent session lifecycle — launch, recover, and respond without human intervention
**Current focus:** Defining requirements for v2.0 Smart Hook Delivery

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-02-17 — Milestone v2.0 started

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

v2.0 decisions:
- Transcript-based extraction over pane scraping: transcript_path JSONL provides exact response text, no tmux noise
- PreToolUse hook for AskUserQuestion: Notification hooks don't include question data; PreToolUse does via tool_input
- Diff-based pane delivery: Git-style delta reduces token waste and signal-to-noise for orchestrator

v1.0 decisions (carried forward):
- Stop hook over polling: Event-driven is more precise, lower overhead, enables intelligent decisions
- Multiple hook events: Stop, Notification (idle_prompt, permission_prompt), SessionEnd, PreCompact for full session visibility
- Per-agent system prompts in registry: Different agents need different personalities/constraints
- jq replaces Python: Cross-platform, no Python dependency for registry operations
- Hybrid hook mode: Async default with optional bidirectional per-agent for instruction injection
- hook_settings nested object: Three-tier fallback (per-agent > global > hardcoded) with per-field merge
- Separate scripts per hook event (SRP)

### Pending Todos

None yet.

### Blockers/Concerns

- Claude Code AskUserQuestion does NOT trigger Notification hooks (known limitation, open feature request)
- PreToolUse hook for AskUserQuestion can detect questions but cannot programmatically answer them
- transcript_path JSONL format needs investigation (line format, message structure)

### Research Findings (v2.0)

Hook stdin JSON fields:
- Common: session_id, transcript_path, cwd, permission_mode, hook_event_name
- Stop: stop_hook_active (boolean)
- Notification: message, title, notification_type (permission_prompt, idle_prompt, auth_success, elicitation_dialog)
- PreCompact: trigger (manual/auto), custom_instructions
- SessionEnd: reason (clear, logout, prompt_input_exit, other)
- PreToolUse/PostToolUse: tool_name, tool_input/tool_response (include actual data)

Key insight: transcript_path provides access to full conversation JSONL, enabling precise response extraction without pane scraping.

---
*Last updated: 2026-02-17 after v2.0 milestone start*
