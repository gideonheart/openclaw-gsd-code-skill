# Requirements: gsd-code-skill

**Defined:** 2026-02-19
**Core Value:** When Claude Code fires any hook event, the right agent wakes up with the right context and knows exactly which GSD slash command to type next

## v4.0 Requirements

Requirements for v4.0 Event-Driven Hook Architecture. Each maps to roadmap phases.

### Event Architecture

- [x] **ARCH-01**: Shared Node.js lib provides `resolveAgentFromSession()` that reads `session` field from hook JSON and looks up agent in agent-registry.json
- [x] **ARCH-02**: Shared lib provides `wakeAgentViaGateway()` that sends content + prompt to agent's OpenClaw session via `openclaw agent --session-id`
- [x] **ARCH-03**: Shared lib provides `extractJsonField()` for safe extraction of any field from hook JSON stdin
- [x] **ARCH-04**: Event folders follow `events/{event_type}/{subtype}/` hierarchy with `event_{name}.mjs` handler + `prompt_{name}.md` template per event
- [x] **ARCH-05**: Each event handler imports a single shared entry point that loads the lib, reads JSON stdin, and resolves the agent
- [x] **ARCH-06**: All event handlers and libs are Node.js (not bash) for cross-platform compatibility (Windows, macOS, Linux)

### TUI Drivers

- [x] **TUI-01**: A generic `bin/tui-driver.mjs` handles TUI interaction for all event types — accepts a session name and command array, creates a queue, and types the first command
- [x] **TUI-02**: Stop TUI driver knows how to type a GSD slash command, tab-complete, and press enter in the tmux pane
- [x] **TUI-03**: AskUserQuestion TUI driver knows how to navigate options (arrow keys), select (space for multiSelect, enter for single-select), and submit
- [x] **TUI-04**: TUI drivers replace monolithic menu-driver.sh for hook-driven interactions
- [x] **TUI-05**: TUI drivers are referenced in prompt templates so the agent knows which driver to call

### Stop Event

- [x] **STOP-01**: Stop event handler extracts `last_assistant_message` from hook JSON and sends it to the resolved agent via OpenClaw gateway with the prompt template
- [x] **STOP-02**: Stop event prompt template instructs agent to read the response content, decide which GSD slash command to type, and call the TUI driver
- [x] **STOP-03**: Stop event handler skips processing when `stop_hook_active` is true (infinite loop guard)

### AskUserQuestion Lifecycle

- [x] **ASK-01**: PreToolUse(AskUserQuestion) handler extracts `tool_input.questions` array with question text, options, and multiSelect flag
- [x] **ASK-02**: PreToolUse(AskUserQuestion) prompt template instructs agent to read the question, decide the answer, and call the AskUserQuestion TUI driver with the chosen option
- [x] **ASK-03**: PostToolUse(AskUserQuestion) handler extracts `tool_response.answers` object and the original `tool_input.questions`
- [x] **ASK-04**: PostToolUse(AskUserQuestion) prompt template instructs agent to verify that the submitted answer matches what agent decided, and report any mismatch

### Registry and Registration

- [x] **REG-01**: `agent-registry.json` replaces `recovery-registry.json` as the agent-to-session mapping file (rename in config/, .gitignore, all references)
- [ ] **REG-02**: Registration script writes all v4.0 event handlers to `~/.claude/settings.json` with correct matchers (PreToolUse matcher: `AskUserQuestion`, PostToolUse matcher: `AskUserQuestion`, Stop: no matcher)
- [ ] **REG-03**: Registration script is idempotent — safe to run multiple times without duplicating entries

### Cleanup and Infrastructure

