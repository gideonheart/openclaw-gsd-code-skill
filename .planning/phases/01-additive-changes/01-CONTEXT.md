# Phase 1: Additive Changes - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Create all new hook scripts, menu-driver type action, and registry schema additions without disrupting existing autoresponder/hook-watcher workflows. No hooks are registered in settings.json yet (that's Phase 2), so all new scripts are inert. Existing sessions continue working unchanged.

</domain>

<decisions>
## Implementation Decisions

### Agent Wake Message

- Structured sections with clear headers (e.g., `[PANE CONTENT]`, `[CONTEXT PRESSURE]`, `[AVAILABLE ACTIONS]`)
- Include session identity: agent_id and tmux_session_name in every message
- Include a state hint line based on simple pattern matching (e.g., `state: menu`, `state: idle`, `state: permission_prompt`)
- Include trigger type: `trigger: response_complete` vs `trigger: session_start` to differentiate fresh responses from session launches
- Always send wake message regardless of state (even on idle) — OpenClaw agent decides if action is needed
- Pane capture depth configurable per-agent via `hook_settings.pane_capture_lines` (default determined by Claude)

### Hook Architecture

- Separate scripts per hook event type (SRP): stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh, pre-compact-hook.sh
- Create permission prompt hook even though --dangerously-skip-permissions is used (future-proofing)
- Hybrid communication mode: default async (capture + background openclaw call + exit 0), with optional bidirectional mode per-agent (`hook_settings.hook_mode: "async" | "bidirectional"`)
- In bidirectional mode: hook waits for OpenClaw response, returns `{ "decision": "block", "reason": "..." }` to inject instructions into Claude
- SessionEnd hook notifies OpenClaw immediately when session terminates (faster recovery than daemon alone)
- All hook scripts share common guard patterns: stdin consumption, stop_hook_active check, $TMUX validation, registry lookup

### Hook Technical Context (from research)

- Claude Code has 14 hook event types total; we use 5: Stop, Notification (idle_prompt), Notification (permission_prompt), SessionEnd, PreCompact
- Stop hooks fire when Claude finishes responding — they do NOT fire on user interrupts
- Hooks snapshot at startup: changes to settings.json require session restart to take effect
- Hook timeout is 10 minutes by default (configurable per hook)
- Exit code 0 with JSON: Claude parses stdout for decisions. Exit code 2: stderr fed back as error
- `decision: "block"` with `reason` makes Claude continue working with that reason as its next instruction
- `continue: false` with `stopReason` halts Claude entirely (different from blocking)
- All matching hooks run in parallel; identical handlers are deduplicated
- Stop and Notification(idle_prompt) do NOT support matchers — they always fire
- Notification(permission_prompt) uses matcher `permission_prompt`
- `--append-system-prompt` appends to Claude's default prompt (preserves built-in capabilities)
- `--append-system-prompt-file <path>` loads from file directly (alternative to reading in bash)
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` env var triggers compaction at custom percentage

### Default System Prompt

- External file: `config/default-system-prompt.txt` tracked in git
- Content: minimal, focused on GSD workflow commands (/gsd:*, /clear, /resume)
- No role/personality content — agents get that from SOUL.md and AGENTS.md
- No mention of managed tmux session or orchestration layer — pure workflow guidance
- Per-agent `system_prompt` in registry always appends to (never replaces) the default
- Use `--append-system-prompt-file` or `--append-system-prompt` to pass to Claude Code (Claude's discretion on which flag)

### Context Pressure Signaling

- Configurable threshold per-agent via `hook_settings.context_pressure_threshold` (default determined by Claude)
- Format: percentage + warning level (e.g., `context: 72% [WARNING]`, `context: 45% [OK]`)
- No recommended action in the message — OpenClaw agent decides what to do (/compact, /clear, or continue)
- GSD slash commands already handle context management when used properly
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` configurable per-agent via `hook_settings.autocompact_pct`

### Registry Schema Design

- `system_prompt` field at top level per agent (string, used by spawn.sh, not hook-related)
- `hook_settings` as nested object per agent for hook-related config
- Global `hook_settings` at registry root level — per-agent overrides specific fields (three-tier fallback: per-agent > global > hardcoded)
- Per-field merge: if per-agent has `pane_capture_lines` but not `context_pressure_threshold`, use per-agent for first and global for second
- Strict known fields only — no open-ended keys
- All defaults documented explicitly in `recovery-registry.example.json`
- Auto-populate `hook_settings` with defaults when creating new agent entries
- Use jq for all registry reads/writes (no Python dependency)
- Read registry fresh every time (no caching)
- Example shows realistic multi-agent setup (Gideon, Warden, Forge) with different `hook_settings`
- Separate registry validation script (not in-hook validation) for pre-deploy confidence

### Claude's Discretion

- Available actions format: all actions always vs. contextual (Claude determines best approach for agent consumption)
- State hint categories: Claude determines useful set of states based on what agents need
- Wake message format: plain text with markers vs. JSON (Claude picks what OpenClaw agents handle best)
- Timestamp inclusion in wake messages (Claude determines operational value)
- Message delivery mechanism: single --message vs. separate flags (based on OpenClaw CLI capabilities)
- Default pane capture depth (currently 120 lines in PRD, Claude picks the right default)
- Default context pressure threshold percentage
- `--append-system-prompt` vs `--append-system-prompt-file` flag choice for spawn.sh

</decisions>

<specifics>
## Specific Ideas

- "This is a new project, no legacy code — remove unused functions, refactor, make it clean, lean, DRY and SRP, nested files and folders always structured well, best practices in OpenClaw ecosystem"
- "OpenClaw should be fully informed about everything happening in Claude Code sessions — add all hooks needed for autonomous operation"
- "Let OpenClaw agent decide what to do about context pressure — he can /compact if needed or just continue. If OpenClaw uses /gsd:* commands, context management shouldn't be an issue"
- Agents already know their role from SOUL.md and AGENTS.md — system_prompt is purely operational workflow guidance, not personality
- Separate validation script for registry so "when we are in production and enable daemon, we can be 101% sure all will work as expected — there is never a situation where we define something and daemon just fails and we never know"

</specifics>

<deferred>
## Deferred Ideas

- Registry validation script (config/validate-registry.sh) — new capability, deserves its own phase or addition to backlog
- PreCompact hook (pre-compact-hook.sh) — could inject context preservation instructions before compaction, but needs deeper investigation
- Agent SDK (Python/TypeScript) as alternative to tmux send-keys — future evolution path for OpenClaw, bypass tmux entirely
- `--permission-prompt-tool` MCP tool for fine-grained permission routing — relevant if moving away from `--dangerously-skip-permissions`

</deferred>

---

*Phase: 01-additive-changes*
*Context gathered: 2026-02-17*
