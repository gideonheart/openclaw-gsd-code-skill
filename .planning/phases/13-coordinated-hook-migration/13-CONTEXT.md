# Phase 13: Coordinated Hook Migration - Context

**Gathered:** 2026-02-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Refactor all 7 hook scripts for consistency: replace duplicated 27-line preamble blocks with single `source lib/hook-preamble.sh`, replace inline settings blocks with `extract_hook_settings()`, complete the v2.0 [CONTENT] label migration for 3 remaining hooks, sweep echo-to-printf for jq piping, and add session-end jq guards. Zero new user-facing behavior — pure maintenance eliminating copy-paste debt.

</domain>

<decisions>
## Implementation Decisions

### Wake message label migration
- Clean break — [PANE CONTENT] replaced with [CONTENT] in all 3 remaining hooks (notification-idle, notification-permission, pre-compact)
- No backward compatibility shim — DRY principle: one format, not two
- Gideon consumes wake messages as free-text via LLM — label change is transparent (confirmed in Phase 6 decisions)

### Pre-compact pattern normalization
- Full normalization — pre-compact must use the same detect_session_state() function as all other hooks
- Divergent case-sensitive grep patterns in pre-compact replaced with shared function's case-insensitive extended regex
- One function, one pattern set — DRY over preserving per-hook quirks

### Hook settings adoption scope
- Every hook that currently inlines settings extraction calls extract_hook_settings() instead
- Hooks that don't use settings don't get the call — SRP: don't add unused code paths
- The function already exists in lib/hook-utils.sh from Phase 12 — this phase is pure adoption

### Claude's Discretion
- Migration ordering across the 7 hooks (grouped by similarity, complexity, or alphabetical)
- Whether to normalize any other minor inconsistencies discovered during the sweep
- Exact printf format patterns where echo replacement isn't 1:1

</decisions>

<specifics>
## Specific Ideas

- Project principles are DRY and SRP — every decision follows from these two constraints
- Quick-9 retrospective identified the specific gaps: [CONTENT] only in stop-hook.sh, pre-compact divergent patterns, diagnose Step 7 exact-match
- Phase 12 decisions explicitly deferred pre-compact pattern normalization to Phase 13

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 13-coordinated-hook-migration*
*Context gathered: 2026-02-18*
