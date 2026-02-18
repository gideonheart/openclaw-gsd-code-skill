# Phase 12: Shared Library Foundation - Research

**Researched:** 2026-02-18
**Domain:** Bash shared library creation — hook-preamble.sh extraction, extract_hook_settings() and detect_session_state() addition to hook-utils.sh
**Confidence:** HIGH — all 7 hook scripts and lib/hook-utils.sh read in full; patterns empirically verified on bash 5.2.21 on production host; prior research (ARCHITECTURE.md, STACK.md, PITFALLS.md, FEATURES.md, SUMMARY.md) verified and synthesized

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| REFAC-01 | lib/hook-preamble.sh extracts the 27-line bootstrap block with BASH_SOURCE[1] caller identity, debug_log(), and hook-utils.sh sourcing | BASH_SOURCE[1] pattern documented and empirically tested. The 27-line block is identical across all 7 hook scripts. Source chain behavior verified. |
| REFAC-02 | hook-preamble.sh includes source guard preventing double-sourcing and direct execution | Standard source guard pattern using sentinel variable and BASH_SOURCE[0] == ${0} check. Both patterns documented with working code examples. |
| REFAC-04 | extract_hook_settings() in lib/hook-utils.sh replaces 4x duplicated 12-line settings extraction with three-tier fallback and error guards | The 12-line block is duplicated in stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, pre-compact-hook.sh. pre-compact copy is missing 2>/dev/null guards that the other three have. Function design with jq compact JSON return is specified. |
| REFAC-05 | detect_session_state() in lib/hook-utils.sh unifies state detection with consistent state names and case-insensitive extended regex patterns | Two divergent state detection implementations exist in the codebase — the pre-compact variant differs in grep flags, patterns, and fallback state name. Decision: use stop/notification pattern (grep -Eiq with consistent state names) as the canonical form; document pre-compact divergence for investigation during Phase 13. |

</phase_requirements>

---

## Summary

Phase 12 creates two files and adds one function — nothing more. The outputs are: `lib/hook-preamble.sh` (new file, approximately 25 lines), `extract_hook_settings()` added to `lib/hook-utils.sh` (approximately 20 lines), and `detect_session_state()` added to `lib/hook-utils.sh` (approximately 20 lines). No hook scripts are modified in this phase. Phase 13 uses these interfaces to refactor all 7 hooks.

The entire technical domain is bash 5.2 sourcing semantics. The non-obvious behavior is `BASH_SOURCE[1]` vs `BASH_SOURCE[0]` inside a sourced preamble file: `BASH_SOURCE[0]` resolves to the preamble's own path, while `BASH_SOURCE[1]` resolves to the calling hook's path. Every identity and path computation in hook-preamble.sh must use `BASH_SOURCE[1]`. This is empirically verified on the production host. It is the single highest-risk implementation point in the phase.

Phase 12's success criteria require the new interfaces to work correctly in isolation before any hook is modified to use them. The verification gate is: source hook-preamble.sh from a test script and confirm that `HOOK_SCRIPT_NAME` shows the test script's name (not "hook-preamble.sh"), that all lib/hook-utils.sh functions are callable, and that `extract_hook_settings()` and `detect_session_state()` produce correct output when called with a test registry and agent data.

**Primary recommendation:** Build Phase 12 as a single task creating the two lib files with inline unit tests. This is pure additive work — no hook script is touched, no production behavior changes. The foundation must be verifiably correct before Phase 13 applies it across all 7 hooks simultaneously.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.2.21 (installed) | BASH_SOURCE array, source semantics, declare -g | Already the hook runtime. BASH_SOURCE is bash-specific; bash 5.2 confirmed on production host. |
| jq | 1.7 (installed) | Three-tier fallback in extract_hook_settings(), grep pattern in detect_session_state() | The only correct way to compute per-agent // global // hardcoded defaults without eval injection risk. Already in every hook. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| shellcheck | 0.9.0-1 (apt, not installed) | Static analysis — catches BASH_SOURCE errors, `echo "$var" \| jq` warnings, source directive validation | Optional but recommended for pre-commit validation of the new lib files |
| flock | util-linux (installed) | Concurrent-safe file operations | Not needed in Phase 12 specifically — used by existing hook-utils.sh functions; preamble adds no new flock usage |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq compact JSON return from extract_hook_settings() | eval key=value output | eval on jq -r output is injection-vulnerable — registry contents could contain `async; rm -rf /`. JSON return + jq -r parse is safe. |
| jq compact JSON return from extract_hook_settings() | bash nameref (local -n) | Works on bash 4.3+ (confirmed on bash 5.2), but requires callers to pre-declare variable names as arguments. More obscure, no benefit over JSON return. |
| BASH_SOURCE[1] for HOOK_SCRIPT_NAME | Pass hook name as parameter to preamble | Parameter passing means every hook must know to pass "${BASH_SOURCE[0]}" explicitly. BASH_SOURCE[1] is automatic and verified correct. |
| return 1 for preamble failure | exit 0 for preamble failure | exit in a sourced file terminates the calling hook process entirely. return 1 lets the hook decide. However: with set -euo pipefail inherited, a non-zero return from source triggers set -e in the caller. Caller must guard: `source preamble || { ...; exit 0; }` |

