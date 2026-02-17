# Phase 1: Additive Changes - Research

**Researched:** 2026-02-17
**Domain:** Bash hook scripts, tmux control, jq JSON operations, Claude Code hook system
**Confidence:** HIGH

## Summary

Phase 1 creates 5 new hook scripts (stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh, pre-compact-hook.sh), a menu-driver type action, registry schema additions (system_prompt + hook_settings), and config/default-system-prompt.txt. All components are additive — they coexist with existing autoresponder/hook-watcher until Phase 2-4 removes polling. The implementation uses bash + jq exclusively (no Python dependency) for cross-platform compatibility and operational simplicity.

Key technical findings:
- tmux capture-pane supports configurable line depth via -S flag (verified up to -200 lines)
- tmux send-keys -l enables literal text input without shell expansion (critical for type action)
- jq 1.7 provides --arg variable binding and // fallback operator for three-tier config resolution
- flock provides atomic registry writes (prevents corruption during concurrent upsert)
- Hook stdin must be consumed immediately (cat >/dev/null) to prevent pipe blocking
- $TMUX environment variable provides instant detection of tmux context (<1ms)
- Context pressure extraction via grep -oE on statusline last 5 lines (percentage + warning level)
- State detection via pattern matching on pane content (menu, idle, permission_prompt, error, working)

**Primary recommendation:** Use bash + jq for all hook scripts and registry operations. No Python dependency ensures portability and simplifies deployment. Use flock for atomic registry writes. All hook scripts share common guard patterns (stdin consumption, $TMUX check, registry lookup, fast-path exits).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Agent Wake Message:**
- Structured sections with clear headers (e.g., `[PANE CONTENT]`, `[CONTEXT PRESSURE]`, `[AVAILABLE ACTIONS]`)
- Include session identity: agent_id and tmux_session_name in every message
- Include a state hint line based on simple pattern matching (e.g., `state: menu`, `state: idle`, `state: permission_prompt`)
- Include trigger type: `trigger: response_complete` vs `trigger: session_start` to differentiate fresh responses from session launches
- Always send wake message regardless of state (even on idle) — OpenClaw agent decides if action is needed
- Pane capture depth configurable per-agent via `hook_settings.pane_capture_lines` (default determined by Claude)

**Hook Architecture:**
- Separate scripts per hook event type (SRP): stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh, pre-compact-hook.sh
- Create permission prompt hook even though --dangerously-skip-permissions is used (future-proofing)
- Hybrid communication mode: default async (capture + background openclaw call + exit 0), with optional bidirectional mode per-agent (`hook_settings.hook_mode: "async" | "bidirectional"`)
- In bidirectional mode: hook waits for OpenClaw response, returns `{ "decision": "block", "reason": "..." }` to inject instructions into Claude
- SessionEnd hook notifies OpenClaw immediately when session terminates (faster recovery than daemon alone)
- All hook scripts share common guard patterns: stdin consumption, stop_hook_active check, $TMUX validation, registry lookup

**Hook Technical Context (from research):**
- Claude Code has 14 hook event types total; we use 5: Stop, Notification (idle_prompt), Notification (permission_prompt), SessionEnd, PreCompact
- Stop hooks fire when Claude finishes responding — they do NOT fire on user interrupts
- Hooks snapshot at startup: changes to settings.json require session restart to take effect
- Hook timeout is 10 minutes by default (configurable per hook)
- Exit code 0 with JSON: Claude parses stdout for decisions. Exit code 2: stderr fed back as error
- `decision: "block"` with `reason` makes Claude continue working with that reason as its next instruction
- `continue: false` with `stopReason` halts Claude entirely (different from blocking)
- All matching hooks run in parallel; identical handlers are deduplicated
- Stop and Notification(idle_prompt) do NOT support matchers — they always fire
- Notification(permission_prompt) uses matcher `permission_prompt`
- `--append-system-prompt` appends to Claude's default prompt (preserves built-in capabilities)
- `--append-system-prompt-file <path>` loads from file directly (alternative to reading in bash)
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` env var triggers compaction at custom percentage

**Default System Prompt:**
- External file: `config/default-system-prompt.txt` tracked in git
- Content: minimal, focused on GSD workflow commands (/gsd:*, /clear, /resume)
- No role/personality content — agents get that from SOUL.md and AGENTS.md
- No mention of managed tmux session or orchestration layer — pure workflow guidance
- Per-agent `system_prompt` in registry always appends to (never replaces) the default
- Use `--append-system-prompt-file` or `--append-system-prompt` to pass to Claude Code (Claude's discretion on which flag)

**Context Pressure Signaling:**
- Configurable threshold per-agent via `hook_settings.context_pressure_threshold` (default determined by Claude)
- Format: percentage + warning level (e.g., `context: 72% [WARNING]`, `context: 45% [OK]`)
- No recommended action in the message — OpenClaw agent decides what to do (/compact, /clear, or continue)
- GSD slash commands already handle context management when used properly
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` configurable per-agent via `hook_settings.autocompact_pct`

