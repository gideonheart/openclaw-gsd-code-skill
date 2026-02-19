# gsd-code-skill

## What This Is

An event-driven hook system for Claude Code that listens to all 15 hook events, routes them to the correct AI agent via OpenClaw gateway, and provides event-specific prompts so the agent can respond with GSD slash commands. Each event type lives in its own folder with a handler script and a prompt template.

## Core Value

When Claude Code fires any hook event, the right agent wakes up with the right context and knows exactly which GSD slash command to type next.

## Current Milestone: v4.0 Event-Driven Hook Architecture

**Goal:** Rewrite the hook system from scratch with an event-folder architecture where each Claude Code hook event maps to a `./events/{event_name}/` folder containing a handler script and agent prompt template.

**Target features:**
- `events/{event_name}/event_{descriptive_name}.sh` handler scripts that read Claude Code's structured JSON stdin
- `events/{event_name}/prompt_{descriptive_name}.md` templates that tell the agent what to do with the event
- Agent resolution from `session` field in hook JSON via `agent-registry.json` (renamed from recovery-registry.json)
- OpenClaw gateway delivery: wake agent with `last_assistant_message` content + event-specific prompt
- Tool-aware handlers for PreToolUse (e.g., AskUserQuestion with `multiSelect` awareness)
- Shared lib for DRY agent resolution, gateway delivery, and JSON extraction
- Hook registration script for `~/.claude/settings.json`
- Cross-platform: works on Windows, macOS, Linux using only OpenClaw dependencies (no additional)

## Requirements

### Validated

<!-- Shipped and confirmed valuable from previous milestones. -->

- spawn.sh — Launch Claude Code in tmux with GSD constraints, auto-upsert registry
- recover-openclaw-agents.sh — Deterministic multi-agent recovery after reboot/OOM
- menu-driver.sh — Atomic TUI actions (snapshot, choose, enter, esc, clear_then, submit, type, arrow_up, arrow_down, space)
- sync-recovery-registry-session-ids.sh — Refresh OpenClaw session IDs from agent directories
- systemd timer — Auto-recovery on boot (45s delay)

### Active

<!-- v4.0 scope. Building toward these. -->

- [ ] Event-folder architecture with handler + prompt per event
- [ ] Agent resolution from structured JSON `session` field via agent-registry.json
- [ ] OpenClaw gateway delivery with `last_assistant_message` + prompt
- [ ] Stop event handler: wake agent with response content, agent picks GSD command
- [ ] PreToolUse/AskUserQuestion handler: forward questions + options, agent decides answer and sends keystrokes to tmux pane
- [ ] PostToolUse verification: confirm agent's submitted answer matches what agent decided (feedback loop)
- [ ] Notification handlers (idle, permission): wake agent with context-specific prompt
- [ ] Shared lib for agent resolution, gateway delivery, JSON field extraction
- [ ] Hook registration script for all events in `~/.claude/settings.json`
- [ ] Delete all v1.0-v3.2 hook scripts, prompts, and dead code
- [ ] Cross-platform compatibility (Windows, macOS, Linux)
- [ ] agent-registry.json replaces recovery-registry.json

### Out of Scope

- Pane scraping / tmux capture-pane for content extraction — `last_assistant_message` from JSON is the source
- State detection via regex on pane content — structured JSON fields replace this
- Transcript JSONL parsing — `last_assistant_message` already contains the response text
- JSONL event logging per hook invocation — simplify, remove v3.0 observability complexity
- Per-agent hook_settings with three-tier fallback — simplify configuration
- Bidirectional hook mode — async-only via OpenClaw gateway

## Context

- **Host:** Ubuntu 24 on Vultr, managed by Laravel Forge, user `forge`
- **Claude Code hook JSON contract:** `{"timestamp", "event", "session", "payload": {"session_id", "transcript_path", "cwd", "permission_mode", "hook_event_name", "last_assistant_message", "stop_hook_active", "tool_name", "tool_input", "tool_use_id"}}`
- **15 hook events:** SessionStart, Setup, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, SubagentStart, SubagentStop, Stop, TeammateIdle, TaskCompleted, PreCompact, SessionEnd, Notification (with subtypes: auth_success, permission_prompt, idle_prompt, elicitation_dialog)
- **Agent architecture:** Gideon (orchestrator), Warden (coding), Forge (infra) — each with tmux sessions
- **Integration points:** Claude Code hooks API (JSON stdin), OpenClaw gateway (`openclaw agent --session-id`), tmux, menu-driver.sh for TUI
- **v1.0-v3.2 shipped but being replaced:** 7 monolithic hook scripts with pane scraping, state regex, transcript parsing — replaced by clean JSON-based handlers
- **Cross-platform:** Must work wherever OpenClaw runs (Windows, macOS, Linux) using only OpenClaw dependencies

## Constraints

- **No additional dependencies**: Only what OpenClaw and Claude Code already provide (node, bash, jq, curl, tmux)
- **DRY/SRP**: Each file does one thing. Shared logic lives in lib. No code duplication.
- **No dead code**: Fresh start — delete everything from v1.0-v3.2 that isn't explicitly needed
- **Structured data only**: Match and route based on JSON fields from Claude Code, never regex on rendered text
- **Cross-platform**: No GNU-only flags, no Linux-specific paths. POSIX-compatible where possible.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Rewrite from scratch (v4.0) | v1.0-v3.2 hook system grew complex with pane scraping, state regex, transcript parsing — all replaced by Claude Code's `last_assistant_message` field | — Pending |
| `events/{event_name}/` folder structure | SRP: each event gets its own handler + prompt. Easy to add new events, easy to find code. | — Pending |
| `agent-registry.json` replaces `recovery-registry.json` | Clearer name, focused purpose: maps sessions to agents | — Pending |
| `last_assistant_message` as primary content source | Claude Code provides the full response text in structured JSON — no need for pane scraping or transcript parsing | — Pending |
| Tool-specific PreToolUse handlers (e.g., AskUserQuestion) | PreToolUse JSON includes `tool_name` and `tool_input` — prompt should teach agent how to interact with specific TUI element (multiSelect awareness) | — Pending |
| PreToolUse → PostToolUse verification loop | PreToolUse: agent reads question, decides answer, sends keystrokes. PostToolUse: agent confirms submitted answer matches decision. Closed-loop control. | — Pending |

---
*Last updated: 2026-02-19 after v4.0 milestone start*
