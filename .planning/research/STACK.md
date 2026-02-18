# Stack Research: Hook Preamble Extraction & Settings Refactor

**Domain:** Bash hook script DRY refactoring — shared preamble bootstrap, unified settings extraction, echo-to-printf migration
**Researched:** 2026-02-18
**Confidence:** HIGH — all patterns verified live on this host (bash 5.2.21, Ubuntu 24)

## Executive Summary

This milestone requires **zero new dependencies**. The entire refactoring uses bash 5.2 primitives
already in every hook script. The question is not "what to install" but "what bash patterns are
safe in source chains under set -euo pipefail."

**Four findings drive all implementation decisions:**

1. `BASH_SOURCE[0]` inside a sourced file always points to that file, not the caller. This makes
   `lib/hook-preamble.sh` safe to resolve `SKILL_ROOT` from its own location via
   `cd "$(dirname "${BASH_SOURCE[0]}")" && pwd` then `..`.

2. `BASH_SOURCE[1]` inside a sourced file always points to the file that sourced it. This is how
   `hook-preamble.sh` extracts `HOOK_SCRIPT_NAME` without the caller passing it as a parameter.

3. Variables and functions set in a sourced file are immediately visible to the calling script in
   the same shell context. No export needed. No subshell. Direct assignment.

4. `echo "$var" | jq` is fragile when var contains backslashes. The correct idiom is
   `printf '%s' "$var" | jq`. Two newer hooks already use this pattern; five older hooks need
   migration. The risk is real: tmux pane content and JSONL payloads can contain backslash sequences
   that `echo` silently strips before jq receives them.

These four facts together mean: a preamble can bootstrap everything — set `SKILL_LOG_DIR`,
`GSD_HOOK_LOG`, `HOOK_ENTRY_MS`, `SCRIPT_DIR`, `REGISTRY_PATH`, define `debug_log()`, and source
`hook-utils.sh` — and every one of those names is available in the hook script after the
`source lib/hook-preamble.sh` line.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| bash | 5.2.21 (installed) | Source chain, BASH_SOURCE array, local -n nameref | Already the hook runtime. BASH_SOURCE is bash-specific (not POSIX sh) but all hooks already use it. bash 5.2 is confirmed on this host. |
| jq | 1.7 (installed) | extract_hook_settings() — three-tier fallback in one jq invocation | The only correct way to compute `agent.hook_settings // global.hook_settings // default` in bash without eval injection risk. Already in every hook. |
| flock | util-linux (installed) | Concurrent-safe JSONL appends (existing) | Already used in extract_pane_diff(). No changes needed; preamble does not add new flock usage. |

### Supporting Patterns (No New Binaries)

| Pattern | Purpose | Verified |
|---------|---------|---------|
| `BASH_SOURCE[0]` in sourced file | Resolve preamble's own directory | YES — points to preamble, not caller |
| `BASH_SOURCE[1]` in sourced file | Extract caller's script name | YES — points to hook script that sourced preamble |
| `BASH_SOURCE[0]` after source returns | Unchanged in caller | YES — reverts to caller path after source completes |
| `local -n` nameref (bash 4.3+) | Function sets caller variables directly | YES — confirmed working on bash 5.2 |
| jq compact JSON output as function return | Return structured data from bash function | YES — caller reads individual fields with `jq -r .field` |
| `set -euo pipefail` inheritance through source | Shell options propagate into sourced file | YES — sourced file inherits the caller's set options |
| `exit` in sourced file | Terminates the entire calling process | YES — use `return` if you only want to stop the sourced file |
| `return` in sourced file | Stops only the sourced file, caller continues | YES — correct for "stop preamble but let hook handle it" |
| `printf '%s' "$var" \| jq` | Safe variable piping to jq | YES — no backslash stripping, no special character hazard |

### Validation Tooling

| Tool | Version | Purpose | Installation |
|------|---------|---------|-------------|
| shellcheck | 0.9.0-1 (in apt) | Static analysis — catches SC2006 `echo "$var" | jq` warnings, unquoted variables, source directive hints | `sudo apt install shellcheck` |

