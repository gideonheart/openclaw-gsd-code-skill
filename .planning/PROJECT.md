# gsd-code-skill

## What This Is

An event-driven hook system for Claude Code that listens to all 15 hook events, routes them to the correct AI agent via OpenClaw gateway, and provides event-specific prompts so the agent can respond with GSD slash commands. Each event type lives in its own folder with a handler script and a prompt template.

## Core Value

When Claude Code fires any hook event, the right agent wakes up with the right context and knows exactly which GSD slash command to type next.

## Current Milestone: v4.0 Event-Driven Hook Architecture

**Goal:** Rewrite the hook system from scratch with an event-folder architecture where each Claude Code hook event maps to a `./events/{event_name}/` folder containing a handler script and agent prompt template.

**Target features:**
- `events/{event_type}/{subtype}/` nested folder structure matching Claude Code's event + matcher hierarchy
- `event_{descriptive_name}.mjs` handler scripts that read Claude Code's structured JSON stdin
- `prompt_{descriptive_name}.md` templates that tell the agent what to do with the event
- Agent resolution from `session` field in hook JSON via `agent-registry.json` (renamed from recovery-registry.json)
- OpenClaw gateway delivery: wake agent with content + event-specific prompt
- TUI driver per event type — routine actions handled by script, agent woken only for decisions
- PreToolUse → PostToolUse verification loop (agent decides answer, then confirms it was submitted correctly)
- Subtype routing: PreToolUse by `tool_name`, Notification by `notification_type`, SubagentStart/Stop by `agent_type`
- Shared lib for DRY agent resolution, gateway delivery, and JSON extraction
- Hook registration script for `~/.claude/settings.json` with proper matchers
- Linux-targeted (Ubuntu 24 — tmux, bash are Linux-only dependencies; SKILL.md os: linux)

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

- [x] Event-folder architecture with handler + prompt per event
- [x] Agent resolution from structured JSON `session` field via agent-registry.json
- [x] OpenClaw gateway delivery with `last_assistant_message` + prompt
- [x] Stop event handler: wake agent with response content, agent picks GSD command
- [x] PreToolUse/AskUserQuestion handler: forward questions + options, agent decides answer and sends keystrokes to tmux pane
- [x] PostToolUse verification: confirm agent's submitted answer matches what agent decided (feedback loop)
- [ ] Notification handlers (idle, permission): wake agent with context-specific prompt
- [x] Shared lib for agent resolution, gateway delivery, JSON field extraction
- [x] Hook registration script for all events in `~/.claude/settings.json` (quick-15: bin/install-hooks.mjs)
- [x] Delete all v1.0-v3.2 hook scripts, prompts, and dead code
- [x] agent-registry.json replaces recovery-registry.json

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
- **Integration points:** Claude Code hooks API (JSON stdin), OpenClaw gateway (`openclaw agent --session-id`), tmux, bin/tui-driver.mjs for TUI
- **v1.0-v3.2 shipped but being replaced:** 7 monolithic hook scripts with pane scraping, state regex, transcript parsing — replaced by clean JSON-based handlers
- **Linux-targeted:** Runs on Ubuntu 24 under the forge user. tmux and bash are Linux-only dependencies.

## Constraints

- **No additional dependencies**: Only what OpenClaw and Claude Code already provide (node, bash, jq, curl, tmux)
- **DRY/SRP**: Each file does one thing. Shared logic lives in lib. No code duplication.
- **No dead code**: Fresh start — delete everything from v1.0-v3.2 that isn't explicitly needed
- **Structured data only**: Match and route based on JSON fields from Claude Code, never regex on rendered text
- **Linux-targeted**: The runtime depends on tmux and bash. SKILL.md declares os: linux. If cross-platform becomes a goal, these dependencies would need abstraction.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Rewrite from scratch (v4.0) | v1.0-v3.2 hook system grew complex with pane scraping, state regex, transcript parsing — all replaced by Claude Code's `last_assistant_message` field | Implemented — Phase 1 deleted all v1-v3 artifacts |
| `events/{event_name}/` folder structure | SRP: each event gets its own handler + prompt. Easy to add new events, easy to find code. | Implemented — Phase 3 created events/stop/, events/session_start/, events/user_prompt_submit/ |
| `agent-registry.json` replaces `recovery-registry.json` | Clearer name, focused purpose: maps sessions to agents | Implemented — Phase 1 plan 01-02 |
| `last_assistant_message` as primary content source | Claude Code provides the full response text in structured JSON — no need for pane scraping or transcript parsing | Adopted — old pane scraping code deleted in Phase 1 |
| Tool-specific PreToolUse handlers (e.g., AskUserQuestion) | PreToolUse JSON includes `tool_name` and `tool_input` — prompt should teach agent how to interact with specific TUI element (multiSelect awareness) | — Pending |
| PreToolUse → PostToolUse verification loop | PreToolUse: agent reads question, decides answer, sends keystrokes. PostToolUse: agent confirms submitted answer matches decision. Closed-loop control. | — Pending |
| Full-stack delivery per event | Each event phase delivers all 3 files (handler + prompt + TUI driver) and validates end-to-end before moving on. No separate TUI phase. | Implemented — Phase 3 (Stop), Phase 4 (AskUserQuestion) |
| Node.js for all handlers and TUI drivers | Linux-targeted (tmux, bash are Linux-only; cross-platform is not a goal). TUI drivers use child_process.execFileSync for tmux send-keys. | Adopted — all event handlers are .mjs (Phase 1-4) |
| @file reference for long TUI content | tmux send-keys treats newlines as Enter — multiline content submits prematurely. Write to `logs/prompts/` and use `@file` syntax in commands. | Adopted — documented in tui-driver.mjs, SKILL.md, prompt_stop.md |
| Session rotation via bin/rotate-session.mjs | Agent openclaw_session_id is hardcoded — need a way to start fresh OpenClaw sessions while archiving old IDs with clickable file paths to session JSONL | Implemented — quick-16, session_history array in agent-registry schema |
| Tab autocomplete delay (500ms) | Claude Code needs time to process Tab autocomplete popup before Enter is sent — without delay, command never submits | Implemented — quick fix in tui-common.mjs, Atomics.wait-based sleep |

---
*Last updated: 2026-02-22 after Phase 04 completion + quick tasks 15-16*
