# Project Research Summary

**Project:** gsd-code-skill v3.1 — Hook Refactoring and Migration Completion
**Domain:** Bash hook system — DRY refactoring, preamble extraction, settings unification, wake format migration
**Researched:** 2026-02-18
**Confidence:** HIGH

## Executive Summary

This milestone is a pure maintenance refactoring with zero new user-facing features and zero new dependencies. The entire scope is eliminating copy-paste debt present since v1.0 and completing migrations that v3.0 left unfinished. The primary deliverable is `lib/hook-preamble.sh` — a sourced bootstrap snippet that replaces the identical 27-line block copy-pasted across all 7 hook scripts. The secondary deliverable is `extract_hook_settings()` added to `lib/hook-utils.sh`, replacing the identical 12-line settings extraction block duplicated across 4 hooks. Everything else — [CONTENT] label migration, diagnose-hooks.sh fixes, echo-to-printf cleanup, session-end-hook guards — is bundled opportunistically because the same files are being touched anyway.

The technical approach is straightforward: bash 5.2 sourcing semantics, already in use throughout the codebase, provide everything needed. The critical non-obvious behavior is `BASH_SOURCE[1]` vs `BASH_SOURCE[0]` inside a sourced preamble file — the preamble must use index `[1]` (the calling hook's path) to correctly compute `HOOK_SCRIPT_NAME`, `SKILL_LOG_DIR`, and `SCRIPT_DIR`. This is the single highest-risk implementation point, verified empirically on the production host. All other patterns are mechanical replacements with well-understood behavior.

The main execution risk is not complexity but completeness: 7 hook scripts must all be migrated in a coordinated pass with specific deletions (remove old `source hook-utils.sh` block) alongside additions (add `source hook-preamble.sh`). Partial migration leaves a mixed state that is technically valid but confusing. The [CONTENT] migration for notification hooks is a label rename only — not a content source change — and this distinction must be enforced. Transcript extraction must NOT be added to notification hooks, which receive no `transcript_path` in their stdin.

## Key Findings

### Recommended Stack

No new dependencies. The refactoring uses bash 5.2 (installed), jq 1.7 (installed), and the existing sourcing mechanism already in every hook script. The pattern is: each hook replaces its 27-line inline preamble with a single `source lib/hook-preamble.sh` call. The preamble uses `BASH_SOURCE[1]` to identify its caller, sets all required variables, defines `debug_log()`, and sources `lib/hook-utils.sh` — making all library functions available to the hook. `shellcheck` (available via apt, not yet installed) can optionally validate the source chain but is not required.

**Core technologies:**
- bash 5.2.21: `BASH_SOURCE` array, `source` semantics, `declare -g` for caller-scope variable setting — all confirmed on production host; all patterns live-tested
- jq 1.7: three-tier fallback in single invocation (`per-agent // global // hardcoded`), compact JSON output for `extract_hook_settings()` return — already in every hook, no new usage
- flock (util-linux, installed): concurrent JSONL append protection — unchanged, preamble adds no new flock usage

### Expected Features

All features are internal refactoring. There are no user-facing behavior changes. The milestone is defined by which maintenance items it closes.

**Must have (table stakes — milestone incomplete without these):**
- `hook-preamble.sh` — extracts the 27-line bootstrap block from all 7 hooks into a single authoritative source file; one-place maintenance for log format, lib path, debug_log behavior
- `extract_hook_settings()` — extracts the 12-line three-tier settings block duplicated in 4 hooks into `lib/hook-utils.sh`; fixes pre-compact's missing `2>/dev/null` guards as a side effect
- [CONTENT] label migration — `notification-idle-hook.sh`, `notification-permission-hook.sh`, `pre-compact-hook.sh` rename `[PANE CONTENT]` to `[CONTENT]` in wake messages (label change only, content source unchanged — pane capture remains correct for these events)
- diagnose-hooks.sh Step 7 prefix-match fix — replace exact `tmux_session_name ==` match with `startswith(agent_id + "-")` to match actual hook lookup behavior; fixes false failures for sessions with `-2` suffix
- diagnose-hooks.sh Step 2 script list — add `pre-tool-use-hook.sh` and `post-tool-use-hook.sh` to the checked scripts array (currently 5, must be 7)
- echo to `printf '%s'` cleanup — replace all `echo "$VAR" | jq` with `printf '%s' "$VAR" | jq` in the 5 affected hook scripts; 2 scripts (pre-tool-use, post-tool-use) already correct

**Should have (bundle while touching the same files):**
- `session-end-hook.sh` jq error guards — add `2>/dev/null || echo ""` to lines 71-72; identified in v3.0 retrospective, not fixed in v3.0; file is being touched for preamble migration anyway
- Unified context pressure extraction — evaluate standardizing on `grep -oE` or `grep -oP` pattern; document the sentinel value choice (`"unknown"` vs `0`) for downstream consumers
- Pre-compact state detection documentation — confirm whether different grep patterns are intentional (different TUI text at PreCompact time) or accidental; add explanatory comment

**Defer (future milestone):**
- `write_hook_event_record()` internal deduplication — function works correctly; two near-identical jq blocks can be unified when next touching the file for another reason
- Eliminate plain-text `debug_log()` entirely — once JSONL coverage is confirmed complete with no gaps
- PostToolUse tool_response schema validation — requires live session data; separate Quick Task

### Architecture Approach

The target architecture is a strict two-layer library chain: each hook sources only `lib/hook-preamble.sh`, which in turn sources `lib/hook-utils.sh`. Hooks no longer source `hook-utils.sh` directly. The separation between the two library files is deliberate and must be preserved: `hook-preamble.sh` is a bootstrap snippet with intentional side effects (variable assignment, directory creation, function definition, log emission); `hook-utils.sh` is a pure function library with no side effects on source. The preamble must not gain initialization behavior that belongs in hooks, and the utils library must not gain bootstrap behavior.

**Major components:**
1. `lib/hook-preamble.sh` (NEW) — sets `SKILL_LOG_DIR`, `GSD_HOOK_LOG`, `HOOK_SCRIPT_NAME`, `SCRIPT_DIR`, `REGISTRY_PATH`, defines `debug_log()`, emits "FIRED" log entry, sources `hook-utils.sh`; uses `BASH_SOURCE[1]` throughout to reference the calling hook's path, not its own; approximately 25 lines
2. `lib/hook-utils.sh` (EXTENDED) — adds `extract_hook_settings()` as the 7th function; function accepts `registry_path` and `agent_data_json`, uses `declare -g` to set `PANE_CAPTURE_LINES`, `CONTEXT_PRESSURE_THRESHOLD`, `HOOK_MODE` in caller scope with three-tier jq fallback; approximately 20 new lines
3. All 7 hook scripts (THINNED) — replace 27+ lines of boilerplate with a single source call; 4 of the 7 also replace 12-line settings block with single `extract_hook_settings()` call; 3 of the 7 also get the [CONTENT] label rename; net reduction approximately 224 lines total across all 7 scripts
4. `scripts/diagnose-hooks.sh` (FIXED) — Step 7 prefix-match correction; Step 2 complete script list; independent of hook refactoring, can ship in the same or separate execution pass

### Critical Pitfalls

1. **`BASH_SOURCE[0]` in preamble resolves to preamble's own path, not the hook's path** — every path and name computation in `hook-preamble.sh` must use `BASH_SOURCE[1]`. Using `[0]` sets `HOOK_SCRIPT_NAME` to `hook-preamble.sh` in all logs (making log filtering by hook name impossible) and resolves `SCRIPT_DIR` to `lib/` instead of `scripts/`. The bug is silent — code runs without error, logs appear, but every entry shows the wrong source. Prevention: use `BASH_SOURCE[1]` in preamble for `HOOK_SCRIPT_NAME` and `SCRIPT_DIR`; verify immediately after extraction by firing a live hook and checking the log prefix.

2. **Old `source hook-utils.sh` block not deleted from hook scripts during migration** — after preamble is added, each hook's existing `source lib/hook-utils.sh` block must be explicitly removed. Double-source is currently harmless (pure function library), but leaving it creates confusion. Prevention: include deletion as an explicit step in the migration checklist; verify completion with `grep -rn 'source.*hook-utils.sh' scripts/` returning zero matches.

3. **[CONTENT] migration for notification hooks must not add transcript extraction** — notification and pre-compact hooks do not receive `transcript_path` in their stdin (Stop-event-specific field). The [CONTENT] migration for these hooks is a section label rename only. Copying stop-hook.sh's `extract_last_assistant_response` call into notification hooks produces code that always falls through to pane fallback — wasteful and misleading. Prevention: migration spec must explicitly state that notification hooks change only the string `[PANE CONTENT]` to `[CONTENT]`; no extraction logic changes.

4. **Pre-compact state detection patterns are not equivalent to stop/notification patterns** — `pre-compact-hook.sh` uses case-sensitive grep with different keyword strings and `"active"` as fallback state (vs `"working"` in other hooks). Blindly unifying state detection would silently change state reporting for pre-compact events. Prevention: do not extract a shared `detect_session_state()` function without first confirming whether pattern differences are intentional. Default to documenting the difference with a comment.

5. **`exit` in sourced preamble terminates the calling hook process** — preamble code runs in the calling hook's shell context. Any `exit` statement in the preamble exits the hook entirely. This is acceptable for the lib-not-found fatal condition only. Prevention: preamble should contain exactly one `exit 0` — the lib-missing guard; all other failure paths use `return 1` and let the calling hook decide.

## Implications for Roadmap

Based on the dependency graph from all four research files, the work splits into three phases with one hard sequencing constraint: the foundation (Phase 1) must complete before hook migration (Phase 2). Diagnostic fixes (Phase 3) are independent and can run in parallel with Phase 2 or after.

### Phase 1: Foundation — Create Shared Library Components

**Rationale:** `hook-preamble.sh` and `extract_hook_settings()` are root dependencies. Every hook file change in Phase 2 relies on these existing and being correct. Building them first means Phase 2 operates on finalized interfaces. The critical BASH_SOURCE[1] correctness requirement must be solved and verified here before Phase 2 uses the preamble across all 7 hooks simultaneously.
**Delivers:** `lib/hook-preamble.sh` (new file, ~25 lines); `extract_hook_settings()` added to `lib/hook-utils.sh` (~20 lines). No hook scripts changed yet.
**Addresses:** The structural duplication problem at its root — one canonical definition replaces 7 copies of the preamble block and 4 copies of the settings block.
**Avoids:** Pitfall 1 (BASH_SOURCE[0] vs BASH_SOURCE[1]) — must be solved and verified before Phase 2 depends on it; Pitfall 5 (exit in preamble) — preamble exit contract established here.
**Verification gate:** Source `hook-preamble.sh` from a test script (not from `lib/` directly), confirm `HOOK_SCRIPT_NAME` shows the test script name (not `hook-preamble.sh`), confirm `lookup_agent_in_registry` is callable after source.

### Phase 2: Hook Script Migration — Apply Preamble and Settings to All 7 Hooks

**Rationale:** All 7 hook scripts must be migrated in one coordinated pass. Mixed state (some hooks with preamble, some without) is technically valid but confusing to debug and leaves the maintenance debt partially intact. The echo-to-printf cleanup and session-end guard fix are bundled here because the same files are being opened anyway — opening each file twice would be pure overhead.
**Delivers:** All 7 hook scripts thinned by ~30-37 lines each; 3 notification/pre-compact hooks get [CONTENT] label rename; echo-to-printf cleanup applied to 5 hooks; session-end jq guards added. Total reduction: approximately 224 lines across 7 scripts, centralized into ~45 lines in lib.
**Implements:** Target source chain: hook → preamble → hook-utils; no hook script sources hook-utils.sh directly after this phase.
**Avoids:** Pitfall 2 (double-source) — deletion of old source blocks is an explicit required step; Pitfall 3 ([CONTENT] migration scope) — notification hooks get label rename only, no transcript extraction added; Pitfall 4 (pre-compact state detection) — keep existing patterns, add explanatory comment.
**Bundled with:** session-end-hook.sh jq guard fix (same file pass); echo-to-printf sweep (same file pass).

### Phase 3: Diagnostic Fixes — Align diagnose-hooks.sh with Production Hook Behavior

**Rationale:** The diagnose-hooks.sh fixes are fully independent of the hook refactoring — they touch a different file and can ship in parallel with Phase 2 or after. Grouping them in their own phase makes the scope explicit and provides a clean verification step.
**Delivers:** `diagnose-hooks.sh` Step 7 uses prefix-match lookup matching actual hook behavior; Step 2 checks all 7 hook scripts instead of 5.
**Uses:** `lookup_agent_in_registry()` from `lib/hook-utils.sh` — either sourced directly into diagnose-hooks.sh or inlined as equivalent jq logic. Sourcing is preferred to prevent future divergence.
**Avoids:** Pitfall 8 (Step 7 fix must not change Step 3) — Step 3 keeps exact `agent_id` match; only Step 7 gets the prefix-match `startswith()` logic.

### Phase Ordering Rationale

- Phase 1 before Phase 2 is a hard dependency: preamble and settings function must exist as stable interfaces before hooks are rewritten to use them.
- Phase 2 can be a single coordinated task: all 7 hook scripts follow the same mechanical pattern and are independent of each other after Phase 1.
- Phase 3 is independent of Phases 1 and 2: diagnose-hooks.sh does not import or depend on hook-preamble.sh. Best shipped alongside or after Phase 2 so that Step 2's complete script list verification reflects the final hook state.
- No separate phase for context pressure unification or state detection documentation: these are investigation tasks resolved inline during Phase 2. Default is to add a comment documenting the difference; unification is a stretch goal only if investigation confirms equivalence.

### Research Flags

No phase requires additional `/gsd:research-phase`. All patterns are empirically verified and implementation-ready.

Phases with well-documented patterns (no additional research needed):
- **Phase 1:** BASH_SOURCE[1] pattern documented and empirically tested on this host. `extract_hook_settings()` design with three-tier jq fallback and `declare -g` caller scope is fully specified with working code examples in STACK.md and ARCHITECTURE.md.
- **Phase 2:** Mechanical replacements — preamble source line, settings function call, echo-to-printf, label rename, guard additions. All patterns specified exactly with before/after examples. No research needed.
- **Phase 3:** Diagnostic fixes are small jq query changes with exact before/after specified in FEATURES.md and PITFALLS.md. Standard jq `startswith()` usage.

Attention point during Phase 2 (not a blocker, resolve inline):
- Pre-compact state detection: read the grep patterns during migration, decide in under 15 minutes whether to add a comment explaining why patterns differ or unify them. Default to comment if uncertain. Do not block Phase 2 on this investigation.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Zero new dependencies; BASH_SOURCE chain, declare -g, printf vs echo behavior all empirically verified on bash 5.2.21 on production host; no version concerns |
| Features | HIGH | Existing codebase is ground truth; all 7 hook scripts and lib files read in full; line-level citations for every duplication site; v3.0 retrospective provides independent validation of all 8 improvement areas |
| Architecture | HIGH | Current and target architecture fully mapped; source chain dependency graph drawn; component responsibilities and boundaries explicit; BASH_SOURCE[0] vs [1] is the only non-obvious element and it is resolved with empirical verification |
| Pitfalls | HIGH | Pitfalls derived from empirical bash testing on production host (not documentation inference); BASH_SOURCE behavior, exit propagation, double-source, variable scoping all confirmed via live execution; diagnose mismatch confirmed via direct jq execution against live registry |

**Overall confidence:** HIGH

### Gaps to Address

- **Pre-compact state detection intent:** Whether `pre-compact-hook.sh` uses different grep patterns intentionally (different TUI text at PreCompact time) or accidentally (copy-paste divergence) cannot be confirmed by static code analysis alone. Resolution during Phase 2: add a comment noting the difference. If Rolands wants confirmation of intent, a live pre-compact observation can be scheduled but is not blocking.

- **Context pressure sentinel unification:** The `"unknown"` vs `0` sentinel difference between stop/notification hooks and pre-compact hook is documented but the correct unified sentinel is not decided. Resolution during Phase 2: keep existing sentinel values per-hook (no change). If unification is needed for downstream OpenClaw parsing, treat as a separate task requiring confirmation of what the agent prompt expects.

- **Notification hook stdin schema:** That notification hooks do not receive `transcript_path` is inferred from the Claude Code hook event type (Notification vs Stop events) and supported by the v3.0 architecture research, but not verified against Claude Code source or official schema documentation. Resolution: the existing fallback in `extract_last_assistant_response()` (returns empty for missing/empty path) makes this risk-free regardless of actual behavior. The [CONTENT] migration for notification hooks does not add transcript extraction, so the schema question is moot.

## Sources

### Primary (HIGH confidence — empirical testing and direct codebase reading)

- `scripts/stop-hook.sh`, `notification-idle-hook.sh`, `notification-permission-hook.sh`, `pre-compact-hook.sh`, `session-end-hook.sh`, `pre-tool-use-hook.sh`, `post-tool-use-hook.sh` — current state, all duplication sites identified with line-level citations, echo vs printf usage confirmed
- `lib/hook-utils.sh` — 6 existing functions, "no side effects on source" design contract at line 4, exact signatures
- `scripts/diagnose-hooks.sh` — Step 7 exact-match bug confirmed via direct jq execution against live registry; Step 2 missing scripts confirmed via array inspection
- `docs/v3-retrospective.md` — 8 improvement items with exact file:line citations; independent validation of all research findings
- Bash 5.2.21 live testing on production host: BASH_SOURCE chain, exit propagation, declare -g, double-source behavior, printf vs echo backslash handling all confirmed empirically

### Secondary (MEDIUM confidence — multiple authoritative sources)

- [How to Geek](https://www.howtogeek.com/heres-why-printf-beats-echo-in-your-linux-scripts/) — printf vs echo safety for variable piping
- [Linuxize](https://linuxize.com/post/bash-printf-command/) — printf '%s' byte-safe behavior
- [Nick Janetakis](https://nickjanetakis.com/blog/detect-if-a-shell-script-is-being-executed-or-sourced) — BASH_SOURCE[0] == ${0} sourced-only enforcement pattern
- [Baeldung](https://www.baeldung.com/linux/shell-script-force-source) — source guard patterns
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) — naming conventions (UPPER_SNAKE_CASE constants, lower_snake_case functions, local for function-internal variables)
- [Arslan.io](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/) — idempotent source guard pattern

### Planning documents (HIGH confidence — first-party)

- `.planning/STATE.md` — Quick-9 scope, active phase decisions, confirmed v2.0 migration was stop-hook.sh only
- `.planning/PROJECT.md` — milestone goal, constraints (bash + jq only, no new binaries), active requirements
- `ROADMAP.md` — v3.0 confirmed shipped, v3.1 scope established

---
*Research completed: 2026-02-18*
*Ready for roadmap: yes*