ShellCheck is not strictly required for this refactoring (the patterns are already understood), but
it provides two concrete benefits: it flags every remaining `echo "$var" | jq` call with SC2001/
SC2086 class warnings, and it validates that `# shellcheck source=` directives are correct in the
new preamble source pattern. Run it before and after the refactor to confirm zero regressions.

## Path Resolution from lib/hook-preamble.sh

The preamble lives in `lib/`. From there, all skill paths resolve correctly:

```bash
# In lib/hook-preamble.sh
PREAMBLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Result: /path/to/gsd-code-skill/lib

SKILL_ROOT="$(cd "${PREAMBLE_LIB_DIR}/.." && pwd)"
# Result: /path/to/gsd-code-skill

SKILL_LOG_DIR="${SKILL_ROOT}/logs"
# Result: /path/to/gsd-code-skill/logs

REGISTRY_PATH="${SKILL_ROOT}/config/recovery-registry.json"
# Result: /path/to/gsd-code-skill/config/recovery-registry.json

# Hook-utils.sh is in the same directory as the preamble
UTILS_PATH="${PREAMBLE_LIB_DIR}/hook-utils.sh"
# Result: /path/to/gsd-code-skill/lib/hook-utils.sh
```

This matches what hook scripts currently compute via `SCRIPT_DIR/../config/recovery-registry.json`.
Both resolve to the same absolute path. The preamble path is cleaner: one canonical root
(`SKILL_ROOT`) from which all paths derive.

## BASH_SOURCE Chain Behavior (3-Level Deep)

Verified with live test when hook sources preamble which sources hook-utils.sh:

```
hook script (scripts/stop-hook.sh)     BASH_SOURCE[0] = .../scripts/stop-hook.sh
  sources preamble (lib/hook-preamble.sh)
    BASH_SOURCE[0] = .../lib/hook-preamble.sh
    BASH_SOURCE[1] = .../scripts/stop-hook.sh   <- caller's path
    sources hook-utils (lib/hook-utils.sh)
      BASH_SOURCE[0] = .../lib/hook-utils.sh
      BASH_SOURCE[1] = .../lib/hook-preamble.sh <- preamble's path
      BASH_SOURCE[2] = .../scripts/stop-hook.sh <- original hook
```

