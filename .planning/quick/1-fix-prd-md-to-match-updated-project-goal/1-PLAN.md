---
phase: quick-1
plan: 01
type: execute
wave: 1
depends_on: []
files_modified: [PRD.md]
autonomous: true
requirements: [HOOK-01, HOOK-02, HOOK-03, HOOK-04, HOOK-05, HOOK-06, HOOK-07, HOOK-08, HOOK-09, HOOK-10, HOOK-11, WAKE-01, WAKE-02, WAKE-03, WAKE-04, WAKE-05, WAKE-06, MENU-01, SPAWN-01, SPAWN-02, SPAWN-03, SPAWN-04, SPAWN-05, RECOVER-01, RECOVER-02, CONFIG-01, CONFIG-02, CONFIG-03, CONFIG-04, CONFIG-05, CONFIG-06, CONFIG-07, CONFIG-08, CLEAN-01, CLEAN-02, CLEAN-03, DOCS-01, DOCS-02]

must_haves:
  truths:
    - "PRD.md describes all 5 hook scripts (stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh, pre-compact-hook.sh)"
    - "PRD.md uses jq for all registry operations with zero Python references"
    - "PRD.md documents hook_settings nested object with three-tier fallback (per-agent > global > hardcoded)"
    - "PRD.md documents hybrid hook mode (async default + bidirectional per-agent)"
    - "PRD.md documents structured wake message format with sections, session identity, state hint, trigger type, context pressure"
    - "PRD.md documents config/default-system-prompt.txt as external file tracked in git"
    - "PRD.md shows settings.json with all hooks registered (Stop, Notification idle_prompt, Notification permission_prompt, SessionEnd, PreCompact)"
    - "PRD.md implementation phases match ROADMAP.md (5 phases with correct scope)"
  artifacts:
    - path: "PRD.md"
      provides: "Complete technical design document matching all 38 requirements"
      contains: "hook_settings"
  key_links:
    - from: "PRD.md"
      to: ".planning/REQUIREMENTS.md"
      via: "All 38 v1 requirements reflected in PRD sections"
      pattern: "hook_settings|notification-idle|session-end|pre-compact|bidirectional"
    - from: "PRD.md"
      to: ".planning/ROADMAP.md"
      via: "Implementation phases match roadmap phases 1-5"
      pattern: "Phase 1.*Additive|Phase 2.*Hook Wiring|Phase 3.*Launcher|Phase 4.*Cleanup|Phase 5.*Documentation"
---

<objective>
Rewrite PRD.md to match the expanded project scope from phase 1 context gathering.

Purpose: The current PRD.md reflects an earlier, narrower design (only stop-hook.sh, Python upsert, no hook_settings, no hybrid mode, no structured wake message). All planning documents (REQUIREMENTS.md, ROADMAP.md, PROJECT.md, 01-CONTEXT.md, ARCHITECTURE.md) have been updated with the full scope. PRD.md must be the authoritative technical design document that matches.

Output: Updated PRD.md at repo root.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/01-additive-changes/01-CONTEXT.md
@.planning/research/ARCHITECTURE.md
@PRD.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Rewrite PRD.md to reflect full expanded scope</name>
  <files>PRD.md</files>
  <action>
Rewrite PRD.md from scratch, preserving the general document structure (Context, Architecture, Changes, Implementation Order, Edge Cases, Verification) but updating ALL content to match the expanded scope. Use the planning documents as source of truth, NOT the old PRD content.

**Context section:**
- Describe the problem (polling-based scripts: autoresponder.sh and hook-watcher.sh)
- Mention the solution uses Claude Code's native hook system with 5 hook event types: Stop, Notification (idle_prompt), Notification (permission_prompt), SessionEnd, PreCompact
- Mention per-agent configurable system prompts via registry
- Mention hybrid hook mode (async default + bidirectional per-agent)
- Mention jq for all registry operations (no Python)

**Architecture diagram:**
- Show all 5 hook scripts, not just stop-hook.sh
- Show hybrid mode flow: async path (background openclaw call + exit 0) and bidirectional path (wait for response, return decision:block)
- Show OpenClaw agent receiving structured wake message with sections
- Show three-tier config fallback: per-agent hook_settings > global hook_settings > hardcoded defaults

**Changes section (expand from 12 items to cover full scope):**

1. NEW: scripts/stop-hook.sh — Core Stop hook. Guards: consume stdin, check stop_hook_active, check $TMUX, registry lookup. Capture pane (configurable depth via hook_settings.pane_capture_lines). Extract context pressure from statusline. Build structured wake message with sections ([SESSION IDENTITY], [TRIGGER], [STATE HINT], [PANE CONTENT], [CONTEXT PRESSURE], [AVAILABLE ACTIONS]). Support hybrid mode: async (background openclaw call) or bidirectional (wait, return decision:block). Use jq for registry reads.

