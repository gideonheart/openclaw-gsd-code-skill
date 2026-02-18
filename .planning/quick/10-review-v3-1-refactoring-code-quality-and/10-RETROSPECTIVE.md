# v3.1 Retrospective: Hook Refactoring and Migration Completion

## Executive Summary

v3.1 (Phases 12-14) successfully extracted the 27-line duplicated hook preamble into a single `lib/hook-preamble.sh`, added two new shared functions (`extract_hook_settings` and `detect_session_state`) to `lib/hook-utils.sh`, completed the v2.0 `[CONTENT]` migration, eliminated `echo`-to-jq patterns across all 7 hooks, and fixed two diagnostic failures in `diagnose-hooks.sh`. The refactoring achieved its stated goals and reduced the per-hook preamble from ~27 lines to 3 lines across 7 scripts (approximately 168 lines removed). However, the delivery pattern triplication (~30 lines each across 3 hooks), the context pressure extraction triplication (13 lines, 3 copies), the "Phase 2 redirect" block repetition (3 lines, 7 copies), and a JSON injection risk in bidirectional echo responses are the principal remaining issues that v4.0 should address.

---

## Scope of Review

### Files Reviewed

| File | Lines | Role |
|------|-------|------|
| `lib/hook-preamble.sh` | 56 | Shared bootstrap (new in v3.1) |
| `lib/hook-utils.sh` | 407 | Shared utility library (extended in v3.1) |
| `scripts/stop-hook.sh` | 207 | Stop event hook |
| `scripts/notification-idle-hook.sh` | 169 | Notification/idle_prompt hook |
| `scripts/notification-permission-hook.sh` | 170 | Notification/permission_prompt hook |
| `scripts/session-end-hook.sh` | 89 | SessionEnd hook (minimal) |
| `scripts/pre-compact-hook.sh` | 135 | PreCompact hook |
| `scripts/pre-tool-use-hook.sh` | 130 | AskUserQuestion forwarding hook |
| `scripts/post-tool-use-hook.sh` | 121 | AskUserQuestion answer logging hook |
| `scripts/diagnose-hooks.sh` | 444 | 11-step hook chain diagnostic |
| `docs/v3-retrospective.md` | 289 | v3.0 retrospective (cross-reference) |

### Phase Coverage

- **Phase 12:** Created `lib/hook-preamble.sh`; added `extract_hook_settings()` (lines 348-364) and `detect_session_state()` (lines 392-407) to `lib/hook-utils.sh`.
- **Phase 13:** Migrated all 7 hooks to source `hook-preamble.sh`; completed `[CONTENT]` migration for notification-idle, notification-permission, pre-compact; replaced all `echo`-to-jq with `printf '%s'`; added `2>/dev/null` guards to `session-end-hook.sh`.
- **Phase 14:** Fixed `diagnose-hooks.sh` Step 7 exact-match to prefix-match; added `pre-tool-use-hook.sh` and `post-tool-use-hook.sh` to Step 2 array.

### Code Volume Affected

- Removed: ~168 lines of duplicated preamble (27 lines x 7 hooks, minus the 3-line source statement replacement = 24 lines saved per hook x 7 = 168 lines)
- Replaced: ~48 lines of settings extraction (12 lines x 4 hooks) with 4x 3-line calls to `extract_hook_settings()`
- Migrated: 3 hooks from `[PANE CONTENT]` to `[CONTENT]` label
- Swept: 7 hooks for `echo`-to-jq patterns, replaced with `printf '%s'`

---

## What Was Executed Well

**1. hook-preamble.sh BASH_SOURCE[1] identity pattern (lib/hook-preamble.sh:29-32)**

The preamble uses `BASH_SOURCE[1]` to resolve the calling hook's identity rather than `BASH_SOURCE[0]` (which would be the preamble file itself). This is non-obvious and correct. `HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]:-hook-unknown.sh}")"` (line 30) and `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-...}")" && pwd)"` (line 32) both derive from the caller's path automatically — no parameter passing required. The `hook-unknown.sh` fallback prevents crashes if the preamble is somehow sourced without a caller context.

