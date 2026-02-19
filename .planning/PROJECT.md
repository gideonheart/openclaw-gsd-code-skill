# gsd-code-skill

## What This Is

A multi-agent Claude Code session management skill for OpenClaw. It launches Claude Code sessions in tmux with strict GSD constraints, provides deterministic recovery after reboot/OOM, and handles interactive menu responses — enabling agents (Gideon, Warden, Forge) to operate autonomously across persistent coding sessions.

## Core Value

Reliable, intelligent agent session lifecycle — launch, recover, and respond to Claude Code sessions without human intervention.

## Current Milestone: v3.2 Per-Hook TUI Instruction Prompts

**Goal:** Replace generic [AVAILABLE ACTIONS] (identical across all hooks) with hook-specific [ACTION REQUIRED] sections loaded from external prompt templates — each hook tells the driving agent exactly what to do for that trigger type.

**Target features:**
- scripts/prompts/*.md — 7 per-hook instruction templates with {SESSION_NAME}, {MENU_DRIVER_PATH}, {SCRIPT_DIR} placeholders
- load_hook_prompt() shared function (#10) in lib/hook-utils.sh for template loading and substitution
- All 7 hooks use [ACTION REQUIRED] with only their relevant commands (not generic menu-driver listing)
- post-tool-use and session-end get [ACTION REQUIRED] sections (currently have none)
- Documentation updated (docs/hooks.md, SKILL.md, README.md)

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- spawn.sh — Launch Claude Code in tmux with GSD constraints, auto-upsert registry
- recover-openclaw-agents.sh — Deterministic multi-agent recovery after reboot/OOM
- menu-driver.sh — Atomic TUI actions (snapshot, choose, enter, esc, clear_then, submit, type)
- sync-recovery-registry-session-ids.sh — Refresh OpenClaw session IDs from agent directories
- systemd timer — Auto-recovery on boot (45s delay)
- Hook system (Stop, Notification, SessionEnd, PreCompact) — event-driven agent control (v1.0)
- Per-agent configurable system prompts via recovery registry (v1.0)
- hook_settings with three-tier fallback (per-agent > global > hardcoded) (v1.0)
- Hybrid hook mode: async default, bidirectional per-agent (v1.0)
- Separate scripts per hook event (SRP) (v1.0)
- Transcript JSONL extraction for Claude response text — no pane noise (v2.0, Phase 6)
- PreToolUse hook forwarding structured AskUserQuestion data to OpenClaw (v2.0, Phase 6)
- Pane diff fallback when transcript unavailable — only new/added lines (v2.0, Phase 6)
- Wake message v2 format with [CONTENT] replacing [PANE CONTENT] — clean break (v2.0, Phase 6)
- Shared lib/hook-utils.sh with DRY extraction functions (v2.0, Phase 6)
- PreToolUse hook registered in settings.json (v2.0, Phase 7)
- Pane state file cleanup on session exit (v2.0, Phase 7)
- SKILL.md updated with v2.0 architecture documentation (v2.0, Phase 7)
- hook-preamble.sh shared bootstrap with BASH_SOURCE[1] identity and source guards (v3.1, Phase 12)
- extract_hook_settings() three-tier jq fallback function in hook-utils.sh (v3.1, Phase 12)
- detect_session_state() unified state detection in hook-utils.sh (v3.1, Phase 12)
- All 7 hooks source hook-preamble.sh as single entry point — 320+ lines removed (v3.1, Phase 13)
- v2.0 [CONTENT] migration complete for notification-idle, notification-permission, pre-compact (v3.1, Phase 13)
- All jq piping uses printf '%s' across all 7 hooks — escape sequence safety (v3.1, Phase 13)
- session-end-hook.sh jq error guards prevent crash on malformed registry data (v3.1, Phase 13)

- diagnose-hooks.sh Step 7 prefix-match fix matching actual hook lookup behavior (v3.1, Phase 14)
- diagnose-hooks.sh Step 2 checks all 7 hook scripts including tool-use hooks (v3.1, Phase 14)
- load_hook_prompt() shared library function #10 with sed-based placeholder substitution (v3.2, Phase 15)
- menu-driver.sh arrow_up, arrow_down, space actions for multi-select TUI navigation (v3.2, Phase 15)
- 7 per-hook prompt template files in scripts/prompts/ with context-specific command subsets (v3.2, Phase 15)

### Active

<!-- Current scope. Building toward these. -->

- [x] Hook-specific [ACTION REQUIRED] in all 7 hook wake messages (Phase 16)
- [x] Documentation updates for prompt template system (Phase 17)

### Out of Scope

- Multi-project session management — one session per agent is sufficient
- Dashboard rendering/UI — warden.kingdom.lv integration is separate work
- Claude Code plugin/extension development — bash scripts only
- /copy programmatic API — no programmatic access exists, user-facing command only

## Context

- **Host:** Ubuntu 24 on Vultr, managed by Laravel Forge, user `forge`
- **Current scripts:** 13 bash scripts (7 hooks + 6 core) + 7 prompt templates, all production-quality
- **Agent architecture:** Gideon (orchestrator), Warden (coding), Forge (infra) — each with tmux sessions
- **Integration points:** Claude Code (`--append-system-prompt`, hooks API), OpenClaw (`openclaw agent --session-id`), tmux, systemd
- **Prior investigation:** Warden idle bug (resolved) — spawn.sh now uses `--append-system-prompt` correctly
- **PRD exists:** `PRD.md` at repo root with detailed technical design

## Constraints

- **Tech stack**: Bash + jq only (no Node/Python runtime dependencies) — matches OpenClaw skill conventions, cross-platform compatible
- **Compatibility**: Must work with Claude Code hooks API (Stop, Notification, SessionEnd, PreCompact, SessionStart)
- **Recovery**: Recovery flow must remain deterministic and work after cold boot
- **Non-breaking**: Existing managed sessions must not break during migration

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Stop hook over polling | Event-driven is more precise, lower overhead, enables intelligent decisions | Confirmed |
| Multiple hook events (Stop, Notification, SessionEnd, PreCompact) | OpenClaw needs full visibility into Claude Code sessions for autonomous operation | Confirmed |
| Per-agent system prompts in registry | Different agents need different personalities/constraints | Confirmed |
| jq replaces Python for registry operations | Cross-platform compatibility, no Python dependency, jq already installed | Confirmed |
| Hybrid hook mode (async + bidirectional) | Default async for speed, optional bidirectional for direct instruction injection | Confirmed |
| hook_settings nested object with three-tier fallback | Per-agent > global > hardcoded, per-field merge for granular config | Confirmed |
| External default-system-prompt.txt | Tracked in git, easy to edit without touching script code | Confirmed |
| Separate scripts per hook event (SRP) | Each script does one thing, easier to maintain and debug | Confirmed |
| Delete autoresponder + hook-watcher | Replaced by hook system; keeping both creates confusion | Confirmed |
| Transcript-based extraction over pane scraping | transcript_path JSONL provides exact response text, no tmux noise | Confirmed |
| PreToolUse hook for AskUserQuestion | Notification hooks don't include question data; PreToolUse does via tool_input | Confirmed |
| Diff-based pane delivery | Git-style delta reduces token waste and signal-to-noise for orchestrator | Confirmed |
| Structured JSONL over plain-text logs | Machine-parseable, dashboard-renderable, full lifecycle capture | Confirmed |
| Single record per invocation (not paired events) | Simpler — accumulate data during execution, write once at end. No correlation_id needed. Background subshell writes after async response. | Confirmed |
| Skill logs/ directory (not OpenClaw sessions/) | Separation of concerns; avoids coupling to OpenClaw internal format and pruning | Confirmed |
| BASH_SOURCE[1] for caller identity in sourced preamble | Automatic and verified; no parameter passing needed from hooks | Confirmed |
| JSON return from extract_hook_settings() | Immune to injection risk; consistent with existing lib/hook-utils.sh pattern | Confirmed |
| Pre-compact state name normalization | idle_prompt->idle, active->working to match detect_session_state() canonical names | Confirmed |
| printf '%s' for all jq piping | echo can expand escape sequences (\n, \t) corrupting JSON; printf '%s' is literal | Confirmed |

| External prompt templates over hardcoded heredocs | Editable without touching hook scripts, per-hook command subsets, git-diffable | Confirmed |
| {SCRIPT_DIR} as third placeholder | Enables prompt templates to reference any script (spawn.sh, menu-driver.sh) | Confirmed |
| sed pipe delimiter for placeholder substitution | Paths contain forward slashes; pipe delimiter avoids escaping | Confirmed |

---
*Last updated: 2026-02-19 after Phase 15*
