# v3.0 Retrospective: Structured Hook Observability

## Executive Summary

v3.0 added structured JSONL logging across all 7 hook scripts, a new PostToolUse hook for AskUserQuestion lifecycle correlation, and JSONL analysis in `diagnose-hooks.sh`. The implementation achieved its core goal — every hook invocation now produces a machine-readable audit record — but did so by accumulating copy-paste debt across hook scripts that was already present in v2.0 and was not addressed during v3.0.

## Scope of Review

Files reviewed (v3.0 implementation spans phases 8-11):

- `lib/hook-utils.sh` — 6 shared functions, the DRY anchor of the whole system
- `scripts/stop-hook.sh` — Stop event hook with full content extraction chain
- `scripts/notification-idle-hook.sh` — Notification/idle_prompt hook
- `scripts/notification-permission-hook.sh` — Notification/permission_prompt hook
- `scripts/session-end-hook.sh` — SessionEnd hook (minimal, always async)
- `scripts/pre-compact-hook.sh` — PreCompact hook with different state detection
- `scripts/pre-tool-use-hook.sh` — AskUserQuestion forwarding hook
- `scripts/post-tool-use-hook.sh` — AskUserQuestion answer logging hook (new in v3.0)
- `scripts/diagnose-hooks.sh` — 11-step end-to-end hook chain diagnostic
- `scripts/install.sh` — Single-entry installer added in Quick Task 7
- `scripts/register-hooks.sh` — Idempotent hook registration
- `docs/hooks.md` — Full behavior specs with JSONL schema documentation
- `SKILL.md` — Agent-facing quick reference
- `README.md` — Admin-facing setup guide with registry schema

Phase coverage:
- Phase 8: Added `write_hook_event_record` (12 params) and `deliver_async_with_logging` to `lib/hook-utils.sh`. Stop hook converted to use new functions.
- Phase 9: All 6 remaining hooks ported to emit JSONL via shared functions. `lib/hook-utils.sh` sourced before any guard exits in all hooks.
- Phase 10: PostToolUse hook added (7th hook). Defensive `answer_selected` extractor for unknown `tool_response` schema. Raw stdin logging for empirical schema validation.
- Phase 11: `diagnose-hooks.sh` Step 10 added (JSONL log analysis). Quick Task 7: `install.sh` added. Quick Task 8: logrotate removed entirely.

---

## What Was Done Well

**1. Shared library extraction is genuinely effective (`lib/hook-utils.sh`)**

All 6 functions (`lookup_agent_in_registry`, `extract_last_assistant_response`, `extract_pane_diff`, `format_ask_user_questions`, `write_hook_event_record`, `deliver_async_with_logging`) have zero side effects on source, which means any hook can source the library at any point without triggering execution. The Phase 9 decision to source it before guard exits (rather than after) was correct — it means the library is available for the guard chain itself to use if needed in the future. The file-missing guard (`if [ -f "$LIB_PATH" ]; then source; else exit 0; fi`) in every hook ensures degradation rather than crash if the library is moved.

**2. The `deliver_async_with_logging` pattern eliminates a class of inconsistency**

Before Phase 8, async delivery was a bare `openclaw agent --session-id ... &` call with no logging. After Phase 8, every async delivery path goes through `deliver_async_with_logging` in `lib/hook-utils.sh` (lines 299-325), which atomically: calls openclaw, captures response, determines `delivered` vs `no_response` outcome, and calls `write_hook_event_record`. The `</dev/null &` idiom (line 324) prevents stdin pipe inheritance from Claude Code, which would block the background subprocess. This is a non-obvious correctness detail that is centralized in one place.

**3. Silent failure design in `write_hook_event_record` is correct**

The function (lib/hook-utils.sh lines 182-269) uses `|| return 0` on the jq construction (lines 230, 258) and `|| true` on the flock append (line 268). This means a JSONL write failure never propagates to the calling hook. Combined with the flock timeout of 2 seconds (line 266), concurrent hook fires cannot block each other. The choice to use 12+1 explicit positional parameters rather than globals (Phase 8 decision) makes the function fully testable in isolation.