2. NEW: scripts/notification-idle-hook.sh — Notification hook for idle_prompt events. Same guard pattern as stop-hook.sh (stdin consumption, $TMUX check, registry lookup). Captures pane, sends structured wake message with trigger: idle_prompt. Always async (no bidirectional for notification hooks).

3. NEW: scripts/notification-permission-hook.sh — Notification hook for permission_prompt events. Future-proofing for fine-grained permission handling. Same guard pattern. Sends wake with trigger: permission_prompt.

4. NEW: scripts/session-end-hook.sh — SessionEnd hook. Notifies OpenClaw immediately when session terminates (faster recovery than daemon polling). Minimal message: session identity + trigger: session_terminated.

5. NEW: scripts/pre-compact-hook.sh — PreCompact hook. Captures state before context compaction. Sends wake with trigger: pre_compact so OpenClaw can inject context preservation instructions if bidirectional mode enabled.

6. NEW: config/default-system-prompt.txt — External default system prompt file tracked in git. Minimal GSD workflow guidance (prefer /gsd:* commands, make atomic commits). No role/personality content. Used by spawn.sh and recover-openclaw-agents.sh via --append-system-prompt or --append-system-prompt-file.

7. MODIFY: scripts/menu-driver.sh — Add `type <text>` action for freeform text input via `tmux send-keys -l`. Update usage().

8. MODIFY: scripts/spawn.sh — Remove --autoresponder flag and launch logic. Remove hardcoded strict_prompt() function. Remove enable_autoresponder variable. Add --system-prompt flag for explicit override. Read system_prompt from registry after upsert. Replace Python upsert with jq. Read default prompt from config/default-system-prompt.txt. Per-agent system_prompt always appends to default (never replaces).

9. MODIFY: scripts/recover-openclaw-agents.sh — Extract system_prompt per agent via jq (replace Python parser). Pass system_prompt via --append-system-prompt on launch. Combine default + per-agent prompt. Handle missing system_prompt gracefully (fallback default).

10. MODIFY: config/recovery-registry.json — Add system_prompt field (top-level per agent, string). Add hook_settings nested object (global at root level + per-agent override). Strict known fields: pane_capture_lines, context_pressure_threshold, autocompact_pct, hook_mode. Three-tier fallback: per-agent > global > hardcoded. Auto-populate hook_settings with defaults for new entries.

11. MODIFY: config/recovery-registry.example.json — Show realistic multi-agent setup (Gideon, Warden, Forge). Document system_prompt field per agent. Document global hook_settings at root. Document per-agent hook_settings overrides. Show different configurations per agent (e.g., Warden with bidirectional mode, Forge with different pane depth).

12. MODIFY: ~/.claude/settings.json — Register ALL hooks:
    - Stop: calls stop-hook.sh
    - Notification (idle_prompt): calls notification-idle-hook.sh (Note: Stop and Notification idle_prompt do NOT support matchers - they always fire)
    - Notification (permission_prompt): calls notification-permission-hook.sh with matcher "permission_prompt"
    - SessionEnd: calls session-end-hook.sh
    - PreCompact: calls pre-compact-hook.sh
    - Remove gsd-session-hook.sh from SessionStart hooks
    - Keep gsd-check-update.js in SessionStart

13. DELETE: scripts/autoresponder.sh — Replaced by hook system + OpenClaw decision-making.

14. DELETE: scripts/hook-watcher.sh — Replaced by hook system.

15. DELETE: ~/.claude/hooks/gsd-session-hook.sh — Only purpose was launching hook-watcher.sh.

16. MODIFY: SKILL.md — Update with new hook architecture.

17. MODIFY: README.md — Update registry schema docs and recovery flow.

**Registry schema section:**
Show complete before/after registry JSON including:
- Global hook_settings at root level with all 4 fields (pane_capture_lines, context_pressure_threshold, autocompact_pct, hook_mode)
- Per-agent system_prompt field
- Per-agent hook_settings override (showing per-field merge)
- Three-tier fallback explanation

**settings.json section:**
Show complete before/after settings.json with ALL 5 hook registrations, not just Stop. Include the Notification hooks with and without matchers. Note that hooks snapshot at startup (changes require session restart).

**Structured wake message format section (NEW):**
Show example wake message with all sections:
- [SESSION IDENTITY]: agent_id, tmux_session_name
- [TRIGGER]: response_complete | idle_prompt | permission_prompt | session_terminated | pre_compact
- [STATE HINT]: menu | idle | permission_prompt | error | working
- [PANE CONTENT]: last N lines from tmux pane
- [CONTEXT PRESSURE]: percentage + warning level (e.g., "72% [WARNING]", "45% [OK]")
- [AVAILABLE ACTIONS]: menu-driver.sh commands

