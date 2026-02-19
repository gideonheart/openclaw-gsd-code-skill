# Requirements: gsd-code-skill

**Defined:** 2026-02-19
**Core Value:** When Claude Code fires any hook event, the right agent wakes up with the right context and knows exactly which GSD slash command to type next

## v4.0 Requirements

Requirements for v4.0 Event-Driven Hook Architecture. Each maps to roadmap phases.

### Event Architecture

- [ ] **ARCH-01**: Shared Node.js lib provides `resolveAgentFromSession()` that reads `session` field from hook JSON and looks up agent in agent-registry.json
- [ ] **ARCH-02**: Shared lib provides `wakeAgentViaGateway()` that sends content + prompt to agent's OpenClaw session via `openclaw agent --session-id`
- [ ] **ARCH-03**: Shared lib provides `extractJsonField()` for safe extraction of any field from hook JSON stdin
- [ ] **ARCH-04**: Event folders follow `events/{event_type}/{subtype}/` hierarchy with `event_{name}.js` handler + `prompt_{name}.md` template per event
- [ ] **ARCH-05**: Each event handler imports a single shared entry point that loads the lib, reads JSON stdin, and resolves the agent
- [ ] **ARCH-06**: All event handlers and libs are Node.js (not bash) for cross-platform compatibility (Windows, macOS, Linux)

### TUI Drivers

- [ ] **TUI-01**: Each event type has a `tui_driver_{event_name}.js` that knows how to interact with the Claude Code TUI for that specific event pattern
- [ ] **TUI-02**: Stop TUI driver knows how to type a GSD slash command, tab-complete, and press enter in the tmux pane
- [ ] **TUI-03**: AskUserQuestion TUI driver knows how to navigate options (arrow keys), select (space for multiSelect, enter for single-select), and submit
- [ ] **TUI-04**: TUI drivers replace monolithic menu-driver.sh for hook-driven interactions
- [ ] **TUI-05**: TUI drivers are referenced in prompt templates so the agent knows which driver to call

### Stop Event

- [ ] **STOP-01**: Stop event handler extracts `last_assistant_message` from hook JSON and sends it to the resolved agent via OpenClaw gateway with the prompt template
- [ ] **STOP-02**: Stop event prompt template instructs agent to read the response content, decide which GSD slash command to type, and call the TUI driver
- [ ] **STOP-03**: Stop event handler skips processing when `stop_hook_active` is true (infinite loop guard)

### AskUserQuestion Lifecycle

- [ ] **ASK-01**: PreToolUse(AskUserQuestion) handler extracts `tool_input.questions` array with question text, options, and multiSelect flag
- [ ] **ASK-02**: PreToolUse(AskUserQuestion) prompt template instructs agent to read the question, decide the answer, and call the AskUserQuestion TUI driver with the chosen option
- [ ] **ASK-03**: PostToolUse(AskUserQuestion) handler extracts `tool_response.answers` object and the original `tool_input.questions`
- [ ] **ASK-04**: PostToolUse(AskUserQuestion) prompt template instructs agent to verify that the submitted answer matches what agent decided, and report any mismatch

### Registry and Registration

- [ ] **REG-01**: `agent-registry.json` replaces `recovery-registry.json` as the agent-to-session mapping file (rename in config/, .gitignore, all references)
- [ ] **REG-02**: Registration script writes all v4.0 event handlers to `~/.claude/settings.json` with correct matchers (PreToolUse matcher: `AskUserQuestion`, PostToolUse matcher: `AskUserQuestion`, Stop: no matcher)
- [ ] **REG-03**: Registration script is idempotent — safe to run multiple times without duplicating entries

### Cleanup and Infrastructure

- [ ] **CLEAN-01**: Delete all v1.0-v3.2 hook scripts (stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, pre-tool-use-hook.sh, post-tool-use-hook.sh, pre-compact-hook.sh, session-end-hook.sh)
- [ ] **CLEAN-02**: Delete old lib/ files (hook-preamble.sh, hook-utils.sh) and replace with new Node.js shared lib
- [ ] **CLEAN-03**: Delete old scripts/prompts/ directory (replaced by events/*/prompt_*.md)
- [ ] **CLEAN-04**: Delete PRD.md, docs/v3-retrospective.md, old test scripts, and other v1-v3 artifacts
- [ ] **CLEAN-05**: Delete monolithic menu-driver.sh (replaced by per-event TUI drivers)
- [ ] **CLEAN-06**: Update install.sh for new event-folder structure and Node.js handlers
- [ ] **CLEAN-07**: Update SKILL.md and README.md with v4.0 architecture documentation
- [ ] **CLEAN-08**: Update .gitignore: rename recovery-registry.json entry to agent-registry.json

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
| ARCH-01 | — | Pending |
| ARCH-02 | — | Pending |
| ARCH-03 | — | Pending |
| ARCH-04 | — | Pending |
| ARCH-05 | — | Pending |
| ARCH-06 | — | Pending |
| TUI-01 | — | Pending |
| TUI-02 | — | Pending |
| TUI-03 | — | Pending |
| TUI-04 | — | Pending |
| TUI-05 | — | Pending |
| STOP-01 | — | Pending |
| STOP-02 | — | Pending |
| STOP-03 | — | Pending |
| ASK-01 | — | Pending |
| ASK-02 | — | Pending |
| ASK-03 | — | Pending |
| ASK-04 | — | Pending |
| REG-01 | — | Pending |
| REG-02 | — | Pending |
| REG-03 | — | Pending |
| CLEAN-01 | — | Pending |
| CLEAN-02 | — | Pending |
| CLEAN-03 | — | Pending |
| CLEAN-04 | — | Pending |
| CLEAN-05 | — | Pending |
| CLEAN-06 | — | Pending |
| CLEAN-07 | — | Pending |
| CLEAN-08 | — | Pending |

**Coverage:**
- v4.0 requirements: 29 total
- Mapped to phases: 0
- Unmapped: 29

---
*Requirements defined: 2026-02-19*
*Last updated: 2026-02-19 after TUI driver and Node.js additions*
