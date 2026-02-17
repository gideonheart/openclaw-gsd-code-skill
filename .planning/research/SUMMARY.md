# Project Research Summary

**Project:** gsd-code-skill v2.0 "Smart Hook Delivery"
**Domain:** Hook-driven autonomous agent control for Claude Code sessions — context optimization
**Researched:** 2026-02-17
**Confidence:** HIGH

## Executive Summary

v2.0 Smart Hook Delivery solves a concrete problem with the working v1.0 system: hook wake messages are too noisy. The orchestrator agent (Gideon) currently receives 120 lines of raw tmux pane content on every hook fire, including ANSI escape codes, statusline garbage, rendering artifacts, and large blocks of content identical to the previous delivery. Claude's actual response text is buried in this rendering noise. v2.0 replaces the raw pane dump with precision-extracted content: the last assistant message extracted directly from the transcript JSONL, a line-level diff of only what changed on screen since the last fire, deduplication to skip redundant wakes entirely, and a structured PreToolUse hook that forwards AskUserQuestion content as structured data before the TUI even renders it.

The recommended approach is strictly additive. Four new capabilities — transcript extraction, PreToolUse forwarding, diff-based delivery, and deduplication — are implemented in a new shared library (`lib/hook-utils.sh`) sourced only by the two scripts that need it (`stop-hook.sh` which is modified, and `pre-tool-use-hook.sh` which is new). The other four hook scripts (notification-idle, notification-permission, session-end, pre-compact) remain completely unchanged. Zero new dependencies are introduced; all tools required (jq, diff, md5sum, flock, tail) are already installed on the production Ubuntu 24 host. Claude Code 2.1.45 already running in production supports all required APIs including the PreToolUse hook with AskUserQuestion matcher.

The key risk is the wake message format change: the orchestrator has been trained on the v1.0 `[PANE CONTENT]` format and switching to `[CLAUDE RESPONSE]` + `[PANE DELTA]` without a transition period will break Gideon's parsing. The mitigation is explicit: add a `wake_message_version: 2` field to every new message, keep backward-compatible sections during the rollout transition, and update Gideon's parsing before or simultaneously with hook deployment. Three additional technical traps must be avoided in the extraction code: using positional `content[0].text` instead of type-filtered `content[]? | select(.type == "text") | .text`, reading full transcript files with `cat` instead of `tail -20`, and forgetting to background the `openclaw` call in the PreToolUse hook.

## Key Findings

### Recommended Stack

v2.0 requires zero new dependencies. All capabilities are built from the same production stack that v1.0 runs on. See `STACK.md` for full version verification.