**Implementation phases (must match ROADMAP.md exactly):**
- Phase 1: Additive Changes — Create all new components without disrupting existing workflows
- Phase 2: Hook Wiring — Register all hooks in settings.json, remove SessionStart hook watcher
- Phase 3: Launcher Updates — Update spawn.sh and recovery for system prompt support (jq-only)
- Phase 4: Cleanup — Remove obsolete polling scripts (autoresponder, hook-watcher, gsd-session-hook)
- Phase 5: Documentation — Update SKILL.md and README.md

**Edge cases (expand for full scope):**
- Non-managed sessions: All hook scripts exit at $TMUX check or registry lookup (~1-5ms overhead)
- Infinite loops: stop_hook_active guard in Stop hook (and equivalent guards in other hooks)
- Stale hook-watcher processes during migration: Die when tmux session ends, brief overlap harmless
- Empty system_prompt in registry: Falls back to config/default-system-prompt.txt
- Registry unreadable: jq wrapped in || true, hook exits 0, never blocks Claude Code
- OpenClaw agent call fails: Backgrounded with || true, never blocks
- Hybrid mode timeout: Bidirectional mode has 10-minute hook timeout (configurable)
- Multiple hooks firing simultaneously: Claude Code runs all matching hooks in parallel, identical handlers deduplicated
- Hook settings missing fields: Three-tier fallback provides defaults for any missing field
- Notification hooks without matchers: Stop and Notification(idle_prompt) always fire — guard logic in script handles non-managed sessions

**Verification section (expand for all hooks):**
1. Stop hook fires in managed tmux session
2. Notification idle hook fires on idle state
3. Notification permission hook fires on permission prompt (when enabled)
4. SessionEnd hook fires on session termination
5. PreCompact hook fires before context compaction
6. Non-managed sessions unaffected (all hooks exit cleanly)
7. Menu-driver type action works
8. System prompt from registry used by spawn.sh
9. System prompt from registry used by recovery
10. Hybrid mode: async sends background wake
11. Hybrid mode: bidirectional returns decision:block
12. Three-tier hook_settings fallback resolves correctly

**CRITICAL rules:**
- ZERO Python references anywhere in the document. All registry operations use jq.
- All variable names and function names must be self-explanatory, no abbreviations (per CLAUDE.md).
- Keep the same general tone and conciseness as the original PRD — this is a technical design doc, not prose.
- Use ASCII art diagrams consistent with the original style.
  </action>
  <verify>
Verify PRD.md content:
1. `grep -c "python\|Python" PRD.md` returns 0 (no Python references)
2. `grep -c "hook_settings" PRD.md` returns > 0 (hook_settings documented)
3. `grep -c "notification-idle-hook" PRD.md` returns > 0 (all 5 hooks present)
4. `grep -c "notification-permission-hook" PRD.md` returns > 0
5. `grep -c "session-end-hook" PRD.md` returns > 0
6. `grep -c "pre-compact-hook" PRD.md` returns > 0
7. `grep -c "bidirectional" PRD.md` returns > 0 (hybrid mode documented)
8. `grep -c "three-tier\|per-agent.*global.*hardcoded" PRD.md` returns > 0 (fallback documented)
9. `grep -c "default-system-prompt.txt" PRD.md` returns > 0
10. `grep -c "Phase 5" PRD.md` returns > 0 (all 5 phases present)
11. `grep -c "SESSION IDENTITY\|STATE HINT\|TRIGGER" PRD.md` returns > 0 (structured wake message)
12. `grep -c "jq" PRD.md` returns > 0 (jq used for registry operations)
  </verify>
  <done>
PRD.md accurately reflects ALL 38 v1 requirements from REQUIREMENTS.md. Contains: 5 hook scripts, hybrid mode, hook_settings with three-tier fallback, structured wake message format, jq-only registry operations, config/default-system-prompt.txt, complete settings.json with all hooks, 5 implementation phases matching ROADMAP.md, expanded edge cases and verification steps. Zero Python references.
  </done>
</task>

</tasks>

<verification>
- PRD.md exists and is non-empty
- No Python/python references in PRD.md
- All 5 hook scripts mentioned by name
- hook_settings, hybrid mode, three-tier fallback documented
- Structured wake message format with all sections documented
- Implementation phases 1-5 match ROADMAP.md
- Registry schema shows both global and per-agent hook_settings
- settings.json example shows all 5 hook registrations
</verification>

<success_criteria>
PRD.md is the authoritative technical design document for the gsd-code-skill v1.0 milestone. Every section matches the decisions captured in 01-CONTEXT.md, the requirements in REQUIREMENTS.md, and the phases in ROADMAP.md. A developer reading only PRD.md would understand the full architecture, all components, and the implementation plan.
</success_criteria>

<output>
After completion, create `.planning/quick/1-fix-prd-md-to-match-updated-project-goal/1-SUMMARY.md`
</output>
