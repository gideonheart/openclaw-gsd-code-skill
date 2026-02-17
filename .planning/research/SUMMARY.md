# Research Summary: Stop Hook Integration for gsd-code-skill

**Domain:** Event-driven agent control for Claude Code sessions
**Researched:** 2026-02-17
**Overall confidence:** HIGH

## Executive Summary

The Stop hook integration milestone replaces polling-based menu detection with event-driven agent control. Research confirms all required components are production-ready and already installed. The architecture is surgical: Claude Code fires a Stop hook when it finishes responding, the hook captures TUI state via tmux, and messages the correct OpenClaw agent directly via session ID.

Key validation: Claude Code 2.1.44 Stop hook provides complete stdin JSON schema with `stop_hook_active` guard, decision control via stdout JSON, and reliable event firing. OpenClaw 2026.2.16 agent CLI supports `--session-id` for precise targeting. tmux 3.4 send-keys `-l` flag handles literal text injection without key name interpretation. No new dependencies needed.

Critical finding: Plugin-based hooks have a known bug where JSON output is not captured (GitHub issue #10875). Solution: use inline settings.json hooks instead. This is a configuration choice, not a code limitation.

The changes are additive-first (Phase 1: create stop-hook.sh, add type action), then wire-up (Phase 2: settings.json), then cleanup (Phase 3: delete polling scripts). This prevents breakage during rollout.

## Key Findings

**Stack:** Bash-only. Claude Code Stop hook (stdin JSON) + tmux send-keys -l + openclaw agent --session-id. Zero new dependencies.

**Architecture:** Event-driven push model. Stop hook → capture pane → lookup agent in registry → background message to OpenClaw → exit. Agent decides action, calls menu-driver.sh.

**Critical pitfall:** Must check `stop_hook_active` field to prevent infinite loops. Hook NEVER blocks (no decision: "block" in output). Plugin hooks broken, use inline settings.json instead.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Phase 1: Additive Changes (No Breakage)**
   - Addresses: Create stop-hook.sh, add menu-driver.sh type action, add system_prompt to registry schema
   - Avoids: Breaking existing polling-based scripts while building new event-driven path
   - Rationale: Build parallel system first, validate in isolation

2. **Phase 2: Wire Up Stop Hook**
   - Addresses: Add Stop hook to ~/.claude/settings.json, remove SessionStart hook (gsd-session-hook.sh)
   - Avoids: Leaving both systems running simultaneously (duplicate wakes)
   - Rationale: Single atomic switchover point

3. **Phase 3: Update Launchers**
   - Addresses: Remove autoresponder.sh launch from spawn.sh, add system_prompt to spawn.sh and recover-openclaw-agents.sh
   - Avoids: Hardcoded prompts, per-agent customization blockers
   - Rationale: Launcher cleanup after hook is proven working

4. **Phase 4: Remove Polling Scripts**
   - Addresses: Delete autoresponder.sh, hook-watcher.sh, gsd-session-hook.sh
   - Avoids: Stale background processes, confusion about which system is active
   - Rationale: Clean slate, no legacy code

5. **Phase 5: Documentation**
   - Addresses: Update SKILL.md, README.md with new architecture
   - Avoids: Outdated documentation causing confusion
   - Rationale: Final polish after code is stable

**Phase ordering rationale:**
- Additive-first prevents breakage (can test stop-hook.sh manually before full integration)
- Wire-up is atomic (single settings.json change activates event-driven path)
- Launcher updates after hook proven working (no rollback complexity)
- Deletion after launchers updated (no orphaned processes)
- Documentation last (reflects actual working state)

**Research flags for phases:**
- Phase 1: No research needed (all technical details verified)
- Phase 2: No research needed (hook configuration schema confirmed)
- Phase 3: No research needed (spawn.sh pattern already uses --append-system-prompt)
- Phase 4: No research needed (simple file deletions)
- Phase 5: No research needed (documentation refresh)

**Conclusion:** This is a well-understood, low-risk refactoring. All technical unknowns resolved. Standard bash patterns. Phased rollout prevents breakage. No phases require deeper research.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All components version-verified in production environment |
| Features | HIGH | Stop hook behavior documented in official Claude Code hooks reference |
| Architecture | HIGH | Event-driven pattern matches OpenClaw's existing webhook model |
| Pitfalls | HIGH | Known bugs documented (plugin hooks), workaround confirmed (inline hooks) |

## Gaps to Address

**None.** All technical questions answered:

- ✅ Stop hook stdin JSON schema: Documented, verified
- ✅ Hook configuration in settings.json: Schema confirmed, example provided
- ✅ tmux send-keys -l behavior: Man page verified, flag supported in tmux 3.4
- ✅ openclaw agent --session-id usage: CLI help output confirms flag, syntax validated
- ✅ Recovery registry JSON structure: Existing file examined, Python upsert pattern clear
- ✅ Plugin vs inline hook decision: Bug researched, workaround identified
- ✅ stop_hook_active guard pattern: Official docs confirm necessity, example provided

**Future considerations (outside this milestone):**
- Monitoring: How to detect when Stop hook fails silently (future observability milestone)
- Scaling: What happens with 10+ concurrent sessions (future load testing milestone)
- Fallback: Should there be a timeout-based fallback if hook doesn't fire (future resilience milestone)

These are post-launch improvements, not blockers.

---
*Research complete for Stop hook integration milestone*
*Ready for roadmap creation*