**Registry Schema Design:**
- `system_prompt` field at top level per agent (string, used by spawn.sh, not hook-related)
- `hook_settings` as nested object per agent for hook-related config
- Global `hook_settings` at registry root level — per-agent overrides specific fields (three-tier fallback: per-agent > global > hardcoded)
- Per-field merge: if per-agent has `pane_capture_lines` but not `context_pressure_threshold`, use per-agent for first and global for second
- Strict known fields only — no open-ended keys
- All defaults documented explicitly in `recovery-registry.example.json`
- Auto-populate `hook_settings` with defaults when creating new agent entries
- Use jq for all registry reads/writes (no Python dependency)
- Read registry fresh every time (no caching)
- Example shows realistic multi-agent setup (Gideon, Warden, Forge) with different `hook_settings`
- Separate registry validation script (not in-hook validation) for pre-deploy confidence

### Claude's Discretion

- Available actions format: all actions always vs. contextual (Claude determines best approach for agent consumption)
- State hint categories: Claude determines useful set of states based on what agents need
- Wake message format: plain text with markers vs. JSON (Claude picks what OpenClaw agents handle best)
- Timestamp inclusion in wake messages (Claude determines operational value)
- Message delivery mechanism: single --message vs. separate flags (based on OpenClaw CLI capabilities)
- Default pane capture depth (currently 120 lines in PRD, Claude picks the right default)
- Default context pressure threshold percentage
- `--append-system-prompt` vs `--append-system-prompt-file` flag choice for spawn.sh

### Deferred Ideas (OUT OF SCOPE)

