# Requirements: gsd-code-skill

**Defined:** 2026-02-17
**Core Value:** Reliable, intelligent agent session lifecycle — launch, recover, and respond without human intervention

## v1 Requirements

Requirements for milestone v1.0: Hook-Driven Agent Control. Each maps to roadmap phases.

### Hook Scripts

- [x] **HOOK-01**: Stop hook fires when Claude Code finishes responding in managed tmux sessions
- [x] **HOOK-02**: Stop hook captures pane content and sends structured wake message to correct OpenClaw agent via session ID
- [x] **HOOK-03**: All hook scripts exit cleanly (<5ms) for non-managed sessions (no $TMUX or no registry match)
- [x] **HOOK-04**: Stop hook guards against infinite loops via stop_hook_active field check
- [x] **HOOK-05**: Stop hook consumes stdin immediately to prevent pipe blocking
- [x] **HOOK-06**: Stop hook extracts context pressure percentage from statusline with configurable threshold
- [x] **HOOK-07**: Notification hook (idle_prompt) notifies OpenClaw when Claude waits for user input
- [x] **HOOK-08**: Notification hook (permission_prompt) notifies OpenClaw on permission dialogs (future-proofing)
- [x] **HOOK-09**: SessionEnd hook notifies OpenClaw immediately when session terminates
- [x] **HOOK-10**: PreCompact hook captures state before context compaction
- [x] **HOOK-11**: Hook scripts support hybrid mode — async by default, bidirectional per-agent via hook_settings.hook_mode

### Wake Message

- [x] **WAKE-01**: Wake message uses structured sections with clear headers ([PANE CONTENT], [CONTEXT PRESSURE], [AVAILABLE ACTIONS])
- [x] **WAKE-02**: Wake message includes session identity (agent_id and tmux_session_name)
- [x] **WAKE-03**: Wake message includes state hint based on pattern matching (menu, idle, permission_prompt, error)
- [x] **WAKE-04**: Wake message includes trigger type (response_complete vs session_start)
- [x] **WAKE-05**: Wake message always sent regardless of detected state — OpenClaw agent decides relevance
- [x] **WAKE-06**: Wake message includes context pressure as percentage + warning level (e.g., `72% [WARNING]`)

### Menu Driver

- [x] **MENU-01**: menu-driver.sh supports `type <text>` action for freeform text input via tmux send-keys -l

### Spawn

- [x] **SPAWN-01**: spawn.sh reads system_prompt from registry entry (fallback to default if empty)
- [x] **SPAWN-02**: spawn.sh supports `--system-prompt <text>` flag for explicit override
- [x] **SPAWN-03**: spawn.sh no longer has autoresponder flag or launch logic
- [x] **SPAWN-04**: spawn.sh no longer has hardcoded strict_prompt() function
- [x] **SPAWN-05**: spawn.sh uses jq for all registry operations (no Python dependency)

### Recovery

- [x] **RECOVER-01**: recover-openclaw-agents.sh passes system_prompt from registry to Claude on launch
- [x] **RECOVER-02**: Recovery handles missing system_prompt field gracefully (fallback default)

### Config

- [x] **CONFIG-01**: recovery-registry.json supports system_prompt field (top-level per agent) and hook_settings nested object
- [x] **CONFIG-02**: recovery-registry.example.json documents system_prompt, hook_settings with realistic multi-agent setup (Gideon, Warden, Forge)
- [x] **CONFIG-03**: settings.json has all hooks registered (Stop, Notification, SessionEnd, PreCompact), gsd-session-hook.sh removed from SessionStart
- [x] **CONFIG-04**: Global hook_settings at registry root level with per-agent override (three-tier fallback: per-agent > global > hardcoded, per-field merge)
- [x] **CONFIG-05**: Default system prompt stored in config/default-system-prompt.txt (tracked in git, minimal GSD workflow guidance)
- [x] **CONFIG-06**: hook_settings supports strict known fields: pane_capture_lines, context_pressure_threshold, autocompact_pct, hook_mode
- [x] **CONFIG-07**: Per-agent system_prompt replaces default entirely when set (CLI override > agent registry > default fallback)
- [x] **CONFIG-08**: New agent entries auto-populate hook_settings with defaults

### Cleanup

- [x] **CLEAN-01**: autoresponder.sh deleted
- [x] **CLEAN-02**: hook-watcher.sh deleted
- [x] **CLEAN-03**: gsd-session-hook.sh deleted

### Documentation

- [x] **DOCS-01**: SKILL.md updated with new hook architecture (all hook scripts, hybrid mode, hook_settings)
- [x] **DOCS-02**: README.md updated with registry schema (system_prompt, hook_settings) and recovery flow

## v2 Requirements

