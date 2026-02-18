# Feature Research

**Domain:** Bash hook system refactoring — gsd-code-skill v3.1 (Hook Refactoring & Migration Completion)
**Researched:** 2026-02-18
**Confidence:** HIGH (existing codebase is the ground truth; all patterns verified by reading actual code)

---

## Context: What v3.0 Built (Already Shipped)

This is a subsequent milestone research file. v3.0 shipped:
- 7 hook scripts (stop, notification-idle, notification-permission, session-end, pre-compact, pre-tool-use, post-tool-use)
- lib/hook-utils.sh with 6 functions: `lookup_agent_in_registry`, `extract_last_assistant_response`, `extract_pane_diff`, `format_ask_user_questions`, `write_hook_event_record`, `deliver_async_with_logging`
- JSONL structured logging per-session (one record per invocation)
- v2.0 [CONTENT] format with transcript extraction — but only applied to stop-hook.sh
- State detection pattern matching — two divergent implementations
- Three-tier hook_settings fallback (per-agent > global > hardcoded) — duplicated 4 times
- diagnose-hooks.sh with 11 diagnostic steps — Step 7 uses wrong lookup strategy

**v3.1 problem statement:** v3.0 achieved structured logging but did not address the copy-paste debt that was present since v1.0. The 27-line hook preamble is duplicated across all 7 hooks. The hook_settings extraction block is duplicated across 4 hooks. State detection exists in two different implementations. The v2.0 [CONTENT] wake format migration was applied only to stop-hook.sh, leaving 3 hooks using the old [PANE CONTENT] header. diagnose-hooks.sh Step 7 uses exact-match lookup while the actual hooks use prefix-match — producing false diagnostic failures. These are pure maintenance debt items with no new user-facing features.

---

## Feature Landscape

### Table Stakes (Must Ship — Milestone Incomplete Without These)

These are the non-negotiable deliverables. The milestone is defined by these. All are internal refactoring — no new external behavior.

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| hook-preamble.sh — shared bootstrap for all 7 hooks | The 27-line preamble (SKILL_LOG_DIR, GSD_HOOK_LOG, HOOK_SCRIPT_NAME, debug_log function, SCRIPT_DIR, LIB_PATH, source with guard) is copy-pasted verbatim across all 7 hook scripts. One change (e.g., log format) requires 7 coordinated edits. Extracted as a sourced snippet, it becomes single-authoritative. | LOW | Must exist before any hook uses it. All 7 hooks must be updated in the same pass to avoid a mixed state where some hooks use preamble and some don't. |
| extract_hook_settings() in lib/hook-utils.sh | 12-line block extracting GLOBAL_SETTINGS, PANE_CAPTURE_LINES, CONTEXT_PRESSURE_THRESHOLD, HOOK_MODE from registry is duplicated identically in stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, pre-compact-hook.sh. The pre-compact copy omits the `2>/dev/null` error guards that the other three have — a silent inconsistency. Extract to a function; all 4 hooks call it with consistent behavior. | LOW | Requires lib/hook-utils.sh (exists). The 4 hooks source the lib before the settings extraction block, so the function is available. Hook-preamble.sh must exist first (since it sources lib). |
| [CONTENT] migration for notification-idle-hook.sh | This hook fires on idle_prompt events and sends [PANE CONTENT] section header. The v2.0 format uses [CONTENT] and is the documented canonical format. OpenClaw consumers must handle both or miss data from this hook. Apply the same migration stop-hook.sh got in v2.0: rename section header, replace raw PANE_CONTENT dump with transcript extraction (primary) and pane diff (fallback). | MEDIUM | Depends on extract_last_assistant_response() (in lib/hook-utils.sh, already exists) and extract_pane_diff() (exists). This is a behavior change — the content sent to OpenClaw becomes cleaner (transcript-extracted) vs the current raw pane dump. |
| [CONTENT] migration for notification-permission-hook.sh | Same as above. This hook fires on permission_prompt events. Same [PANE CONTENT] → [CONTENT] migration, same transcript/pane-diff extraction chain. | MEDIUM | Same as notification-idle migration. The two scripts are structurally identical post-guard — changes are parallel. |
| [CONTENT] migration for pre-compact-hook.sh | Same migration, but pre-compact is slightly different: it uses a different context pressure extraction pattern (grep -oP with Perl lookahead) and a different state detection pattern set. Migration includes normalizing context pressure extraction and unifying state detection if applicable. | MEDIUM | Same lib functions. However, pre-compact state detection is genuinely different (fires at a different point in the Claude Code lifecycle) so the decision on whether to unify state detection affects this migration. |
| diagnose-hooks.sh Step 7 prefix-match fix | Step 7 checks the registry with `select(.tmux_session_name == $session)` — exact match. The actual hooks use `lookup_agent_in_registry` which does `startswith($agent.agent_id + "-")` — prefix match. When a session has a `-2` suffix (tmux conflict resolution), hooks work but Step 7 reports failure. The diagnostic must match production behavior. Fix: replace Step 7 jq with the same startswith prefix logic (or call lookup_agent_in_registry if diagnose can source the lib). | LOW | lookup_agent_in_registry() exists in lib/hook-utils.sh. diagnose-hooks.sh can source the lib (it already knows SCRIPT_DIR and lib path). |
| diagnose-hooks.sh Step 2 — add pre-tool-use-hook.sh and post-tool-use-hook.sh | Step 2 checks 5 hook scripts but the system now has 7. pre-tool-use-hook.sh and post-tool-use-hook.sh added in Phases 6-10 were never added to Step 2's array. A missing or non-executable post-tool-use-hook.sh would silently break AskUserQuestion lifecycle logging without the diagnostic catching it. | LOW | No dependencies. Array addition only. |
| echo → printf '%s' cleanup for jq piping | Older hooks (stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh) use `echo "$AGENT_DATA" | jq ...` to pipe JSON. Under some shells, `echo` interprets backslash sequences and adds trailing newlines that corrupt JSON strings. Newer hooks (pre-tool-use-hook.sh, post-tool-use-hook.sh) correctly use `printf '%s'`. Under `set -euo pipefail`, this is a latent correctness risk. Replace all `echo "$VAR" \| jq` with `printf '%s' "$VAR" \| jq` in the affected hooks. | LOW | No dependencies. Search-and-replace across 4 files. |

