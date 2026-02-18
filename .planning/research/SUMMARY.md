# Project Research Summary

**Project:** gsd-code-skill v3.0 — Structured Hook Observability
**Domain:** Structured JSONL event logging from bash hook scripts in a Claude Code / OpenClaw agent control system
**Researched:** 2026-02-18
**Confidence:** HIGH

## Executive Summary

v3.0 adds structured JSONL event logging to the six Claude Code hook scripts that drive OpenClaw agent control in gsd-code-skill. The current v2.0 system is a working production system: hooks fire on Claude Code events (Stop, PreToolUse, Notification, SessionEnd, PreCompact), extract pane/transcript content, build wake messages, and deliver them to OpenClaw agents synchronously or asynchronously. The problem is purely observability — the plain-text `debug_log()` outputs are not machine-parseable, the full wake message body sent to OpenClaw is never stored, and async responses are dumped as unlabeled raw text with no way to correlate which response belongs to which hook invocation. v3.0 replaces this with paired `hook.request` / `hook.response` JSONL events linked by correlation ID.

The recommended implementation uses zero new dependencies: `jq 1.7` (already installed, already used in all hooks), `uuidgen` or `date +%s` for correlation IDs, `flock` (already used for pane state files), and `logrotate 3.21.0` (already installed) for rotation. All work concentrates in one file — `lib/hook-utils.sh` — where five new functions are added alongside the four existing extraction functions. Each of the six hook scripts then follows a mechanical modification pattern: source lib earlier, generate a correlation ID at entry, call `log_hook_request()` before delivery, and replace the bare `openclaw &` call with `deliver_async_with_logging()`. This is an integration task, not a greenfield build.

The critical risk is JSON correctness: wake messages contain newlines, quotes, ANSI codes, and embedded JSON that will silently corrupt JSONL records if assembled via bash string interpolation instead of `jq --arg`. A secondary risk is concurrent write interleaving — Stop and Notification hooks can fire within milliseconds of each other, and JSONL records with wake message bodies routinely exceed the 4KB POSIX atomicity guarantee for `>>` appends. Both risks are fully preventable with non-negotiable rules: every string field uses `jq --arg`, and every append uses `flock`. There are no architectural surprises — the build order, component boundaries, and integration points are fully mapped from the v2.0 codebase.

## Key Findings

### Recommended Stack

The entire implementation is bash + jq. No new packages or runtimes. jq 1.7 handles JSON construction with `--arg` for safe string embedding. GNU `date` with `%3N` provides millisecond-precision timestamps. `uuidgen --random` or `date +%s_$$` provides collision-resistant correlation IDs. `flock` (already in use for pane state) provides concurrent append safety. `logrotate 3.21.0` with `copytruncate` handles rotation without breaking open file descriptors.

**Core technologies:**
- `jq 1.7` (installed): JSONL record generation via `jq -cn --arg` — the only safe way to embed arbitrary string content (wake messages, responses) in JSON from bash; 2ms per invocation; all required flags confirmed
- `date -u +'%Y-%m-%dT%H:%M:%S.%3NZ'` (GNU coreutils 9.4, installed): millisecond-precision ISO 8601 UTC timestamps — required because multiple hooks can fire within the same second
- `uuidgen --random` (util-linux, installed): UUIDv4 correlation IDs at 2ms per call — confirmed at `/usr/bin/uuidgen`; fallback is `date +%s_$$` which is universally available
- `flock -x -w 2` (util-linux, installed): exclusive file locking for concurrent JSONL appends — same pattern already used in `extract_pane_diff()`; lock file lives alongside JSONL file (`${SESSION_NAME}.jsonl.lock`)
- `logrotate 3.21.0` (installed): size-based log rotation with `copytruncate` — required because hook scripts hold open `>>` file descriptors; `copytruncate` truncates in place rather than renaming, keeping the file descriptor valid

**What NOT to add:** Python, Node.js, SQLite, OpenTelemetry, or any logging framework. All add startup latency (50–200ms) to hooks that must complete in under 5ms for non-managed sessions. The jq pattern produces identical output at under 2ms.

### Expected Features