**4. Guard chain exits fast for non-managed sessions**

Every hook has an identical 4-step guard chain: TMUX check → session name extraction → registry file existence → registry lookup match. For non-managed sessions (the common case on a machine with many Claude Code sessions), all 7 hooks exit at or before step 4 in under 5ms. The prefix-match logic in `lookup_agent_in_registry` (lib/hook-utils.sh lines 34-37) using `startswith($agent.agent_id + "-")` correctly handles `-2` suffix increments without requiring exact session name matches.

**5. Two-phase logging pattern is correct**

Every hook begins logging to the shared `hooks.log` (Phase 1) and then redirects to the per-session `{SESSION_NAME}.log` and sets `JSONL_FILE` after the session name is known (Phase 2). This means all debug output — including the FIRED log line at the top of each hook — is always captured, even for hooks that exit early at the TMUX guard. The design correctly handles the ordering problem: you need session name to route logs, but you want logs before you have session name.

**6. `extract_last_assistant_response` handles the thinking-block edge case explicitly**

The comment at lib/hook-utils.sh lines 62-65 documents why `select(.type == "text")` is used instead of `content[0].text` — positional indexing fails when thinking or tool_use blocks precede the text block. This is a real Claude Code schema quirk that would cause silent content loss without the explicit type filter. The `tail -40` before the jq pipe (line 66) gives constant-time reads on growing JSONL files regardless of session length.

**7. PostToolUse raw stdin logging for empirical validation is pragmatic**

`post-tool-use-hook.sh` line 44 logs the full stdin as compact JSON. This was explicitly acknowledged as a Phase 10 design decision: the `tool_response` schema for AskUserQuestion PostToolUse is unconfirmed from live session data. Rather than guessing, the hook logs raw data to enable retroactive validation. The defensive multi-shape extractor (lines 104-106) handles both object and string `tool_response` shapes with a single jq expression rather than branching.

**8. Documentation is well-layered and audience-appropriate**

The three-document split — `SKILL.md` (agent-facing quick reference), `README.md` (admin setup + registry schema), `docs/hooks.md` (full behavior specs + edge cases) — correctly separates audiences. `docs/hooks.md` documents each hook's exact step sequence, configuration fields, edge cases, and exit times. The JSONL schema table (docs/hooks.md lines 397-409) and lifecycle correlation example (lines 416-420) provide enough detail for consumers of the log data without requiring them to read the implementation.

---

## What Could Be Improved

**1. The hook preamble is copy-pasted 7 times with near-zero variation**

The first 27 lines of every hook script are structurally identical:

```bash
# stop-hook.sh (lines 1-27):
#!/usr/bin/env bash
set -euo pipefail
SKILL_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$SKILL_LOG_DIR"
GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
debug_log() { ... }
debug_log "FIRED ..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_PATH="..."
if [ -f "$LIB_PATH" ]; then source "$LIB_PATH"; else ... exit 0; fi

# notification-idle-hook.sh (lines 1-27): identical except missing debug_log "sourced" line
# notification-permission-hook.sh (lines 1-27): identical
# session-end-hook.sh (lines 1-27): identical
# pre-compact-hook.sh (lines 1-27): identical
# pre-tool-use-hook.sh (lines 1-27): nearly identical (has "sourced lib" line)
# post-tool-use-hook.sh (lines 1-27): nearly identical (has "sourced lib" line)
```

The only variation is that `stop-hook.sh` and `pre-tool-use-hook.sh` and `post-tool-use-hook.sh` log `"sourced lib/hook-utils.sh"` after the source line, while `notification-idle-hook.sh`, `notification-permission-hook.sh`, `session-end-hook.sh`, and `pre-compact-hook.sh` do not. This is an inconsistency that exists purely because of copy-paste ordering, not intentional design. A `hook-preamble.sh` snippet or a `_initialize_hook` function in `lib/hook-utils.sh` would reduce this to a single sourced call.

