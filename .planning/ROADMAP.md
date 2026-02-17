# Roadmap: gsd-code-skill

## Overview

This roadmap transforms polling-based menu detection into event-driven agent control via Claude Code's native Stop hook. The journey starts with additive changes (new files that don't disrupt existing sessions), wires the Stop hook globally, updates launchers to use per-agent system prompts, removes obsolete polling scripts, and concludes with documentation updates. Each phase delivers a coherent, verifiable capability with zero risk to production sessions.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Additive Changes** - Create new components without disrupting existing sessions
- [ ] **Phase 2: Hook Wiring** - Register Stop hook globally, remove SessionStart hook watcher
- [ ] **Phase 3: Launcher Updates** - Update spawn and recovery scripts for system prompt support
- [ ] **Phase 4: Cleanup** - Remove obsolete polling scripts
- [ ] **Phase 5: Documentation** - Update skill documentation with new architecture

## Phase Details

### Phase 1: Additive Changes
**Goal**: Create all new components (stop-hook.sh, menu-driver type action, system_prompt field) without disrupting existing autoresponder/hook-watcher workflows
**Depends on**: Nothing (first phase)
**Requirements**: HOOK-01, HOOK-02, HOOK-03, HOOK-04, HOOK-05, HOOK-06, MENU-01, CONFIG-01, CONFIG-02
**Success Criteria** (what must be TRUE):
  1. stop-hook.sh exists and contains all safety guards (stop_hook_active check, stdin consumption, $TMUX validation, registry lookup, fast-path exits)
  2. menu-driver.sh supports `type <text>` action using tmux send-keys -l for literal freeform input
  3. recovery-registry.json schema includes system_prompt field with empty string default, backward compatible with existing entries
  4. Python upsert function uses setdefault for system_prompt field
  5. recovery-registry.example.json documents system_prompt field with usage examples
**Plans**: TBD

Plans:
- [ ] 01-01: TBD
- [ ] 01-02: TBD

### Phase 2: Hook Wiring
**Goal**: Wire Stop hook globally in settings.json and remove SessionStart hook watcher launcher
**Depends on**: Phase 1
**Requirements**: CONFIG-03
**Success Criteria** (what must be TRUE):
  1. Stop hook registered in ~/.claude/settings.json calling stop-hook.sh
  2. gsd-session-hook.sh removed from SessionStart hooks array in settings.json
  3. New Claude Code sessions fire Stop hook instead of spawning hook-watcher.sh
  4. Existing sessions with running hook-watcher continue working (brief overlap tolerated)
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

### Phase 3: Launcher Updates
**Goal**: Update spawn.sh and recover-openclaw-agents.sh to use system_prompt from registry with fallback defaults
**Depends on**: Phase 1
**Requirements**: SPAWN-01, SPAWN-02, SPAWN-03, SPAWN-04, RECOVER-01, RECOVER-02
**Success Criteria** (what must be TRUE):
  1. spawn.sh reads system_prompt from registry entry after upsert and uses it via --append-system-prompt (falls back to default if empty)
  2. spawn.sh supports --system-prompt flag for explicit override
  3. spawn.sh has no autoresponder flag or launch logic
  4. spawn.sh has no hardcoded strict_prompt function
  5. recover-openclaw-agents.sh extracts system_prompt per agent from registry and passes via --append-system-prompt on launch
  6. Recovery script handles missing system_prompt field gracefully with fallback default
  7. Recovery script uses per-agent error handling (no set -e abort) and sends summary even on partial success
  8. Registry writes use atomic pattern with flock to prevent corruption
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
**Goal**: Update skill documentation to reflect new Stop hook architecture and system_prompt configuration
**Depends on**: Phase 4
**Requirements**: DOCS-01, DOCS-02
**Success Criteria** (what must be TRUE):
  1. SKILL.md documents Stop hook architecture, flow, and system_prompt configuration
  2. README.md documents updated registry schema with system_prompt field and recovery flow with Stop hook
  3. Script list reflects removed scripts (autoresponder, hook-watcher, gsd-session-hook) and added stop-hook.sh
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Additive Changes | 0/2 | Not started | - |
| 2. Hook Wiring | 0/1 | Not started | - |
| 3. Launcher Updates | 0/2 | Not started | - |
| 4. Cleanup | 0/1 | Not started | - |
| 5. Documentation | 0/1 | Not started | - |