### Differentiators (High Leverage — Ship If Time Allows)

These improve the system beyond baseline correctness but are not required for the milestone goal.

| Feature | Value Proposition | Complexity | Dependencies |
|---------|-------------------|------------|--------------|
| session-end-hook.sh jq error guard fix | `session-end-hook.sh` lines 71-72 use `echo "$AGENT_DATA" \| jq -r '.agent_id'` without `2>/dev/null \|\| echo ""` guards that all other hooks use. Under `set -euo pipefail`, a malformed AGENT_DATA causes the hook to crash (propagating a non-zero exit to Claude Code). Fix: add `2>/dev/null \|\| echo ""` to both lines. | LOW | No dependencies. Same fix pattern used in all other hooks. |
| Unified context pressure extraction | stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh use `grep -oE '[0-9]{1,3}%' \| tr -d '%'` — matches any N% string. pre-compact-hook.sh uses `grep -oP '\d+(?=% of context)'` — matches only numbers before "% of context". The pre-compact pattern is strictly more precise. After the [CONTENT] migration touches all four files, unify to the more precise pattern. Normalizes CONTEXT_PRESSURE="unknown" vs CONTEXT_PRESSURE_PCT=0 sentinel values. | LOW | Requires [CONTENT] migration of pre-compact-hook.sh. Can be bundled with that migration. |
| Unified state detection — document pre-compact intentional differences | pre-compact-hook.sh uses different grep patterns (case-sensitive, different keywords, `active` fallback vs `working`) than the other three pane-capturing hooks. Before unifying, verify whether these differences are intentional (different TUI text at PreCompact time) or accidental copy-paste divergence. If intentional, add an explanatory comment. If accidental, extract `detect_session_state()` to lib/hook-utils.sh and use it everywhere. | MEDIUM | Requires understanding of Claude Code TUI behavior at PreCompact vs Stop events. Cannot verify without a live session — flag as needing validation. |
| write_hook_event_record() internal deduplication | The function in lib/hook-utils.sh (lines 203-258) has two near-identical `jq -cn` blocks differing only by the extra_fields merge. A single invocation that conditionally includes `--argjson extra_fields` and `+ $extra_fields` only when extra_fields_json is non-empty would halve the function body. Reduces the risk of the two code paths diverging. | LOW | Internal to lib/hook-utils.sh. No hook script changes needed. |