**2. The hook_settings extraction block is copy-pasted 4 times with zero variation**

`stop-hook.sh` lines 99-111, `notification-idle-hook.sh` lines 92-104, `notification-permission-hook.sh` lines 93-105, and `pre-compact-hook.sh` lines 81-93 contain this exact pattern:

```bash
GLOBAL_SETTINGS=$(jq -r '.hook_settings // {}' "$REGISTRY_PATH" 2>/dev/null || echo "{}")
PANE_CAPTURE_LINES=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.pane_capture_lines // $global.pane_capture_lines // 100)' 2>/dev/null || echo "100")
CONTEXT_PRESSURE_THRESHOLD=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.context_pressure_threshold // $global.context_pressure_threshold // 50)' 2>/dev/null || echo "50")
HOOK_MODE=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.hook_mode // $global.hook_mode // "async")' 2>/dev/null || echo "async")
```

This block is 100% identical across all 4 files. An `extract_hook_settings` function in `lib/hook-utils.sh` accepting `registry_path` and `agent_data` and outputting a single JSON object (or setting named variables) would eliminate all 4 copies. The `pre-compact-hook.sh` copy (lines 81-93) omits the `2>/dev/null` guards that the other three copies have — a silent inconsistency that could cause failures in edge cases where jq returns non-zero.

**3. State detection logic is duplicated with two different implementations**

`stop-hook.sh`, `notification-idle-hook.sh`, and `notification-permission-hook.sh` share one state detection pattern:

```bash
# stop-hook.sh lines 134-142 (identical in notification-idle and notification-permission):
if echo "$PANE_CONTENT" | grep -Eiq 'Enter to select|numbered.*option'; then STATE="menu"
elif echo "$PANE_CONTENT" | grep -Eiq 'permission|allow|dangerous'; then STATE="permission_prompt"
elif echo "$PANE_CONTENT" | grep -Eiq 'What can I help|waiting for'; then STATE="idle"
elif echo "$PANE_CONTENT" | grep -Ei 'error|failed|exception' | grep -v 'error handling'; then STATE="error"
fi
```

`pre-compact-hook.sh` uses a completely different pattern:

```bash
# pre-compact-hook.sh lines 110-118:
if echo "$PANE_CONTENT" | grep -q "Choose an option:"; then STATE="menu"
elif echo "$PANE_CONTENT" | grep -q "Continue this conversation"; then STATE="idle_prompt"
elif echo "$PANE_CONTENT" | grep -q "permission to"; then STATE="permission_prompt"
else STATE="active"
fi
```

Differences: (a) case-insensitive vs case-sensitive grep, (b) different menu patterns (`Enter to select|numbered.*option` vs `Choose an option:`), (c) different idle patterns, (d) different fallback states (`working` vs `active`), (e) no error state in pre-compact. These differences may reflect genuine TUI differences during PreCompact vs Stop events, but they are undocumented. If the TUI text actually differs, the patterns should be documented as intentionally different. If they are the same TUI, the patterns should be consolidated.

**4. Wake message format is inconsistent across hooks**

`notification-idle-hook.sh` (line 162) and `notification-permission-hook.sh` (line 158) use `[PANE CONTENT]` as the section header:

```bash
# notification-idle-hook.sh lines 150-174:
WAKE_MESSAGE="...
[PANE CONTENT]
${PANE_CONTENT}
..."
```

`stop-hook.sh` (line 198) uses `[CONTENT]` (the v2.0 format):

```bash
# stop-hook.sh lines 190-214:
WAKE_MESSAGE="...
[CONTENT]
${CONTENT_SECTION}
..."
```

`pre-compact-hook.sh` (line 137) also uses `[PANE CONTENT]`. The v2.0 migration was explicitly documented as a breaking change (`[PANE CONTENT]` replaced by `[CONTENT]`), but the migration was only applied to `stop-hook.sh`. Three of the four pane-capturing hooks still use `[PANE CONTENT]`. The SKILL.md v2.0 section (lines 171-177) documents the breaking change but does not note that three hooks were not migrated. Any downstream parser that handles both formats will work, but any parser that only handles `[CONTENT]` will miss notification hook payloads.