**Must have (table stakes — v3.0 core, all ship together):**
- `jsonl_log()` shared function in `lib/hook-utils.sh` — the DRY foundation all six hooks source; uses `jq -cn --arg` for all fields; wraps append with `flock`; fire-and-forget with `|| true`
- `hook_fired` event in all 6 hook scripts — proves execution started, captures entry state: correlation ID, session, hook script name, stdin bytes, PID
- `hook_exit` event on all early-exit paths — distinguishes "never fired" from "fired and exited early" for non-managed sessions; replaces existing `debug_log "EXIT: ..."` lines
- `hook.request` / `wake_sent` event — captures the full wake message body sent to OpenClaw, content source (transcript vs pane diff), trigger type, delivery mode, wake message byte count
- `hook.response` / `wake_response_received` event — captures OpenClaw's response, exit code, outcome classification (delivered / error / blocked), and decision field in bidirectional mode
- Correlation ID linking request and response — generated once per hook invocation before the async fork, passed explicitly as a parameter through `deliver_async_with_logging()`
- `question_forwarded` event in `pre-tool-use-hook.sh` — AskUserQuestion audit trail capturing tool_use_id, question count, options count
- Per-session JSONL file (`logs/{SESSION_NAME}.jsonl`) parallel to existing plain-text `.log` files

**Should have (v3.x — add after core validated):**
- `answer_selected` event via new `post-tool-use-hook.sh` — closes the AskUserQuestion lifecycle loop; requires new script and hook registration; PostToolUse stdin schema needs empirical verification
- `duration_ms` in all events — time from hook entry to event emission; requires capturing `EPOCHREALTIME` at script start
- Log rotation guard in `jsonl_log()` — inline size check before write prevents unbounded growth between logrotate runs

**Defer (v4+):**
- Remove plain-text `debug_log()` entirely — only after JSONL event coverage is confirmed complete with no gaps
- Cross-session query tooling (`query-logs.sh`) — deferred until dashboard integration begins
- OTLP export — only if a local collector is ever deployed on this host

### Architecture Approach

All new logic lives in `lib/hook-utils.sh` as five new functions added alongside the four existing extraction functions. The six hook scripts are mechanically modified to source lib earlier and call the new functions — no new files for v3.0 core. The `deliver_async_with_logging()` wrapper replaces the bare `openclaw ... &` pattern across all async delivery paths: it captures stdout from the `openclaw` call inside a background subshell (with explicit `</dev/null` to prevent stdin inheritance hangs) and emits the `hook.response` event with the captured response and exit code. The log file format changes from plain-text to JSONL for both `hooks.log` and per-session files; `diagnose-hooks.sh` may need updating to parse JSONL with `jq` instead of plain `grep`.

**Major components:**
1. `lib/hook-utils.sh` (EXTENDED) — adds `generate_correlation_id()`, `jsonl_log()`, `log_hook_request()`, `log_hook_response()`, `deliver_async_with_logging()` alongside unchanged extraction functions; grows from ~150 lines to ~220 lines
2. Six hook scripts (ALL MODIFIED) — source lib at top of script (before any guard), generate correlation ID at entry, replace inline `debug_log()` with `jsonl_log()` at lifecycle points, replace bare `openclaw &` with `deliver_async_with_logging()`
3. `logs/` directory — `{SESSION_NAME}.jsonl` files added parallel to existing `.log` files; same two-phase routing as plain-text logs (Phase 1: `hooks.jsonl`, Phase 2: `{SESSION_NAME}.jsonl`)

**Build order:** Step 1 (extend lib) must complete before Steps 2-7 (modify each hook script). Steps 2-7 are fully parallel — all six hook scripts depend only on Step 1, not on each other. This makes Phase 2 a single Warden task.

### Critical Pitfalls

1. **JSON string interpolation in bash** — Wake messages contain newlines, quotes, ANSI codes, and embedded JSON. Any `printf '{"field":"%s"}' "$VAR"` or `jq -n "{\"field\": \"$VAR\"}"` pattern silently produces invalid JSONL on first special character. Prevention: every string field uses `jq -n --arg field "$VAR"` without exception. Verify with `grep -n 'jq.*"\$' lib/hook-utils.sh` — must return zero matches.

2. **Concurrent JSONL appends without flock** — Stop and Notification hooks can fire simultaneously for the same session. JSONL records with full wake message bodies are routinely 5–15KB, far exceeding the 4KB POSIX `O_APPEND` atomicity guarantee. Interleaved writes produce merged corrupt lines. Prevention: `jsonl_log()` must use `flock -x -w 2` on `${LOG_FILE}.lock` for every append — same pattern already used for pane state files.

