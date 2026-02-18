# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-18)

**Core value:** Reliable, intelligent agent session lifecycle — launch, recover, and respond without human intervention
**Current focus:** v3.0 Structured Hook Observability

## Current Position

Phase: 11 of 11 (Operational Hardening) -- COMPLETE
Plan: 2/2 — complete
Status: v3.0 Structured Hook Observability milestone COMPLETE. All phases 8-11 shipped.
Last activity: 2026-02-18 — Phase 11 Operational Hardening shipped (2/2 plans)

Progress: [██████████] 100% (v3.0 Phases 8-11)

## Performance Metrics

**Velocity:**
- Total plans completed: 22 (v1.0 phases 1-5 + v2.0 phases 6-7 + v3.0 phases 8-11)
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1-5 (v1.0) | 9 | — | — |
| 6 (v2.0) | 3 | ~9 min | ~3 min |
| 7 (v2.0) | 2 | ~7 min | ~3.5 min |
| 8 (v3.0) | 2 | ~6 min | ~3 min |
| 9 (v3.0) | 3 | ~8 min | ~2.7 min |
| 10 (v3.0) | 1 | ~3 min | ~3 min |
| 11 (v3.0) | 2 | ~4 min | ~2 min |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

Phase 6 decisions (confirmed and shipped):
- Transcript extraction as PRIMARY source — tail -40 + jq type-filtered content[] select. Confirmed working.
- Pane diff as FALLBACK only — diff last 40 pane lines, send only new additions. One source per message, never both.
- PreToolUse for AskUserQuestion — async background call, never blocks TUI. format_ask_user_questions via lib.
- Clean break from v1 — all v1 [PANE CONTENT] code removed. v2 [CONTENT] section only.
- lib/hook-utils.sh is the DRY anchor — three functions, sourced by stop-hook.sh and pre-tool-use-hook.sh only.
- fd-based flock with command group for atomic pane diff read-write cycle.

Phase 7 decisions (confirmed and shipped):
- PreToolUse timeout set to 10s (hook backgrounds work and exits immediately)
- register-hooks.sh registers 6 hook events including PreToolUse with AskUserQuestion matcher

Phase 8 decisions (confirmed and shipped):
- 12 explicit positional parameters for write_hook_event_record — no globals for full testability
- Silent failure (return 0) on jq error and flock timeout — never crash calling hook
- deliver_async_with_logging() backgrounds subshell with </dev/null — hook exits immediately
- lib/hook-utils.sh now has 6 functions: 4 original + write_hook_event_record + deliver_async_with_logging

Phase 9 decisions (confirmed and shipped):
- Option A for ASK-04: dedicated extra_fields_json parameter (13th) for write_hook_event_record, not wake_message reuse
- All 6 hooks source lib/hook-utils.sh at top of script before any guard exit
- HOOK_ENTRY_MS placed after STDIN_JSON=$(cat) — measures processing time, not startup
- Bidirectional branches use write_hook_event_record() directly with outcome=sync_delivered
- Plain-text debug_log preserved in parallel — JSONL is additive, not replacing

Phase 10 decisions (confirmed and shipped):
- Defensive multi-shape tool_response extractor for answer_selected — MEDIUM confidence on AskUserQuestion PostToolUse stdin schema until empirical validation from live session
- Raw stdin logged via debug_log for ASK-05 empirical validation — intentionally verbose in Phase 10, can be reduced once schema confirmed
- PostToolUse hook registers with AskUserQuestion matcher, timeout=10 (same as PreToolUse since hook backgrounds immediately)

Phase 11 decisions (confirmed and shipped):
- copytruncate for logrotate — required because hook scripts hold open >> file descriptors; standard rename would silently lose data
- daily rotation without size trigger — logrotate checks once daily regardless; observed rates ~70KB/day make daily appropriate
- No create directive in logrotate config — has no effect when copytruncate is in use
- JSONL diagnostic as Step 10 in diagnose-hooks.sh — between existing Step 9 (Hook Debug Logs) and optional test-wake (renumbered to Step 11)
- Missing JSONL file handled as INFO not FAIL — fresh installs have not fired hooks yet

### Pending Todos

None.

### Blockers/Concerns

- ~~Gideon's wake message parsing must be updated to handle v2 [CONTENT] format~~ — RESOLVED: no hardcoded parser exists. Wake messages are free-text consumed by LLM agents. Format change is transparent.
- ~~Session name sanitization: if future sessions use spaces or slashes in names, /tmp file naming breaks~~ — RESOLVED: pane state files now live in logs/ using SESSION_NAME in filename; same constraint but logs/ is persistent and skill-local.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 5 | Move GSD hook logs from /tmp to skill-local logs/ with per-session files | 2026-02-18 | c9b74c3 | [5-move-gsd-hook-logs-from-tmp-to-skill-loc](./quick/5-move-gsd-hook-logs-from-tmp-to-skill-loc/) |

### Quick Task Decisions

Quick-5 (2026-02-18): Two-phase logging — hooks.log shared until SESSION_NAME known, then redirect to {SESSION_NAME}.log per-session. SKILL_LOG_DIR computed via BASH_SOURCE at script top, separate from SCRIPT_DIR used for registry/lib lookups.

## Session Continuity

Last session: 2026-02-18
Stopped at: Completed Phase 11 (Operational Hardening) — v3.0 milestone complete
Resume file: None