**Installation:** No new packages. bash and jq already installed.

---

## Architecture Patterns

### Recommended Project Structure (after Phase 12 — lib only changes)

```
gsd-code-skill/
├── lib/
│   ├── hook-utils.sh          EXTENDED — adds extract_hook_settings() and detect_session_state()
│   └── hook-preamble.sh       NEW — extracted 27-line bootstrap block
├── scripts/
│   └── [all 7 hooks]          UNCHANGED in Phase 12 (Phase 13 modifies these)
```

### Pattern 1: Sourced Preamble via BASH_SOURCE[1]

**What:** A shared setup file (`lib/hook-preamble.sh`) is sourced into each hook as its first executable action. The preamble uses `BASH_SOURCE[1]` (not `BASH_SOURCE[0]`) to resolve the caller's script name and directory.

**When to use:** Phase 12 creates this file. Phase 13 applies it to all 7 hooks.

**BASH_SOURCE chain behavior (3-level deep, empirically verified):**

```
hook script (scripts/stop-hook.sh)         BASH_SOURCE[0] = .../scripts/stop-hook.sh
  sources preamble (lib/hook-preamble.sh)
    BASH_SOURCE[0] = .../lib/hook-preamble.sh
    BASH_SOURCE[1] = .../scripts/stop-hook.sh   <- caller's path (USE THIS)
    sources hook-utils (lib/hook-utils.sh)
      BASH_SOURCE[0] = .../lib/hook-utils.sh
      BASH_SOURCE[1] = .../lib/hook-preamble.sh  <- preamble's path
      BASH_SOURCE[2] = .../scripts/stop-hook.sh  <- original hook
```

**Example (lib/hook-preamble.sh — complete implementation):**

```bash
#!/usr/bin/env bash
# lib/hook-preamble.sh — Shared bootstrap for all GSD hook scripts.
# Sourced as the FIRST action of every hook script (after set -euo pipefail).
# Uses BASH_SOURCE[1] throughout — the calling hook's path, not this file's path.
# No set -euo pipefail here — inherits from caller.
# No stdin consumption here — hook body reads stdin after source returns.
# No HOOK_ENTRY_MS here — timing starts in hook body after source returns.

# Source guard: prevent double-sourcing (idempotent)
[[ -n "${_GSD_HOOK_PREAMBLE_LOADED:-}" ]] && return 0

# Direct execution guard: reject bash lib/hook-preamble.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf 'ERROR: %s must be sourced, not executed directly.\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi

readonly _GSD_HOOK_PREAMBLE_LOADED=1

# Resolve skill root from preamble's own location (BASH_SOURCE[0] is preamble)
_GSD_PREAMBLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GSD_SKILL_ROOT="$(cd "${_GSD_PREAMBLE_LIB_DIR}/.." && pwd)"

# Set path variables derived from skill root
SKILL_LOG_DIR="${_GSD_SKILL_ROOT}/logs"
mkdir -p "$SKILL_LOG_DIR" 2>/dev/null || true
REGISTRY_PATH="${_GSD_SKILL_ROOT}/config/recovery-registry.json"

# HOOK_SCRIPT_NAME: use BASH_SOURCE[1] (the calling hook's path, not preamble's)
HOOK_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]:-hook-unknown.sh}")"
# SCRIPT_DIR: the calling hook's scripts/ directory — used for path construction in hook body
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${_GSD_PREAMBLE_LIB_DIR}}")" && pwd)"

# GSD_HOOK_LOG: conditional — hooks redirect this mid-execution (Phase 2 redirect)
GSD_HOOK_LOG="${GSD_HOOK_LOG:-${SKILL_LOG_DIR}/hooks.log}"

debug_log() {
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$*" \
    >> "$GSD_HOOK_LOG" 2>/dev/null || true
}

debug_log "FIRED — PID=$$ TMUX=${TMUX:-<unset>}"

# Source hook-utils.sh from lib/ directory (same location as this preamble)
_GSD_UTILS_PATH="${_GSD_PREAMBLE_LIB_DIR}/hook-utils.sh"
if [ -f "$_GSD_UTILS_PATH" ]; then
  # shellcheck source=./hook-utils.sh
  source "$_GSD_UTILS_PATH"
  debug_log "sourced lib/hook-utils.sh"
else
  printf '[%s] [%s] FATAL: hook-utils.sh not found at %s\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$HOOK_SCRIPT_NAME" "$_GSD_UTILS_PATH" \
    >> "$GSD_HOOK_LOG" 2>/dev/null || true
  exit 0
fi
```