Requirements for milestone v2.0: Smart Hook Delivery. Replaces noisy 120-line raw pane dumps with precise, extracted content delivery.

### Content Extraction

- [x] **EXTRACT-01**: Stop hook extracts last assistant response from transcript_path JSONL using type-filtered content parsing (`content[]? | select(.type == "text")`)
- [x] **EXTRACT-02**: When transcript extraction fails (file missing, empty, parse error), fall back to pane diff (only new/added lines from last 40 pane lines)
- [x] **EXTRACT-03**: Per-session previous pane state stored in /tmp for diff fallback calculation

### AskUserQuestion Forwarding

- [x] **ASK-01**: PreToolUse hook fires on AskUserQuestion tool calls only (matcher: `"AskUserQuestion"`)
- [x] **ASK-02**: PreToolUse hook extracts structured question data (questions, options, header, multiSelect) from tool_input in stdin
- [x] **ASK-03**: PreToolUse hook sends question data to OpenClaw agent asynchronously (background, never blocks Claude Code UI)

### Wake Format

- [x] **WAKE-07**: Wake messages use v2 structured format: [SESSION IDENTITY], [TRIGGER], [CONTENT] (transcript or pane diff), [STATE HINT], [CONTEXT PRESSURE], [AVAILABLE ACTIONS]
- [x] **WAKE-08**: v1 wake format code removed entirely — clean break, no backward compatibility layer
- [x] **WAKE-09**: AskUserQuestion forwarding uses dedicated [ASK USER QUESTION] section with structured question/options data

### Shared Library

- [x] **LIB-01**: lib/hook-utils.sh contains shared extraction and diff functions (DRY — sourced by stop-hook.sh and pre-tool-use-hook.sh only)
- [x] **LIB-02**: Each function in lib has single responsibility — extract response, compute diff, format questions are separate functions

### Registration

- [x] **REG-01**: register-hooks.sh registers PreToolUse hook with AskUserQuestion matcher in settings.json
- [x] **REG-02**: session-end-hook.sh cleans up /tmp pane state files on session exit

### Documentation

- [x] **DOCS-03**: SKILL.md updated with v2.0 architecture (lib, pre-tool-use-hook.sh, v2 wake format)

## v3 Requirements

Requirements for milestone v3.0: Structured Hook Observability. Replaces plain-text debug_log with structured JSONL event logging — one complete record per hook invocation with full lifecycle data.

**Design decision:** Single-record-per-invocation approach — accumulate all lifecycle data (trigger, state, content, wake message, response, outcome, duration) during hook execution and write one JSONL record at the end. No correlation_id needed; no paired events to link. Background subshell writes the record after async response arrives.

### JSONL Foundation

- [ ] **JSONL-01**: Single complete JSONL record per hook invocation containing all accumulated lifecycle data (trigger, state, content source, wake message, response, outcome, duration)
- [ ] **JSONL-02**: Per-session `.jsonl` log files at `logs/{SESSION_NAME}.jsonl` alongside existing `.log` files
- [ ] **JSONL-03**: All string fields safely escaped via `jq --arg` — wake messages containing newlines, quotes, ANSI codes, embedded JSON produce valid JSONL
- [ ] **JSONL-04**: All JSONL appends use `flock` for atomic writes under concurrent hook fires (records >4KB exceed POSIX O_APPEND guarantee)
- [ ] **JSONL-05**: Shared `write_hook_event_record()` function in `lib/hook-utils.sh` — DRY foundation all six hooks source; single write point, single fix point

### Hook Migration

- [ ] **HOOK-12**: stop-hook.sh emits structured JSONL record replacing plain-text debug_log — includes full wake message body and OpenClaw response
- [ ] **HOOK-13**: pre-tool-use-hook.sh emits structured JSONL record replacing plain-text debug_log — includes AskUserQuestion data forwarded
- [ ] **HOOK-14**: notification-idle-hook.sh emits structured JSONL record replacing plain-text debug_log
- [ ] **HOOK-15**: notification-permission-hook.sh emits structured JSONL record replacing plain-text debug_log
- [ ] **HOOK-16**: session-end-hook.sh emits structured JSONL record replacing plain-text debug_log
- [ ] **HOOK-17**: pre-compact-hook.sh emits structured JSONL record replacing plain-text debug_log

### AskUserQuestion Lifecycle

- [ ] **ASK-04**: PreToolUse JSONL record includes `questions_forwarded` field showing what questions, options, and headers were sent to OpenClaw agent
- [x] **ASK-05**: PostToolUse hook (`post-tool-use-hook.sh`) emits JSONL record showing which answer OpenClaw agent selected and how TUI was controlled to achieve that decision
- [x] **ASK-06**: PreToolUse and PostToolUse records share `tool_use_id` field enabling question-to-answer lifecycle linking

### Operational

