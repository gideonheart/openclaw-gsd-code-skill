# Requirements: gsd-code-skill

**Defined:** 2026-02-17
**Core Value:** Reliable, intelligent agent session lifecycle — launch, recover, and respond without human intervention

## v1 Requirements

Requirements for milestone v1.0: Hook-Driven Agent Control. Each maps to roadmap phases.

### Stop Hook

- [ ] **HOOK-01**: Stop hook fires when Claude Code finishes responding in managed tmux sessions
- [ ] **HOOK-02**: Stop hook captures pane content (last 120 lines) and sends to correct OpenClaw agent via session ID
- [ ] **HOOK-03**: Stop hook exits cleanly (<5ms) for non-managed sessions (no $TMUX or no registry match)
- [ ] **HOOK-04**: Stop hook guards against infinite loops via stop_hook_active field check
- [ ] **HOOK-05**: Stop hook consumes stdin immediately to prevent pipe blocking
- [ ] **HOOK-06**: Stop hook extracts context pressure percentage from statusline

### Menu Driver

- [ ] **MENU-01**: menu-driver.sh supports `type <text>` action for freeform text input via tmux send-keys -l

### Spawn

- [ ] **SPAWN-01**: spawn.sh reads system_prompt from registry entry (fallback to default if empty)
- [ ] **SPAWN-02**: spawn.sh supports `--system-prompt <text>` flag for explicit override
- [ ] **SPAWN-03**: spawn.sh no longer has autoresponder flag or launch logic
- [ ] **SPAWN-04**: spawn.sh no longer has hardcoded strict_prompt() function

### Recovery

- [ ] **RECOVER-01**: recover-openclaw-agents.sh passes system_prompt from registry to Claude on launch
- [ ] **RECOVER-02**: Recovery handles missing system_prompt field gracefully (fallback default)

### Config

- [ ] **CONFIG-01**: recovery-registry.json supports system_prompt field per agent entry
- [ ] **CONFIG-02**: recovery-registry.example.json documents system_prompt field
- [ ] **CONFIG-03**: settings.json has Stop hook registered, gsd-session-hook.sh removed from SessionStart

### Cleanup

- [ ] **CLEAN-01**: autoresponder.sh deleted
- [ ] **CLEAN-02**: hook-watcher.sh deleted
- [ ] **CLEAN-03**: gsd-session-hook.sh deleted

### Documentation

- [ ] **DOCS-01**: SKILL.md updated with new Stop hook architecture
- [ ] **DOCS-02**: README.md updated with registry schema and recovery flow

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Observability

- **OBS-01**: Stop hook logs execution metrics (latency, registry hit/miss) to tmp file
- **OBS-02**: Dashboard integration for hook-driven agent activity

### Resilience

- **RES-01**: Timeout-based fallback if Stop hook doesn't fire
- **RES-02**: Rate limiting on agent wakes for high-concurrency scenarios (20+ sessions)

### Advanced Features

- **ADV-01**: Context pressure heuristics beyond percentage threshold
- **ADV-02**: Registry caching in /tmp for 20+ concurrent sessions

## Out of Scope

| Feature | Reason |
|---------|--------|
| LLM decision-making inside Stop hook | Hook must exit in <5ms; LLM inference takes 2-10s. OpenClaw agent handles decisions. |
| Plugin-based hooks | Known bug in Claude Code 2.1.44 (GitHub #10875) — JSON output not captured. Use inline settings.json. |
| Multi-agent swarm coordination | Single agent per session is sufficient for current architecture. |
| Polling fallback alongside Stop hook | Running both systems creates duplicate events and confusion. Commit to event-driven. |
| Automatic menu answering in hook | Defeats purpose of intelligent agent decisions. Send pane to agent, let agent decide. |

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
| MENU-01 | Phase 1 | Pending |
| CONFIG-01 | Phase 1 | Pending |
| CONFIG-02 | Phase 1 | Pending |
| CONFIG-03 | Phase 2 | Pending |
| SPAWN-01 | Phase 3 | Pending |
| SPAWN-02 | Phase 3 | Pending |
| SPAWN-03 | Phase 3 | Pending |
| SPAWN-04 | Phase 3 | Pending |
| RECOVER-01 | Phase 3 | Pending |
| RECOVER-02 | Phase 3 | Pending |
| CLEAN-01 | Phase 4 | Pending |
| CLEAN-02 | Phase 4 | Pending |
| CLEAN-03 | Phase 4 | Pending |
| DOCS-01 | Phase 5 | Pending |
| DOCS-02 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0

---
*Requirements defined: 2026-02-17*
*Last updated: 2026-02-17 after initial definition*