**Core technologies:**
- `bash 5.x` — all hook scripts and lib functions; Ubuntu 24, production verified
- `jq 1.7` — JSONL parsing from transcript files, JSON extraction from hook stdin, registry operations
- `tail` (coreutils) — constant-time reads from transcript JSONL files regardless of session length; always `tail -20`, never `cat`; 2ms vs 100ms+ for large files
- `diff` (GNU diffutils 3.12) — pane delta extraction using `--new-line-format='%L' --old-line-format='' --unchanged-line-format=''` for clean new-lines-only output without diff markup noise
- `md5sum` (coreutils) — per-session pane content hashing for deduplication; chosen over sha256sum for speed (non-cryptographic use)
- `flock` (util-linux) — exclusive per-session locking on `/tmp` state files to prevent race conditions when Stop and Notification hooks fire concurrently
- `Claude Code 2.1.45` — provides `transcript_path` in all hook stdin payloads and supports `PreToolUse` with `"AskUserQuestion"` matcher; must be >= 2.0.76 (bug fix: GitHub #13439 that caused AskUserQuestion results to be stripped when any PreToolUse hook was active)

**What NOT to use:**
- Python or Node.js for JSONL parsing — adds dependency, 50ms startup vs 2ms for `tail + jq`
- `cat transcript | jq` — reads full file; latency grows unbounded with session age
- `diff -u` unified format — includes `+`/`-` markers and context lines; use `--new-line-format` flags instead
- Global PreToolUse matcher `"*"` — fires on every tool call (Bash, Read, Write, Edit, Glob); use specific `"AskUserQuestion"` matcher
- Separate state management daemon — over-engineering; `/tmp` files with `flock` are sufficient

### Expected Features

All six milestone features are table stakes — they must ship together because the wake message v2 format depends on the extraction features being complete. See `FEATURES.md` for behavior descriptions, schemas, and edge cases.

**Must have (all six required for v2.0 — tightly coupled through wake format):**
- Transcript-based response extraction — reads `transcript_path` JSONL, extracts last assistant `message.content[]` text blocks using type filtering, adds as `[CLAUDE RESPONSE]` section; eliminates ANSI noise entirely
- PreToolUse hook for AskUserQuestion — new `pre-tool-use-hook.sh`, registered in settings.json with matcher `"AskUserQuestion"` only; receives exact `tool_input.questions[]` with question text, header, options, multiSelect; sends `[ASK USER QUESTION]` section before TUI renders; always exits 0 (notification-only)
- Diff-based pane delivery — stores previous pane capture per session in `/tmp/gsd-pane-prev-SESSION.txt`; sends only new/changed lines as `[PANE DELTA]` instead of full 120-line dump
- Deduplication — md5sum hash comparison against `/tmp/gsd-pane-hash-SESSION.txt`; if pane content unchanged since last fire, skip full delivery; minimum 10-line context guarantee enforced even in skip path
- Structured wake message v2 format — compact format with `wake_message_version: 2`: `[SESSION IDENTITY]`, `[TRIGGER]`, `[CLAUDE RESPONSE]`, `[STATE HINT]`, `[PANE DELTA]`, `[CONTEXT PRESSURE]`, `[AVAILABLE ACTIONS]`; removes raw `[PANE CONTENT]`
- Minimum context guarantee — when pane delta is fewer than 10 lines (e.g., only a statusline change), pad with `tail -10` of current pane so orchestrator always has actionable baseline

**Defer to v2.x (post-validation):**
- Per-hook dedup mode settings in hook_settings (measure actual dedup rates first)
- AskUserQuestion async pre-notification with configurable delay window
- Transcript diff delivery (conversation delta instead of pane delta) — higher complexity, higher value for long sessions
- Selective hook muting (orchestrator instructs hook to be silent for N turns)
- PostToolUse hook for AskUserQuestion (forward which answer was selected)

### Architecture Approach

v2.0 is strictly additive to the existing 5-hook architecture. New capabilities are centralized in `lib/hook-utils.sh` to avoid duplicating extraction logic across hook scripts. Only two scripts change: `stop-hook.sh` gains three new processing steps (transcript extraction at step 7b, dedup check at step 9b, diff extraction at step 9c) and an updated wake message builder (step 10); `pre-tool-use-hook.sh` is created new. All four other hook scripts are untouched. See `ARCHITECTURE.md` for exact line-level integration points and complete data flow diagrams.

**Major components:**
1. `lib/hook-utils.sh` (NEW) — shared library with four functions: `extract_last_assistant_response()`, `extract_pane_diff()`, `is_pane_duplicate()`, `format_ask_user_questions()`; sourced only by stop-hook.sh and pre-tool-use-hook.sh; all new v2.0 extraction logic lives here
2. `scripts/stop-hook.sh` (MODIFIED) — Stop event entry point; gains transcript extraction, dedup check, diff extraction, and v2 wake format; all existing guards, registry lookup, state detection, and delivery logic unchanged
3. `scripts/pre-tool-use-hook.sh` (NEW) — PreToolUse entry point; matcher-scoped to AskUserQuestion only; always exits 0 (notification-only, never blocks); openclaw delivery is mandatory async background
4. `scripts/register-hooks.sh` (MODIFIED) — adds PreToolUse block with AskUserQuestion matcher to settings.json HOOKS_CONFIG; adds pre-tool-use-hook.sh to HOOK_SCRIPTS verification array
5. `/tmp/gsd-pane-prev-SESSION.txt` and `/tmp/gsd-pane-hash-SESSION.txt` (NEW runtime) — per-session ephemeral state files with flock protection; `/tmp` provides natural cleanup on reboot; stale file detection (24-hour age check) at hook startup
6. `config/recovery-registry.json` (OPTIONAL MODIFICATION) — v2 hook_settings fields (transcript_extract_chars, min_context_lines, dedup_enabled) if configurability is needed; hardcoded defaults acceptable for v2.0 MVP

**Build order (dependency chain from ARCHITECTURE.md):**
- Step 1: Create `lib/hook-utils.sh` — no dependencies
- Step 2: Create `pre-tool-use-hook.sh` — depends on lib (format_ask_user_questions)
- Step 3: Modify `stop-hook.sh` — depends on lib (three extraction functions)
- Step 4: Modify `register-hooks.sh` — depends on pre-tool-use-hook.sh existing and executable
- Steps 2 and 3 can proceed in parallel once Step 1 is complete; Steps 2 and 3 have no mutual dependency

### Critical Pitfalls

The following pitfalls produce silent wrong behavior that is hard to debug in production. See `PITFALLS.md` for full symptom lists, recovery strategies, performance trap analysis, and a 12-item "looks done but isn't" verification checklist.

1. **Positional content indexing** — Using `content[0].text` fails silently when thinking blocks or tool_use blocks precede the text block. Always use `content[]? | select(.type == "text") | .text`. Symptom: extraction works in simple sessions, fails randomly in sessions with extended thinking enabled.

2. **Full transcript file read** — Using `cat transcript | jq` causes hook latency to grow with session age (100ms–2s on multi-MB files). Always use `tail -20`. Performance degrades invisibly; only manifests in long-running production sessions.

3. **Synchronous openclaw call in PreToolUse** — Not backgrounding the `openclaw agent` call blocks Claude Code's UI for 200ms–2s before showing the AskUserQuestion prompt. Always use `</dev/null >/dev/null 2>&1 &`. Every single AskUserQuestion invocation is affected.

4. **Missing flock on pane state files** — Stop and Notification hooks can fire concurrently for the same session. Without `flock -x -w 2` on a per-session lock file, concurrent reads and writes to `/tmp/gsd-pane-prev-SESSION.txt` produce corrupt state and duplicate wakes. flock is required from day one.

5. **Wake message v2 format breaks orchestrator parsing** — The format change from `[PANE CONTENT]` to `[CLAUDE RESPONSE]` + `[PANE DELTA]` is a breaking change for Gideon. Add `wake_message_version: 2` to every new message header. Keep backward-compatible sections during rollout. Update Gideon's parsing before deploying new hooks, not after. Note: hooks snapshot at session startup — existing sessions keep v1 format until restarted.

6. **Dedup skip path with zero context** — When hash matches and wake is suppressed, failing to send the 10-line minimum context leaves the orchestrator unable to assess session state after a recovery. The minimum-context guarantee is a hard requirement, not optional — enforce it even in the "no change" path.

## Implications for Roadmap

All six v2.0 features share a single dependency chain: the shared library must be built first, then the two entry points, then registration. The features are tightly coupled through the wake message v2 format — `[CLAUDE RESPONSE]` replacing `[PANE CONTENT]` requires transcript extraction; `[PANE DELTA]` requires diff working with dedup running before it. The wake format change also creates a deployment sequencing concern: Gideon must be updated before the new hook format reaches it. This points to a clean 2-phase structure: build in Phase 1, deploy safely in Phase 2.

### Phase 1: Core Extraction and Delivery Engine

**Rationale:** All six milestone features are tightly coupled through the wake message v2 format and share the dependency chain through `lib/hook-utils.sh`. Building the library first, then the two scripts that source it, is the only valid order. This entire phase produces working new code without touching existing hook registration — safe to develop and test without affecting live sessions.

**Delivers:** `lib/hook-utils.sh` with all four extraction functions; `pre-tool-use-hook.sh` (complete new script); `stop-hook.sh` updated with transcript extraction (step 7b), dedup check (step 9b), diff extraction (step 9c), and wake message v2 format (step 10) with `wake_message_version: 2` field.

**Addresses:** All six v2.0 milestone features — transcript extraction, PreToolUse AskUserQuestion forwarding, diff-based delivery, deduplication, wake message v2 format, minimum 10-line context guarantee.

**Avoids:**
- Content[0].text indexing failure — use type-filtered `content[]? | select(.type == "text") | .text` (Pitfall 1)
- Full-file transcript reads — enforce `tail -20` in lib function comments and code (Pitfall 2 / Pitfall 3)
- Synchronous PreToolUse delivery — always background openclaw call (Pitfall 3)
- Missing flock — use from day one on all `/tmp` state file read-write cycles (Pitfall 4)
- Empty extraction results — always provide non-empty fallback strings (Pitfall 2)
- transcript_path file not found — check file existence before reading (Pitfall 11 in PITFALLS.md)

**Build order within phase:**
1. Create `lib/hook-utils.sh` (no dependencies; provides all four functions)
2. Create `pre-tool-use-hook.sh` in parallel with step 3 (depends on lib)
3. Modify `stop-hook.sh` in parallel with step 2 (depends on lib)

### Phase 2: Registration, Deployment, and Backward Compatibility

**Rationale:** Hook scripts snapshot at session startup — existing Claude Code sessions keep running v1.0 hooks until they restart. During the transition, Gideon receives both v1.0 `[PANE CONTENT]` and v2.0 `[CLAUDE RESPONSE]` format messages simultaneously. Registration and Gideon compatibility handling must be addressed as a coordinated deployment, not as a pure code change.

**Delivers:** Updated `register-hooks.sh` with PreToolUse registration block (AskUserQuestion matcher, 30s timeout); `session-end-hook.sh` updated to clean up `/tmp/gsd-pane-prev-SESSION.txt` on clean exits; stale temp file detection (24-hour age check) added to hook startup; verification that Gideon's parsing handles both v1 and v2 format messages; SKILL.md documentation update with minimum version requirement (Claude Code >= 2.0.76).

**Avoids:**
- Wake v2 format breaking Gideon's parsing — update orchestrator parsing before deploying registration (Pitfall 5)
- Stale pane delta files from dead sessions — age check at hook startup + session-end cleanup (Pitfall 7)
- PreToolUse + AskUserQuestion bug — add `claude --version >= 2.0.76` gate in register-hooks.sh (Pitfall 4 in PITFALLS.md)

**Deployment gate:** Gideon's wake message parsing must be updated and confirmed before `register-hooks.sh` is run. The `wake_message_version: 2` field allows Gideon to detect and handle both formats simultaneously during the session transition period.

### Phase Ordering Rationale

- Phase 1 before Phase 2: registration requires the scripts to exist; the format change risk requires Gideon to be updated first
- `lib/hook-utils.sh` before both entry points: both scripts source it; no shortcuts
- Steps 2 and 3 within Phase 1 can proceed in parallel: `pre-tool-use-hook.sh` and `stop-hook.sh` share only the lib dependency, not each other
- Gideon orchestrator update is a Phase 2 concern, not Phase 1: the new hook scripts can be tested locally without registering them in settings.json
- `session-end-hook.sh` cleanup belongs in Phase 2: the temp file naming pattern is established in Phase 1, cleanup implementation depends on knowing those names

### Research Flags

Phases with well-documented patterns — skip additional research:
- **Phase 1 (lib/hook-utils.sh):** All four function implementations specified with working bash code in ARCHITECTURE.md; JSONL structure verified against live transcripts; no new patterns required
- **Phase 1 (stop-hook.sh modifications):** Exact integration points mapped to specific line numbers in ARCHITECTURE.md (steps 7b, 9b, 9c, 10); no ambiguity about where changes go
- **Phase 1 (pre-tool-use-hook.sh):** Complete data flow diagram and full wake message format in ARCHITECTURE.md; AskUserQuestion schema confirmed from official docs and live transcripts
- **Phase 2 (register-hooks.sh):** Registration pattern already exists in v1.0 for Stop/Notification/SessionEnd/PreCompact hooks; PreToolUse addition follows identical pattern

Phases that need coordination during execution (not research gaps):
- **Phase 2 (Gideon compatibility):** Research documents the format change and version field, but does not inspect Gideon's actual wake message parsing code. Before Phase 2 registration, Gideon's parsing logic must be found and confirmed. This is an execution-time coordination step with the orchestrator, not a research gap for the hooks themselves.
- **Phase 2 (session-end-hook.sh):** Current session-end-hook.sh implementation should be inspected before adding temp file cleanup to confirm no unintended side effects on existing clean-exit behavior.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Zero new dependencies; all tools version-checked on production host (`claude --version` 2.1.45, `jq --version` 1.7, `diff --version` GNU 3.10, `flock` confirmed); Claude Code 2.1.45 confirmed supporting all required APIs and exceeding 2.0.76 bug-fix threshold |
| Features | HIGH | Six features fully specified with schemas from official docs; AskUserQuestion tool_input structure confirmed from live transcripts and official platform.claude.com docs; all edge cases enumerated (11 edge case scenarios in FEATURES.md); before/after behavior described with example wake messages |
| Architecture | HIGH | Integration points mapped to exact line numbers in stop-hook.sh (steps 7b at line 101, 9b, 9c at line 135, 10 at line 142); all four lib function implementations provided in working bash code; build dependency chain explicit with parallelization opportunities identified |
| Pitfalls | HIGH | Based on official Claude Code documentation, two confirmed GitHub issues with exact version fix numbers (#13439, #12031), live transcript verification, and analysis of existing v1.0 codebase; all pitfalls have specific bash prevention patterns, symptom lists, and recovery steps; 12-item verification checklist provided |

**Overall confidence:** HIGH

### Gaps to Address

- **Gideon's wake message parsing implementation:** Research identifies the format change risk and specifies the `wake_message_version: 2` mitigation, but does not inspect Gideon's actual parsing code. Before Phase 2 deployment, locate and confirm Gideon's parsing logic. This is a coordination dependency, not a research gap for the hook system itself.

- **Actual dedup rate in production:** Research identifies deduplication as HIGH value but cannot quantify what percentage of Stop hook fires are truly duplicate in live sessions. Defer per-hook dedup mode settings to v2.x until real rates are measured. The core dedup feature is correct and cheap regardless of the actual rate.

- **Session name sanitization:** ARCHITECTURE.md notes that tmux session names with spaces or slashes would break `/tmp/gsd-pane-prev-SESSION.txt` file naming. Current production sessions (`warden-main`, `forge-main`) are safe. If future sessions use unusual names, add `SESSION_SAFE_NAME=$(echo "$SESSION_NAME" | tr ' /' '__')` sanitization. Low-severity, document in PITFALLS.md for future reference.

## Sources

### Primary (HIGH confidence — official documentation)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — complete PreToolUse stdin JSON schema, matcher patterns, transcript_path field, all hook event schemas and lifecycle
- [Handle approvals and user input — Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/user-input) — AskUserQuestion tool_input.questions[] structure, question/header/options/multiSelect fields, 1-4 questions and 2-4 options per call constraints, confirmed response format
- [GitHub Issue #13439](https://github.com/anthropics/claude-code/issues/13439) — PreToolUse + AskUserQuestion bug confirmed fixed in v2.0.76; symptoms documented
- [GitHub Issue #12031](https://github.com/anthropics/claude-code/issues/12031) — same bug, additional symptom confirmation; AskUserQuestion answers stripped when any PreToolUse hook active

### Primary (HIGH confidence — local verification)
- Live transcript JSONL inspection on host — confirmed `type: "assistant"`, `message.content[].type`, `message.content[].text` structure; confirmed AskUserQuestion `tool_input.questions[].{question, header, options, multiSelect}` field paths from actual transcripts
- `claude --version` output — 2.1.45 (all required hook features supported, bug-fix threshold 2.0.76 exceeded)
- `diff --version` output — GNU diffutils 3.10 (supports `--new-line-format` flag confirmed)
- `jq --version` output — 1.7 (supports JSONL streaming and `select()`)
- `flock` confirmed available — util-linux package on Ubuntu 24
- `scripts/stop-hook.sh` v1.0 source (196 lines) — exact line numbers for all integration points verified
- `scripts/register-hooks.sh` v1.0 source (240 lines) — hook registration pattern for PreToolUse addition confirmed

### Secondary (MEDIUM confidence — community)
- [claude-code-log](https://github.com/daaain/claude-code-log) — JSONL content type enumeration confirming text, tool_use, and thinking blocks in content array
- [Analyzing Claude Code Interaction Logs with DuckDB](https://liambx.com/blog/claude-code-log-analysis-with-duckdb) — real JSONL structure showing message.role and content[] fields
- [Claude Code Transcript JSONL Format — Simon Willison](https://simonwillison.net/2025/Dec/25/claude-code-transcripts/) — confirms JSONL format and session structure
- GNU diff manual — `--new-line-format` / `--old-line-format` / `--unchanged-line-format` flag documentation
- flock(1) and diff(1) Linux man pages — standard utility behavior

---
*Research completed: 2026-02-17*
*Ready for roadmap: yes*