### Anti-Features (Do Not Build)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Hook generator script (template → 7 hook scripts) | 7 scripts share 70-80% structure — a generator would enforce consistency | v3.1 scope is reducing existing duplication, not introducing new build tooling. Generator adds a build step to a bash-only skill. The preamble extraction achieves the same duplication reduction with no new tooling dependency. | Extract hook-preamble.sh + extract_hook_settings() — these achieve the same structural consistency without a build pipeline. |
| Consolidating 7 hook scripts into fewer files | "One file per event type" seems verbose | Each script must exit fast, independently, and has event-specific logic. Merging scripts that fire for different events would require multiplexing on event type inside one script — increasing branching complexity and making individual hook behavior harder to audit. The Claude Code hooks API calls each script independently; merging provides no performance benefit. | Keep 7 scripts. Reduce their shared boilerplate to a sourced preamble. |
| Retry logic for failed openclaw deliveries | Some deliveries return no_response — retrying would improve reliability | Retries inside async hook background processes create latency uncertainty. The hook architecture is fire-and-forget by design. Failed deliveries are already captured in JSONL as `no_response` outcomes — the diagnostic surfaces them. A retry mechanism belongs in OpenClaw's session management, not in hook scripts. | Keep `no_response` JSONL records as the signal. No retry in hooks. |
| PostToolUse tool_response schema validation in v3.1 | post-tool-use-hook.sh defensive extractor still unvalidated | Requires a live AskUserQuestion session to collect raw stdin data — this is an empirical investigation task, not a refactoring task. It is out of scope for a refactoring milestone. | Keep raw stdin logging and defensive extractor in post-tool-use-hook.sh. Resolve in a dedicated Quick Task when live session data is available. |
| printf '%s' migration to STDIN_JSON processing | STDIN_JSON comes from `cat` (not `echo`), so no echo-related risk | STDIN_JSON is set by `STDIN_JSON=$(cat)` — this is correct. Only the *piping* of STDIN_JSON or AGENT_DATA through `echo "$VAR" \| jq` is risky. Don't change the `cat` input pattern, only the downstream piping. | Scope the echo→printf fix only to `echo "$AGENT_DATA" \| jq` and `echo "$STDIN_JSON" \| jq` patterns — not to stdin consumption. |

---

## Feature Dependencies

```
hook-preamble.sh
    └──must exist before──> all 7 hooks use it
    └──must source──> lib/hook-utils.sh (to make debug_log visible from preamble, or preamble defines debug_log itself)
    └──ordering note──> ALL 7 hooks must be updated in one coordinated pass — mixed state (some with preamble, some without) is valid but confusing

extract_hook_settings() in lib/hook-utils.sh
    └──must exist before──> stop-hook.sh calls it (replaces lines 99-111)
    └──must exist before──> notification-idle-hook.sh calls it (replaces lines 92-104)
    └──must exist before──> notification-permission-hook.sh calls it (replaces lines 93-105)
    └──must exist before──> pre-compact-hook.sh calls it (replaces lines 81-93)
    └──requires──> hook-preamble.sh exists (hooks source lib via preamble; lib must be sourced before settings extraction)
    └──outputs──> PANE_CAPTURE_LINES, CONTEXT_PRESSURE_THRESHOLD, HOOK_MODE (set in calling hook scope via nameref or echo parsing)

[CONTENT] migration — notification-idle-hook.sh
    └──requires──> extract_last_assistant_response() in lib/hook-utils.sh (exists, no change needed)
    └──requires──> extract_pane_diff() in lib/hook-utils.sh (exists, no change needed)
    └──requires──> hook-preamble.sh applied (lib already sourced, so functions available)
    └──parallel with──> notification-permission-hook.sh migration (identical structure, can be one plan)

[CONTENT] migration — notification-permission-hook.sh
    └──same dependency tree as notification-idle migration
    └──parallel with──> notification-idle-hook.sh migration

[CONTENT] migration — pre-compact-hook.sh
    └──same extraction functions as above
    └──enhances──> context pressure unification (same file, bundle in same pass)
    └──may require──> state detection decision (unify vs document) before migration commits

diagnose-hooks.sh Step 7 prefix-match fix
    └──can source──> lib/hook-utils.sh and call lookup_agent_in_registry() directly
    └──independent of all other features (can ship in any order)

diagnose-hooks.sh Step 2 script list update
    └──independent of all other features
    └──parallel with──> Step 7 fix (same file, ship together)

echo → printf '%s' cleanup
    └──affects──> stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh
    └──can be bundled with──> [CONTENT] migration of notification hooks (same files touched)
    └──independent of preamble and settings extraction

session-end-hook.sh jq guard fix
    └──independent of all other features (one file, two lines)
    └──can be bundled with──> echo-to-printf cleanup (session-end is in the affected list)
```