**Example (hook-side source idiom — for Phase 13 reference):**

```bash
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../lib/hook-preamble.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/hook-preamble.sh"
# Now available: SKILL_LOG_DIR, GSD_HOOK_LOG, HOOK_SCRIPT_NAME, SCRIPT_DIR,
#                REGISTRY_PATH, debug_log(), and all hook-utils.sh functions
STDIN_JSON=$(cat)
HOOK_ENTRY_MS=$(date +%s%3N)
debug_log "stdin: ${#STDIN_JSON} bytes, ..."
```

**Note on `exit 0` in preamble:** The preamble uses `exit 0` for the lib-not-found fatal case. This terminates the calling hook entirely. This is intentional and acceptable for this single case — a missing hook-utils.sh is fatal and the hook cannot continue. The preamble must contain exactly one `exit` statement. All other failure paths use `return 0` or conditional assignments.

### Pattern 2: extract_hook_settings() — JSON Return Function

**What:** A function in `lib/hook-utils.sh` that accepts `registry_path` and `agent_data_json`, executes the three-tier jq fallback once, and returns compact JSON to stdout. The caller reads individual fields.

**The 4x duplicated block being replaced:**

```bash
# Current pattern in stop-hook.sh, notification-idle-hook.sh,
# notification-permission-hook.sh, pre-compact-hook.sh:
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

**Note on pre-compact copy:** The pre-compact-hook.sh copy (lines 81-93) omits `2>/dev/null || echo "default"` guards. Under `set -euo pipefail`, a malformed AGENT_DATA crashes this hook. The function fixes this inconsistency by always including guards.

**Function implementation for hook-utils.sh:**

```bash
# ==========================================================================
# extract_hook_settings
# ==========================================================================
# Extracts hook_settings fields from registry with three-tier fallback:
#   1. Per-agent hook_settings (agent_data .hook_settings.field)
#   2. Registry-level global hook_settings (.hook_settings.field at root)
#   3. Hardcoded defaults (pane_capture_lines=100, threshold=50, mode=async)
#
# Arguments:
#   $1 - registry_path:    path to recovery-registry.json
#   $2 - agent_data_json:  JSON string from lookup_agent_in_registry()
# Returns:
#   Compact JSON on stdout:
#   {"pane_capture_lines":100,"context_pressure_threshold":50,"hook_mode":"async"}
#   On any jq failure, returns the hardcoded defaults JSON string.
#   Never exits non-zero. Never crashes the calling hook.
# ==========================================================================
extract_hook_settings() {
  local registry_path="$1"
  local agent_data_json="$2"

  local global_settings
  global_settings=$(jq -r '.hook_settings // {}' "$registry_path" 2>/dev/null \
    || printf '{}')

  printf '%s' "$agent_data_json" | jq -c \
    --argjson global "$global_settings" \
    '{
      pane_capture_lines:           (.hook_settings.pane_capture_lines           // $global.pane_capture_lines           // 100),
      context_pressure_threshold:   (.hook_settings.context_pressure_threshold   // $global.context_pressure_threshold   // 50),
      hook_mode:                    (.hook_settings.hook_mode                    // $global.hook_mode                    // "async")
    }' 2>/dev/null \
    || printf '{"pane_capture_lines":100,"context_pressure_threshold":50,"hook_mode":"async"}'
}
```

**Caller pattern (replaces the 12-line block with 4 lines):**

```bash
HOOK_SETTINGS=$(extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA")
PANE_CAPTURE_LINES=$(printf '%s' "$HOOK_SETTINGS" | jq -r '.pane_capture_lines')
CONTEXT_PRESSURE_THRESHOLD=$(printf '%s' "$HOOK_SETTINGS" | jq -r '.context_pressure_threshold')
HOOK_MODE=$(printf '%s' "$HOOK_SETTINGS" | jq -r '.hook_mode')
```

### Pattern 3: detect_session_state() — Standard State Detection Function

**What:** A function in `lib/hook-utils.sh` that accepts pane content and returns a state name string. Uses case-insensitive extended regex patterns (`grep -Eiq`) consistent with the stop/notification hook pattern. Returns one of: `menu`, `permission_prompt`, `idle`, `error`, `working`.

**The two divergent implementations being unified:**

Stop/notification hooks (stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh):

```bash
STATE="working"
if echo "$PANE_CONTENT" | grep -Eiq 'Enter to select|numbered.*option' 2>/dev/null; then
  STATE="menu"
elif echo "$PANE_CONTENT" | grep -Eiq 'permission|allow|dangerous' 2>/dev/null; then
  STATE="permission_prompt"
elif echo "$PANE_CONTENT" | grep -Eiq 'What can I help|waiting for' 2>/dev/null; then
  STATE="idle"
elif echo "$PANE_CONTENT" | grep -Ei 'error|failed|exception' 2>/dev/null | grep -v 'error handling' >/dev/null 2>&1; then
  STATE="error"
fi
```

Pre-compact hook (pre-compact-hook.sh):

```bash
if echo "$PANE_CONTENT" | grep -q "Choose an option:"; then
  STATE="menu"
elif echo "$PANE_CONTENT" | grep -q "Continue this conversation"; then
  STATE="idle_prompt"
elif echo "$PANE_CONTENT" | grep -q "permission to"; then
  STATE="permission_prompt"
else
  STATE="active"
fi
```

**Differences (empirically confirmed from direct code reading):**

| Aspect | Stop/notification | Pre-compact |
|--------|-------------------|-------------|
| grep flags | `-Eiq` (extended, case-insensitive) | `-q` (no -E, case-sensitive) |
| Menu pattern | `Enter to select\|numbered.*option` | `Choose an option:` |
| Idle pattern | `What can I help\|waiting for` | `Continue this conversation` |
| Idle state name | `idle` | `idle_prompt` |
| Fallback state | `working` | `active` |
| Error detection | Present (`error\|failed\|exception`) | Absent |

**Decision for detect_session_state() in Phase 12:** Use the stop/notification pattern as the canonical form (grep -Eiq, consistent state names including `working` and `idle`). The pre-compact patterns differ in both the grep keywords and state names — whether these differences are intentional (different TUI text during PreCompact) or accidental cannot be determined by static code analysis alone. The function will implement the standard pattern. During Phase 13, when pre-compact-hook.sh is modified to call this function, the difference will be evaluated: if pre-compact state detection must remain different, pre-compact-hook.sh will keep its own inline state detection with a comment explaining why.

**Implementation for hook-utils.sh:**

```bash
# ==========================================================================
# detect_session_state
# ==========================================================================
# Detects the current session state from tmux pane content using
# case-insensitive extended regex patterns. Returns a consistent state name
# across all hook event types that use standard pane pattern matching.
#
# State names (in detection priority order):
#   menu             — Claude Code option selection screen
#   permission_prompt — permission or allow dialog
#   idle             — Claude waiting for user input
#   error            — error/failure detected in pane
#   working          — default (no specific pattern matched)
#
# Arguments:
#   $1 - pane_content: string of current tmux pane capture
# Returns:
#   State name string on stdout. Always returns a non-empty string.
#   Never exits non-zero. Never crashes the calling hook.
#
# Note: pre-compact-hook.sh uses different patterns and state names
# (case-sensitive grep, "Choose an option:", "Continue this conversation",
# "active" fallback). Until pre-compact TUI text is empirically verified,
# that hook may retain its own inline detection rather than calling this function.
# ==========================================================================
detect_session_state() {
  local pane_content="$1"

  if printf '%s\n' "$pane_content" | grep -Eiq 'Enter to select|numbered.*option' 2>/dev/null; then
    printf 'menu'
  elif printf '%s\n' "$pane_content" | grep -Eiq 'permission|allow|dangerous' 2>/dev/null; then
    printf 'permission_prompt'
  elif printf '%s\n' "$pane_content" | grep -Eiq 'What can I help|waiting for' 2>/dev/null; then
    printf 'idle'
  elif printf '%s\n' "$pane_content" | grep -Ei 'error|failed|exception' 2>/dev/null \
    | grep -v 'error handling' >/dev/null 2>&1; then
    printf 'error'
  else
    printf 'working'
  fi
}
```

**Note on printf '%s\n' vs echo:** The function uses `printf '%s\n'` for piping to grep (line-oriented tool needs the newline). This is the QUAL-01 requirement — replacing `echo "$VAR" | jq/grep` with `printf '%s' "$VAR"` for jq and `printf '%s\n' "$VAR"` for line-oriented tools. The function is written with the correct form from the start.

### Pattern 4: Source Guard Design

**Double-source prevention:**

```bash
# At top of hook-preamble.sh — before any other code
[[ -n "${_GSD_HOOK_PREAMBLE_LOADED:-}" ]] && return 0
readonly _GSD_HOOK_PREAMBLE_LOADED=1
```

The `return 0` (not `exit 0`) is correct here — we want to stop preamble execution without terminating the calling hook. This is the only place in the preamble that uses `return` instead of `exit`.

**Direct execution prevention:**

```bash
# After source guard, before any path computation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf 'ERROR: %s must be sourced, not executed directly.\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi
```

When the preamble is executed directly (`bash lib/hook-preamble.sh`), `BASH_SOURCE[0]` equals `${0}`. When sourced, `BASH_SOURCE[0]` is the preamble path but `${0}` is the calling script's path — they differ. The condition is false, execution continues normally.

### Anti-Patterns to Avoid

- **BASH_SOURCE[0] for identity in preamble:** Using `$(basename "${BASH_SOURCE[0]}")` in preamble sets `HOOK_SCRIPT_NAME` to `hook-preamble.sh` in all logs. Every path and name computation must use `BASH_SOURCE[1]`.
- **stdin consumption in preamble:** `STDIN_JSON=$(cat)` in the preamble robs the hook of its input. Verified destructive — once cat reads stdin in a sourced file, the hook's subsequent `cat` returns empty.
- **HOOK_ENTRY_MS in preamble:** Setting timing in the preamble includes preamble startup overhead (~5ms). Timing must start in the hook body after `source` returns.
- **Multiple exit statements in preamble:** Preamble must contain exactly one `exit 0` — the lib-missing fatal case. All other conditional paths must use `return 0` or conditional assignments, never `exit`.
- **declare -g for extract_hook_settings() output:** Using `declare -g` to set caller-scope variables is an alternative but is more obscure and creates implicit side effects. JSON return with explicit caller parsing is cleaner, consistent with existing lib function style, and immune to injection risk.
- **Putting hook-preamble.sh in scripts/:** The preamble is a library component, not an executable entry point. In `scripts/` it would be picked up by diagnose-hooks.sh Step 2's executable check, causing false failures. It belongs in `lib/` alongside `hook-utils.sh`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Three-tier fallback (per-agent // global // hardcoded) | Custom bash conditionals | jq `//` operator in single invocation | jq handles null/missing fields correctly. Bash conditionals require separate `[ -z ]` checks for each field — verbose and error-prone. The existing 12-line pattern shows the complexity that `jq // // ` eliminates. |
| Source guard | Custom variable check | `[[ -n "${_LOADED:-}" ]] && return 0` sentinel | Standard pattern, zero overhead when already loaded. |
| Caller identity in sourced file | Pass script name as parameter | `BASH_SOURCE[1]` | Automatic, no hook modification needed, empirically verified. |
| State detection regex | Hardcode patterns in hooks | detect_session_state() function in lib | Patterns must be identical across all hooks. One function ensures consistency. |

**Key insight:** The domain is bash library extraction — there are no complex algorithms, only correct sourcing semantics and jq idioms. The only custom logic is the `BASH_SOURCE[1]` pattern, which is standard bash documented behavior.

---

## Common Pitfalls

### Pitfall 1: BASH_SOURCE[0] in Preamble Resolves to Preamble's Own Path

**What goes wrong:** Copying the existing hook preamble verbatim sets `HOOK_SCRIPT_NAME` to `hook-preamble.sh` and `SCRIPT_DIR` to the `lib/` directory. Log entries show `[hook-preamble.sh]` for every hook. Filtering logs by hook name returns zero results.

**Why it happens:** The existing per-hook code uses `BASH_SOURCE[0]` which is the hook itself. Moving this code to the preamble changes the meaning of `BASH_SOURCE[0]`.

**How to avoid:** Use `BASH_SOURCE[1]` in preamble for `HOOK_SCRIPT_NAME`, `SKILL_LOG_DIR`, and `SCRIPT_DIR`. Verify immediately after creation by sourcing from a test script and checking the resulting variable values.

**Warning signs:** Log prefix shows `[hook-preamble.sh]` instead of `[stop-hook.sh]`.

### Pitfall 2: set -euo pipefail Interaction with Source Return Codes

**What goes wrong:** If preamble uses `return 1` for any failure path, and the calling hook has `set -euo pipefail` active, the `source preamble.sh` command exits non-zero, triggering `set -e` and terminating the hook with no log entry.

**Why it happens:** `source file.sh` inherits the caller's shell options. A non-zero `return` from the sourced file becomes a non-zero exit of the `source` command. With `set -e`, this terminates the caller.

**How to avoid:**
- Use `exit 0` only for the lib-not-found fatal case (terminates hook, but intentionally)
- Use `return 0` for the source guard (idempotent early return — success)
- Never use `return 1` anywhere in the preamble
- Hook-side guard: `source "${SCRIPT_DIR}/../lib/hook-preamble.sh" || { printf '...'; exit 0; }`

**Warning signs:** Hook fires but produces no log entries at all (source fails silently, set -e terminates hook before debug_log "FIRED").

### Pitfall 3: Double-Sourcing hook-utils.sh

**What goes wrong:** After Phase 13 applies the preamble to all hooks, each hook's existing `source lib/hook-utils.sh` block remains — double-sourcing the library. Currently harmless (pure function library), but adds overhead and creates confusion.

**Why it happens:** Phase 12 creates the preamble. Phase 13 must explicitly delete the old source blocks from each hook alongside adding the preamble source line. This deletion is easy to omit.

**How to avoid:** Phase 13 plan must include the deletion as an explicit step. Verify with `grep -rn 'source.*hook-utils.sh' scripts/` returning zero matches after migration. This is a Phase 13 concern, not Phase 12, but the Phase 12 preamble design must anticipate it.

**Warning signs:** `grep -rn 'source.*hook-utils.sh' scripts/` shows hits after Phase 13.

### Pitfall 4: extract_hook_settings() Agent Data Passed as String vs Piped

**What goes wrong:** The function accepts `agent_data_json` as a positional argument (`$2`) and pipes it to jq via `printf '%s' "$agent_data_json" | jq`. If the agent data contains special characters that survive the `printf` but confuse the shell's argument handling (specifically, very long JSON strings with embedded quotes), the jq parse may fail silently, falling through to hardcoded defaults without any log entry indicating why.

**Why it happens:** JSON strings from jq output can be multi-line and contain embedded quotes. Passing them as positional arguments through `$2` is safe in bash (the shell does not interpret content of quoted variables), but developers may doubt this and attempt workarounds that break the pattern.

**How to avoid:** Pass agent data directly as `$2`. Use `printf '%s' "$2"` (not `echo`) to pipe to jq. The `2>/dev/null || printf '...'` guard handles jq parse errors. Test with a registry entry containing a system_prompt with newlines and quotes.

**Warning signs:** `extract_hook_settings` always returns hardcoded defaults even when registry has custom values.

### Pitfall 5: detect_session_state() Returns Nothing for Empty Pane

**What goes wrong:** If `pane_content` is empty, all grep patterns return non-zero (no match), the function falls through to the final `else` branch — but if there is no `else`, it exits with the last command's exit code. Under `set -e`, a non-zero exit propagates.

**Why it happens:** The function must always return a value. The `working` fallback must be unconditional.

**How to avoid:** The `else` clause with `printf 'working'` must always be present. No pattern should be able to leave the function without printing a state name.

**Warning signs:** Hook exits with non-zero when pane content is empty (e.g., early in session before any content appears).

---

## Code Examples

Verified patterns from direct codebase reading and empirical testing:

### Preamble Source Test (verification pattern)

```bash
#!/usr/bin/env bash
# test-preamble.sh — run from scripts/ directory for testing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/hook-preamble.sh"

# Verify HOOK_SCRIPT_NAME is test-preamble.sh, not hook-preamble.sh
printf 'HOOK_SCRIPT_NAME=%s\n' "$HOOK_SCRIPT_NAME"

# Verify lookup_agent_in_registry is callable (sourced from hook-utils.sh via preamble)
if declare -f lookup_agent_in_registry >/dev/null 2>&1; then
  printf 'lookup_agent_in_registry: available\n'
fi

# Verify SCRIPT_DIR points to scripts/, not lib/
printf 'SCRIPT_DIR=%s\n' "$SCRIPT_DIR"
```

### extract_hook_settings() Call Pattern

```bash
# After lookup_agent_in_registry() populates AGENT_DATA:
HOOK_SETTINGS=$(extract_hook_settings "$REGISTRY_PATH" "$AGENT_DATA")
PANE_CAPTURE_LINES=$(printf '%s' "$HOOK_SETTINGS" | jq -r '.pane_capture_lines')
CONTEXT_PRESSURE_THRESHOLD=$(printf '%s' "$HOOK_SETTINGS" | jq -r '.context_pressure_threshold')
HOOK_MODE=$(printf '%s' "$HOOK_SETTINGS" | jq -r '.hook_mode')

# Fallback if HOOK_SETTINGS parsing fails (paranoid guard):
PANE_CAPTURE_LINES="${PANE_CAPTURE_LINES:-100}"
CONTEXT_PRESSURE_THRESHOLD="${CONTEXT_PRESSURE_THRESHOLD:-50}"
HOOK_MODE="${HOOK_MODE:-async}"
```

### detect_session_state() Call Pattern

```bash
STATE=$(detect_session_state "$PANE_CONTENT")
debug_log "state=$STATE"
```

### Unit Test for extract_hook_settings() (inline bash test)

```bash
# Create a minimal test registry
TEST_REGISTRY=$(mktemp)
printf '{"hook_settings":{"pane_capture_lines":50},"agents":[{"agent_id":"test","openclaw_session_id":"sess-1","hook_settings":{"hook_mode":"bidirectional"}}]}' > "$TEST_REGISTRY"

# Test agent data (simulates lookup_agent_in_registry output)
TEST_AGENT='{"agent_id":"test","openclaw_session_id":"sess-1","hook_settings":{"hook_mode":"bidirectional"}}'

SETTINGS=$(extract_hook_settings "$TEST_REGISTRY" "$TEST_AGENT")

# Verify three-tier fallback:
# pane_capture_lines: global=50 (no per-agent override) -> expected 50
# context_pressure_threshold: no global, no per-agent -> expected hardcoded 50
# hook_mode: per-agent=bidirectional -> expected bidirectional
printf 'pane_capture_lines=%s\n' "$(printf '%s' "$SETTINGS" | jq -r '.pane_capture_lines')"           # 50
printf 'context_pressure_threshold=%s\n' "$(printf '%s' "$SETTINGS" | jq -r '.context_pressure_threshold')"  # 50
printf 'hook_mode=%s\n' "$(printf '%s' "$SETTINGS" | jq -r '.hook_mode')"                            # bidirectional

rm -f "$TEST_REGISTRY"
```

### Unit Test for detect_session_state()

```bash
# Test each state
STATE=$(detect_session_state "Use arrow keys or Enter to select option")
printf 'menu test: %s\n' "$STATE"  # expected: menu

STATE=$(detect_session_state "Claude needs permission to run this command")
printf 'permission test: %s\n' "$STATE"  # expected: permission_prompt

STATE=$(detect_session_state "What can I help you with today?")
printf 'idle test: %s\n' "$STATE"  # expected: idle

STATE=$(detect_session_state "Error: command not found")
printf 'error test: %s\n' "$STATE"  # expected: error

STATE=$(detect_session_state "Analyzing your codebase...")
printf 'working test: %s\n' "$STATE"  # expected: working

STATE=$(detect_session_state "")
printf 'empty test: %s\n' "$STATE"  # expected: working
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 27-line preamble inline in each hook | Same (still the current state) | Not yet changed (Phase 12 creates the replacement) | Phase 12 creates hook-preamble.sh; Phase 13 applies it |
| 12-line settings block inline in 4 hooks | Same (still the current state) | Not yet changed | Phase 12 creates extract_hook_settings(); Phase 13 applies it |
| State detection inline per hook | Two divergent implementations | Not yet changed | Phase 12 creates detect_session_state() with standard pattern; Phase 13 applies it to 3 hooks |
| BASH_SOURCE[0] for hook identity | Well-understood but requires re-learning when extracting to preamble | Always worked in inline code; becomes a pitfall only when extracting to preamble | Phase 12 must use BASH_SOURCE[1] throughout |

**Deprecated/outdated:**
- `echo "$VAR" | jq` patterns in older hooks: not yet deprecated but marked for cleanup in Phase 13 (QUAL-01). The detect_session_state() function pre-adopts `printf '%s\n'` to be correct from the start.

---

## Open Questions

1. **Pre-compact state detection intent**
   - What we know: pre-compact-hook.sh uses different grep patterns (`Choose an option:`, `Continue this conversation`) and different state names (`idle_prompt`, `active`) vs stop/notification hooks (`Enter to select`, `What can I help`, `idle`, `working`)
   - What's unclear: whether these differences reflect genuinely different TUI text during PreCompact events or are accidental copy-paste divergence from before the patterns were standardized
   - Recommendation: Phase 12 creates `detect_session_state()` with the stop/notification standard pattern. During Phase 13, when pre-compact-hook.sh is edited, check the TUI text differences. If the patterns differ because the TUI shows different text during compaction, keep pre-compact's inline detection with an explanatory comment. If they are accidental, call `detect_session_state()`. This decision is deferred to Phase 13 and does not block Phase 12.

2. **REGISTRY_PATH in preamble vs caller**
   - What we know: the preamble can compute `REGISTRY_PATH="${_GSD_SKILL_ROOT}/config/recovery-registry.json"` from its own location. Current hooks compute it from `SCRIPT_DIR/../config/`. Both resolve to the same path when `lib/` and `scripts/` are siblings under SKILL_ROOT.
   - What's unclear: whether to have preamble set REGISTRY_PATH or leave it to each hook
   - Recommendation: Have preamble set REGISTRY_PATH. It is the same value for all hooks and depends on SKILL_ROOT (already computed in preamble). Centralizing it in the preamble removes one more repeated computation from each hook.

3. **SCRIPT_DIR semantics after preamble**
   - What we know: hooks use `SCRIPT_DIR` only to construct `REGISTRY_PATH` (computed in preamble) and `LIB_PATH` (replaced by preamble). After refactoring, `SCRIPT_DIR` in hooks becomes unused.
   - What's unclear: whether to keep setting SCRIPT_DIR in preamble (as the caller's directory) for backward compatibility with any hook body code that references it
   - Recommendation: Set `SCRIPT_DIR` in the preamble using `BASH_SOURCE[1]` (the hook's directory). This preserves backward compatibility. If hooks reference `SCRIPT_DIR` for their own path needs, the value is correct. During Phase 13, if `SCRIPT_DIR` is confirmed unused in hook bodies after refactoring, it can be removed.

---

## Sources

### Primary (HIGH confidence — direct reading and empirical testing)

- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/lib/hook-utils.sh` — 6 existing functions, "no side effects on source" design contract, exact signatures; confirms pure function library design that extract_hook_settings() and detect_session_state() must follow
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/stop-hook.sh` — 27-line preamble block (lines 1-27), 12-line settings block (lines 99-111), state detection (lines 132-143); reference implementation for all three patterns
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-idle-hook.sh` — 27-line preamble (identical to stop-hook), settings block (lines 92-104), state detection (identical to stop-hook)
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-permission-hook.sh` — identical to notification-idle-hook.sh structure
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/pre-compact-hook.sh` — settings block (lines 81-93) without 2>/dev/null guards; divergent state detection (lines 109-118) with different patterns and state names
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/session-end-hook.sh` — preamble pattern; missing jq guards at lines 71-72 (FIX-03, addressed in Phase 13)
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/pre-tool-use-hook.sh` — preamble pattern; already uses printf '%s' correctly
- `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/post-tool-use-hook.sh` — preamble pattern; already uses printf '%s' correctly
- `.planning/research/ARCHITECTURE.md` — target source chain diagram, BASH_SOURCE[1] pattern, component responsibilities; HIGH confidence, all patterns verified
- `.planning/research/STACK.md` — bash 5.2 pattern verification, set -euo pipefail interaction rules, extract_hook_settings() design alternatives; HIGH confidence, live-tested
- `.planning/research/PITFALLS.md` — 11 detailed pitfalls with prevention and recovery strategies; HIGH confidence, empirically derived
- `.planning/research/FEATURES.md` — feature dependency graph, duplication sites with line numbers, MVP definition
- `.planning/research/SUMMARY.md` — executive summary, critical pitfalls synthesis, phase ordering rationale

### Secondary (MEDIUM confidence — verified community sources)

- Source guard pattern: `[[ -n "${_LOADED:-}" ]] && return 0` — [Arslan.io idempotent bash scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/)
- Sourced-only enforcement: `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` — [Nick Janetakis](https://nickjanetakis.com/blog/detect-if-a-shell-script-is-being-executed-or-sourced)
- `printf '%s' "$var" | jq` vs `echo "$var" | jq` correctness: [How to Geek](https://www.howtogeek.com/heres-why-printf-beats-echo-in-your-linux-scripts/)
- Google Shell Style Guide naming conventions (UPPER_SNAKE_CASE, lower_snake_case, local) — [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — zero new dependencies; all patterns live-tested on bash 5.2.21 on production host
- Architecture: HIGH — preamble design derived from reading all 7 hook scripts; BASH_SOURCE[1] behavior empirically confirmed; prior milestone research provides independent validation
- Pitfalls: HIGH — derived from empirical testing (not documentation inference); source guard, exit propagation, stdin consumption, double-source all confirmed via live execution on production host
- detect_session_state() canonical form: MEDIUM — the pre-compact pattern difference is documented but its intent (intentional vs accidental) is unconfirmed pending live session observation

**Research date:** 2026-02-18
**Valid until:** 2026-03-20 (bash 5.2 and jq 1.7 are stable; no version concerns for 30+ days)

**What might have been missed:**
- Whether REGISTRY_PATH should be set in preamble or left to each hook (resolved above: set in preamble)
- Whether `SCRIPT_DIR` should remain in preamble output after Phase 13 removes its uses (resolved above: keep for backward compatibility, remove in Phase 13 if confirmed unused)
- Whether diagnose-hooks.sh should source hook-preamble.sh (it should not — diagnose may need to call lookup_agent_in_registry but does not need the full bootstrap; it should source hook-utils.sh directly)
