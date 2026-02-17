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

Deferred to future release. Tracked but not in current roadmap.

### Observability

- **OBS-01**: Hook scripts log execution metrics (latency, registry hit/miss) to tmp file
- **OBS-02**: Dashboard integration for hook-driven agent activity

### Resilience

- **RES-01**: Timeout-based fallback if Stop hook doesn't fire
- **RES-02**: Rate limiting on agent wakes for high-concurrency scenarios (20+ sessions)

### Advanced Features

- **ADV-01**: Context pressure heuristics beyond percentage threshold
- **ADV-02**: Registry caching in /tmp for 20+ concurrent sessions

### Validation

- **VAL-01**: Registry validation script (config/validate-registry.sh) for pre-deploy confidence

## Out of Scope

| Feature | Reason |
|---------|--------|
| LLM decision-making inside hook scripts | Hook must exit quickly; LLM inference takes 2-10s. OpenClaw agent handles decisions. Bidirectional mode injects via decision:block reason, not LLM in hook. |
| Plugin-based hooks | Known bug in Claude Code (GitHub #10875) — JSON output not captured. Use inline settings.json. |
| Multi-agent swarm coordination | Single agent per session is sufficient for current architecture. |
| Polling fallback alongside hooks | Running both systems creates duplicate events and confusion. Commit to event-driven. |
| Automatic menu answering in hooks | Defeats purpose of intelligent agent decisions. Send pane to agent, let agent decide. |
| Python for registry manipulation | jq handles all JSON operations; no Python dependency for cross-platform compatibility. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HOOK-01 | Phase 1 | Pending |
| HOOK-02 | Phase 1 | Pending |
| HOOK-03 | Phase 1 | Pending |
| HOOK-04 | Phase 1 | Pending |
| HOOK-05 | Phase 1 | Pending |
| HOOK-06 | Phase 1 | Pending |
| HOOK-07 | Phase 1 | Pending |
| HOOK-08 | Phase 1 | Pending |
| HOOK-09 | Phase 1 | Pending |
| HOOK-10 | Phase 1 | Pending |
| HOOK-11 | Phase 1 | Pending |
| WAKE-01 | Phase 1 | Pending |
| WAKE-02 | Phase 1 | Pending |
| WAKE-03 | Phase 1 | Pending |
| WAKE-04 | Phase 1 | Pending |
| WAKE-05 | Phase 1 | Pending |
| WAKE-06 | Phase 1 | Pending |
| MENU-01 | Phase 1 | Pending |
| SPAWN-01 | Phase 3 | Pending |
| SPAWN-02 | Phase 3 | Pending |
| SPAWN-03 | Phase 3 | Pending |
| SPAWN-04 | Phase 3 | Pending |
| SPAWN-05 | Phase 3 | Pending |
| RECOVER-01 | Phase 3 | Pending |
| RECOVER-02 | Phase 3 | Pending |
| CONFIG-01 | Phase 1 | Pending |
| CONFIG-02 | Phase 1 | Pending |
| CONFIG-03 | Phase 2 | Pending |
| CONFIG-04 | Phase 1 | Pending |
| CONFIG-05 | Phase 1 | Pending |
| CONFIG-06 | Phase 1 | Pending |
| CONFIG-07 | Phase 1 | Pending |
| CONFIG-08 | Phase 1 | Pending |
| CLEAN-01 | Phase 4 | Pending |
| CLEAN-02 | Phase 4 | Pending |
| CLEAN-03 | Phase 4 | Pending |
| DOCS-01 | Phase 5 | Pending |
| DOCS-02 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 38 total
- Mapped to phases: 38
- Unmapped: 0

---
*Requirements defined: 2026-02-17*
*Last updated: 2026-02-17 after phase 1 context discussion*