### Dependency Notes

- **hook-preamble.sh is the root dependency.** All hook changes (settings extraction, [CONTENT] migration, echo→printf) touch the same files that will gain the preamble. Applying the preamble first means the subsequent changes operate on already-refactored files. Applying it last means doing two passes over every hook file. Build preamble first.
- **extract_hook_settings() is the second dependency.** It must land in lib/hook-utils.sh before the 4 pane-capture hooks are updated to call it. Since lib changes are additive (no hook behavior changes), this can land alongside or slightly after the preamble.
- **[CONTENT] migrations are independent of each other.** notification-idle and notification-permission are structurally identical — they can be one plan or two plans. pre-compact is different enough (context pressure extraction, state detection) to warrant its own plan.
- **diagnose-hooks.sh changes are fully independent.** They can ship in any order and do not affect hook behavior.
- **State detection unification requires investigation before committing.** Do not assume pre-compact patterns are wrong — they may be intentionally different. Flag this for a validation step, and default to documenting the difference if uncertain.

---

## MVP Definition

### Ship With This Milestone (v3.1 Core)

The minimum that makes v3.1 meaningful. All refactoring with no new behavior.

- [ ] **hook-preamble.sh** — All 7 hooks source it instead of carrying 27 lines of bootstrap code each. Immediate maintenance benefit: one place to change log format, lib path, or debug_log() behavior.
- [ ] **extract_hook_settings()** — Function in lib/hook-utils.sh replacing 4 identical 12-line blocks. The pre-compact copy's missing 2>/dev/null guards are fixed as a side effect.
- [ ] **[CONTENT] migration — notification-idle-hook.sh** — Section header and content extraction matches stop-hook.sh format. OpenClaw receives transcript-extracted content (not raw pane noise) for idle_prompt events.
- [ ] **[CONTENT] migration — notification-permission-hook.sh** — Same as above for permission_prompt events.
- [ ] **[CONTENT] migration — pre-compact-hook.sh** — Same migration plus context pressure extraction normalization.
- [ ] **diagnose-hooks.sh Step 7 prefix-match fix** — Diagnostic matches actual hook behavior for sessions with -2 suffix.
- [ ] **diagnose-hooks.sh Step 2 complete script list** — All 7 hook scripts checked, not 5.
- [ ] **echo → printf '%s' cleanup** — All `echo "$VAR" | jq` patterns in hook files replaced with `printf '%s' "$VAR" | jq`.

### Add After Validation (v3.1 Follow-on)

- [ ] **session-end-hook.sh jq error guard fix** — Can bundle with echo→printf cleanup since session-end is in the affected list.
- [ ] **Unified context pressure extraction** — Bundle with pre-compact [CONTENT] migration. Evaluate during that pass whether to use the more precise `grep -oP` pattern everywhere.
- [ ] **State detection documentation or unification** — Requires live session observation to confirm whether pre-compact TUI text differs. Default to documenting if unsure.

### Future Consideration (v4+)