**5. Context pressure extraction uses two different grep patterns**

`stop-hook.sh` (line 149) and `notification-*` hooks (same line) extract pressure with:

```bash
PERCENTAGE=$(echo "$PANE_CONTENT" | tail -5 | grep -oE '[0-9]{1,3}%' | tail -1 | tr -d '%')
```

`pre-compact-hook.sh` (lines 99-100) uses:

```bash
CONTEXT_PRESSURE_PCT=$(echo "$LAST_LINES" | grep -oP '\d+(?=% of context)' | tail -1 || echo "0")
```

These are not equivalent. The stop/notification pattern matches any `N%` string in the last 5 lines. The pre-compact pattern uses a Perl-compatible lookahead to match only numbers followed by `% of context`. The pre-compact pattern is strictly more precise (it won't false-positive on unrelated percentages), but it introduces a dependency on Perl-compatible regex support (`grep -oP`). Additionally, the stop/notification pattern falls through to `CONTEXT_PRESSURE="unknown"` while the pre-compact pattern falls through to `CONTEXT_PRESSURE_PCT=0`, producing different sentinel values. These should be consolidated with the more precise pattern used everywhere.

**6. `session-end-hook.sh` field extraction omits `2>/dev/null` error suppression**

`session-end-hook.sh` lines 71-72:

```bash
AGENT_ID=$(echo "$AGENT_DATA" | jq -r '.agent_id')
OPENCLAW_SESSION_ID=$(echo "$AGENT_DATA" | jq -r '.openclaw_session_id')
```

All other hooks add `2>/dev/null || echo ""` to these jq calls (e.g., `stop-hook.sh` lines 87-88). Under `set -euo pipefail`, a jq error here would propagate. The pattern in the other hooks is defensive because `AGENT_DATA` may be partially malformed. This was likely an oversight from when `session-end-hook.sh` was written earlier (pre-Phase 8 style) and not updated during the v3.0 porting.

**7. `diagnose-hooks.sh` Step 7 uses exact-match lookup instead of prefix-match**

`diagnose-hooks.sh` line 263-265 performs its registry lookup with:

```bash
LOOKUP_RESULT=$(jq -c --arg session "$TMUX_SESSION_NAME" \
  '.agents[] | select(.tmux_session_name == $session) | {agent_id, openclaw_session_id}' \
  "$REGISTRY_PATH")
```

But the hook scripts use `lookup_agent_in_registry` which does prefix-match (`startswith($agent.agent_id + "-")`). If a session was launched with a `-2` suffix (e.g., `warden-main-2`), the hooks would find it (because `warden-main-2` starts with `warden-`) but Step 7 of diagnose would report failure (because `warden-main` != `warden-main-2`). This creates a false diagnostic failure: hooks work in production but diagnose says they won't.

**8. `diagnose-hooks.sh` Step 2 checks only 5 of 7 hook scripts**

`diagnose-hooks.sh` lines 99-105 checks:

```bash
HOOK_SCRIPTS=(
  "stop-hook.sh"
  "notification-idle-hook.sh"
  "notification-permission-hook.sh"
  "session-end-hook.sh"
  "pre-compact-hook.sh"
)
```

It does not check `pre-tool-use-hook.sh` or `post-tool-use-hook.sh`. These were added in Phase 9/10 and the Step 2 list was never updated. A corrupted or non-executable `pre-tool-use-hook.sh` would be missed by the diagnostic.

---

## Architectural Pros and Cons

### Pros

- **Library-first approach**: `lib/hook-utils.sh` is the single write point for all JSONL emission and async delivery. All 7 hooks benefit from improvements to 2 functions rather than 7 separate implementations.
- **Additive logging**: JSONL records are written in parallel with existing plain-text debug logs. No data was lost during the v3.0 migration and both formats coexist.
- **Registry-as-truth**: Hook behavior (pane capture lines, context threshold, mode) is driven by registry JSON, not hardcoded per-hook. New agents get observability for free by virtue of being in the registry.
- **Lifecycle correlation is queryable**: The `tool_use_id` shared between PreToolUse and PostToolUse records enables correlating question-and-answer pairs from JSONL logs without relying on timestamps or heuristics.
- **Graceful degradation at every layer**: Missing registry, missing lib, jq errors, flock timeouts, openclaw unavailability — every failure mode has a `|| return 0` or `|| exit 0` that prevents hooks from breaking Claude Code sessions.
- **The guard chain is a natural firewall**: Non-managed sessions (the majority) exit in <5ms at step 1 or 2. Only the 4 TMUX→name→registry→field checks are needed before the hook is committed to doing real work.

### Cons

- **Copy-paste debt is the dominant code smell**: The 27-line preamble, the hook_settings extraction block, and the state detection patterns are duplicated across 3-4 files each. Any change to these patterns requires coordinated edits across multiple files, which is a known maintenance risk that will compound as hooks are added.
- **Wake message section headers are inconsistent**: `[CONTENT]` vs `[PANE CONTENT]` across hooks means downstream consumers (OpenClaw agents) must handle both formats or miss data from 3 of 4 pane-capturing hooks. This was a v2.0 migration that was never completed.
- **`write_hook_event_record` has a jq code duplication problem within itself**: The function has two near-identical `jq -cn` blocks (lines 203-230 and 232-258) that differ only by the presence of `--argjson extra_fields "$extra_fields_json"` and `+ $extra_fields`. A single invocation building the base object and then conditionally merging extra fields would halve the function's line count.
- **The `tool_response` schema for PostToolUse is unvalidated**: The defensive multi-shape extractor in `post-tool-use-hook.sh` (lines 104-106) handles three shapes, but the raw stdin logging exists specifically because the correct shape is unknown. This is a known unknown that degrades answer correlation quality until live session data is collected and the extractor is narrowed.
- **No retry or dead-letter queue for failed deliveries**: `deliver_async_with_logging` records `no_response` outcomes but makes no attempt to retry. High-frequency hook fires during periods when openclaw is unavailable silently accumulate `no_response` records. The diagnostic can surface these, but there is no automatic recovery path.
- **Session name spaces/slashes are still a potential issue**: The pane state files use `gsd-pane-prev-${SESSION_NAME}.txt` naming. Session names containing `/` would create subdirectories unexpectedly. The constraint is documented in STATE.md as resolved but the fix was a comment, not a sanitization guard in the code.

---

## Patterns Worth Keeping

**The `deliver_async_with_logging` encapsulation model** should become the template for any future async call that produces observable side effects. The pattern of: background subshell + explicit `</dev/null` + capture response + determine outcome + write structured record is the right abstraction boundary.

**The two-phase logging pattern** (shared log until session name known, then per-session) should be adopted by any new hook or utility script that runs before context is fully established.

**The 12+1 explicit positional parameters** on `write_hook_event_record` enforce call-site clarity at the cost of verbosity. This is the right tradeoff for a logging function that is called from 7 different files — implicit globals would make call sites impossible to read.

**The `|| return 0` defensive exits in shared library functions** prevent any library error from propagating to calling hooks. This pattern should be extended: any function added to `lib/hook-utils.sh` should either be provably correct or end with `|| return 0`.

**The guard chain ordering** (TMUX → session name → registry file → registry match → field validation) provides the correct 4-layer exit hierarchy. Reordering these guards (e.g., checking the registry before session name) would add latency to the common-case fast exit.

---

## Patterns to Reconsider

**The `echo "$VAR" | jq ...` pipeline for JSON extraction** should be replaced with `printf '%s' "$VAR" | jq ...` consistently. `echo` can interpret escape sequences in some shells and may add a trailing newline that corrupts JSON passed as a string. `pre-tool-use-hook.sh` and `post-tool-use-hook.sh` correctly use `printf '%s'` (e.g., lines 81, 86, 92, 98) while the older hooks (`stop-hook.sh`, `notification-*`, `session-end-hook.sh`) still use `echo "$AGENT_DATA" | jq ...`. This is a latent correctness risk if agent data ever contains backslash sequences.

**The bidirectional mode `--json` flag** in stop-hook.sh line 225 and notification hooks sends a `--json` flag to `openclaw agent`, but the async path via `deliver_async_with_logging` does not. The sync paths expect JSON-formatted response to parse `.decision` and `.reason` fields, but this coupling between hook and OpenClaw response format is not documented. If the OpenClaw API changes its response format, the bidirectional decision parsing breaks silently.

**`HOOK_ENTRY_MS` placement after `STDIN_JSON=$(cat)`** is correct for measuring processing time (not startup time), but `date +%s%3N` is called after stdin is consumed. On a loaded system, stdin consumption can take 1-5ms for large STDIN payloads. This means `duration_ms` in the JSONL record measures "processing after stdin consumed" not "total hook duration". For the stated purpose (observability), this distinction probably does not matter, but it should be documented.

**The `check()` function in `diagnose-hooks.sh`** wraps commands but only increments counters — it does not propagate the pass/fail state correctly. The code uses both `check()` and direct counter manipulation, creating two parallel counting systems that can get out of sync. Steps 1 uses direct counter increments inside loops, while Step 2 uses the `check()` wrapper. Consolidating to one pattern would eliminate counting bugs.

---

## Lessons for Next Version

**v4.0 priority 1: Write a shared hook preamble.** The 27-line preamble copy-pasted across 7 files is the highest-leverage cleanup available. Extract `SKILL_LOG_DIR`, `GSD_HOOK_LOG`, `HOOK_SCRIPT_NAME`, the `debug_log` function, and the lib-source block into a `hook-preamble.sh` that is sourced by every hook. This eliminates the most error-prone duplicated code and ensures future hooks automatically get correct logging setup.

**v4.0 priority 2: Add `extract_hook_settings` to `lib/hook-utils.sh`.** The hook_settings extraction block (12 lines, 4 copies) is the second-most copied pattern. A function accepting `registry_path` and `agent_data` and echoing a settings JSON object would clean up all 4 pane-capture hooks and make the three-tier fallback logic auditable in one place.

**v4.0 priority 3: Finish the v2.0 wake format migration.** Apply `[CONTENT]` section naming (instead of `[PANE CONTENT]`) to `notification-idle-hook.sh`, `notification-permission-hook.sh`, and `pre-compact-hook.sh`. Evaluate whether notification hooks should also use the transcript extraction chain like `stop-hook.sh` does, or whether raw pane capture is intentional for those events.

**v4.0 priority 4: Complete the `tool_response` schema validation for PostToolUse.** Run a live AskUserQuestion session, collect the raw stdin logged by `post-tool-use-hook.sh`, and narrow the defensive multi-shape extractor to the confirmed field path. Remove or gate the raw stdin logging behind a `DEBUG_MODE` flag.

**v4.0 priority 5: Fix `diagnose-hooks.sh` Step 7 to use prefix-match.** Replace the exact `tmux_session_name` match in Step 7 with a call to `lookup_agent_in_registry` (or the same `startswith` logic), so the diagnostic accurately reflects what the hooks actually do. Add `pre-tool-use-hook.sh` and `post-tool-use-hook.sh` to Step 2's script list.

**v4.0 priority 6: Consolidate state detection patterns.** Determine definitively whether `pre-compact-hook.sh` needs different state patterns than the other hooks. If not, extract a shared `detect_session_state` function to `lib/hook-utils.sh`. If yes, document the difference with a comment that explains why each pattern set is correct for its event type.

**Long-term: Evaluate a hook generator script.** The 7 hook scripts share 70-80% of their structure. A template-based generator that produces hook scripts from a configuration file (trigger name, state detection variant, content extraction mode, bidirectional support) would reduce the surface area for divergence in v4.0 and beyond.