**2. Source guard prevents double-sourcing idempotently (lib/hook-preamble.sh:10-18)**

`[[ -n "${_GSD_HOOK_PREAMBLE_LOADED:-}" ]] && return 0` (line 10) followed by `readonly _GSD_HOOK_PREAMBLE_LOADED=1` (line 18) is a correct idempotency guard. The `:-` default expansion handles the unset case under `set -u`. The guard uses `return 0` (not `exit 0`) so it works correctly when sourced from hook body code. The `exit 1` for direct execution (lines 13-16) catches misuse clearly.

**3. extract_hook_settings() three-tier fallback is injection-safe (lib/hook-utils.sh:348-364)**

The function reads global settings first with `jq -r '.hook_settings // {}' "$registry_path"` (line 353), passes it as `--argjson global` (line 357), and uses `//` chaining: `(.hook_settings.pane_capture_lines // $global.pane_capture_lines // 100)` (line 359). Crucially, `agent_data_json` is piped via `printf '%s'` (line 356) rather than `echo`, and the entire output is a compact JSON object rather than three separate variable assignments. This eliminates the injection risk that the old `echo "$AGENT_DATA" | jq` pattern had. The `|| printf '{"pane_capture_lines":100,...}'` fallback on line 363 ensures the function never returns empty — all callers can unconditionally parse its output.

**4. detect_session_state() centralization with case-insensitive regex (lib/hook-utils.sh:392-407)**

Five states are detected in priority order: `menu` (line 395), `permission_prompt` (line 397), `idle` (line 399), `error` (lines 401-402), `working` (line 404). The `grep -Eiq` flag (case-insensitive, extended regex, quiet) avoids shell quoting issues from `grep -E` combined with `if` branches. The `error` state uses a two-step pipe with `grep -v 'error handling'` to avoid false positives from error-handling documentation text — this edge case exists in real Claude Code output. The function `printf`s a state name without a trailing newline, consistent with all other hook-utils.sh return patterns. Phase 13 normalized pre-compact's `idle_prompt` and `active` states to `idle` and `working`, achieving consistent naming across all hooks.

