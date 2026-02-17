# Roadmap: gsd-code-skill

## Overview

This roadmap transforms polling-based menu detection into event-driven agent control via Claude Code's native hook system (Stop, Notification, SessionEnd, PreCompact). The journey starts with additive changes (new hook scripts, registry schema, config files), wires all hooks globally, updates launchers to use per-agent system prompts, removes obsolete polling scripts, and concludes with documentation updates. Each phase delivers a coherent, verifiable capability with zero risk to production sessions. All scripts use bash + jq only — no Python dependency.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Additive Changes** - Create new hook scripts, config files, and registry schema without disrupting existing sessions
- [ ] **Phase 2: Hook Wiring** - Register all hooks globally, remove SessionStart hook watcher
- [ ] **Phase 3: Launcher Updates** - Update spawn and recovery scripts for system prompt support (jq-only)
- [ ] **Phase 4: Cleanup** - Remove obsolete polling scripts
- [ ] **Phase 5: Documentation** - Update skill documentation with new architecture

## Phase Details

### Phase 1: Additive Changes
**Goal**: Create all new components (5 hook scripts, menu-driver type action, hook_settings schema, default-system-prompt.txt) without disrupting existing autoresponder/hook-watcher workflows
**Depends on**: Nothing (first phase)
**Requirements**: HOOK-01 through HOOK-11, WAKE-01 through WAKE-06, MENU-01, CONFIG-01, CONFIG-02, CONFIG-04 through CONFIG-08
**Success Criteria** (what must be TRUE):
  1. stop-hook.sh exists with all safety guards (stop_hook_active check, stdin consumption, $TMUX validation, registry lookup, fast-path exits, hybrid mode support)
  2. notification-idle-hook.sh exists and handles idle_prompt events
  3. notification-permission-hook.sh exists and handles permission_prompt events (future-proofing)
  4. session-end-hook.sh exists and notifies OpenClaw on session termination
  5. pre-compact-hook.sh exists and captures state before context compaction
  6. All hook scripts share common guard patterns (stdin consumption, $TMUX check, registry lookup)
  7. menu-driver.sh supports `type <text>` action using tmux send-keys -l for literal freeform input
  8. recovery-registry.json schema includes system_prompt field (top-level) and hook_settings nested object with strict known fields
  9. Global hook_settings at registry root level with per-agent override and per-field merge (three-tier fallback)
  10. recovery-registry.example.json documents all fields with realistic multi-agent setup (Gideon, Warden, Forge)
  11. config/default-system-prompt.txt exists with minimal GSD workflow guidance, tracked in git
  12. Wake message format includes structured sections, session identity, state hint, trigger type, and context pressure with warning level
  13. No Python dependency — all registry operations use jq
**Plans**: 3 plans

Plans:
- [ ] 01-01-PLAN.md -- Foundation: registry schema (system_prompt, hook_settings), default system prompt, menu-driver type action
- [ ] 01-02-PLAN.md -- Wake-capable hooks: stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh
- [ ] 01-03-PLAN.md -- Lifecycle hooks: session-end-hook.sh, pre-compact-hook.sh

### Phase 2: Hook Wiring
**Goal**: Register all hooks globally in settings.json (Stop, Notification idle_prompt, Notification permission_prompt, SessionEnd, PreCompact) and remove SessionStart hook watcher launcher
**Depends on**: Phase 1
**Requirements**: CONFIG-03
**Success Criteria** (what must be TRUE):
  1. Stop hook registered in ~/.claude/settings.json calling stop-hook.sh
  2. Notification hooks registered with matchers for idle_prompt and permission_prompt
  3. SessionEnd hook registered calling session-end-hook.sh
  4. PreCompact hook registered calling pre-compact-hook.sh
  5. gsd-session-hook.sh removed from SessionStart hooks array in settings.json
  6. New Claude Code sessions fire all hooks instead of spawning hook-watcher.sh
  7. Existing sessions with running hook-watcher continue working (brief overlap tolerated)
**Plans**: 1 plan

Plans:
- [ ] 02-01-PLAN.md -- Create idempotent registration script, wire all 5 hooks into settings.json, remove gsd-session-hook.sh from SessionStart

### Phase 3: Launcher Updates
**Goal**: Update spawn.sh and recover-openclaw-agents.sh to use system_prompt from registry with fallback defaults, using jq for all registry operations
**Depends on**: Phase 1
**Requirements**: SPAWN-01 through SPAWN-05, RECOVER-01, RECOVER-02
**Success Criteria** (what must be TRUE):
  1. spawn.sh reads system_prompt from registry entry after upsert and uses it via --append-system-prompt (falls back to default-system-prompt.txt if empty)
  2. spawn.sh supports --system-prompt flag for explicit override
  3. spawn.sh has no autoresponder flag or launch logic
  4. spawn.sh has no hardcoded strict_prompt function
  5. spawn.sh uses jq for all registry operations (no Python upsert)
  6. Per-agent system_prompt always appends to default (never replaces)
  7. recover-openclaw-agents.sh extracts system_prompt per agent from registry and passes via --append-system-prompt on launch
  8. Recovery script handles missing system_prompt field gracefully with fallback default
  9. Recovery script uses per-agent error handling (no set -e abort) and sends summary even on partial success
  10. Registry writes use atomic pattern with flock to prevent corruption
**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD

### Phase 4: Cleanup
**Goal**: Remove obsolete polling scripts (autoresponder, hook-watcher, gsd-session-hook) now that spawn and recovery no longer launch them
**Depends on**: Phase 2, Phase 3
**Requirements**: CLEAN-01, CLEAN-02, CLEAN-03
**Success Criteria** (what must be TRUE):
  1. autoresponder.sh deleted from scripts directory
  2. hook-watcher.sh deleted from scripts directory
  3. ~/.claude/hooks/gsd-session-hook.sh deleted
  4. All existing hook-watcher processes killed via pkill
  5. Watcher state files removed from /tmp
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

### Phase 5: Documentation
**Goal**: Update skill documentation to reflect new hook architecture, all hook scripts, hybrid mode, hook_settings, and system_prompt configuration
**Depends on**: Phase 4
**Requirements**: DOCS-01, DOCS-02
**Success Criteria** (what must be TRUE):
  1. SKILL.md documents hook architecture (all 5 hook scripts), hybrid mode, hook_settings configuration, and system_prompt
  2. README.md documents updated registry schema with system_prompt field, hook_settings object, and recovery flow with all hooks
  3. Script list reflects removed scripts (autoresponder, hook-watcher, gsd-session-hook) and added hook scripts (stop-hook, notification-idle-hook, notification-permission-hook, session-end-hook, pre-compact-hook)
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Additive Changes | 0/3 | Not started | - |
| 2. Hook Wiring | 0/1 | Not started | - |
| 3. Launcher Updates | 0/2 | Not started | - |
| 4. Cleanup | 0/1 | Not started | - |
| 5. Documentation | 0/1 | Not started | - |
