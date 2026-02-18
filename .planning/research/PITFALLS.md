# Pitfalls Research

**Domain:** Hook script refactoring — extracting shared preamble, unifying patterns, completing [CONTENT] migration in production bash hook system
**Researched:** 2026-02-18
**Confidence:** HIGH — pitfalls derived from empirical bash testing (BASH_SOURCE chain, set -e propagation, variable scoping, double-source behavior), direct reading of all 7 production hook scripts, v3.0 retrospective analysis, and confirmed diagnose-hooks.sh mismatch

---

## Scope

This document covers pitfalls specific to v3.1 refactoring: extracting a shared `hook-preamble.sh`, unifying state detection and context pressure patterns, completing the [CONTENT] wake format migration in notification hooks, fixing `diagnose-hooks.sh` to use prefix-match lookup, and replacing `echo` with `printf '%s'` for JSON pipeline safety. The prior milestone pitfalls (JSON escaping, flock atomicity, correlation IDs, async stdin inheritance) are solved in the shipped v3.0 codebase and are NOT re-documented here.

---

## Critical Pitfalls

### Pitfall 1: hook-preamble.sh Using BASH_SOURCE[0] Computes Its Own Location, Not the Hook's Location

**What goes wrong:**
If `hook-preamble.sh` lives in `lib/` and uses `BASH_SOURCE[0]` to compute `SKILL_LOG_DIR` — as the current hook scripts do with `$(dirname "${BASH_SOURCE[0]}")` — it resolves to `lib/`, not `scripts/`. The path computation `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` inside a sourced file returns the directory of the sourced file itself, not the directory of the script that called `source`. This is the expected bash behavior but counterintuitive for preamble extraction.

Concretely: `hook-preamble.sh` in `lib/` using `$(dirname "${BASH_SOURCE[0]}")/../logs` would resolve to `lib/../logs` which happens to equal `logs/` — the same result as `scripts/../logs`. This is accidentally correct in the current layout where `lib/` and `scripts/` are siblings under the skill root. If the layout ever changes (preamble moves to `scripts/lib/` or any nested directory), the path computation breaks silently.

**Why it happens:**
Developers extracting preamble code copy the existing `BASH_SOURCE[0]` pattern verbatim without verifying what it resolves to in the preamble's context. They test with the current layout where `lib/../logs` and `scripts/../logs` happen to be identical, and the test passes. The bug only surfaces if directory layout changes.

**How to avoid:**
Use `BASH_SOURCE[1]` to get the calling hook's directory when computing paths inside the preamble, OR pass the hook's `SCRIPT_DIR` as a parameter to the preamble, OR use the accidentally-correct `BASH_SOURCE[0]` only after documenting that it must remain in `lib/` (sibling of `scripts/`).

The cleanest approach: have the hook script compute `SKILL_LOG_DIR` and `SCRIPT_DIR` before sourcing the preamble, then the preamble inherits those values via `${SKILL_LOG_DIR:-}` conditionals. This keeps path computation in the hook (where it belongs) and preamble stays path-agnostic.

```bash
# In hook script (before sourcing preamble):
SKILL_LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$SKILL_LOG_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/hook-preamble.sh"

# In hook-preamble.sh (uses inherited SKILL_LOG_DIR, no BASH_SOURCE path math):
GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]:-}")"
```

Empirically verified: `BASH_SOURCE[1]` inside a sourced preamble correctly returns the calling hook script's path (tested with bash 5.2.21 on the production host).

**Warning signs:**
- Preamble tests pass but preamble is always tested from `lib/` directory or with matching layout
- `SKILL_LOG_DIR` resolves correctly in CI but breaks when symlinked or when install path changes
- Logs appear in wrong directory without error (silent wrong path)

**Phase to address:**
Phase 1 (hook-preamble.sh creation) — establish the path computation contract before writing any preamble code. Document which BASH_SOURCE index is used and why.

---

### Pitfall 2: HOOK_SCRIPT_NAME Set by Preamble Before debug_log Is Defined Produces Wrong Script Name

**What goes wrong:**
If `hook-preamble.sh` sets `HOOK_SCRIPT_NAME` using `$(basename "${BASH_SOURCE[0]}")`, every hook logs `[hook-preamble.sh]` instead of `[stop-hook.sh]` or `[notification-idle-hook.sh]`. The `debug_log()` function uses `$HOOK_SCRIPT_NAME` in its output. If preamble sets this variable using its own `BASH_SOURCE[0]`, all log entries are attributed to the preamble, not the calling hook. This makes log analysis impossible — you cannot filter by hook script name.

**Why it happens:**
The current per-hook preamble code uses `HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"` — this works in each hook because `BASH_SOURCE[0]` is the hook itself. When this line is moved verbatim to `hook-preamble.sh`, `BASH_SOURCE[0]` becomes `hook-preamble.sh`. Developers run a quick test and see logs appear — they do not notice the script name is wrong until checking actual log entries.