- [ ] **write_hook_event_record() internal deduplication** — Low priority; function works correctly. Reduce code duplication within lib/hook-utils.sh when next touching the file for other reasons.
- [ ] **Eliminate plain-text debug_log() entirely** — Once JSONL covers all debug_log cases, remove the parallel plain-text log. Requires confirming JSONL has no coverage gaps.
- [ ] **PostToolUse tool_response schema validation** — Empirical investigation requiring live AskUserQuestion session data. Separate Quick Task, not a refactoring phase.

---

## Feature Prioritization Matrix

| Feature | Maintenance Value | Implementation Cost | Priority |
|---------|-----------------|---------------------|----------|
| hook-preamble.sh | HIGH — 7 files reduced to sourced snippet | LOW — write once, source in 7 files | P1 |
| extract_hook_settings() | HIGH — 4 identical blocks collapsed | LOW — 12-line function, 4 call sites | P1 |
| [CONTENT] migration — notification-idle | HIGH — format consistency, cleaner content | MEDIUM — transcript extraction chain | P1 |
| [CONTENT] migration — notification-permission | HIGH — same as above | MEDIUM — identical to idle migration | P1 |
| [CONTENT] migration — pre-compact | MEDIUM — format consistency | MEDIUM — context pressure normalization needed | P1 |
| diagnose Step 7 prefix-match fix | HIGH — false diagnostic failures eliminated | LOW — replace one jq select() | P1 |
| diagnose Step 2 script list | MEDIUM — diagnostic coverage complete | LOW — array addition | P1 |
| echo → printf '%s' cleanup | MEDIUM — latent correctness risk removed | LOW — search-and-replace | P1 |
| session-end jq guard fix | MEDIUM — crash under malformed AGENT_DATA | LOW — add 2>/dev/null || echo "" | P2 |
| Context pressure unification | LOW — sentinel value consistency | LOW — bundle with pre-compact migration | P2 |
| State detection unification | MEDIUM — eliminates pattern divergence | MEDIUM — needs investigation first | P2 |
| write_hook_event_record() deduplication | LOW — internal quality | LOW — rewrites the jq block | P3 |

**Priority key:**
- P1: Core milestone scope — ships together
- P2: High value, low risk — bundle with P1 if same files are being touched
- P3: Quality improvement — deferred unless already in the same file pass

---

## Implementation Mechanics: Concrete Expected Behavior Per Feature Area

### 1. Shared Preamble Sourcing (hook-preamble.sh)

**Pattern in bash hook systems:** A shared preamble is a sourced snippet (not a function library) that runs initialization code when sourced. It has intentional side effects: creating directories, setting variables, defining functions.

**The source idiom in each hook script:**
```bash
# Capture SCRIPT_DIR BEFORE sourcing — BASH_SOURCE[0] reflects the preamble path after source
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/hook-preamble.sh"
```

The `BASH_SOURCE[0]` reference must be captured in the hook script before the source call, because after source, `BASH_SOURCE[0]` reflects the preamble file path, not the hook's path.

**What hook-preamble.sh must set (verified against all 7 hook scripts):**
- `SKILL_LOG_DIR` — resolved relative to SCRIPT_DIR (which the hook set before sourcing)
- `mkdir -p "$SKILL_LOG_DIR"` — intentional side effect on source (must happen before logging)
- `GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"` — shared log with env override
- `HOOK_SCRIPT_NAME` — set via `$(basename "${BASH_SOURCE[1]}")` (BASH_SOURCE[1] is the sourcing script, not the preamble)
- `debug_log()` — function definition writing to GSD_HOOK_LOG via printf
- `debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"` — first log line, fires immediately on source
- `LIB_PATH="${SCRIPT_DIR}/../lib/hook-utils.sh"` — path to function library
- Source lib/hook-utils.sh with `[ -f "$LIB_PATH" ]` guard and fatal exit on missing

**The BASH_SOURCE[1] trick for HOOK_SCRIPT_NAME:**
When hook-preamble.sh is sourced by a hook script, `BASH_SOURCE[0]` is the preamble file and `BASH_SOURCE[1]` is the sourcing hook script. Using `$(basename "${BASH_SOURCE[1]}")` in the preamble correctly sets HOOK_SCRIPT_NAME to the hook's name ("stop-hook.sh"), not "hook-preamble.sh". This is the correct pattern — any preamble that sets script identity must reference `BASH_SOURCE[1]`.

