# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-18)

**Core value:** Reliable, intelligent agent session lifecycle — launch, recover, and respond without human intervention
**Current focus:** v3.1 Diagnostic Fixes (Phase 14)

## Current Position

Phase: 14 — Diagnostic Fixes
Plan: —
Status: Ready to plan (Phase 13 complete)
Last activity: 2026-02-18 — Phase 13 executed and verified (3 plans, 320+ lines removed)

## Performance Metrics

**Velocity:**
- Total plans completed: 26 (v1.0 phases 1-5 + v2.0 phases 6-7 + v3.0 phases 8-11 + v3.1 phases 12-13)
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
| 12 (v3.1) | 1 | ~4 min | ~4 min |
| 13 (v3.1) | 3 | ~6 min | ~2 min |

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

Phase 12 decisions (confirmed and shipped):
- BASH_SOURCE[1] for caller identity in sourced preamble — automatic, no parameter passing needed
- JSON return from extract_hook_settings() — immune to injection risk, consistent with existing lib style
- Stop/notification grep pattern as canonical for detect_session_state() — pre-compact differences deferred to Phase 13
- exit 0 only for lib-not-found fatal case in preamble — all other paths use return 0
- lib/hook-utils.sh now has 8 functions: 6 original + extract_hook_settings + detect_session_state

Phase 13 decisions (confirmed and shipped):
- All 7 hooks source hook-preamble.sh as single entry point — zero direct hook-utils.sh sourcing
- Pre-compact state detection normalized: idle_prompt -> idle, active -> working (using shared detect_session_state())
- [PANE CONTENT] label replaced with [CONTENT] across notification-idle, notification-permission, and pre-compact hooks
- All jq piping in hook scripts uses printf '%s' — echo-to-jq patterns eliminated from all 7 hooks
- session-end-hook.sh jq calls all have 2>/dev/null error guards — cleanup never crashes on malformed data
- Pre-tool-use and post-tool-use hooks needed only preamble migration — already used printf and had no settings/state detection

### Pending Todos

None.

### Blockers/Concerns

- ~~Gideon's wake message parsing must be updated to handle v2 [CONTENT] format~~ — RESOLVED: no hardcoded parser exists. Wake messages are free-text consumed by LLM agents. Format change is transparent.
- ~~Session name sanitization: if future sessions use spaces or slashes in names, /tmp file naming breaks~~ — RESOLVED: pane state files now live in logs/ using SESSION_NAME in filename; same constraint but logs/ is persistent and skill-local.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 5 | Move GSD hook logs from /tmp to skill-local logs/ with per-session files | 2026-02-18 | c9b74c3 | [5-move-gsd-hook-logs-from-tmp-to-skill-loc](./quick/5-move-gsd-hook-logs-from-tmp-to-skill-loc/) |
| 6 | Update SKILL.md, README.md, docs/hooks.md for Phase 10-11 additions | 2026-02-18 | 9cb9b76 | [6-update-docs-skill-md-readme-md-docs-hook](./quick/6-update-docs-skill-md-readme-md-docs-hook/) |
| 7 | Create install.sh single entry point installer | 2026-02-18 | 27cbed1 | [7-create-install-sh-single-entry-point-to-](./quick/7-create-install-sh-single-entry-point-to-/) |
| 8 | Remove logrotate dependency and update all docs | 2026-02-18 | a280418 | [8-remove-logrotate-dependency-and-update-a](./quick/8-remove-logrotate-dependency-and-update-a/) |
| 9 | Review v3.0 code and write retrospective | 2026-02-18 | e35296b | [9-review-v3-0-code-and-write-retrospective](./quick/9-review-v3-0-code-and-write-retrospective/) |

### Quick Task Decisions

Quick-5 (2026-02-18): Two-phase logging — hooks.log shared until SESSION_NAME known, then redirect to {SESSION_NAME}.log per-session. SKILL_LOG_DIR computed via BASH_SOURCE at script top, separate from SCRIPT_DIR used for registry/lib lookups.

Quick-6 (2026-02-18): Fixed stale /tmp reference in docs/hooks.md pane diff fallback description that was missed by Quick-5 migration.

Quick-7 (2026-02-18): Logrotate failure non-critical (warns and continues). Diagnostics optional via agent-name argument.

Quick-8 (2026-02-18): Removed logrotate entirely — user-space skill should not require sudo/root system config. install.sh reduced to 5 steps: pre-flight, logs dir, hooks, diagnostics, banner.

Quick-9 (2026-02-18): Incomplete v2.0 wake message migration — [CONTENT] applied only to stop-hook.sh; notification-idle, notification-permission, and pre-compact still use [PANE CONTENT]. Pre-compact state detection uses different grep patterns than other hooks (case-sensitive, different patterns). Diagnose Step 7 uses exact match vs hook prefix-match — fix needed for v4.0.

## Session Continuity

Last session: 2026-02-18
Stopped at: Phase 13 complete — Phase 14 planning is next
Resume file: None