**How to avoid:**
Set `HOOK_SCRIPT_NAME` using `BASH_SOURCE[1]` (the caller's path) inside the preamble, or have each hook set `HOOK_SCRIPT_NAME` itself before sourcing the preamble (in which case the preamble uses `${HOOK_SCRIPT_NAME:-}` conditionally). The `BASH_SOURCE[1]` approach is cleaner because hooks do not need to know about this detail:

```bash
# In hook-preamble.sh:
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]:-hook-unknown.sh}")"
```

Empirically verified: `BASH_SOURCE[1]` inside `hook-preamble.sh` sourced by `stop-hook.sh` returns `stop-hook.sh` (tested).

**Warning signs:**
- Log entries show `[hook-preamble.sh]` instead of `[stop-hook.sh]`
- All hook invocations appear to come from the same script in log analysis
- `grep 'stop-hook.sh' logs/warden-main.log` returns zero results for stop events

**Phase to address:**
Phase 1 (hook-preamble.sh creation) — verify `HOOK_SCRIPT_NAME` in log output after preamble extraction by checking a live hook fire log.

---

### Pitfall 3: exit in Sourced Preamble Terminates the Calling Hook

**What goes wrong:**
`exit` in a sourced file (`source hook-preamble.sh`) terminates the entire calling hook process, not just the preamble. This is correct bash behavior — `exit` in a sourced script exits the calling process. However, if `hook-preamble.sh` ever contains an early-exit guard (e.g., `if [ ! -f "$LIB_PATH" ]; then exit 0; fi`), that `exit 0` would silently terminate any hook that sources the preamble whenever the library is missing. This is hard to detect because the hook exits cleanly (exit code 0) with no indication of where it stopped.

The current per-hook guard pattern uses `exit 0` on missing lib — this is intentional. But if the preamble gains additional early-exit conditions in the future (or if a developer copies the pattern incorrectly), the preamble's exit propagates to the hook without warning.

**Why it happens:**
Developers who know `exit` in a subshell stays local to the subshell forget that `source` does NOT create a subshell — it executes in the current shell. An `exit` in a sourced file is an `exit` in the current shell.

**How to avoid:**
Limit preamble early-exit paths to exactly one: the lib-not-found case. Document the behavior explicitly in the preamble header. Do not add any other early-exit conditions to `hook-preamble.sh` — it should be a pure setup file. If `hook-preamble.sh` itself sources `hook-utils.sh`, the lib-not-found guard should remain in `hook-preamble.sh` (not the hook script), and that is the only `exit` the preamble should contain.

```bash
# hook-preamble.sh: only acceptable exit pattern
LIB_PATH="${PREAMBLE_DIR}/hook-utils.sh"
if [ ! -f "$LIB_PATH" ]; then
  printf '[%s] [%s] FATAL: hook-utils.sh not found\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$(basename "${BASH_SOURCE[1]:-}")" \
    >> "${GSD_HOOK_LOG:-/dev/stderr}" 2>/dev/null || true
  exit 0
fi
source "$LIB_PATH"
```

**Warning signs:**
- Hook fires but produces no log entries at all (exits at preamble, before debug_log "FIRED")
- `diagnose-hooks.sh` shows hooks registered and scripts executable, but no FIRED entries in logs
- Behavior changes after adding a new condition to preamble

**Phase to address:**
Phase 1 (hook-preamble.sh creation) — document the exit propagation behavior in the preamble header comment; code review any future preamble changes for unapproved exit paths.

---

### Pitfall 4: Preamble Unconditional Variable Assignment Overwrites Hook's Pre-Set Values

**What goes wrong:**
If `hook-preamble.sh` uses direct assignment (`GSD_HOOK_LOG="..."`) instead of conditional assignment (`GSD_HOOK_LOG="${GSD_HOOK_LOG:-...}"`), it overwrites any value the hook set before sourcing. Empirically tested: preamble direct assignment clobbers the hook's pre-set value. This becomes a problem if any hook needs to set `GSD_HOOK_LOG` to a custom value before calling the preamble, or if the preamble is sourced from a context where the variable is already set correctly.

More importantly: `set -euo pipefail` in hooks means `${UNSET_VAR}` causes an immediate exit. If preamble sets `HOOK_SCRIPT_NAME` conditionally with `:-` and the variable is expected to be set already by the hook — but is not — the hook exits at the first reference to `$HOOK_SCRIPT_NAME`. The opposite is also a risk: if preamble unconditionally sets variables the hook later expects to control, the hook's assignments after sourcing have no effect on already-computed values.

**Why it happens:**
Developers copying the existing top-of-hook pattern copy the direct assignment form (because that is what the current hooks use). The conditional form requires a conscious choice to prefer it. Without testing the override scenario explicitly, the overwrite behavior is invisible.

**How to avoid:**
Use `${VAR:-default}` for any variable that the hook might legitimately set before or after sourcing the preamble. Use direct assignment only for variables that the preamble definitively owns and the hook should never override. For `GSD_HOOK_LOG` specifically: use conditional because hooks redirect it mid-execution in Phase 2 (after session name is known). For `HOOK_SCRIPT_NAME`: use `${BASH_SOURCE[1]}` approach which is always correct regardless of pre-set values.

**Warning signs:**
- Hook sets a variable before sourcing preamble, but preamble's value takes effect
- GSD_HOOK_LOG points to `hooks.log` even after the hook's Phase 2 redirect (because preamble reset it)
- Custom per-hook log paths ignored silently

**Phase to address:**
Phase 1 (hook-preamble.sh creation) — review each variable the preamble sets and decide: conditional vs unconditional. Document the contract.

---

### Pitfall 5: Double-Sourcing hook-utils.sh When Preamble Already Sources It

**What goes wrong:**
All 7 current hooks contain the pattern:
```bash
LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"
if [ -f "$LIB_PATH" ]; then
  source "$LIB_PATH"
fi
```
If `hook-preamble.sh` is introduced and it also sources `hook-utils.sh`, this block becomes a double-source. The functions redefine harmlessly (empirically verified: double-sourcing does not cause errors), but any state variables set inside `hook-utils.sh` at source time (not in functions) get reset. The current `hook-utils.sh` has no top-level state assignments — it is pure function definitions — so double-sourcing is currently harmless but fragile.

The real risk: the old `source hook-utils.sh` block must be DELETED from each hook during migration. If it is not deleted — which is an easy omission when making multiple edits to 7 files — the hook sources hook-utils.sh twice. This adds ~1ms overhead per hook fire and creates confusion when reading the scripts.

**Why it happens:**
Refactoring 7 files simultaneously with a shared preamble requires remembering to remove the per-hook lib-source block from each file. This is a deletion that must happen alongside the addition of the preamble source line. Forgetting one file is easy.

**How to avoid:**
Make the deletion explicit in the migration plan — not just "add preamble source" but "add preamble source AND delete the existing lib-source block". Verify with `grep -n 'source.*hook-utils.sh' scripts/*.sh` after migration — all matches should be zero (the source now happens inside preamble.sh, not in hook scripts directly).

**Warning signs:**
- `grep -rn 'source.*hook-utils.sh' scripts/'` shows hits in any hook script after migration
- Hook scripts are slightly slower (one extra source per invocation)
- `hook-utils.sh` contains a counter or `echo` statement for debugging — you see it fire twice

**Phase to address:**
Phase 1 (hook script migration) — include explicit deletion step in migration checklist; verify with grep after each hook script is modified.

---

### Pitfall 6: Pre-compact-hook.sh State Detection Uses Different Grep Patterns — Unification Changes Behavior

**What goes wrong:**
`pre-compact-hook.sh` state detection differs from all other hooks in four confirmed ways (empirically verified):

| Aspect | stop/notification hooks | pre-compact-hook.sh |
|--------|------------------------|---------------------|
| Case sensitivity | `grep -Eiq` (case-insensitive) | `grep -q` (case-sensitive) |
| Menu pattern | `'Enter to select\|numbered.*option'` | `"Choose an option:"` |
| Idle pattern | `'What can I help\|waiting for'` | `"Continue this conversation"` |
| Fallback state | `"working"` | `"active"` |
| Error detection | `grep -Ei 'error\|failed\|exception'` present | Absent (no error state) |

These are NOT equivalent. A pane containing `"Choose an option:"` is detected as `menu` by pre-compact but falls through to `working` by the stop/notification pattern (empirically confirmed). A pane containing `"Continue this conversation"` is detected as `idle_prompt` by pre-compact but falls through to `working` by stop/notification.

If `detect_session_state` is extracted as a shared function using the stop/notification pattern, `pre-compact-hook.sh` would silently start reporting `working` for states it currently reports as `menu` or `idle_prompt`.

**Why it happens:**
The patterns were written at different times for different triggers. The PreCompact event fires during Claude Code's compaction dialog (specific TUI text). The Stop/Notification events fire at different points with different TUI content. The patterns may be genuinely different TUI text — or they may be stale copies from before the TUI text was known precisely. The difference is undocumented.

**How to avoid:**
Do not blindly unify state detection. Investigate whether the patterns reflect different actual TUI text (if yes: keep separate patterns, add a comment explaining why) or whether they are historical accidents (if yes: consolidate after verifying with live session data). Until verified, treat pre-compact state detection as intentionally different from stop/notification state detection.

If a `detect_session_state` function is added to `lib/hook-utils.sh`, it should accept a variant parameter:
```bash
detect_session_state "compact" "$PANE_CONTENT"  # pre-compact patterns
detect_session_state "standard" "$PANE_CONTENT"  # stop/notification patterns
```

Or keep two separate named functions: `detect_state_standard()` and `detect_state_compact()`.

**Warning signs:**
- After extraction, `pre-compact-hook.sh` JSONL records show `state=working` where they previously showed `state=menu` or `state=idle_prompt`
- OpenClaw agents receive different state hints for pre-compact events after refactoring
- No visible error — silent behavior change in state detection

**Phase to address:**
Phase 1 or dedicated research — before extracting state detection into a shared function, document why the two patterns exist and confirm (via live session observation or code archaeology) whether they should be unified.

---

### Pitfall 7: [CONTENT] Migration on Notification Hooks Fails Because transcript_path Is Absent

**What goes wrong:**
The v2.0 [CONTENT] format migration in `stop-hook.sh` uses `transcript_path` from stdin JSON:
```bash
TRANSCRIPT_PATH=$(printf '%s' "$STDIN_JSON" | jq -r '.transcript_path // ""')
EXTRACTED_RESPONSE=$(extract_last_assistant_response "$TRANSCRIPT_PATH")
```
`transcript_path` is provided by Claude Code only for Stop events (which fire after a response completes). `notification-idle-hook.sh`, `notification-permission-hook.sh`, and `pre-compact-hook.sh` do NOT receive `transcript_path` in their stdin — these events fire during Claude Code UI state changes, not after response completion.

If [CONTENT] migration for notification hooks is implemented by copying the stop-hook.sh pattern verbatim (including transcript extraction), `TRANSCRIPT_PATH` will always be empty for these hooks, `extract_last_assistant_response ""` will return empty, and the content section will fall through to the pane diff fallback. This is the same end result as the current [PANE CONTENT] approach — correct behavior but wasteful (runs transcript extraction that always fails).

The real risk is if the check `if [ -f "$TRANSCRIPT_PATH" ]` is not guarded and triggers a failure when the path is empty under `set -euo pipefail`. The current `extract_last_assistant_response()` function guards against empty path:
```bash
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  printf ''
  return
fi
```
So a direct copy would be safe but wasteful.

**Why it happens:**
Developers implementing [CONTENT] migration apply the stop-hook.sh pattern uniformly without checking which events provide `transcript_path`. The notification hooks fire on different events than Stop and have different stdin schemas.

**How to avoid:**
For notification and pre-compact hooks, the [CONTENT] migration is specifically NOT about transcript extraction — it is only about renaming the wake message section from `[PANE CONTENT]` to `[CONTENT]`. The content source remains pane capture. The change is minimal: replace the string `[PANE CONTENT]` with `[CONTENT]` in the WAKE_MESSAGE heredoc. Do not add transcript extraction to these hooks.

```bash
# WRONG for notification hooks:
EXTRACTED_RESPONSE=$(extract_last_assistant_response "$TRANSCRIPT_PATH")  # Always empty
CONTENT_SECTION="${EXTRACTED_RESPONSE:-$PANE_CONTENT}"  # Falls through to pane anyway

# CORRECT for notification hooks:
CONTENT_SECTION="$PANE_CONTENT"  # Direct — no transcript for these events
# And in WAKE_MESSAGE:
WAKE_MESSAGE="...
[CONTENT]
${CONTENT_SECTION}
..."
```

**Warning signs:**
- Notification hooks always show `content_source=pane_diff` instead of expected pane capture
- Slight latency increase on notification hooks from unnecessary transcript path checking
- `transcript_path` appears in notification hook debug logs with empty value

**Phase to address:**
Phase covering [CONTENT] migration — specify per-hook what the migration means: notification/pre-compact hooks change only the section label; stop-hook.sh already has full transcript extraction and should not be changed.

---

### Pitfall 8: diagnose-hooks.sh Step 7 Prefix-Match Fix Must Not Break Agent Name Lookup in Step 3

**What goes wrong:**
`diagnose-hooks.sh` Step 3 uses exact `agent_id` match: `select(.agent_id == $agent_id)`. Step 7 currently uses exact `tmux_session_name` match: `select(.tmux_session_name == $session)`. The fix for Step 7 is to use the same `startswith($agent.agent_id + "-")` prefix logic that hooks use. However, the fix must not accidentally change Step 3 — which correctly uses exact match on `agent_id` (the user provides the agent name as CLI argument).

Additionally, the prefix-match fix for Step 7 requires knowing `AGENT_ID` (which comes from Step 3). The current Step 7 uses the raw `TMUX_SESSION_NAME` variable from Step 3's registry lookup. The fix must chain from Step 3's data, not from the raw CLI argument.

If the fix incorrectly modifies Step 3 to use prefix match on `agent_id`, a user running `diagnose-hooks.sh warden` would match ALL agents whose ID starts with "warden" — potentially a false positive for similarly-named agents.

**Why it happens:**
The two lookups serve different purposes: Step 3 is "find the configured entry for this agent name" (user-provided exact name), Step 7 is "simulate what the hook scripts would do with this session name" (prefix match on session name). Conflating them produces either false positives (Step 3 too loose) or false negatives (Step 7 too strict, current bug).

**How to avoid:**
Fix ONLY Step 7. Replace the exact `tmux_session_name` match with the `startswith($agent.agent_id + "-")` pattern, sourcing `AGENT_ID` from the Step 3 result:

```bash
# Step 7 fix: use same prefix-match logic as lookup_agent_in_registry()
LOOKUP_RESULT=$(jq -c \
  --arg session "$TMUX_SESSION_NAME" \
  --arg agent_id "$AGENT_ID" \
  '.agents[] | select($session | startswith($agent_id + "-")) | {agent_id, openclaw_session_id}' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")
```

Alternative: import `lookup_agent_in_registry` from `lib/hook-utils.sh` into `diagnose-hooks.sh` by sourcing it, then call the same function. This guarantees diagnose and hooks use identical logic and any future changes to the lookup logic update both.

**Warning signs:**
- After Step 7 fix, a session `warden-main-2` triggers prefix match on agent_id `warden-` — matched correctly
- A session `forge-prod` with agent_id `forge` also matches — verify this is correct behavior
- Step 3 results are unchanged (agent name lookup still uses exact `agent_id` match)

**Phase to address:**
Phase covering diagnose-hooks.sh fixes — fix is isolated to Step 7 jq query; verify Step 3 is untouched.

---

### Pitfall 9: session-end-hook.sh Missing 2>/dev/null Guards — Still Unfixed After v3.0

**What goes wrong:**
`session-end-hook.sh` lines 71-72 use bare `jq -r '.agent_id'` without `2>/dev/null || echo ""` guards:
```bash
AGENT_ID=$(echo "$AGENT_DATA" | jq -r '.agent_id')
OPENCLAW_SESSION_ID=$(echo "$AGENT_DATA" | jq -r '.openclaw_session_id')
```
All other hooks add `2>/dev/null || echo ""`. Under `set -euo pipefail`, a jq non-zero exit on malformed `AGENT_DATA` propagates and terminates the hook. The v3.0 retrospective (item 6) identified this but it was not fixed during v3.0. If this hook is touched during v3.1 preamble migration, the missing guards remain unless explicitly fixed.

**Why it happens:**
`session-end-hook.sh` was written at a different time (pre-Phase 8 style) and the guards were added to other hooks during v3.0 porting without retrofitting session-end-hook.sh. Code review on a single file during refactoring may not catch this because the pattern looks syntactically valid.

**How to avoid:**
Fix the guards during the preamble migration pass since session-end-hook.sh will be touched anyway:
```bash
AGENT_ID=$(echo "$AGENT_DATA" | jq -r '.agent_id' 2>/dev/null || echo "")
OPENCLAW_SESSION_ID=$(echo "$AGENT_DATA" | jq -r '.openclaw_session_id' 2>/dev/null || echo "")
```

**Warning signs:**
- session-end-hook.sh silently exits on malformed registry entries (no log entry, no JSONL record)
- Other hooks handle malformed data gracefully but session-end-hook terminates without notification delivery

**Phase to address:**
Phase 1 (hook script migration) — fix during the preamble extraction pass since the file is being edited; treat as "while we're here" cleanup.

---

### Pitfall 10: echo "$VAR" | jq Silently Corrupts JSON Containing Backslash Sequences

**What goes wrong:**
The older hooks (`stop-hook.sh`, `notification-idle-hook.sh`, `notification-permission-hook.sh`, `session-end-hook.sh`, `pre-compact-hook.sh`) use `echo "$AGENT_DATA" | jq ...` to pipe JSON to jq. In bash, `echo` with the `-e` flag (or when `xpg_echo` is set) interprets escape sequences — `\n`, `\t`, `\r`, `\\`, etc. If `AGENT_DATA` or any piped variable ever contains a literal backslash followed by `n`, `t`, or other escape characters, `echo` may emit a newline or tab instead, corrupting the JSON string before jq receives it.

The newer hooks (`pre-tool-use-hook.sh`, `post-tool-use-hook.sh`) correctly use `printf '%s'` which always passes content literally without escape interpretation. The inconsistency means that a registry entry with backslash sequences in agent_id or openclaw_session_id would cause the older hooks to extract wrong values, while the newer hooks would work correctly. Bash's built-in `echo` behavior also varies across shells (dash vs bash vs zsh), creating portability risk if scripts are ever run under a different interpreter.

**Why it happens:**
The older hooks were written before the retrospective identified `echo "$VAR" | jq` as a latent correctness risk. The `printf '%s'` convention was adopted in newer hooks but the older hooks were not updated. During the v3.1 refactoring pass, the echo→printf migration requires visiting every hook file — it is easy to update some files and not others, leaving the system in a mixed state.

**How to avoid:**
Replace all `echo "$VAR" | jq` patterns with `printf '%s' "$VAR" | jq`. This applies to every occurrence in scripts/, not just the agent data extractions. Do a comprehensive sweep with:
```bash
grep -n "echo \"\$" scripts/*.sh | grep '| jq'
```
Every match should be changed to `printf '%s'`. The replacement is mechanical — identical behavior for non-backslash content, correct behavior for backslash-containing content.

Note: `echo "$STDIN_JSON" | jq ...` in a few places needs the same treatment. The current hooks have a mix — `post-tool-use-hook.sh` (line 45) correctly uses `printf '%s' "$STDIN_JSON"` while `notification-idle-hook.sh` (line 36) and `session-end-hook.sh` (line 35) use `echo "$STDIN_JSON"`.

**Warning signs:**
- After migration, `grep -n "echo \"\$" scripts/*.sh | grep '| jq'` returns hits — migration is incomplete
- Any hook using `echo` for jq input instead of `printf '%s'` is a mixed-state indicator
- Agent IDs or session IDs with backslash sequences produce empty extraction results (silent wrong value)

**Phase to address:**
Phase covering echo→printf migration — apply to all 7 hook scripts in a single pass; verify with grep after completion.

---

### Pitfall 11: Context Pressure Extraction Unification Introduces grep -oP Dependency or Changes Sentinel Value

**What goes wrong:**
`stop-hook.sh` and `notification-*` hooks extract context pressure with:
```bash
PERCENTAGE=$(echo "$PANE_CONTENT" | tail -5 | grep -oE '[0-9]{1,3}%' | tail -1 | tr -d '%' 2>/dev/null || echo "")
```
This uses POSIX ERE (`grep -oE`) and falls through to `CONTEXT_PRESSURE="unknown"` when no percentage is found.

`pre-compact-hook.sh` uses:
```bash
CONTEXT_PRESSURE_PCT=$(echo "$LAST_LINES" | grep -oP '\d+(?=% of context)' | tail -1 || echo "0")
```
This uses Perl-compatible regex (`grep -oP`) — not guaranteed available on all systems — and falls through to `CONTEXT_PRESSURE_PCT=0` (numeric zero, not the string "unknown").

These two extraction patterns produce different behavior:
1. The stop/notification pattern matches ANY `N%` in the last 5 lines and may false-positive on unrelated percentages (e.g., battery level, disk usage shown in pane).
2. The pre-compact pattern is more precise — only matches numbers followed by `% of context` — but requires Perl regex support.
3. The sentinel values differ: `"unknown"` (string, non-numeric) vs `0` (numeric zero). Downstream code that checks `[ "$CONTEXT_PRESSURE" = "unknown" ]` will fail to detect the pre-compact fallback.

If context pressure extraction is unified into a shared function, choosing the grep -oP pattern introduces a grep dependency that may not be available. Choosing the grep -oE pattern reduces precision. Using "unknown" as the universal sentinel breaks pre-compact's existing behavior (where 0 means "no pressure detected"). Using 0 as sentinel silently reports 0% pressure when extraction fails.

**Why it happens:**
The two hooks were written at different times for different event types (Stop vs PreCompact). The PreCompact hook was written with a more targeted pattern because compaction events happen during a specific Claude Code dialog that shows percentage of context. The Stop hook uses a broader pattern because stop events occur at any point.

**How to avoid:**
Before unifying, decide: is the stop/notification pattern's broader matching actually causing false positives in practice? If not, unify on the grep -oE pattern (wider compatibility) and standardize on `"unknown"` as the sentinel. If precision matters, unify on the grep -oP pattern but add a fallback for systems where grep -oP is unavailable. Document the sentinel choice explicitly: downstream code must handle both `"unknown"` and numeric strings.

Do not silently change pre-compact's sentinel from `0` to `"unknown"` without verifying that no downstream consumer checks `[ "$CONTEXT_PRESSURE_PCT" -eq 0 ]`.

**Warning signs:**
- After unification, pre-compact events log `context_pressure=unknown` where they previously logged `context_pressure=at 0%`
- grep -oP fails on minimal Linux installations where grep is compiled without PCRE support
- Downstream OpenClaw agent parsing breaks when receiving `"unknown"` instead of a numeric `0`

**Phase to address:**
Phase covering state detection / context pressure unification — document the sentinel choice and test with a pre-compact event after the change to verify pressure reporting is unchanged.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Copying hook preamble verbatim into preamble.sh without verifying BASH_SOURCE context | Fast extraction | BASH_SOURCE[0] resolves to wrong location in preamble; script name wrong in logs | Never — must verify BASH_SOURCE[0] vs [1] |
| Unifying state detection with single grep pattern | Simpler shared function | Pre-compact behavior changes silently — `menu` and `idle_prompt` states become `working` | Never — verify pattern equivalence first |
| Applying [CONTENT] migration by copying stop-hook.sh extract pattern | Uniform code | Wasteful transcript extraction for events with no transcript_path | Never — notification hooks need only label change |
| Fixing diagnose Step 7 without sourcing lookup_agent_in_registry | Simpler change | Logic diverges again when hook-utils.sh lookup logic changes | Acceptable short-term; prefer sourcing hook-utils.sh for full parity |
| Leaving double-source block in hook scripts after preamble migration | Defensive coding | Redundant source adds overhead; creates confusion during future edits | Never — preamble owns the single source of hook-utils.sh |
| Partial echo→printf migration (update some hooks, skip others) | Less work | Mixed-state codebase — harder to audit, backslash bugs lurk in skipped hooks | Never — migrate all 7 hooks in a single pass |
| Unifying context pressure extraction on grep -oP pattern | More precise matching | PCRE dependency fails on minimal systems; sentinel value change breaks downstream | Only if grep -oP availability is confirmed and sentinel is documented |

---

## Integration Gotchas

Common mistakes when connecting hook-preamble.sh to existing hook scripts.

| Integration Point | Common Mistake | Correct Approach |
|-------------------|----------------|------------------|
| BASH_SOURCE in preamble | Use BASH_SOURCE[0] for SKILL_LOG_DIR | Compute SKILL_LOG_DIR in hook before sourcing preamble; preamble inherits via ${SKILL_LOG_DIR:-} |
| HOOK_SCRIPT_NAME in preamble | Use BASH_SOURCE[0] (gives preamble.sh) | Use BASH_SOURCE[1] to get calling hook's name |
| GSD_HOOK_LOG assignment | Unconditional assignment in preamble | Conditional: `${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}` — hook's Phase 2 redirect must survive |
| hook-utils.sh source block | Leave old source block in hook scripts | Delete old block from every hook — preamble owns the single source |
| set -e propagation | Assume sourced preamble is isolated | exit in preamble exits the calling hook — keep preamble exits to minimum (lib-not-found only) |
| [CONTENT] migration for notification hooks | Copy stop-hook.sh extract_last_assistant_response call | Notification hooks: rename label only — pane capture is the correct content source |
| diagnose Step 7 lookup | Change Step 3 logic to match hooks | Fix ONLY Step 7 to use startswith prefix-match; Step 3 keeps exact agent_id match |
| Pre-compact state unification | Replace with stop/notification grep patterns | Verify TUI text equivalence first; if in doubt, keep separate patterns with comment explaining difference |
| echo→printf migration | Update only newly touched files | Sweep all 7 hook scripts in a single pass; verify with grep after completion |
| Context pressure sentinel | Change pre-compact sentinel from 0 to "unknown" without checking downstream | Decide sentinel once, document it, apply consistently; check JSONL consumers before changing |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **hook-preamble.sh BASH_SOURCE test:** After extraction, fire a live hook and verify log entries show `[stop-hook.sh]` not `[hook-preamble.sh]` — check `tail -5 logs/warden-main.log`
- [ ] **Old source blocks removed:** `grep -rn 'source.*hook-utils.sh' scripts/` returns zero matches (source now inside preamble.sh only)
- [ ] **GSD_HOOK_LOG Phase 2 redirect works:** After session name extraction, debug_log goes to per-session file not hooks.log — verify by checking session-specific log exists after a Stop event
- [ ] **Notification [CONTENT] label only:** `grep -n 'PANE CONTENT' scripts/notification-*.sh scripts/pre-compact-hook.sh` returns zero matches; `grep -n '\[CONTENT\]' scripts/notification-*.sh` returns matches
- [ ] **No transcript extraction added to notification hooks:** `grep -n 'extract_last_assistant_response\|TRANSCRIPT_PATH' scripts/notification-*.sh scripts/pre-compact-hook.sh` returns zero matches
- [ ] **Pre-compact state detection unchanged:** After refactoring, fire a pre-compact event and verify `state=menu` is reported when "Choose an option:" is in pane; `state=working` should NOT appear for this pane content
- [ ] **diagnose Step 7 prefix match:** Run `diagnose-hooks.sh warden` against a session named `warden-main-2`; Step 7 should PASS (was failing before fix)
- [ ] **diagnose Step 2 includes all 7 scripts:** `grep -A 10 'HOOK_SCRIPTS=(' scripts/diagnose-hooks.sh` shows all 7: stop, notification-idle, notification-permission, session-end, pre-compact, pre-tool-use, post-tool-use
- [ ] **session-end-hook.sh guards fixed:** `grep 'jq.*agent_id' scripts/session-end-hook.sh` shows `2>/dev/null || echo ""` on both jq calls
- [ ] **echo→printf migration complete:** `grep -n "echo \"\$" scripts/*.sh | grep '| jq'` returns zero matches across all 7 hook scripts
- [ ] **Context pressure sentinel documented:** After any context pressure unification, JSONL records for pre-compact events still show expected pressure values (not "unknown" where 0% was previously reported)

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| HOOK_SCRIPT_NAME wrong (shows preamble.sh) | LOW | 1. Change preamble to use `BASH_SOURCE[1]` 2. Redeploy (session restart required for hooks to reload) |
| GSD_HOOK_LOG overwritten by preamble | LOW | 1. Make preamble assignment conditional: `${GSD_HOOK_LOG:-...}` 2. Verify Phase 2 redirect works 3. Redeploy |
| Double-source confusion | LOW | 1. Delete old source block from hook scripts 2. Verify with grep 3. No session restart required (functions redefine identically) |
| Pre-compact state silent behavior change | MEDIUM | 1. Identify which state detection pattern was incorrectly applied 2. Restore pre-compact to its original patterns (or add variant parameter) 3. Redeploy 4. Check JSONL logs for `state=working` where `state=menu` was expected |
| Notification hook [CONTENT] migration includes transcript extraction | LOW | 1. Remove extract_last_assistant_response call from notification hooks 2. Keep only label rename 3. Redeploy |
| diagnose Step 7 fix breaks Step 3 | LOW | 1. Revert Step 7 to use AGENT_ID from Step 3 correctly 2. Apply prefix-match only to Step 7, not Step 3 |
| exit in preamble terminates hook silently | LOW-MEDIUM | 1. Check which condition causes preamble exit 2. Move guard to hook script if appropriate 3. Add plain printf log before exit so failure is visible |
| Partial echo→printf migration leaves some hooks unchanged | LOW | 1. Run `grep -n "echo \"\$" scripts/*.sh | grep '| jq'` to find remaining occurrences 2. Apply printf '%s' replacement to each hit 3. Re-verify with grep |
| Context pressure sentinel changed silently | LOW-MEDIUM | 1. Check JSONL logs for pre-compact events 2. Compare `context_pressure` values before and after 3. Restore pre-compact to its original sentinel if downstream consumers are affected |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| BASH_SOURCE[0] wrong in preamble (SKILL_LOG_DIR, HOOK_SCRIPT_NAME) | Phase creating hook-preamble.sh | Fire live hook, check log prefix is hook name not preamble name |
| exit propagation from preamble | Phase creating hook-preamble.sh | Code review: count exit statements in preamble (should be 1 max) |
| Preamble unconditional assignment overwrites hook vars | Phase creating hook-preamble.sh | Set GSD_HOOK_LOG before source, verify it survives to debug_log |
| Double-source of hook-utils.sh | Phase migrating hook scripts | `grep -rn 'source.*hook-utils.sh' scripts/` returns zero |
| Pre-compact state detection changed silently | Phase extracting shared state detection | JSONL logs: pre-compact `state` field values unchanged |
| [CONTENT] migration adds transcript extraction to notification hooks | Phase doing [CONTENT] migration | `grep -rn 'extract_last_assistant_response' scripts/notification-*.sh` returns zero |
| diagnose Step 7 fix changes Step 3 | Phase fixing diagnose-hooks.sh | Run diagnose with exact and -2 suffix sessions; verify Step 3 exact, Step 7 prefix |
| session-end-hook.sh missing jq guards | Phase migrating session-end-hook.sh | `grep 'jq.*agent_id' scripts/session-end-hook.sh` shows `2>/dev/null || echo ""` |
| diagnose Step 2 missing pre-tool-use and post-tool-use | Phase fixing diagnose-hooks.sh | `grep -c 'hook.sh' <(grep -A 20 'HOOK_SCRIPTS=(' scripts/diagnose-hooks.sh)` returns 7 |
| echo→printf incomplete migration | Phase applying echo→printf sweep | `grep -n "echo \"\$" scripts/*.sh | grep '| jq'` returns zero matches |
| Context pressure sentinel change | Phase unifying context pressure extraction | Fire pre-compact event after change; verify JSONL `context_pressure` field unchanged |

---

## Sources

### Empirically Tested (HIGH confidence — bash 5.2.21 on production host)

- BASH_SOURCE behavior in sourced files: `BASH_SOURCE[0]` = sourced file path; `BASH_SOURCE[1]` = calling script path — confirmed via direct testing
- `exit` in sourced file exits calling process — confirmed: `source preamble.sh` with `exit 0` in preamble terminates caller
- Variable scope in sourced files: all top-level assignments are global in calling shell — confirmed
- GSD_HOOK_LOG update after source: `debug_log()` reads `$GSD_HOOK_LOG` at call time, not at define time — confirmed (Phase 2 redirect works correctly)
- Double-source is harmless for pure-function libraries: functions redefine without error — confirmed
- Preamble direct assignment overwrites hook pre-set values — confirmed: preamble runs after hook, clobbers hook's value if not conditional
- Flock prevents concurrent write corruption even at >4KB — confirmed: 5 concurrent writers produce 5 valid JSON records

### Codebase Analysis (HIGH confidence — direct reading)

- `pre-compact-hook.sh` state detection differences: case-sensitive vs insensitive, different patterns, different fallback states — confirmed via code reading and grep equivalence testing
- `notification-idle-hook.sh`, `notification-permission-hook.sh` stdin schema: no `transcript_path` field — implicit from hook type (Notification vs Stop events); `transcript_path` documented as Stop-event-specific by Claude Code hook spec
- `diagnose-hooks.sh` Step 7 exact match vs hook prefix match: confirmed discrepancy via direct jq execution — `warden-main-2` fails Step 7 but hooks find agent correctly
- `session-end-hook.sh` missing guards: confirmed at lines 71-72 per v3.0 retrospective item 6
- echo vs printf usage split: `post-tool-use-hook.sh` and `pre-tool-use-hook.sh` use `printf '%s'` correctly; `stop-hook.sh`, `notification-idle-hook.sh`, `notification-permission-hook.sh`, `session-end-hook.sh`, `pre-compact-hook.sh` use `echo` — confirmed via direct code reading
- Context pressure extraction pattern split: stop/notification hooks use `grep -oE '[0-9]{1,3}%'` with "unknown" sentinel; pre-compact uses `grep -oP '\d+(?=% of context)'` with numeric 0 sentinel — confirmed via direct code reading

### v3.0 Retrospective (HIGH confidence — first-party analysis)

- `docs/v3-retrospective.md` — 8 identified improvements; pitfalls 1-9 address items 1-8; pitfalls 10-11 address the "Patterns to Reconsider" section (echo→printf and context pressure patterns)
- `.planning/STATE.md` Quick-9 note: "Incomplete v2.0 wake message migration — [CONTENT] applied only to stop-hook.sh; notification-idle, notification-permission, and pre-compact still use [PANE CONTENT]. Diagnose Step 7 uses exact match vs hook prefix-match — fix needed for v4.0."

---

*Pitfalls research for: v3.1 Hook Refactoring and Migration Completion*
*Researched: 2026-02-18*
*Researcher: GSD Project Researcher*
*Confidence: HIGH — empirical bash testing, direct codebase analysis, v3.0 retrospective*