- [ ] **OPS-01**: Every JSONL record includes `duration_ms` field — time from hook entry to record write
- [ ] **OPS-02**: logrotate config at `/etc/logrotate.d/gsd-code-skill` prevents unbounded disk growth with `copytruncate` (safe for open `>>` file descriptors)
- [ ] **OPS-03**: `diagnose-hooks.sh` parses JSONL log files with `jq` for meaningful diagnostic output

## Future Requirements

Deferred beyond v3.0. Tracked but not in current roadmap.

### Resilience

- **RES-01**: Timeout-based fallback if Stop hook doesn't fire
- **RES-02**: Rate limiting on agent wakes for high-concurrency scenarios (20+ sessions)

### Advanced Delivery

- **ADV-01**: Context pressure heuristics beyond percentage threshold
- **ADV-02**: Registry caching in /tmp for 20+ concurrent sessions
- **ADV-03**: Per-hook dedup mode settings in hook_settings (measure actual rates first)
- **ADV-04**: Transcript diff delivery (conversation delta instead of pane delta)

### Validation

- **VAL-01**: Registry validation script (config/validate-registry.sh) for pre-deploy confidence

### Observability (beyond v3.0)

- **OBS-03**: Cross-session query tooling (`query-logs.sh`) for log analysis
- **OBS-04**: Remove plain-text `debug_log()` entirely after JSONL coverage confirmed complete

## Out of Scope

| Feature | Reason |
|---------|--------|
| LLM decision-making inside hook scripts | Hook must exit quickly; LLM inference takes 2-10s. OpenClaw agent handles decisions. |
| Plugin-based hooks | Known bug in Claude Code (GitHub #10875) — JSON output not captured. Use inline settings.json. |
| Global PreToolUse matcher (`"*"`) | Fires on every tool call — extreme overhead. Use specific `"AskUserQuestion"` matcher. |
| Blocking PreToolUse hook | AskUserQuestion is for interactive user input; blocking adds latency to TUI. Forward async only. |
| Python or Node.js for JSONL parsing | `tail + jq` is 2ms; Python/Node adds 50ms startup + dependency. |
| Dashboard rendering/UI | warden.kingdom.lv integration is separate work — v3.0 is log structure only. |
| OTLP/OpenTelemetry export | Only if a local collector is ever deployed on this host. |
| JSONL for guard exits (no TMUX, no registry) | jq overhead (5-15ms) on every non-managed session is unacceptable. Guard exits use plain printf or are omitted. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

### v1.0 (Shipped)

| Requirement | Phase | Status |
|-------------|-------|--------|
| HOOK-01 through HOOK-11 | Phase 1 | Done |
| WAKE-01 through WAKE-06 | Phase 1 | Done |
| MENU-01 | Phase 1 | Done |
| SPAWN-01 through SPAWN-05 | Phase 3 | Done |
| RECOVER-01, RECOVER-02 | Phase 3 | Done |
| CONFIG-01 through CONFIG-08 | Phase 1-2 | Done |
| CLEAN-01 through CLEAN-03 | Phase 4 | Done |
| DOCS-01, DOCS-02 | Phase 5 | Done |

### v2.0 (Shipped)

| Requirement | Phase | Status |
|-------------|-------|--------|
| LIB-01 | Phase 6 | Done |
| LIB-02 | Phase 6 | Done |
| EXTRACT-01 | Phase 6 | Done |
| EXTRACT-02 | Phase 6 | Done |
| EXTRACT-03 | Phase 6 | Done |
| ASK-01 | Phase 6 | Done |
| ASK-02 | Phase 6 | Done |
| ASK-03 | Phase 6 | Done |
| WAKE-07 | Phase 6 | Done |
| WAKE-08 | Phase 6 | Done |
| WAKE-09 | Phase 6 | Done |
| REG-01 | Phase 7 | Done |
| REG-02 | Phase 7 | Done |
| DOCS-03 | Phase 7 | Done |

### v3.0 (Active)

| Requirement | Phase | Status |
|-------------|-------|--------|
| JSONL-01 through JSONL-05 | Phase 8 | Pending |
| HOOK-12 through HOOK-17 | Phase 9 | Pending |
| ASK-04 | Phase 9 | Pending |
| ASK-05, ASK-06 | Phase 10 | Pending |
| OPS-01 | Phase 8 | Pending |
| OPS-02, OPS-03 | Phase 11 | Pending |

**Coverage:**
- v1 requirements: 38 total, all done
- v2 requirements: 14 total, all done
- v3 requirements: 17 total, all pending
- Mapped to phases: 17 (Phase 8: 6, Phase 9: 7, Phase 10: 2, Phase 11: 2)
- Unmapped: 0

---
*Requirements defined: 2026-02-17*
*Last updated: 2026-02-18 — v3.0 requirements added*