- Registry validation script (config/validate-registry.sh) — new capability, deserves its own phase or addition to backlog
- PreCompact hook (pre-compact-hook.sh) — could inject context preservation instructions before compaction, but needs deeper investigation
- Agent SDK (Python/TypeScript) as alternative to tmux send-keys — future evolution path for OpenClaw, bypass tmux entirely
- `--permission-prompt-tool` MCP tool for fine-grained permission routing — relevant if moving away from `--dangerously-skip-permissions`
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| HOOK-01 | Stop hook fires when Claude Code finishes responding in managed tmux sessions | tmux environment detection via $TMUX variable, registry lookup via jq |
| HOOK-02 | Stop hook captures pane content and sends structured wake message to correct OpenClaw agent via session ID | tmux capture-pane -S flag, openclaw agent --session-id CLI, jq registry queries |
| HOOK-03 | All hook scripts exit cleanly (<5ms) for non-managed sessions (no $TMUX or no registry match) | $TMUX check (instant), jq query (verified <5ms on small registry), fast-path exit pattern |
| HOOK-04 | Stop hook guards against infinite loops via stop_hook_active field check | stdin JSON parsing (cat then jq -r), conditional exit based on boolean field |
| HOOK-05 | Stop hook consumes stdin immediately to prevent pipe blocking | cat >/dev/null pattern (verified non-blocking), process stdin before any logic |
| HOOK-06 | Stop hook extracts context pressure percentage from statusline with configurable threshold | grep -oE pattern for percentage extraction, tail -5 for statusline area, threshold comparison |
| HOOK-07 | Notification hook (idle_prompt) notifies OpenClaw when Claude waits for user input | Same guard patterns as stop-hook, trigger field differentiation, async-only mode |
| HOOK-08 | Notification hook (permission_prompt) notifies OpenClaw on permission dialogs (future-proofing) | matcher "permission_prompt" in settings.json, same wake message structure |
| HOOK-09 | SessionEnd hook notifies OpenClaw immediately when session terminates | Minimal message (session identity + trigger), no pane capture needed |
| HOOK-10 | PreCompact hook captures state before context compaction | Same pane capture as stop-hook, trigger: pre_compact, optional bidirectional mode |
| HOOK-11 | Hook scripts support hybrid mode — async by default, bidirectional per-agent via hook_settings.hook_mode | jq three-tier fallback for hook_mode field, background & vs synchronous openclaw call, JSON decision response |
| WAKE-01 | Wake message uses structured sections with clear headers | Plain text format with [SECTION] markers (better LLM parsing than JSON) |
| WAKE-02 | Wake message includes session identity (agent_id and tmux_session_name) | jq extraction from registry, string interpolation in bash |
| WAKE-03 | Wake message includes state hint based on pattern matching | grep -Eiq patterns for menu/idle/permission_prompt/error/working states |
| WAKE-04 | Wake message includes trigger type (response_complete vs session_start) | String literal based on hook script type, differentiates Stop vs Notification events |
| WAKE-05 | Wake message always sent regardless of detected state | No conditional skipping logic, OpenClaw agent filters relevance |
| WAKE-06 | Wake message includes context pressure as percentage + warning level | grep -oE for percentage, threshold comparison for OK/WARNING/CRITICAL labels |
| MENU-01 | menu-driver.sh supports `type <text>` action for freeform text input via tmux send-keys -l | tmux send-keys -l literal mode (verified), C-u line clear, Enter submission |
| CONFIG-01 | recovery-registry.json supports system_prompt field (top-level per agent) and hook_settings nested object | jq schema extension, backward-compatible (existing agents don't break) |
| CONFIG-02 | recovery-registry.example.json documents system_prompt, hook_settings with realistic multi-agent setup | Example structure with Gideon/Warden/Forge showing different configs |
| CONFIG-04 | Global hook_settings at registry root level with per-agent override (three-tier fallback) | jq // fallback operator enables per-field merge (verified in tests) |
| CONFIG-05 | Default system prompt stored in config/default-system-prompt.txt | cat file content, append to per-agent prompt, tracked in git |
| CONFIG-06 | hook_settings supports strict known fields: pane_capture_lines, context_pressure_threshold, autocompact_pct, hook_mode | jq field extraction with defaults, no open-ended keys |
| CONFIG-07 | Per-agent system_prompt always appends to default (never replaces) | String concatenation in bash: DEFAULT + "\n\n" + AGENT_PROMPT |
| CONFIG-08 | New agent entries auto-populate hook_settings with defaults | jq update during upsert adds empty hook_settings object if missing |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 4.0+ | Hook script execution, registry operations | Universal on Linux/macOS, no runtime dependencies |
| jq | 1.7 | JSON parsing and registry manipulation | Industry standard for command-line JSON, replaces Python |
| tmux | 2.0+ | Pane capture and keystroke injection | Already required by gsd-code-skill, battle-tested |
| flock | util-linux 2.39+ | Atomic registry file locking | Prevents corruption during concurrent writes |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| grep | GNU/BSD | Pattern matching for state detection | State hint extraction from pane content |
| sed | GNU/BSD | Text transformation (if needed) | Optional fallback for complex text processing |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq | Python json module | Python adds dependency, jq is faster for simple queries |
| flock | lockfile or mkdir locking | flock is cleaner, more portable, built into util-linux |
| bash | sh/dash | bash provides better string manipulation, already required |

**Installation:**
```bash
# All tools already installed on Ubuntu 24 (verified)
jq --version  # jq-1.7
flock --version  # flock from util-linux 2.39.3
tmux -V  # tmux 3.4+
bash --version  # GNU bash 5.2+
```

## Architecture Patterns

### Recommended Project Structure
```
scripts/
├── stop-hook.sh                    # Stop hook (response complete)
├── notification-idle-hook.sh       # Notification hook (idle_prompt)
├── notification-permission-hook.sh # Notification hook (permission_prompt)
├── session-end-hook.sh             # SessionEnd hook
├── pre-compact-hook.sh             # PreCompact hook
├── menu-driver.sh                  # Add type action
├── spawn.sh                        # (existing, Phase 3 changes)
└── recover-openclaw-agents.sh      # (existing, Phase 3 changes)

config/
├── recovery-registry.json          # Add system_prompt + hook_settings
├── recovery-registry.example.json  # Document new schema
└── default-system-prompt.txt       # NEW: default system prompt content
```

### Pattern 1: Hook Script Structure

**What:** Standard pattern for all hook scripts (guards, registry lookup, wake message, hybrid mode)

**When to use:** All 5 hook scripts share this structure with minor variations per event type

**Example:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. CONSUME STDIN IMMEDIATELY (prevent pipe blocking)
STDIN_JSON=$(cat)

# 2. GUARD: stop_hook_active check (infinite loop prevention)
STOP_HOOK_ACTIVE=$(echo "$STDIN_JSON" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# 3. GUARD: $TMUX environment check (non-tmux sessions exit fast)
if [ -z "${TMUX:-}" ]; then
  exit 0
fi

# 4. EXTRACT tmux session name
SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
if [ -z "$SESSION_NAME" ]; then
  exit 0
fi

# 5. REGISTRY LOOKUP (jq, no Python)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_PATH="${SCRIPT_DIR}/../config/recovery-registry.json"

if [ ! -f "$REGISTRY_PATH" ]; then
  exit 0
fi

AGENT_DATA=$(jq -r \
  --arg session "$SESSION_NAME" \
  '.agents[] | select(.tmux_session_name == $session) |
   {agent_id, openclaw_session_id, hook_settings}' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")

if [ -z "$AGENT_DATA" ] || [ "$AGENT_DATA" = "null" ]; then
  exit 0  # Non-managed session, fast exit
fi

AGENT_ID=$(echo "$AGENT_DATA" | jq -r '.agent_id')
OPENCLAW_SESSION_ID=$(echo "$AGENT_DATA" | jq -r '.openclaw_session_id')

# 6. EXTRACT hook_settings with three-tier fallback
GLOBAL_SETTINGS=$(jq -r '.hook_settings // {}' "$REGISTRY_PATH")
PANE_LINES=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.pane_capture_lines // $global.pane_capture_lines // 120)')

# 7. CAPTURE PANE CONTENT
PANE_CONTENT=$(tmux capture-pane -pt "${SESSION_NAME}:0.0" -S "-${PANE_LINES}" 2>/dev/null || echo "")

# 8. DETECT STATE (pattern matching)
STATE="working"
if echo "$PANE_CONTENT" | grep -Eiq 'Enter to select'; then
  STATE="menu"
elif echo "$PANE_CONTENT" | grep -Eiq 'What can I help'; then
  STATE="idle"
fi

# 9. EXTRACT CONTEXT PRESSURE
PERCENTAGE=$(echo "$PANE_CONTENT" | tail -5 | grep -oE '[0-9]{1,3}%' | tail -1 | tr -d '%')
THRESHOLD=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.context_pressure_threshold // $global.context_pressure_threshold // 50)')

if [ -n "$PERCENTAGE" ]; then
  if [ "$PERCENTAGE" -ge 80 ]; then
    CONTEXT="${PERCENTAGE}% [CRITICAL]"
  elif [ "$PERCENTAGE" -ge "$THRESHOLD" ]; then
    CONTEXT="${PERCENTAGE}% [WARNING]"
  else
    CONTEXT="${PERCENTAGE}% [OK]"
  fi
else
  CONTEXT="unknown"
fi

# 10. BUILD STRUCTURED WAKE MESSAGE
WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: ${AGENT_ID}
tmux_session_name: ${SESSION_NAME}

[TRIGGER]
response_complete

[STATE HINT]
${STATE}

[PANE CONTENT]
${PANE_CONTENT}

[CONTEXT PRESSURE]
${CONTEXT}

[AVAILABLE ACTIONS]
menu-driver.sh ${SESSION_NAME} choose <n>
menu-driver.sh ${SESSION_NAME} type <text>
menu-driver.sh ${SESSION_NAME} clear_then <command>
menu-driver.sh ${SESSION_NAME} enter
menu-driver.sh ${SESSION_NAME} esc
menu-driver.sh ${SESSION_NAME} submit
menu-driver.sh ${SESSION_NAME} snapshot"

# 11. HYBRID MODE: async or bidirectional
HOOK_MODE=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.hook_mode // $global.hook_mode // "async")')

if [ "$HOOK_MODE" = "bidirectional" ]; then
  # Wait for OpenClaw response, return decision:block if provided
  RESPONSE=$(openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" --json 2>/dev/null || echo "")
  # Parse response for decision injection (future enhancement)
  exit 0
else
  # Async: background call, exit immediately
  openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >/dev/null 2>&1 &
  exit 0
fi
```
**Source:** Synthesized from PRD requirements, user decisions in CONTEXT.md, and verified bash/jq patterns

### Pattern 2: Three-Tier Config Fallback (jq)

**What:** Per-field configuration resolution: per-agent > global > hardcoded default

**When to use:** All hook_settings field extraction (pane_capture_lines, context_pressure_threshold, autocompact_pct, hook_mode)

**Example:**
```bash
# Extract with three-tier fallback
GLOBAL_SETTINGS=$(jq -r '.hook_settings // {}' "$REGISTRY_PATH")

PANE_LINES=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.pane_capture_lines // $global.pane_capture_lines // 120)')

THRESHOLD=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.context_pressure_threshold // $global.context_pressure_threshold // 50)')

HOOK_MODE=$(echo "$AGENT_DATA" | jq -r \
  --argjson global "$GLOBAL_SETTINGS" \
  '(.hook_settings.hook_mode // $global.hook_mode // "async")')
```
**Source:** Verified in /tmp/test-three-tier-fallback.sh test, jq --argjson + // fallback operator

### Pattern 3: Atomic Registry Update (flock + jq)

**What:** Safe concurrent registry writes using file locking and atomic rename

**When to use:** spawn.sh upsert, any registry modification from concurrent processes

**Example:**
```bash
# Atomic update with flock
REGISTRY_PATH="/path/to/recovery-registry.json"
LOCK_PATH="${REGISTRY_PATH}.lock"

flock "$LOCK_PATH" bash -c "
  jq \
    --arg agent_id 'warden' \
    --arg system_prompt 'Custom prompt text' \
    '.agents |= map(
      if .agent_id == \$agent_id
      then . + {system_prompt: \$system_prompt}
      else .
      end
    )' \
    '$REGISTRY_PATH' > '${REGISTRY_PATH}.tmp' &&
  mv '${REGISTRY_PATH}.tmp' '$REGISTRY_PATH'
"
```
**Source:** Verified in /tmp test with jq update + mv, flock man page util-linux 2.39.3

### Pattern 4: menu-driver.sh type Action

**What:** Send literal freeform text to Claude using tmux send-keys -l (no shell expansion)

**When to use:** OpenClaw agent needs to respond with arbitrary text (not just menu choices)

**Example:**
```bash
type)
  text="${1:-}"
  [ -n "$text" ] || { echo "type requires <text>" >&2; exit 1; }
  tmux send-keys -t "$SESSION:0.0" C-u        # Clear current line
  tmux send-keys -t "$SESSION:0.0" -l -- "$text"  # Send literal text (no expansion)
  tmux send-keys -t "$SESSION:0.0" Enter
  ;;
```
**Source:** tmux man page send-keys -l flag, existing menu-driver.sh choose action pattern

### Anti-Patterns to Avoid

- **Python for registry operations:** Adds dependency, slower startup than jq, not needed for simple JSON queries
- **Caching registry in /tmp:** Stale data risk, registry reads are <5ms with jq, premature optimization
- **LLM inference in hooks:** Hook must exit quickly (<10 minutes timeout), LLM takes 2-10s, breaks async model
- **Open-ended hook_settings keys:** Typos undetected, no schema validation, use strict known fields only
- **Replacing default system prompt:** Per-agent prompt should append (preserves GSD workflow guidance), not replace
- **Polling fallback alongside hooks:** Running both creates duplicate events, choose event-driven only

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing in bash | String manipulation, awk/sed hacks | jq 1.7 | jq handles edge cases (escaping, nested objects, arrays), battle-tested |
| File locking | mkdir-based locks, PID files | flock | flock is atomic, handles stale locks, built into util-linux |
| Context pressure extraction | Complex regex chains | grep -oE + tail -5 | Statusline is last 5 lines, simple percentage pattern sufficient |
| State detection | AI/ML classification | Pattern matching (grep -Eiq) | Deterministic, instant, covers 5 states needed by agents |
| Atomic file updates | Write direct, hope for best | flock + write tmp + mv | Prevents corruption from concurrent writes (spawn + hooks) |

**Key insight:** Bash + jq + tmux already provide all needed capabilities. Custom solutions add complexity without value. Stick to standard Unix tools with decades of production hardening.

## Common Pitfalls

### Pitfall 1: Forgetting to Consume Stdin in Hooks

**What goes wrong:** Hook script reads stdin later in logic, Claude Code hook system times out waiting for hook to finish reading

**Why it happens:** Stdin is piped from Claude Code, blocks until consumed

**How to avoid:** First line of logic: `STDIN_JSON=$(cat)` — consume entire stdin immediately

**Warning signs:** Hook hangs, 10-minute timeout, Claude Code frozen waiting for hook response

### Pitfall 2: Using Python in Registry Operations

**What goes wrong:** Python not available in some environments, slower startup (import overhead), adds dependency

**Why it happens:** Existing spawn.sh and recover-openclaw-agents.sh use Python, copy-paste pattern

**How to avoid:** Use jq for all JSON operations. Verified faster and more portable.

**Warning signs:** "python3: command not found" in non-standard environments, 50-100ms startup overhead

### Pitfall 3: Race Conditions in Registry Writes

**What goes wrong:** Concurrent spawn.sh or hook writes corrupt registry JSON (partial writes, invalid syntax)

**Why it happens:** No locking, multiple processes write simultaneously

**How to avoid:** Wrap all registry writes with `flock "$REGISTRY_PATH.lock" ...` and atomic tmp + mv pattern

**Warning signs:** Registry becomes unparseable JSON, agents fail to spawn/recover, jq parse errors

### Pitfall 4: Not Checking $TMUX Before tmux Commands

**What goes wrong:** Hook fires in non-tmux Claude Code session, tmux display-message fails, hook crashes

**Why it happens:** Hooks registered globally (settings.json), fire for ALL Claude Code sessions

**How to avoid:** Guard: `[ -z "${TMUX:-}" ] && exit 0` at top of every hook script

**Warning signs:** Hook errors in /tmp logs when running Claude Code outside tmux

### Pitfall 5: Hardcoding Config Values Instead of Three-Tier Fallback

**What goes wrong:** Per-agent customization impossible, global defaults ignored, hardcoded magic numbers scattered

**Why it happens:** Simpler to hardcode than implement fallback chain

**How to avoid:** Always use jq three-tier fallback: `(.hook_settings.field // $global.field // HARDCODED_DEFAULT)`

**Warning signs:** Can't configure pane depth or threshold per agent, must edit script for each agent's needs

### Pitfall 6: Using tmux send-keys Without -l for Freeform Text

**What goes wrong:** Shell expansion in text input (e.g., `$(cmd)` executes, `*` expands to files)

**Why it happens:** tmux send-keys default mode interprets shell metacharacters

**How to avoid:** Always use `tmux send-keys -l` for literal text input (type action)

**Warning signs:** Unexpected command execution, glob expansion in Claude responses, security risk

### Pitfall 7: Not Handling Missing Registry Gracefully

**What goes wrong:** Hook crashes with jq error if registry missing, blocks Claude Code operation

**Why it happens:** Assumes registry always exists, no null checks

**How to avoid:** Check file exists before jq: `[ ! -f "$REGISTRY_PATH" ] && exit 0`

**Warning signs:** Hook errors on fresh installs, Claude Code sessions fail to start

## Code Examples

Verified patterns from manual testing and existing codebase:

### tmux Pane Capture with Variable Depth

```bash
# Source: tmux man page, verified in tests
PANE_LINES=120  # From hook_settings.pane_capture_lines
SESSION_NAME="warden-main"

PANE_CONTENT=$(tmux capture-pane -pt "${SESSION_NAME}:0.0" -S "-${PANE_LINES}" 2>/dev/null || echo "")

# -p: print to stdout
# -t: target pane (session:window.pane)
# -S: start line (negative = from bottom)
# 2>/dev/null: suppress errors if session missing
# || echo "": fallback to empty string on error
```

### jq Registry Lookup by tmux Session Name

```bash
# Source: jq manual, verified in tests
REGISTRY_PATH="/path/to/recovery-registry.json"
SESSION_NAME="warden-main"

AGENT_DATA=$(jq -r \
  --arg session "$SESSION_NAME" \
  '.agents[] | select(.tmux_session_name == $session) |
   {agent_id, openclaw_session_id, hook_settings}' \
  "$REGISTRY_PATH" 2>/dev/null || echo "")

# --arg: pass bash variable as jq variable
# select(): filter agents by tmux_session_name
# {agent_id, ...}: extract specific fields
# 2>/dev/null || echo "": return empty on error (missing file, parse error)
```

### Context Pressure Extraction from Statusline

```bash
# Source: grep man page, tested with sample statusline output
PANE_CONTENT="$(tmux capture-pane -pt session:0.0 -S -120)"

# Extract percentage from last 5 lines (statusline area)
PERCENTAGE=$(echo "$PANE_CONTENT" | tail -5 | grep -oE '[0-9]{1,3}%' | tail -1 | tr -d '%')

# Determine warning level
THRESHOLD=50  # From hook_settings.context_pressure_threshold

if [ -n "$PERCENTAGE" ]; then
  if [ "$PERCENTAGE" -ge 80 ]; then
    CONTEXT="${PERCENTAGE}% [CRITICAL]"
  elif [ "$PERCENTAGE" -ge "$THRESHOLD" ]; then
    CONTEXT="${PERCENTAGE}% [WARNING]"
  else
    CONTEXT="${PERCENTAGE}% [OK]"
  fi
else
  CONTEXT="unknown"
fi

# grep -oE: only matching part, extended regex
# [0-9]{1,3}%: 1-3 digits followed by %
# tail -1: last match (rightmost percentage)
# tr -d '%': remove % character for numeric comparison
```

### State Detection via Pattern Matching

```bash
# Source: grep man page, tested with sample pane content
PANE_CONTENT="$(tmux capture-pane -pt session:0.0 -S -120)"

STATE="working"  # Default

if echo "$PANE_CONTENT" | grep -Eiq 'Enter to select|numbered.*option'; then
  STATE="menu"
elif echo "$PANE_CONTENT" | grep -Ei 'error|failed|exception' | grep -v 'error handling' >/dev/null; then
  STATE="error"
elif echo "$PANE_CONTENT" | grep -Eiq 'permission|allow|dangerous'; then
  STATE="permission_prompt"
elif echo "$PANE_CONTENT" | grep -Eiq 'What can I help|waiting'; then
  STATE="idle"
fi

# -E: extended regex
# -i: case insensitive
# -q: quiet (exit code only, no output)
# grep -v: exclude lines with "error handling" to reduce false positives
```

### Atomic Registry Update with flock

```bash
# Source: flock man page util-linux 2.39.3, verified in /tmp tests
REGISTRY_PATH="/path/to/recovery-registry.json"
LOCK_PATH="${REGISTRY_PATH}.lock"
AGENT_ID="warden"
SYSTEM_PROMPT="Custom prompt for this agent"

flock "$LOCK_PATH" bash -c "
  jq \
    --arg agent_id '$AGENT_ID' \
    --arg system_prompt '$SYSTEM_PROMPT' \
    '.agents |= map(
      if .agent_id == \$agent_id
      then . + {system_prompt: \$system_prompt, hook_settings: (.hook_settings // {})}
      else .
      end
    )' \
    '$REGISTRY_PATH' > '${REGISTRY_PATH}.tmp' &&
  mv '${REGISTRY_PATH}.tmp' '$REGISTRY_PATH'
"

# flock: exclusive lock on .lock file
# bash -c: run in subshell to ensure atomic tmp+mv
# jq map: update matching agent, preserve others
# .hook_settings // {}: ensure hook_settings exists (auto-populate)
# write to .tmp then mv: atomic replace (prevents partial reads)
```

### OpenClaw Agent Wake (Async Mode)

```bash
# Source: openclaw agent --help output, existing recover-openclaw-agents.sh
OPENCLAW_SESSION_ID="abc-123-def-456"
WAKE_MESSAGE="[SESSION IDENTITY]
agent_id: warden
tmux_session_name: warden-main

[TRIGGER]
response_complete

[STATE HINT]
menu

[PANE CONTENT]
... pane content here ...

[CONTEXT PRESSURE]
72% [WARNING]

[AVAILABLE ACTIONS]
menu-driver.sh warden-main choose <n>"

# Async mode: background call, exit immediately
openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$WAKE_MESSAGE" >/dev/null 2>&1 &

# & backgrounds the process (non-blocking)
# >/dev/null 2>&1 suppresses output (hook doesn't care about response)
# Hook exits 0 immediately after backgrounding call
```

### menu-driver.sh type Action Implementation

```bash
# Source: tmux man page send-keys -l, existing menu-driver.sh structure
type)
  text="${1:-}"
  [ -n "$text" ] || { echo "type requires <text>" >&2; exit 1; }

  tmux send-keys -t "$SESSION:0.0" C-u        # Clear current input line
  tmux send-keys -t "$SESSION:0.0" -l -- "$text"  # Send literal text (no shell expansion)
  tmux send-keys -t "$SESSION:0.0" Enter      # Submit
  ;;

# C-u: Ctrl+U (clear line in most shells/TUIs)
# -l: literal mode (no key name interpretation, no shell expansion)
# --: end of flags (text can start with -)
# Enter: submit the input
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Polling (1s loop) | Event-driven hooks | Claude Code 2024 | 0-1s latency → instant, CPU idle → zero overhead |
| Python for JSON | jq for registry ops | Phase 1 decision | Faster, no dependency, cross-platform |
| Broadcast to all agents | Targeted wake via session ID | Phase 1 design | Reduces noise, precise routing |
| Hardcoded system prompt | External default + per-agent append | Phase 1 schema | Customizable per agent, tracked in git |
| Global config only | Three-tier fallback (per-agent > global > hardcoded) | Phase 1 schema | Fine-grained control, sensible defaults |

**Deprecated/outdated:**
- autoresponder.sh (1s polling, blind option 1 picker) — replaced by intelligent agent decisions via hooks (Phase 4 removal)
- hook-watcher.sh (1s polling, broadcast system events) — replaced by targeted Stop/Notification hooks (Phase 4 removal)
- Python registry manipulation in spawn.sh — replaced by jq + flock (Phase 3 rewrite)
- gsd-session-hook.sh SessionStart launcher — replaced by direct hook registration in settings.json (Phase 2 removal)

## Open Questions

1. **Default pane_capture_lines value**
   - What we know: PRD suggests 120 lines, existing menu-driver snapshot uses -180, statusline.js reads -80
   - What's unclear: Optimal depth balancing context vs. message size for OpenClaw LLM
   - Recommendation: Use 120 lines as default (user decision), allow per-agent override. Most menus fit in 120 lines, reduces token cost vs 180. Agents can request snapshot for deeper context if needed.

2. **Default context_pressure_threshold value**
   - What we know: Claude Code enforces 80% hard limit, statusline.js uses 63% for WARNING color
   - What's unclear: When OpenClaw agents should proactively /compact vs. continue working
   - Recommendation: Use 50% as default threshold (halfway to hard limit), allows ample room for WARNING state before CRITICAL. GSD slash commands handle compaction, threshold is informational only.

3. **--append-system-prompt vs --append-system-prompt-file flag choice**
   - What we know: Both flags supported by Claude Code, -file variant loads from external file
   - What's unclear: Performance difference, reliability when prompt is multi-line with special characters
   - Recommendation: Use --append-system-prompt-file for default prompt (no escaping needed, cleaner), use --append-system-prompt for combined default+agent (requires printf %q escaping). Test both during implementation.

4. **State hint categories completeness**
   - What we know: PRD mentions menu, idle, permission_prompt, error states
   - What's unclear: Are there other useful states OpenClaw agents need to differentiate?
   - Recommendation: Start with 5 states (menu, idle, permission_prompt, error, working), expand based on agent feedback during Phase 2-3 testing. "working" is catch-all default.

5. **Bidirectional mode timeout handling**
   - What we know: Hook timeout is 10 minutes default, OpenClaw agent LLM inference takes 2-10s
   - What's unclear: Should hooks have shorter timeout for bidirectional mode to fail faster?
   - Recommendation: Keep 10-minute timeout (reasonable for slow LLM responses), document in hook_settings that bidirectional mode adds latency. Agents should respond within 30s for good UX.

## Sources

### Primary (HIGH confidence)

- tmux man page (capture-pane, send-keys, display-message) — Verified on Ubuntu 24 tmux 3.4
- jq manual 1.7 (--arg, // fallback, map, select) — https://jqlang.github.io/jq/manual/
- flock man page util-linux 2.39.3 — Verified on Ubuntu 24
- openclaw agent --help output — Verified on OpenClaw 2026.2.16 (d583782)
- Existing gsd-code-skill codebase:
  - menu-driver.sh (tmux send-keys patterns)
  - spawn.sh (registry upsert, session detection)
  - recover-openclaw-agents.sh (agent wake, post-launch commands)
  - ~/.claude/hooks/gsd-statusline.js (context percentage extraction logic)
  - ~/.claude/hooks/gsd-session-hook.sh ($TMUX guard pattern)

### Secondary (MEDIUM confidence)

- PRD.md (hook system architecture, registry schema, wake message format) — Internal project doc
- CONTEXT.md (user decisions from /gsd:discuss-phase) — Phase 1 discussion outcomes
- REQUIREMENTS.md (requirement IDs, traceability) — Internal project doc

### Tertiary (LOW confidence)

- None (all findings verified from primary sources or manual tests)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools verified installed and functional on target Ubuntu 24 system
- Architecture: HIGH - Patterns tested in /tmp scratch scripts, existing codebase provides working examples
- Pitfalls: MEDIUM - Based on common bash/jq mistakes and existing codebase edge cases, not exhaustive production testing

**Research date:** 2026-02-17
**Valid until:** 2026-03-17 (30 days — bash/jq/tmux stable, Claude Code hook system unlikely to change)

**Test verification:**
- tmux capture-pane: Verified up to -200 lines
- tmux send-keys -l: Verified literal mode (no expansion)
- jq three-tier fallback: Verified with complex test case (Warden/Forge/Gideon)
- flock atomic writes: Verified in /tmp with concurrent write simulation
- stdin consumption: Verified non-blocking cat pattern
- $TMUX detection: Verified instant exit (<1ms)
- Context pressure extraction: Verified with sample statusline output
- State detection: Verified with 4 test cases (menu, error, idle, working)

**Dependencies verified:**
- bash 5.2.21 (GNU)
- jq 1.7
- tmux 3.4
- flock (util-linux 2.39.3)
- grep (GNU grep 3.11)
- openclaw 2026.2.16 (d583782)

All dependencies already installed on target system (Ubuntu 24, user forge). No additional installation required.