- [x] **CLEAN-01**: Delete all v1.0-v3.2 hook scripts (stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, pre-tool-use-hook.sh, post-tool-use-hook.sh, pre-compact-hook.sh, session-end-hook.sh)
- [x] **CLEAN-02**: Delete old lib/ files (hook-preamble.sh, hook-utils.sh) and replace with new Node.js shared lib
- [x] **CLEAN-03**: Delete old scripts/prompts/ directory (replaced by events/*/prompt_*.md)
- [x] **CLEAN-04**: Delete PRD.md, docs/v3-retrospective.md, old test scripts, and other v1-v3 artifacts
- [x] **CLEAN-05**: Delete monolithic menu-driver.sh (replaced by per-event TUI drivers)
- [ ] **CLEAN-06**: Update install.sh for new event-folder structure and Node.js handlers
- [x] **CLEAN-07**: Update SKILL.md and README.md with v4.0 architecture documentation
- [x] **CLEAN-08**: Update .gitignore: rename recovery-registry.json entry to agent-registry.json

## Future Requirements

### Additional Event Handlers

- **NOTIF-01**: Notification(idle_prompt) handler wakes agent when Claude is idle waiting for input
- **NOTIF-02**: Notification(permission_prompt) handler for non-bypass-permissions sessions
- **SESS-01**: SessionEnd handler for cleanup and state persistence
- **COMP-01**: PreCompact handler warns agent about context pressure
- **SUB-01**: SubagentStop handler tracks subagent completions

### Enhanced Automation

- **AUTO-01**: Hybrid mode where some events are handled by TUI driver directly (no agent wake)
- **AUTO-02**: Rule-based auto-response for predictable patterns (e.g., always select option 1 for specific questions)

## Out of Scope

| Feature | Reason |
|---------|--------|
| PermissionRequest handler | GSD always runs with --dangerously-skip-permissions |
| Pane scraping / tmux capture-pane for content | `last_assistant_message` from JSON replaces this |
| State detection via regex on pane content | Structured JSON fields replace this |
| Transcript JSONL parsing | `last_assistant_message` already has the text |
| JSONL structured event logging per hook | Simplify — remove v3.0 observability complexity |
| Per-agent hook_settings with three-tier fallback | Simplify configuration |
| Bidirectional hook mode | Async-only via OpenClaw gateway |
| Handling all 15 events in v4.0 | Focus on Stop + AskUserQuestion lifecycle first |
| Bash event handlers | Node.js for cross-platform, bash only where tmux requires it |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ARCH-01 | Phase 2 | Complete |
| ARCH-02 | Phase 2 | Complete |
| ARCH-03 | Phase 2 | Complete |
| ARCH-04 | Phase 3 | Complete |
| ARCH-05 | Phase 2 | Complete |
| ARCH-06 | Phase 2 | Complete |
| TUI-01 | Phase 3 | Complete |
| TUI-02 | Phase 3 | Complete |
| TUI-03 | Phase 4 | Complete |
| TUI-04 | Phase 4 | Complete |
| TUI-05 | Phase 3 | Complete |
| STOP-01 | Phase 3 | Complete |
| STOP-02 | Phase 3 | Complete |
| STOP-03 | Phase 3 | Complete |
| ASK-01 | Phase 4 | Complete |
| ASK-02 | Phase 4 | Complete |
| ASK-03 | Phase 4 | Complete |
| ASK-04 | Phase 4 | Complete |
| REG-01 | Phase 1 | Complete |
| REG-02 | Phase 5 | Pending |
| REG-03 | Phase 5 | Pending |
| CLEAN-01 | Phase 1 | Complete |
| CLEAN-02 | Phase 1 | Complete |
| CLEAN-03 | Phase 1 | Complete |
| CLEAN-04 | Phase 1 | Complete |
| CLEAN-05 | Phase 1 | Complete |
| CLEAN-06 | Phase 5 | Pending |
| CLEAN-07 | quick-11/12 | Complete |
| CLEAN-08 | Phase 1 | Complete |

**Coverage:**
- v4.0 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0

---
*Requirements defined: 2026-02-19*
*Last updated: 2026-02-22 — Phase 4 (ASK-01 through ASK-04) complete, quick-15 added install-hooks.mjs*