**Current inconsistency the preamble normalizes:** 3 hooks (stop, pre-tool-use, post-tool-use) emit `debug_log "sourced lib/hook-utils.sh"` inside the lib-source guard. The other 4 do not. The preamble standardizes this — either all hooks emit it (via the preamble) or none do. Recommended: include it in the preamble.

### 2. Shared Settings Extraction (extract_hook_settings())

**Pattern in bash function libraries:** A function that accepts parameters and echoes a structured result (JSON object) to stdout. The caller captures and parses the output.

**What must be extracted (verified against 4 duplicate blocks):**
```bash
# Current duplicated pattern in stop-hook.sh, notification-idle, notification-permission, pre-compact:
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

**Two valid output approaches for the extracted function:**

Option 1 — Echo JSON object (consistent with all other lib functions):
```bash
extract_hook_settings() {
  local registry_path="$1"
  local agent_data="$2"
  local global_settings
  global_settings=$(jq -r '.hook_settings // {}' "$registry_path" 2>/dev/null || printf '{}')
  jq -cn \
    --argjson global "$global_settings" \
    --argjson agent "$agent_data" \
    '{
      pane_capture_lines: ($agent.hook_settings.pane_capture_lines // $global.pane_capture_lines // 100),
      context_pressure_threshold: ($agent.hook_settings.context_pressure_threshold // $global.context_pressure_threshold // 50),
      hook_mode: ($agent.hook_settings.hook_mode // $global.hook_mode // "async")
    }' 2>/dev/null || printf '{"pane_capture_lines":100,"context_pressure_threshold":50,"hook_mode":"async"}'
}
# Caller:
SETTINGS=$(extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA")
PANE_CAPTURE_LINES=$(printf '%s' "$SETTINGS" | jq -r '.pane_capture_lines')
CONTEXT_PRESSURE_THRESHOLD=$(printf '%s' "$SETTINGS" | jq -r '.context_pressure_threshold')
HOOK_MODE=$(printf '%s' "$SETTINGS" | jq -r '.hook_mode')
```

Option 2 — Set variables directly (fewer jq invocations):
```bash
extract_hook_settings() {
  local registry_path="$1"
  local agent_data="$2"
  # Uses printf -v or global variables — less clean, harder to test
}
```

**Recommendation:** Option 1. Consistent with the echo-to-stdout pattern used by all 5 existing lib functions. The extra 3 jq calls at 2ms each add 6ms total — acceptable for a one-time hook setup step. Easier to unit test.

**The guard inconsistency the function fixes:** pre-compact-hook.sh lines 81-93 lack `2>/dev/null || echo "default"` on all three jq calls. The function adds them consistently. Under `set -euo pipefail` with malformed AGENT_DATA, the unguarded pre-compact jq calls currently crash the hook.

### 3. [CONTENT] Migration (notification-idle, notification-permission, pre-compact)

**What [PANE CONTENT] currently sends (notification hooks):**
```bash
WAKE_MESSAGE="...
[PANE CONTENT]
${PANE_CONTENT}
..."
# PANE_CONTENT = raw tmux capture-pane output: prompts, colors, UI chrome, progress bars
```

**What [CONTENT] sends (stop-hook.sh reference implementation):**
```bash
# Primary source: extract last assistant response from transcript JSONL
TRANSCRIPT_PATH=$(printf '%s' "$STDIN_JSON" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
EXTRACTED_RESPONSE=$(extract_last_assistant_response "$TRANSCRIPT_PATH")
# Fallback: pane diff (delta from last invocation only)
if [ -n "$EXTRACTED_RESPONSE" ]; then
  CONTENT_SECTION="$EXTRACTED_RESPONSE"
  CONTENT_SOURCE="transcript"
else
  PANE_FOR_DIFF=$(printf '%s\n' "$PANE_CONTENT" | tail -40)
  CONTENT_SECTION=$(extract_pane_diff "$SESSION_NAME" "$PANE_FOR_DIFF")
  CONTENT_SOURCE="pane_diff"
fi
WAKE_MESSAGE="...
[CONTENT]
${CONTENT_SECTION}
..."
```

**Expected behavior after migration:**
- notification-idle and notification-permission: identical to stop-hook.sh content extraction chain
- `CONTENT_SOURCE` field in JSONL record reflects "transcript" or "pane_diff" correctly
- For notification hooks, `transcript_path` comes from STDIN_JSON — must verify that Notification hook stdin includes `transcript_path`. If not, fallback to pane_diff is automatic and correct (extract_last_assistant_response returns empty for missing file).
- The `[PANE CONTENT]` section header is removed. `[CONTENT]` replaces it.
- pre-compact: same chain but `transcript_path` may not be in PreCompact hook stdin (different hook type). Default behavior: pane_diff fallback.

**Scope boundary:** The section header rename (`[PANE CONTENT]` → `[CONTENT]`) and the content source upgrade (raw pane → transcript/pane_diff) are a single atomic change per hook. Do not rename without upgrading content source — a [CONTENT] section containing raw pane dump is worse than a [PANE CONTENT] section containing the same.

### 4. diagnose-hooks.sh Step 7 Prefix-Match Fix

**Current broken behavior (line 263-265):**
```bash
LOOKUP_RESULT=$(jq -c --arg session "$TMUX_SESSION_NAME" \
  '.agents[] | select(.tmux_session_name == $session) | {agent_id, openclaw_session_id}' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")
```
Uses `select(.tmux_session_name == $session)` — exact match on the field `tmux_session_name`.

**Actual hook behavior (lookup_agent_in_registry in lib/hook-utils.sh line 34-37):**
```bash
jq -r \
  --arg session "$session_name" \
  '.agents[] | . as $agent |
   select($session | startswith($agent.agent_id + "-")) |
   {agent_id, openclaw_session_id, hook_settings}' \
  "$registry_path" 2>/dev/null || printf ''
```
Uses `startswith($agent.agent_id + "-")` — prefix match on the session name against agent_id.

**Expected behavior after fix:** Step 7 sources lib/hook-utils.sh (safe — lib has no side effects on source) and calls `lookup_agent_in_registry "$REGISTRY_PATH" "$TMUX_SESSION_NAME"`. Pass/fail reflects whether the actual hook would find the agent for this session.

**Alternative (inline the same logic):**
```bash
LOOKUP_RESULT=$(jq -c --arg session "$TMUX_SESSION_NAME" \
  '.agents[] | . as $agent |
   select($session | startswith($agent.agent_id + "-")) |
   {agent_id, openclaw_session_id}' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")
```
Inline is simpler (no source needed) but duplicates the lookup logic. If lookup_agent_in_registry ever changes, Step 7 will diverge again. Recommended: source the lib and call the function directly.

### 5. echo → printf '%s' Cleanup

**Why echo is risky for JSON piping:**
In bash with `set -euo pipefail`, `echo "$VAR"` has two problems when piping JSON:
1. `echo` in some shells (notably older bash and sh-compatible modes) interprets `\n`, `\t` etc. as escape sequences, potentially corrupting JSON string values containing backslash sequences.
2. `echo` adds a trailing newline — harmless for jq (jq ignores trailing whitespace) but semantically incorrect for strings expected to be exact.

`printf '%s' "$VAR"` has neither problem: no escape interpretation, no trailing newline unless explicitly specified.

**Affected patterns (verified by code search across all 7 hooks):**
- `echo "$AGENT_DATA" | jq ...` — in stop, notification-idle, notification-permission, pre-compact, session-end
- `echo "$STDIN_JSON" | jq ...` — in stop (line 42: STOP_HOOK_ACTIVE extraction), notification-idle (line 36), notification-permission (line 37), pre-compact (line 35), session-end (line 35)
- `echo "$RESPONSE" | jq ...` — in stop, notification-idle, notification-permission bidirectional branches
- `echo "$PANE_CONTENT" | grep ...` — this is grep, not jq, and echo is safe here (PANE_CONTENT is plain text, not JSON)

**Not affected (already correct):** pre-tool-use-hook.sh and post-tool-use-hook.sh use `printf '%s'` throughout.

**Scope of fix:** Replace only the `echo "$VAR" | jq` patterns. Do not change `echo "$PANE_CONTENT" | grep` (grep doesn't care about escape sequences) or `echo "$STDIN_JSON"` inside debug_log (debug_log is printf-based, not piped). Targeted, surgical replacement only.

---

## Edge Cases

| Scenario | Severity | Behavior |
|----------|----------|----------|
| hook-preamble.sh sets HOOK_SCRIPT_NAME using BASH_SOURCE[1] but is called from a non-hook context | LOW | Acceptable — BASH_SOURCE[1] will be whatever sourced the preamble. Add a comment in preamble that this variable is hook-script-identity. |
| [CONTENT] migration sends transcript content for permission_prompt events but transcript may not yet exist (early in session) | LOW | extract_last_assistant_response() returns empty on missing transcript — fallback to pane diff handles this correctly. Same behavior as stop-hook.sh today. |
| Notification hook stdin does not include transcript_path field | LOW | extract_last_assistant_response() returns empty for missing/empty path — pane_diff fallback activates automatically. CONTENT_SOURCE logged as "pane_diff". No error. |
| extract_hook_settings() encounters AGENT_DATA with no hook_settings field | NONE | The three-tier fallback (per-agent // global // hardcoded) handles this — missing field returns global or hardcoded defaults. This is the existing behavior; just extracting it to a function doesn't change the logic. |
| diagnose-hooks.sh sources lib/hook-utils.sh to call lookup_agent_in_registry() | LOW | diagnose-hooks.sh currently does not source the lib. Adding a source call at the start of diagnose is safe — lib has no side effects on source (confirmed by code comment: "Contains ONLY function definitions - no side effects on source"). |
| State detection for pre-compact TUI is intentionally different | MEDIUM | The `grep -q "Continue this conversation"` pattern (pre-compact line 112) may be unique to the PreCompact TUI rendering. Must not blindly replace with stop-hook patterns without verifying the TUI text. Default: document the difference, do not force-unify. |
| echo in debug_log argument expansion | NONE | `debug_log "stdin: ${#STDIN_JSON} bytes, hook_event_name=$(echo "$STDIN_JSON" | jq ...)"` — the echo is inside a command substitution inside a string argument. The string is passed to debug_log which uses printf. This echo pattern is inside a subshell with no pipefail propagation risk. Not in scope for echo→printf cleanup. |

---

## Sources

**HIGH confidence (existing codebase — ground truth, all directly read):**
- `scripts/stop-hook.sh` — current state, copy-paste patterns, [CONTENT] format reference
- `scripts/notification-idle-hook.sh` — [PANE CONTENT] format, hook_settings copy #2
- `scripts/notification-permission-hook.sh` — [PANE CONTENT] format, hook_settings copy #3
- `scripts/pre-compact-hook.sh` — divergent state detection, hook_settings copy #4 (missing 2>/dev/null)
- `scripts/session-end-hook.sh` — missing jq error guards on lines 71-72
- `scripts/pre-tool-use-hook.sh` — already uses printf '%s', sourced lib before guards
- `scripts/post-tool-use-hook.sh` — raw stdin logging for empirical validation
- `scripts/diagnose-hooks.sh` — Step 7 exact-match vs prefix-match gap (line 263-265), Step 2 missing scripts (lines 99-105)
- `lib/hook-utils.sh` — all 6 functions, write_hook_event_record() internal duplication (lines 203-258)
- `.planning/PROJECT.md` — milestone goal, active requirements, constraints (bash + jq only)
- `docs/v3-retrospective.md` — systematic code review identifying all 8 improvement areas with exact line numbers

**HIGH confidence (bash preamble patterns — standard practice):**
- BASH_SOURCE[1] for caller identity from sourced scripts — standard bash idiom, documented in bash manual section 6.11 "Special Parameters"
- Source-safe library design (no side effects except intentional init) — confirmed by lib/hook-utils.sh header comment: "Contains ONLY function definitions - no side effects on source"
- `printf '%s' "$VAR" | jq` vs `echo "$VAR" | jq` — correctness difference in echo escape handling documented in bash manual section 4.1 "Bourne Shell Builtins"

---

*Feature research for: gsd-code-skill v3.1 Hook Refactoring & Migration Completion*
*Researched: 2026-02-18*