**5. All 7 hooks have identical source statement at line 3 (scripts/*.sh:3)**

Every hook script has exactly:
```bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/hook-preamble.sh"
```
The pattern uses `BASH_SOURCE[0]` (the hook's own path) to locate the `../lib` directory, making the path resolution portable regardless of working directory at hook invocation time. Zero divergence across all 7 hooks — this is the single most verifiable outcome of v3.1.

**6. [CONTENT] migration completed for 3 remaining hooks (Phase 13)**

`notification-idle-hook.sh` line 117, `notification-permission-hook.sh` line 118, and `pre-compact-hook.sh` line 94 now all use `[CONTENT]` as the wake message section header, consistent with `stop-hook.sh` line 153. The v3.0 retrospective identified this as a partial v2.0 migration (only `stop-hook.sh` had been updated). All 4 pane-capturing hooks now produce identical section naming for downstream OpenClaw consumers.

**7. printf '%s' sweep completed — zero echo-to-jq patterns in hook scripts**

The v3.0 retrospective flagged `echo "$AGENT_DATA" | jq` as a latent correctness risk because `echo` can expand escape sequences in some shells. Phase 13 replaced all such patterns across 7 hook scripts. Spot-check confirmation: `stop-hook.sh` lines 61-62, `notification-idle-hook.sh` lines 55-56, `notification-permission-hook.sh` lines 56-57, `pre-compact-hook.sh` lines 46-47, `pre-tool-use-hook.sh` lines 54-55, `post-tool-use-hook.sh` lines 60-61 all use `printf '%s' "$AGENT_DATA" | jq -r`. The `diagnose-hooks.sh` echo patterns (lines 155-157) were out of scope and remain.

**8. session-end-hook.sh jq error guards added (scripts/session-end-hook.sh:46-47)**

The v3.0 retrospective identified `session-end-hook.sh` as missing `2>/dev/null || echo ""` on its jq field extractions. Phase 13 fixed this: lines 46-47 now read:
```bash
AGENT_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.agent_id' 2>/dev/null || echo "")
OPENCLAW_SESSION_ID=$(printf '%s' "$AGENT_DATA" | jq -r '.openclaw_session_id' 2>/dev/null || echo "")
```
Under `set -euo pipefail`, a jq non-zero exit without `|| echo ""` would crash the hook. The fix also added the `FIX-03` comment (line 45) documenting the Phase 13 origin.

---

## Remaining Issues

**1. Delivery pattern triplication — ~30 lines, 3 copies**

`notification-idle-hook.sh` lines 139-169, `notification-permission-hook.sh` lines 140-170, and `stop-hook.sh` lines 177-207 contain near-identical bidirectional/async delivery blocks. The bidirectional branch (~12 lines):

```bash
# notification-idle-hook.sh lines 139-160 (identical in notification-permission lines 140-161):
if [ "$HOOK_MODE" = "bidirectional" ]; then
  RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" --json 2>&1 || echo "")
  write_hook_event_record "$JSONL_FILE" "$HOOK_ENTRY_MS" "$HOOK_SCRIPT_NAME" ...
  if [ -n "$RESPONSE" ]; then
    DECISION=$(printf '%s' "$RESPONSE" | jq -r '.decision // ""' 2>/dev/null || echo "")
    REASON=$(printf '%s' "$RESPONSE" | jq -r '.reason // ""' 2>/dev/null || echo "")
    if [ "$DECISION" = "block" ] && [ -n "$REASON" ]; then
      echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
    fi
  fi
  exit 0
else
  deliver_async_with_logging "$OPENCLAW_SESSION_ID" "$WAKE_MESSAGE" ...
  exit 0
fi
```

The stop-hook.sh bidirectional branch (lines 177-207) differs only in that it also handles transcript content. This is the largest remaining duplication in the codebase: approximately 90 lines of nearly identical logic across 3 files. A `deliver_with_mode` function in `lib/hook-utils.sh` accepting `hook_mode`, `openclaw_session_id`, `wake_message`, and all JSONL parameters could collapse these three blocks into a single call per hook.

**2. Stale comment in detect_session_state() (lib/hook-utils.sh:386-391)**

Lines 386-391 contain this comment block:
```
# Note: pre-compact-hook.sh uses different patterns and state names
# (case-sensitive grep, "Choose an option:", "Continue this conversation",
# "active" fallback). Until pre-compact TUI text is empirically verified,
# that hook may retain its own inline detection rather than calling this
# function. See Phase 12 research for details.
```

This comment was accurate during Phase 12 but is now false: Phase 13 migrated `pre-compact-hook.sh` to use `detect_session_state()` (line 76 of pre-compact-hook.sh). The stale comment creates misleading documentation — a reader of `hook-utils.sh` will believe pre-compact still has divergent detection when it does not. The comment should be removed or replaced with a note that Phase 13 unified detection across all hooks.

**3. JSON injection in bidirectional echo response (3 occurrences)**

`notification-idle-hook.sh` line 157, `notification-permission-hook.sh` line 158, and `stop-hook.sh` line 195 all contain:
```bash
echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
```

`$REASON` is extracted from OpenClaw's JSON response via `jq -r '.reason // ""'`. The `-r` flag strips jq's quote wrapping, returning a raw string. If the OpenClaw response includes a reason containing double quotes (e.g., `"stop because \"unsafe\" content detected"`), the literal `"` in `$REASON` will break the manually constructed JSON, causing Claude Code to receive malformed JSON. The fix is to use `jq -cn --arg reason "$REASON" '{"decision": "block", "reason": $reason}'` which escapes the value correctly. This is a security-adjacent correctness issue: a crafted reason string can cause hook injection into Claude Code's decision parsing.

**4. write_hook_event_record() internal duplication (lib/hook-utils.sh:203-258)**

The function contains two `jq -cn` blocks (lines 203-230 and lines 232-258) that are structurally identical except that the first includes `--argjson extra_fields "$extra_fields_json"` and appends `+ $extra_fields` to the output object. The base record construction (13 `--arg` parameters plus the JSON object literal) is copy-pasted. The duplication is approximately 28 lines. A cleaner approach: always build the base record, then conditionally merge extra fields:

```bash
# Build base record once, then merge if extra_fields provided
record=$(jq -cn ... '{timestamp, hook_script, ...}' 2>/dev/null) || return 0
if [ -n "$extra_fields_json" ]; then
  record=$(printf '%s\n%s' "$record" "$extra_fields_json" | jq -sc '.[0] + .[1]') || return 0
fi
```

This would reduce the function from ~56 lines to ~35 lines and eliminate the copy-paste risk if the base record schema ever changes.

**5. echo-to-jq patterns in diagnose-hooks.sh (scripts/diagnose-hooks.sh:155-157)**

Three `echo "$AGENT_ENTRY" | jq` patterns survive at lines 155-157:
```bash
TMUX_SESSION_NAME=$(echo "$AGENT_ENTRY" | jq -r '.tmux_session_name // ""')
OPENCLAW_SESSION_ID=$(echo "$AGENT_ENTRY" | jq -r '.openclaw_session_id // ""')
AGENT_ID=$(echo "$AGENT_ENTRY" | jq -r '.agent_id // ""')
```

The v3.1 printf sweep explicitly targeted only the 7 hook scripts, leaving `diagnose-hooks.sh` out of scope. These three lines carry the same latent escape-sequence risk that was fixed in the hooks. While `diagnose-hooks.sh` is a human-run diagnostic (not a Claude Code hook), the inconsistency is notable. If `AGENT_ENTRY` ever contains backslash-escaped content (e.g., Windows paths in registry data), these extractions could silently produce wrong values.

**6. Context pressure extraction triplication (13 lines, 3 copies)**

`notification-idle-hook.sh` lines 87-99, `notification-permission-hook.sh` lines 88-100, and `stop-hook.sh` lines 104-116 contain this identical 13-line block:
```bash
PERCENTAGE=$(printf '%s\n' "$PANE_CONTENT" | tail -5 | grep -oE '[0-9]{1,3}%' | tail -1 | tr -d '%' 2>/dev/null || echo "")
if [ -n "$PERCENTAGE" ]; then
  if [ "$PERCENTAGE" -ge 80 ]; then
    CONTEXT_PRESSURE="${PERCENTAGE}% [CRITICAL]"
  elif [ "$PERCENTAGE" -ge "$CONTEXT_PRESSURE_THRESHOLD" ]; then
    CONTEXT_PRESSURE="${PERCENTAGE}% [WARNING]"
  else
    CONTEXT_PRESSURE="${PERCENTAGE}% [OK]"
  fi
else
  CONTEXT_PRESSURE="unknown"
fi
```

`pre-compact-hook.sh` lines 65-73 has a different but functionally similar version using `grep -oP '\d+(?=% of context)'` (Perl regex, stricter pattern). The 3-copy version could be extracted as an `extract_context_pressure` function in `lib/hook-utils.sh`. The pre-compact version is intentionally different (precision over generality) and would remain inline or become a separate function variant.

**7. "Phase 2 redirect" block duplicated in all 7 hooks (21 lines, 7 copies)**

After `SESSION_NAME` extraction, every hook contains a 3-line "Phase 2 redirect" block:
```bash
# stop-hook.sh lines 42-44 (identical in all 7 hooks at similar positions):
GSD_HOOK_LOG="${SKILL_LOG_DIR}/${SESSION_NAME}.log"
JSONL_FILE="${SKILL_LOG_DIR}/${SESSION_NAME}.jsonl"
debug_log "=== log redirected to per-session file ==="
```

This appears in: `stop-hook.sh:42-44`, `notification-idle-hook.sh:36-38`, `notification-permission-hook.sh:37-39`, `session-end-hook.sh:28-30`, `pre-compact-hook.sh:28-30`, `pre-tool-use-hook.sh:35-37`, `post-tool-use-hook.sh:41-43`. Moving this into `hook-preamble.sh` is not possible without also passing `SESSION_NAME` to preamble (which runs before session name extraction). A utility function `redirect_to_session_log() { local session_name="$1"; GSD_HOOK_LOG="..."; JSONL_FILE="..."; debug_log "..."; }` would consolidate it, though the global variable assignment would need `declare -g` or be accepted as a documented side effect.

---

## Missed Opportunities

**1. hook-preamble.sh could have eliminated the Phase 2 redirect block**

The preamble was designed to set `GSD_HOOK_LOG` to the shared `hooks.log` as a default. However, it does not set `JSONL_FILE` at all — `JSONL_FILE` is always set in the per-session redirect block in each hook body. A `redirect_to_session_log()` function could have been added to `lib/hook-utils.sh` alongside the other shared functions during Phase 12, reducing the 7x 3-line duplication. The plan did not include this, but it was a natural extension of the preamble work.

**2. write_hook_event_record() internal duplication was flagged in v3.0 and not fixed**

The v3.0 retrospective explicitly documented: "A single invocation building the base object and then conditionally merging extra fields would halve the function's line count." This was the lowest-risk improvement possible (self-contained function, no callers change signature) and was available in Phase 12 when the file was being actively modified to add two new functions. It was not included in the v3.1 scope. The two-block duplication in `write_hook_event_record` (lib/hook-utils.sh:203-258) now spans ~56 lines.

**3. Context pressure extraction could have been a fourth shared function**

Phase 12 added `extract_hook_settings()` and `detect_session_state()`. Context pressure extraction (13 lines, 3 identical copies in stop/idle/permission hooks) is equally mechanical and equally correct for extraction. A `classify_context_pressure(pane_content, threshold)` function would have been a natural third addition during the same Phase 12 session, but the plan did not target it. The `pre-compact-hook.sh` variant (grep -oP lookahead) creates a genuine two-implementation problem that still needs resolution.

**4. The delivery pattern was not targeted despite being the largest remaining duplication**

At ~30 lines per copy across 3 hooks (stop, notification-idle, notification-permission), the bidirectional/async delivery pattern is the single largest remaining duplication block. v3.1's stated goal was "Extract shared code from duplicated hook preambles, unify divergent patterns." The delivery pattern is equally duplicated but was not in scope for v3.1. A `deliver_with_mode()` function adding one parameter (`hook_mode`) to the existing `deliver_async_with_logging()` signature could have reduced 90 lines of duplication to 3 call sites.

---

## v3.0 Issue Resolution Scorecard

The following table maps each issue from `docs/v3-retrospective.md` "What Could Be Improved" section to its v3.1 resolution status.

| v3.0 Issue | v3.0 Location | v3.1 Status | Notes |
|-----------|---------------|-------------|-------|
| 27-line hook preamble copy-pasted 7x | All 7 hooks lines 1-27 | **FIXED** | `lib/hook-preamble.sh` introduced; all hooks reduced to 3-line source statement |
| hook_settings extraction block copy-pasted 4x | stop/idle/permission/pre-compact | **FIXED** | `extract_hook_settings()` added to hook-utils.sh:348-364; 4 hooks use 3-line call |
| State detection: two different implementations | stop/idle/permission vs pre-compact | **FIXED** | `detect_session_state()` added to hook-utils.sh:392-407; pre-compact normalized |
| `[PANE CONTENT]` vs `[CONTENT]` inconsistency | idle:162, permission:158, pre-compact:137 | **FIXED** | All 4 pane-capturing hooks now use `[CONTENT]` label |
| Context pressure: two different grep patterns | stop vs pre-compact | **PARTIAL** | Same patterns not unified; pre-compact still uses `grep -oP` lookahead; duplication not extracted |
| session-end-hook.sh missing `2>/dev/null` guards | session-end-hook.sh:71-72 | **FIXED** | Lines 46-47 now have `2>/dev/null \|\| echo ""` |
| diagnose Step 7 exact-match vs prefix-match | diagnose-hooks.sh:263-265 | **FIXED** | Step 7 now uses `startswith($agent.agent_id + "-")` prefix-match |
| diagnose Step 2 missing pre-tool-use/post-tool-use | diagnose-hooks.sh:99-105 | **FIXED** | Both scripts added to HOOK_SCRIPTS array:99-107 |
| `write_hook_event_record` internal jq duplication | hook-utils.sh:203-258 | **UNCHANGED** | Two identical jq blocks remain; not targeted in v3.1 |
| echo-to-jq patterns across older hooks | stop/idle/permission/session-end | **FIXED** (hooks) | 7 hooks swept; diagnose-hooks.sh lines 155-157 still use echo |
| Bidirectional `--json` flag coupling undocumented | stop:225, notification hooks | **UNCHANGED** | Not targeted; still undocumented coupling to OpenClaw response format |
| JSON injection in bidirectional reason echo | idle:157, permission:158, stop:195 | **UNCHANGED** | `echo "{...\"$REASON\"}"` still present in 3 hooks |

**Summary: 7 of 12 v3.0 issues fully fixed, 1 partially fixed, 4 unchanged.**

---

## Lessons for Future Refactoring

**1. Scope all related duplication in the same phase, not just the highest-priority copy**

v3.1 fixed the preamble duplication (highest priority per v3.0 retrospective) and also added `extract_hook_settings()` and `detect_session_state()` as natural companions. But context pressure extraction (equally mechanical, equally duplicated) and the delivery pattern (the largest remaining block) were left out of scope. When a refactoring phase opens a shared library file for modification, the marginal cost of adding one more function is near zero. The opportunity cost of deferral is another full future phase.

**2. Stale comments are code rot — treat them as bugs**

The `detect_session_state()` comment at hook-utils.sh:386-391 became false the moment Phase 13 migrated pre-compact. Comments that describe "why this hook does X instead of calling the shared function" must be updated or deleted when the behavior changes. In shared library files read by multiple developers, false comments are worse than no comments.

**3. JSON construction via string interpolation is always wrong for user-controlled values**

Three occurrences of `echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"` survived v3.1 despite the `printf '%s'` sweep. The sweep only targeted jq input piping, not jq output construction. A code review checklist item — "no shell variable interpolation inside JSON string literals" — would catch this category. Always use `jq -cn --arg value "$VALUE" '{"key": $value}'` for JSON construction involving shell variables.

**4. "Out of scope" designations should be documented in the plan, not just applied implicitly**

The v3.1 plan explicitly targeted hook scripts for the `printf '%s'` sweep. `diagnose-hooks.sh` was implicitly out of scope but was not noted as such in the plan. As a result, `diagnose-hooks.sh` lines 155-157 survived with `echo`-to-jq patterns that create a visible inconsistency. If a boundary is intentional, state it: "printf sweep applies to 7 hook scripts only; diagnose-hooks.sh deferred."

**5. Retrospective-driven planning is effective — write retrospectives before planning the next phase**

v3.0's retrospective correctly identified all 6 major issues that v3.1 addressed. The retrospective-first approach ensures that known technical debt gets prioritized rather than accumulating silently. The issues that v3.0 flagged as "v4.0 priorities" were exactly what v3.1 shipped. The issues that v3.1 leaves for v4.0 (delivery triplication, JSON injection, write_hook_event_record duplication) are now documented with specific file:line references, making the next phase's scoping straightforward.