3. **Correlation ID lost in async subprocess** — If `CORRELATION_ID` is a local variable and the background subshell does not receive it as an explicit parameter, the response event gets an empty or mismatched ID. Prevention: `deliver_async_with_logging()` takes `correlation_id` as an explicit positional parameter — never relies on implicit variable inheritance.

4. **Log file path split across Phase 1/Phase 2 routing** — Each hook script mutates `$GSD_HOOK_LOG` mid-execution. If `deliver_async_with_logging()` reads `$GSD_HOOK_LOG` from the global at fork time rather than receiving the path as an explicit parameter, request and response events can end up in different files. Prevention: pass log file path as an explicit argument captured after Phase 2 redirect.

5. **jq process overhead at guard exits** — Each `jq -n` call costs 5–15ms. Emitting JSONL at every guard exit adds 20–75ms to hook execution for ALL sessions including personal non-managed Claude Code sessions. Prevention: JSONL events for managed session lifecycle only (`hook.request`, `hook.response`); guard exits use plain `printf` or are omitted.

6. **Async stdin inheritance causing hangs** — `deliver_async_with_logging()` captures `openclaw` output via `$()` inside a background subshell. Without explicit `</dev/null`, the subshell inherits the hook's stdin, which can cause `openclaw` to block waiting for input. Prevention: `</dev/null` on both the outer subshell and the `openclaw` call inside it.

7. **lib sourced after inline debug_log removed** — v2.0 sources lib late (after TMUX guard, around line 35-50). v3.0 needs lib at the top of the script for the `hook_fired` event. Removing the inline `debug_log()` before moving the source line causes "command not found" on early logging calls. Prevention: move `source lib/hook-utils.sh` immediately after `SKILL_LOG_DIR` and `GSD_HOOK_LOG` setup; add plain-printf fallback for lib-not-found path.

## Implications for Roadmap

Based on research, the implementation has a clear two-phase structure: build and validate the shared library foundation, then apply the mechanical hook script migration.

### Phase 1: JSONL Logging Foundation (lib/hook-utils.sh)

**Rationale:** All other work depends on this. The five new functions in `lib/hook-utils.sh` are the prerequisite for every hook script change. The critical correctness rules — jq `--arg` for all string fields, `flock` on every append, explicit parameter passing for correlation ID and log file path, `</dev/null` in the delivery wrapper — must be established here before any hook script calls these functions. Retrofitting correctness issues after Phase 2 would require touching all 6 scripts again. This phase can be tested in isolation by calling the functions directly in bash without any running Claude Code session.

**Delivers:** Extended `lib/hook-utils.sh` with `generate_correlation_id()`, `jsonl_log()`, `log_hook_request()`, `log_hook_response()`, `deliver_async_with_logging()`.

**Addresses features:** `jsonl_log()` / `emit_event()` foundation; correlation ID generation; async delivery wrapper with response capture.

**Avoids pitfalls:** Pitfall 1 (jq --arg), Pitfall 2 (flock), Pitfall 3 (explicit correlation_id param), Pitfall 4 (explicit log_file param), Pitfall 6 (stdin /dev/null) — all must be correct in the lib before any hook uses it.

### Phase 2: Hook Script Migration (all 6 scripts)

**Rationale:** Once lib is tested and correct, all 6 hook scripts can be modified in a single Warden task. The modification pattern is mechanical and identical across all 6: move source earlier, generate correlation ID, replace debug_log calls with jsonl_log calls, replace bare openclaw call with logging wrappers. This is the bulk of the implementation by file count but the lowest-risk work given a correct lib — each script change is a straightforward find-and-replace of known patterns.

**Delivers:** All 6 hook scripts emitting `hook_fired`, `hook_exit`, `hook.request`, and `hook.response` JSONL events to per-session `.jsonl` files. Plain-text `.log` files continue in parallel for backward compatibility.

**Addresses features:** `hook_fired` event, `hook_exit` event, `hook.request` / `wake_sent` event, `hook.response` / `wake_response_received` event, `question_forwarded` event in pre-tool-use-hook.sh, per-session JSONL file.