**Implication for HOOK_SCRIPT_NAME extraction:**
The preamble must use `BASH_SOURCE[1]` (the direct caller) to get the hook script name. Using
`BASH_SOURCE[2]` would be wrong (that's only populated inside hook-utils, not inside preamble).
`basename "${BASH_SOURCE[1]}"` from inside the preamble gives the correct hook script filename.

## extract_hook_settings() — Recommended Design

Use jq to compute all three settings in a single invocation returning compact JSON. The caller
reads individual fields with separate `jq -r` calls on the cached result. This avoids three
separate jq subshell calls with the same global settings computation each time.

**Function in hook-utils.sh:**

```bash
# ==========================================================================
# extract_hook_settings
# ==========================================================================
# Extracts the three hook settings from agent_data with three-tier fallback:
#   1. Agent-level hook_settings (most specific)
#   2. Registry-level hook_settings (global default)
#   3. Hardcoded defaults (pane_capture_lines=100, threshold=50, mode=async)
#
# Arguments:
#   $1 - registry_path: path to recovery-registry.json
#   $2 - agent_data:    JSON string from lookup_agent_in_registry()
# Returns:
#   Compact JSON object on stdout:
#   {"pane_capture_lines":100,"context_pressure_threshold":50,"hook_mode":"async"}
#   On any failure, returns the hardcoded defaults JSON string.
# ==========================================================================
extract_hook_settings() {
  local registry_path="$1"
  local agent_data="$2"

  local global_settings
  global_settings=$(jq -r '.hook_settings // {}' "$registry_path" 2>/dev/null || echo "{}")

  printf '%s' "$agent_data" | jq -c \
    --argjson global "$global_settings" \
    '{
      pane_capture_lines:          (.hook_settings.pane_capture_lines          // $global.pane_capture_lines          // 100),
      context_pressure_threshold:  (.hook_settings.context_pressure_threshold  // $global.context_pressure_threshold  // 50),
      hook_mode:                   (.hook_settings.hook_mode                   // $global.hook_mode                   // "async")
    }' 2>/dev/null \
    || printf '{"pane_capture_lines":100,"context_pressure_threshold":50,"hook_mode":"async"}'
}
```

**Caller pattern in each hook:**

```bash
HOOK_SETTINGS=$(extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA")
PANE_CAPTURE_LINES=$(printf '%s' "$HOOK_SETTINGS" | jq -r '.pane_capture_lines')
CONTEXT_PRESSURE_THRESHOLD=$(printf '%s' "$HOOK_SETTINGS" | jq -r '.context_pressure_threshold')
HOOK_MODE=$(printf '%s' "$HOOK_SETTINGS" | jq -r '.hook_mode')
```

**Why not eval with key=value output:** eval on jq `-r` output is injection-vulnerable. If a
registry entry contains `hook_mode: "async; rm -rf /"`, the string passes through `jq -r`
unchanged and `eval "HOOK_MODE=async; rm -rf /"` executes the command. The JSON-return pattern
is immune: caller destructures via `jq -r '.hook_mode'`, which always returns a scalar string.

**Why not nameref (local -n):** Nameref requires passing variable names as arguments
(`extract_hook_settings_into "$registry" "$agent" PANE_LINES THRESHOLD MODE`). This works
(tested on bash 5.2) but is more obscure than the JSON-return pattern and doesn't eliminate
the three separate `jq` reads. Use JSON return for clarity and equivalence.

## hook-preamble.sh — Scope and Boundaries

### What the preamble MUST contain (the 27-line duplicate block)

```bash
# lib/hook-preamble.sh — sourced by all hook scripts, no set -euo pipefail here
# (inherits caller's shell options via source)

PREAMBLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${PREAMBLE_LIB_DIR}/.." && pwd)"
SKILL_LOG_DIR="${SKILL_ROOT}/logs"
mkdir -p "$SKILL_LOG_DIR"

GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]:-hook-unknown.sh}")"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" \
    >> "$GSD_HOOK_LOG" 2>/dev/null || true
}

SCRIPT_DIR="${PREAMBLE_LIB_DIR}"  # hooks use SCRIPT_DIR for registry path
REGISTRY_PATH="${SKILL_ROOT}/config/recovery-registry.json"

# Source hook-utils.sh from same lib/ directory
if [ -f "${PREAMBLE_LIB_DIR}/hook-utils.sh" ]; then
  source "${PREAMBLE_LIB_DIR}/hook-utils.sh"
else
  return 1  # return (not exit) — let caller decide whether to abort
fi
```

### What the preamble MUST NOT contain

- `STDIN_JSON=$(cat)` — consuming stdin in the preamble robs the hook of its input. Verified:
  once cat reads stdin in the sourced file, the hook's subsequent `cat` returns empty.
- `HOOK_ENTRY_MS=$(date +%s%3N)` — timing must start in the hook body after `source`, because
  source execution itself takes ~5ms. Measuring from preamble start skews hook timing.
- Guards using `exit 0` — preamble `exit` terminates the calling hook process immediately.
  Use `return 1` to signal failure and let the hook decide to exit.
- Guards using `exit N` with N > 0 — with `set -euo pipefail` inherited by the source call,
  a non-zero `return` from a sourced file propagates as a non-zero exit of the `source` command
  and triggers set -e in the caller.

### Hook-side source idiom

Each hook reduces its 27-line preamble to:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/hook-preamble.sh
source "${SCRIPT_DIR}/../lib/hook-preamble.sh" || { echo "FATAL: preamble failed" >&2; exit 0; }

# Now available: SKILL_LOG_DIR, GSD_HOOK_LOG, HOOK_SCRIPT_NAME, REGISTRY_PATH,
#                debug_log(), and all hook-utils.sh functions

STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)
debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"
```

Note: `SCRIPT_DIR` is computed in the hook itself (from `BASH_SOURCE[0]` which is the hook's own
path) before source is called. This is correct. The preamble then re-exports `SCRIPT_DIR` pointing
at its own lib directory. If existing hook code uses `SCRIPT_DIR` for preamble-relative paths,
that still works — both hook's scripts/ and preamble's lib/ are siblings under SKILL_ROOT.

**Alternative:** Compute SCRIPT_DIR only in the preamble and don't touch it in the hook. The hook
currently uses `SCRIPT_DIR` only to construct `REGISTRY_PATH` (already set by preamble) and
`LIB_PATH` (replaced by the preamble itself). So `SCRIPT_DIR` in the hook body becomes unused
after refactoring. Leave it or remove it — either is safe.

## Shared Library Design Principles

These principles apply to both the new `hook-preamble.sh` and the existing `hook-utils.sh`:

### Variable Scoping

- **Library-internal variables**: Use `local` inside every function. No exceptions.
- **Variables set for caller consumption**: Bare assignment (no `local`) at the top level of the
  sourced file. These are intentionally "exported" to the caller's scope by source semantics.
- **Constants that should not change**: Use `readonly`. Example: `readonly SKILL_ROOT`. However,
  avoid `readonly` on variables the caller might legitimately override (e.g., `GSD_HOOK_LOG`).
- **Do not use `export`**: Variables set in a sourced file are visible to the caller without
  export. `export` would additionally expose them to child processes, which is not desired for
  internal hook state.

### Naming Conventions (verified against Google Shell Style Guide)

- **User-visible constants** (set once, never changed): `UPPER_SNAKE_CASE` — e.g., `SKILL_ROOT`,
  `REGISTRY_PATH`, `HOOK_SCRIPT_NAME`
- **Mutable state variables**: `UPPER_SNAKE_CASE` — consistent with existing hook style
- **Function names**: `lower_snake_case` — matches existing `debug_log`, `lookup_agent_in_registry`
- **Function-local variables**: `lower_snake_case` with `local` — matches existing pattern
- **Library internal sentinel variables**: `_LIBNAME_LOADED` pattern for source-guard flags

### Source Guard (Idempotent Sourcing)

If `hook-preamble.sh` could be sourced more than once (via a hook that calls another function that
sources it), use a sentinel variable to prevent double execution:

```bash
# At top of hook-preamble.sh
[[ -n "${_GSD_HOOK_PREAMBLE_LOADED:-}" ]] && return 0
readonly _GSD_HOOK_PREAMBLE_LOADED=1
```

In practice, hooks only source preamble once at the top. But the guard costs nothing and prevents
subtle bugs if the loading structure ever changes.

### Enforce Sourced-Only Use

Add a guard that prevents accidental direct execution of the preamble:

```bash
# Ensure this file is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf 'ERROR: %s must be sourced, not executed directly.\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi
```

This is defensive but valuable: if a developer accidentally runs `bash lib/hook-preamble.sh` for
debugging, they get an explicit error instead of a confusing empty-output failure.

### Error Handling in Library Functions

- All functions that call external commands must either use `|| fallback` or be explicitly designed
  to propagate failures (documented in the function header).
- Functions MUST NOT use `exit`. Use `return 1` for failure. The caller decides whether to exit.
- Silent failure with return 0 is acceptable ONLY for logging/instrumentation functions where a
  failure would be worse than silence (e.g., `write_hook_event_record` already does this).
- Functions MUST document their return values in the header comment.

## echo-to-printf Migration

### Why This Migration Is Necessary

`echo "$var"` is unsafe when `$var` may contain backslashes. On bash 5.2, `echo` with no flags
does NOT interpret `\n`, `\t` etc. — but it does silently strip a trailing `\` . More critically:

- `echo "$STDIN_JSON" | jq` — STDIN_JSON is Claude Code's hook payload. It contains JSON,
  which contains backslashes in string values (escaped quotes, file paths like `C:\Users\...`,
  transcript content). Backslash loss corrupts the JSON before jq parses it.
- `echo "$PANE_CONTENT" | grep` — tmux pane content contains ANSI escape codes (`\e[`, `\x1b`).
  Echo-based piping is inconsistent with these sequences under different locales.
- `echo "$AGENT_DATA" | jq` — AGENT_DATA comes from jq output of the registry. If any string
  field contains a backslash (system prompts, file paths), the value round-trips incorrectly.

### Migration Scope (from code inspection, 2026-02-18)

**Five scripts need migration:**
- `stop-hook.sh` — 9 occurrences of `echo "$VAR" | jq` (partially migrated: 1 printf already present)
- `notification-idle-hook.sh` — 8 `echo | jq` + 5 `echo | grep` occurrences
- `notification-permission-hook.sh` — 8 `echo | jq` + 5 `echo | grep` occurrences
- `pre-compact-hook.sh` — 6 `echo | jq` + 5 `echo | grep/tail` occurrences
- `session-end-hook.sh` — 3 `echo | jq` occurrences

**Two scripts already correct:**
- `pre-tool-use-hook.sh` — uses `printf '%s'` throughout
- `post-tool-use-hook.sh` — uses `printf '%s'` throughout

### Safe Migration Pattern

Replace all occurrences of:
```bash
echo "$VARIABLE" | jq -r '.field'
```

With:
```bash
printf '%s' "$VARIABLE" | jq -r '.field'
```

The `%s` format specifier in `printf` treats its argument as a literal string — no backslash
interpretation, no special character handling. The variable contents pass through byte-for-byte.

This also applies to `grep` and other pipe destinations:
```bash
# Before (fragile)
echo "$PANE_CONTENT" | grep -Eiq 'pattern'

# After (safe)
printf '%s\n' "$PANE_CONTENT" | grep -Eiq 'pattern'
```

Note: `printf '%s'` does NOT add a trailing newline. For piping to line-oriented tools (grep, tail,
wc), use `printf '%s\n'` to preserve the newline that `echo` added automatically. For piping to jq
(which reads arbitrary streams), `printf '%s'` without `\n` is sufficient and correct.

### Special Cases to Preserve

These `echo` usages are CORRECT and should NOT be migrated:

```bash
# Fallback default values — literal strings, no variable content
... 2>/dev/null || echo "false"
... 2>/dev/null || echo ""
... 2>/dev/null || echo "{}"
... 2>/dev/null || echo "0"
... 2>/dev/null || echo "async"
```

```bash
# Decision injection to Claude Code stdout — literal JSON string
echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
```

The decision-injection `echo` is a special case: the `$REASON` value comes from jq-parsed registry
content and should not contain literal backslashes. If hardening is desired, use:
```bash
printf '{"decision": "block", "reason": "%s"}\n' "$REASON"
```
But note that if `$REASON` itself contains a `%`, `printf` will misinterpret it. The safest
approach for the decision JSON is to build it with `jq -n`:
```bash
jq -cn --arg reason "$REASON" '{"decision":"block","reason":$reason}'
```
This is already how `write_hook_event_record` and `deliver_async_with_logging` handle all JSON
construction. Apply the same pattern here for consistency.

### Migration Order (Lowest to Highest Risk)

1. `session-end-hook.sh` — 3 occurrences, simplest hook, no pane state or context pressure
2. `pre-compact-hook.sh` — 6 + 5 occurrences, has hook_settings extraction (candidate for extract_hook_settings())
3. `notification-idle-hook.sh` — 8 + 5 occurrences, complex state detection
4. `notification-permission-hook.sh` — 8 + 5 occurrences, identical structure to notification-idle
5. `stop-hook.sh` — 9 occurrences, most complex hook (has both modes), already partially migrated

## set -euo pipefail Interaction Rules (Verified)

| Scenario | Behavior | Action |
|----------|---------|--------|
| Command in preamble succeeds | Normal, continues | OK |
| Command in preamble fails with `\|\| fallback` | Fallback executes, continues | OK — all preamble assignments should use `\|\| echo "default"` |
| Command in preamble fails without fallback | `set -e` triggers, hook exits non-zero | Write `|| echo "default"` guards on all preamble assignments |
| `source hook-preamble.sh` fails (file missing) | `set -e` triggers if `source` exits non-zero | Caller must guard: `source ... \|\| { ...; exit 0; }` |
| `return 1` at end of preamble | `source` command exits with 1, `set -e` triggers | Use `return 0` or let preamble fall through normally |
| `exit 0` inside preamble | Entire hook process terminates | Never use exit in preamble |
| `exit N` (N>0) inside preamble | Entire hook process terminates with N | Never use exit in preamble |

**Key rule:** The preamble contains only assignments and one function definition. Every assignment
that calls an external command must have `2>/dev/null || echo "fallback"`. No bare commands. No
`exit`. Communicate failure via `return 1` and let the caller `source ... || { abort }`.

## [CONTENT] Migration Scope

Current state (from code inspection):
- `stop-hook.sh`: uses `[CONTENT]` with transcript-based content (correct, migrated)
- `notification-idle-hook.sh`: uses `[PANE CONTENT]` (not migrated)
- `notification-permission-hook.sh`: uses `[PANE CONTENT]` (not migrated)
- `pre-compact-hook.sh`: uses `[PANE CONTENT]` (not migrated)

The `[CONTENT]` section (stop-hook pattern) uses the transcript-extraction path as primary source
and pane-diff as fallback. The `[PANE CONTENT]` sections use raw pane capture only.

Migration means: replace `[PANE CONTENT]\n${PANE_CONTENT}` with the transcript+pane-diff pattern
from stop-hook.sh. This adds `extract_last_assistant_response()` and `extract_pane_diff()` calls
(both already in hook-utils.sh) and changes the section label from `[PANE CONTENT]` to `[CONTENT]`.

No new functions needed for [CONTENT] migration. All utilities already exist in hook-utils.sh.

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| jq compact JSON return from extract_hook_settings() | eval key=value output | eval on jq -r output is injection-vulnerable. Registry contents are operator-controlled but defense-in-depth matters. |
| jq compact JSON return from extract_hook_settings() | bash nameref (local -n) | Works (tested), but requires caller to pre-declare variable names as arguments. More obscure than reading JSON fields. No benefit over JSON return. |
| `return 1` for preamble failure | `exit 0` for preamble failure | exit in a sourced file terminates the calling hook process entirely. Works, but preamble should not own the exit decision — the hook should. |
| `BASH_SOURCE[1]` for HOOK_SCRIPT_NAME | Pass hook name as parameter to preamble | Parameter passing means every hook must know to pass `"$0"` or `"${BASH_SOURCE[0]}"`. BASH_SOURCE[1] is automatic and verified correct. |
| Single source call per hook | Multiple source calls (one per lib file) | Each source call adds overhead and another potential failure point. Preamble sources hook-utils.sh; hooks source only preamble. One indirection layer. |
| `printf '%s' "$var" \| jq` | `echo "$var" \| jq` | echo is unsafe with backslashes in variable content. printf '%s' is byte-for-byte safe. Two newer hooks already use printf consistently. |
| `printf '%s\n' "$var" \| grep` | `echo "$var" \| grep` | Same backslash safety reason. Note the `\n` difference: grep is line-oriented and needs the newline printf doesn't add automatically. |
| `jq -cn --arg reason "$REASON"` for decision JSON | `echo "{...\"$REASON\"...}"` | If REASON contains quotes or backslashes the echo version produces invalid JSON. jq -cn --arg handles all special characters safely. |

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `cat` in preamble | Consumes hook's stdin — verified destructive | Always read stdin in the hook body after source returns |
| `HOOK_ENTRY_MS` in preamble | Skews timing measurement by including preamble startup cost | Set it in hook body as first line after source |
| `exit` in preamble | Terminates calling hook process — correct only for fatal library failures | `return 1` from preamble, `exit 0` in the hook's error handler |
| Preamble as a subshell invocation | `$(source preamble.sh)` loses all variable assignments (subshell scope) | `source` directly in the hook's shell context |
| `export` on variables set in preamble | Not needed for same-process visibility; only needed for child processes | Direct assignment is sufficient for hook-utils.sh functions to see SKILL_LOG_DIR |
| `set -euo pipefail` inside hook-preamble.sh | Redundant — inherited from caller. Adding it again is harmless but misleading | Leave the comment: "no set -euo pipefail here — inherits from caller" |
| `echo "$var" \| jq` anywhere | Backslash stripping corrupts JSON. ShellCheck SC2006 class warning | `printf '%s' "$var" \| jq` |
| `printf "$var"` (no format specifier) | If var contains `%s` or other printf specifiers, output is garbled | Always `printf '%s' "$var"` with explicit format string |

## Version Compatibility

| Component | Version | Relevant Feature | Status |
|-----------|---------|-----------------|--------|
| bash | 5.2.21 (installed) | `BASH_SOURCE` array, `local -n` nameref (4.3+), `source` semantics | All confirmed working |
| jq | 1.7 (installed) | `-c` compact output, `--argjson` for injecting JSON objects as variables, `jq -cn --arg` | Confirmed present |
| shellcheck | 0.9.0-1 (in apt, not installed) | SC2006, SC2086 echo warnings, `# shellcheck source=` directive | `sudo apt install shellcheck` |
| Ubuntu 24 / coreutils 9.4 | installed | `dirname`, `basename`, `pwd`, `mkdir -p` | All POSIX, no version concerns |

## Sources

**HIGH confidence (live verification on this host, 2026-02-18):**

- `BASH_SOURCE[0]` in sourced file points to sourced file, not caller — verified with 3-level chain test
- `BASH_SOURCE[1]` in sourced file points to direct caller — verified
- Variables assigned in sourced file visible in calling script — verified (no export needed)
- Functions defined in sourced file callable from calling script — verified
- `set -euo pipefail` inherited through source — verified (bare failing command in sourced file triggers set -e in caller)
- `exit` in sourced file terminates calling process — verified
- `return` in sourced file stops only the sourced file, caller continues — verified
- `cat` in sourced file consumes stdin, subsequent `cat` in caller gets empty — verified
- eval on jq `-r` output is injection-vulnerable — demonstrated with `async; rm -rf /` test value
- `printf '%s' "$agent_data" | jq -c --argjson global ... '{...}'` — correct jq idiom for three-tier settings extraction with defaults, confirmed working
- `local -n nameref` on bash 5.2 — confirmed working for setting caller variables from function
- echo-to-printf migration scope: 5 scripts (stop, notification-idle, notification-permission, pre-compact, session-end) contain `echo "$VAR" | jq`; 2 scripts (pre-tool-use, post-tool-use) already use `printf '%s'`

**MEDIUM confidence (multiple authoritative sources, 2026-02-18):**

- `printf '%s' "$var"` vs `echo "$var"` safety: multiple sources confirm backslash stripping in echo, printf '%s' is byte-safe — [How to Geek](https://www.howtogeek.com/heres-why-printf-beats-echo-in-your-linux-scripts/), [Linuxize](https://linuxize.com/post/bash-printf-command/)
- Source guard pattern (`[[ -n "${_LOADED:-}" ]] && return 0`) — [idempotent bash scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/)
- `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` for sourced-only enforcement — [Nick Janetakis](https://nickjanetakis.com/blog/detect-if-a-shell-script-is-being-executed-or-sourced), [Baeldung](https://www.baeldung.com/linux/shell-script-force-source)
- Function naming: `lower_snake_case`, constants `UPPER_SNAKE_CASE`, local variables with `local` — [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- ShellCheck 0.9.0 in Ubuntu 24 apt — verified in apt-cache on this host
- `printf '%s\n' "$var" | grep` preferred over `echo "$var" | grep` for line-oriented tools — [Baeldung](https://www.baeldung.com/linux/bash-escape-characters)

**Existing code analysis (HIGH confidence):**
- 27-line preamble block identified as identical across all 7 hook scripts (with minor variations noted)
- 12-line hook_settings extraction block duplicated in 4 hooks (stop, notification-idle, notification-permission, pre-compact)
- [CONTENT] migration scope: 3 hooks use [PANE CONTENT] (notification-idle, notification-permission, pre-compact), 1 uses [CONTENT] (stop-hook)
- hook-utils.sh already contains all functions needed for [CONTENT] migration (extract_last_assistant_response, extract_pane_diff)

---
*Stack research for: gsd-code-skill — hook preamble extraction, settings refactor & echo-to-printf migration*
*Researched: 2026-02-18*
*Confidence: HIGH — zero new dependencies, all patterns live-tested on this host*