**Avoids pitfalls:** Pitfall 7 (lib sourcing order — move source to top of all 6 scripts), Pitfall 4 (log file routing — pass explicit path after Phase 2 redirect).

### Phase 3: AskUserQuestion Lifecycle Completion (v3.x)

**Rationale:** The `question_forwarded` event ships in Phase 2. The `answer_selected` event requires a new `post-tool-use-hook.sh` and a new hook registration — medium complexity and a new script touches settings.json. More importantly, the PostToolUse stdin field names for AskUserQuestion tool_response have medium confidence and need empirical verification before the typed event schema is finalized. Validate `question_forwarded` and `tool_use_id` correlation in production first, then build the PostToolUse hook with confirmed field names.

**Delivers:** `post-tool-use-hook.sh` (new script) with `answer_selected` event; PostToolUse hook registration in `settings.json`; validated AskUserQuestion lifecycle end-to-end.

**Addresses features:** `answer_selected` event (P2), closed AskUserQuestion question-to-answer lifecycle.

**Avoids pitfalls:** Empirical verification of PostToolUse stdin schema before committing to field names.

### Phase 4: Operational Hardening

**Rationale:** After core events are confirmed correct in production, add the operational hygiene items that depend on observing real usage patterns: `duration_ms` requires confirming baseline hook execution times, log rotation needs depend on actual log growth rates, and `diagnose-hooks.sh` updates need confirmed JSONL field names. These are low-risk additions that improve long-term stability but do not affect core observability.

**Delivers:** `duration_ms` in all events; logrotate config at `/etc/logrotate.d/gsd-code-skill` with `copytruncate`; optional inline rotation guard in `jsonl_log()` for `hooks.jsonl`; updated `diagnose-hooks.sh` parsing JSONL with `jq`.

**Addresses features:** duration_ms (P2), log rotation (P3), diagnose-hooks.sh compatibility.

### Phase Ordering Rationale

- Phase 1 before Phase 2 is a hard dependency — shared library functions must exist and be correct before any hook script calls them.
- Phase 2 can be a single Warden task — all 6 hook scripts follow the same mechanical pattern; they are independent of each other after Phase 1.
- Phase 3 after Phase 2 because: (a) `question_forwarded` must be validated in production before the PostToolUse schema is committed, (b) the new script + hook registration is higher deployment risk than modifying existing scripts.
- Phase 4 last because it depends on observing Phase 2/3 events in production to confirm baselines and rotation needs.
- This ordering concentrates all correctness-critical decisions into Phase 1 where they are testable in isolation, before they are exercised across 6 hook scripts simultaneously.

### Research Flags

Phases with well-documented patterns — skip additional research:
- **Phase 1:** All tools locally verified on this host (jq 1.7, flock, uuidgen, date %3N). Implementation patterns are production-proven. Concurrent write flock pattern already exists in `extract_pane_diff()`. No external research needed.
- **Phase 2:** Mechanical modification of known, fully-read code. All 6 hook scripts read in full; the modification pattern is exact and identical across all scripts. No research needed.
- **Phase 4:** logrotate 3.21.0 with `copytruncate` — confirmed installed and working. Pattern is standard and fully specified in STACK.md.

Phases needing empirical validation during implementation (not additional pre-research):
- **Phase 3 (PostToolUse stdin schema):** MEDIUM confidence on field names for `tool_response.content` in PostToolUse hook stdin for AskUserQuestion. The `tool_use_id` field in PreToolUse stdin is confirmed. Plan: build `post-tool-use-hook.sh` to log raw stdin first, verify field names against a live session, then add the typed `answer_selected` event schema. Do not commit to field names before empirical verification.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All tools verified locally: jq 1.7, uuidgen, date %3N, flock, logrotate 3.21.0. Benchmarked (uuidgen: 2ms, jq --arg: correct escaping of multiline content confirmed). Zero new dependencies. |
| Features | HIGH | v2.0 codebase read in full. Feature set derived from PROJECT.md, REQUIREMENTS.md, and direct code analysis. The one medium-confidence item (PostToolUse stdin schema) is correctly scoped to v3.x, not v3.0 core. |
| Architecture | HIGH | All 6 hook scripts and lib/hook-utils.sh read in full. Integration points mapped to exact functions and patterns. Build order validated against dependency graph. No architectural unknowns. |
| Pitfalls | HIGH | Sourced from Linux kernel documentation, empirical write-atomicity research (POSIX O_APPEND limits, PIPE_BUF measurements), official jq manual, official flock man page, and direct analysis of v2.0 codebase. All 7 pitfalls have concrete prevention steps and verification commands. |

**Overall confidence:** HIGH

### Gaps to Address

- **PostToolUse stdin schema for AskUserQuestion:** The `tool_response.content` field name is inferred from the PreToolUse pattern and hooks documentation structure. Must be empirically verified in Phase 3 before finalizing the `answer_selected` event schema. Mitigation: log raw stdin first, validate field names, then commit to typed schema.

- **diagnose-hooks.sh JSONL compatibility:** The script reads the plain-text log files. The exact changes needed to parse JSONL with `jq` are not mapped — the script was not read in full during research. Assess at Phase 4 implementation start.

- **logrotate scheduling frequency for hooks.jsonl:** Default logrotate runs once daily. For `hooks.jsonl` (pre-session events that can accumulate before a session starts), the daily schedule may allow excessive growth. Mitigation: add an inline `rotate_jsonl_if_needed()` size guard specifically for `hooks.jsonl`, or configure a more frequent logrotate invocation via cron. Decide based on observed growth rate in Phase 4.

## Sources

### Primary (HIGH confidence — local verification on this host)
- `lib/hook-utils.sh` (v2.0) — exact function signatures, 150 lines, read in full
- `scripts/stop-hook.sh`, `pre-tool-use-hook.sh`, `notification-idle-hook.sh`, `notification-permission-hook.sh`, `session-end-hook.sh`, `pre-compact-hook.sh` (all v2.0) — read in full; inline debug_log pattern, openclaw delivery calls, async/bidirectional branches confirmed
- `jq --version` on host: `jq-1.7` — all flags (`--arg`, `--argjson`, `-c`, `-n`) confirmed
- `date -u +'%Y-%m-%dT%H:%M:%S.%3NZ'` on host: `2026-02-18T09:25:32.056Z` — millisecond precision confirmed
- `uuidgen --random` on host: valid UUIDv4 at 2ms latency (100-iteration benchmark)
- `flock -x -w 2` on host: confirmed working in `extract_pane_diff()`, same util-linux version
- `logrotate --version`: `logrotate 3.21.0`, `copytruncate` directive confirmed in man page
- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/STATE.md` — v3.0 goals, constraints, existing lib architecture
- OpenClaw session JSONL schema from live session files — `type`, `id`, `parentId`, `timestamp` pattern confirmed

### Secondary (HIGH confidence — official documentation)
- [JSON Lines specification](http://jsonlines.org/) — UTF-8, one JSON value per line, newline-delimited
- [jq 1.8 Manual — jqlang.org](https://jqlang.org/manual/) — `--arg`, `--argjson`, `@json` flags
- [flock(1) — Linux Manual Page](https://man7.org/linux/man-pages/man1/flock.1.html) — `-x` exclusive lock, `-w` timeout, fd-based lock file pattern
- [Appending to a log — Paul Khuong (2021)](https://pvk.ca/Blog/2021/01/22/appending-to-a-log-an-introduction-to-the-linux-dark-arts/) — POSIX O_APPEND atomicity limits for concurrent writes
- [Command Execution Environment — Bash Reference Manual](https://www.gnu.org/software/bash/manual/html_node/Command-Execution-Environment.html) — background subshell environment inheritance

### Tertiary (MEDIUM confidence — community sources)
- [Are Files Appends Really Atomic? — Not The Wizard (2014)](https://www.notthewizard.com/2014/06/17/are-files-appends-really-atomic/) — empirical PIPE_BUF limits by OS (pre-2025, still accurate for ext4)
- [Build a JSON String With Bash Variables — Baeldung on Linux](https://www.baeldung.com/linux/bash-variables-create-json-string) — `jq -n --arg` pattern for safe variable injection
- [Structured Logging: Best Practices — Uptrace](https://uptrace.dev/glossary/structured-logging) — standard field names (timestamp, correlation_id, event type)
- [How to make a shell script log JSON messages — stegard.net](https://stegard.net/2021/07/how-to-make-a-shell-script-log-json-messages/) — jq-based structured logging in bash

---
*Research completed: 2026-02-18*
*Ready for roadmap: yes*
