# Stack Research: Stop Hook Integration

**Domain:** Event-driven agent control for Claude Code sessions
**Researched:** 2026-02-17
**Confidence:** HIGH

## Executive Summary

This milestone adds event-driven agent control to replace polling-based menu detection. The stack remains bash-only with no new runtime dependencies. Changes are surgical: Claude Code Stop hook integration, tmux freeform text injection, and OpenClaw agent messaging. All components are already installed and version-verified.

**Key Finding:** Claude Code Stop hook provides native stdin JSON and decision control. No wrapper needed. OpenClaw agent CLI supports direct session messaging. tmux send-keys -l handles literal text injection. All pieces fit existing architecture.

## Core Technologies (No Changes)

| Technology | Version | Current Usage | Why It Stays |
|------------|---------|---------------|--------------|
| Bash | 5.x (Ubuntu 24 default) | All scripts use bash with set -euo pipefail | Universal, deterministic, zero token cost |
| tmux | 3.4 | Session management, pane capture, input injection | Core multiplexer, proven reliable |
| Claude Code CLI | 2.1.44 | Session runtime with --append-system-prompt | Latest stable, hook support confirmed |
| OpenClaw CLI | 2026.2.16 | Agent messaging, event wake | Current production version |
| jq | 1.7 | JSON parsing in bash scripts | Ubiquitous JSON CLI tool |
| ~~Python 3~~ | ~~3.x (embedded)~~ | ~~Recovery registry upsert only~~ | **REMOVED** — replaced by jq for all registry operations (cross-platform, no dependency) |

**Rationale:** All existing. No upgrades needed. No new dependencies.

## Stack Additions for Stop Hook

### 1. Claude Code Stop Hook (Native Feature)

**Version:** Claude Code 2.1.44 (confirmed hook support)
**Purpose:** Event-driven session state capture when Claude finishes responding
**Why:** Replaces 1-second polling loop with zero-latency event notification

#### stdin JSON Schema

Official schema from Claude Code hooks reference (code.claude.com/docs/en/hooks):

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/working/directory",
  "permission_mode": "default",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
```

**Critical fields:**
- `session_id`: Claude Code's internal session identifier (not used; we use tmux session name)
- `stop_hook_active`: Boolean guard to prevent infinite loops (MUST check this)
- `hook_event_name`: Always "Stop" for this event

**Integration pattern:**
```bash
#!/usr/bin/env bash
HOOK_INPUT=$(cat)  # Read stdin JSON
STOP_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
[ "$STOP_ACTIVE" = "true" ] && exit 0  # Guard: already processing a stop hook
```

#### stdout JSON Schema (Decision Control)

When hook returns JSON to stdout with exit code 0:

```json
{
  "decision": "block",
  "reason": "Must be provided when blocking Claude from stopping"
}
```

**Fields:**
- `decision`: Optional. "block" prevents Claude from stopping. Omit to allow stop.
- `reason`: Required when decision is "block". Tells Claude why to continue.

**Integration pattern for this skill:**
Hybrid mode: Default async (background message to OpenClaw → exit 0 immediately). Optional bidirectional per-agent (wait for OpenClaw response → return decision:block with reason → Claude continues with injected instruction).

```bash
# Async mode (default):
exit 0  # No JSON output = allow Claude to stop normally

# Bidirectional mode (per-agent via hook_settings.hook_mode):
# Wait for OpenClaw response, then:
echo '{"decision":"block","reason":"OpenClaw instruction here"}' && exit 0
```

#### Hook Configuration (settings.json)

Location: `~/.claude/settings.json`

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/stop-hook.sh\"",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

**Fields:**
- `type`: "command" (runs shell command)
- `command`: Absolute path to hook script
- `timeout`: Optional, seconds (default: 600)

**Why absolute path:** Hook runs in session cwd, not skill directory. Must be absolute.

**No matcher:** Stop event doesn't support matchers. Always fires on every occurrence.

### 2. tmux send-keys -l (Literal Mode)

**Version:** tmux 3.4 (confirmed flag support)
**Purpose:** Inject freeform text without key name interpretation
**Why:** Menu options and slash commands may contain characters that tmux interprets as key names

#### Command Pattern

```bash
tmux send-keys -t "$SESSION:0.0" -l -- "$TEXT"
tmux send-keys -t "$SESSION:0.0" Enter
```

**Flags:**
- `-t "$SESSION:0.0"`: Target pane (session:window.pane)
- `-l`: Literal mode - treat all arguments as UTF-8 characters, not key names
- `--`: End of flags (safety for text starting with -)
- `Enter`: Sent separately (key name, not literal)

**Why -l:** Without -l, tmux parses text for key names like "Space", "C-a", "NPage". With -l, "Space" is sent as literal string "Space", not a space character.

**Use case:** `/gsd:new-project @PRD.md` contains no special keys, but -l prevents any interpretation.

**Existing usage without -l:**
```bash
# spawn.sh line 312 (works because slash commands have no ambiguous strings)
tmux send-keys -t "$session_name:0.0" -l -- "$first_cmd"
```

**New usage in menu-driver.sh type action:**
```bash
type)
  text="${1:-}"
  [ -n "$text" ] || { echo "type requires <text>" >&2; exit 1; }
  tmux send-keys -t "$SESSION:0.0" C-u       # Clear line first
  tmux send-keys -t "$SESSION:0.0" -l -- "$text"
  tmux send-keys -t "$SESSION:0.0" Enter
  ;;
```

**Why C-u first:** Clears any partial input before sending text. Atomic operation.

### 3. OpenClaw agent --session-id (Direct Session Messaging)

**Version:** OpenClaw 2026.2.16 (confirmed flag support)
**Purpose:** Send message directly to specific OpenClaw agent session
**Why:** Precise agent targeting instead of broadcast via openclaw system event

#### CLI Schema

```bash
openclaw agent --session-id <uuid> --message "<text>" [--json]
```

**Required flags:**
- `--session-id <uuid>`: Explicit OpenClaw session UUID (from recovery registry)
- `--message "<text>"`: Message body for the agent

**Optional flags:**
- `--json`: Output result as JSON (not needed for background fire-and-forget)
- `--deliver`: Send reply back to channel (not needed, agent decides)
- `--thinking <level>`: Override thinking level (not needed, use session default)

**Integration pattern:**
```bash
# From stop-hook.sh (backgrounded, fire-and-forget)
openclaw agent \
  --session-id "$OPENCLAW_SESSION_ID" \
  --message "$(cat <<EOF
Claude Code session $TMUX_SESSION paused. Current state:

$PANE_CONTENT

Available actions:
- menu-driver.sh $TMUX_SESSION choose <n>
- menu-driver.sh $TMUX_SESSION type <text>
- menu-driver.sh $TMUX_SESSION clear_then <command>
EOF
)" >/dev/null 2>&1 &
```

**Why background:** Hook must exit immediately. OpenClaw call takes 1-2s. Background with &, discard output.

**Message format:** Freeform text. Agent sees it as user message in conversation thread.

**Session ID source:** Recovery registry JSON at `config/recovery-registry.json`:

```bash
OPENCLAW_SESSION_ID=$(jq -r \
  --arg tmux_session "$TMUX_SESSION" \
  '.agents[] | select(.tmux_session_name == $tmux_session) | .openclaw_session_id // empty' \
  "$REGISTRY_FILE")
```

**Fallback if missing:** Exit 0 (non-managed session, no agent to notify).

### 4. Recovery Registry Schema Addition

**File:** `config/recovery-registry.json`
**Format:** JSON
**Purpose:** Map tmux sessions to OpenClaw agents and their configurations

#### New Field: system_prompt

```json
{
  "global_status_openclaw_session_id": "uuid",
  "global_status_openclaw_session_key": "agent:...",
  "hook_settings": {
    "pane_capture_lines": 120,
    "context_pressure_threshold": 50,
    "autocompact_pct": 50,
    "hook_mode": "async"
  },
  "agents": [
    {
      "agent_id": "warden",
      "enabled": true,
      "auto_wake": true,
      "topic_id": 1,
      "openclaw_session_id": "11111111-2222-3333-4444-555555555555",
      "working_directory": "/home/forge/workspace",
      "tmux_session_name": "warden-main",
      "claude_resume_target": "",
      "claude_launch_command": "claude --dangerously-skip-permissions",
      "claude_post_launch_mode": "resume_then_agent_pick",
      "system_prompt": "Prefer /gsd:quick for small tasks, /gsd:debug for bugs. Make atomic commits.",
      "hook_settings": {
        "pane_capture_lines": 150,
        "hook_mode": "bidirectional"
      }
    }
  ]
}
```

**New fields:**
- `system_prompt` (top-level per agent): String. Custom system prompt appended to default. Empty = default only.
- `hook_settings` (global at root): Default hook configuration for all agents
- `hook_settings` (per agent): Override specific fields (three-tier fallback: per-agent > global > hardcoded, per-field merge)
- `hook_settings.pane_capture_lines`: Number. Lines of pane to capture.
- `hook_settings.context_pressure_threshold`: Number. Percentage to trigger warning.
- `hook_settings.autocompact_pct`: Number. CLAUDE_AUTOCOMPACT_PCT_OVERRIDE value.
- `hook_settings.hook_mode`: "async" | "bidirectional". Communication mode.

**Why:** Replace hardcoded strict_prompt() in spawn.sh. Per-agent customization without code changes. Strict known fields only.

**Default when empty:**
Stored in `config/default-system-prompt.txt` (tracked in git). Minimal GSD workflow guidance:
- /gsd:* commands, /clear, /resume
- No role/personality (agents get that from SOUL.md and AGENTS.md)
- Per-agent system_prompt always appends to this default, never replaces

**Usage in spawn.sh:**
```bash
# Read default from file
DEFAULT_PROMPT="$(cat config/default-system-prompt.txt)"

# Read per-agent override from registry
AGENT_PROMPT=$(jq -r \
  --arg agent_id "$effective_agent_id" \
  '.agents[] | select(.agent_id == $agent_id) | .system_prompt // ""' \
  "$registry_file_path")

# Combine: default + per-agent (always append, never replace)
FULL_PROMPT="${DEFAULT_PROMPT}"
[ -n "$AGENT_PROMPT" ] && FULL_PROMPT="${FULL_PROMPT}\n\n${AGENT_PROMPT}"

claude_cmd="claude --dangerously-skip-permissions --append-system-prompt $(printf %q "$FULL_PROMPT")"
```

**jq upsert (replaces Python):**
```bash
# Add system_prompt with default empty string if missing
jq --arg agent_id "$AGENT_ID" \
  '(.agents[] | select(.agent_id == $agent_id)) += {system_prompt: (.system_prompt // "")}' \
  "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"
```

**NOTE:** Per discussion decision, ALL registry operations use jq. Python upsert is removed.

## Supporting Libraries (No Changes)

| Library | Version | Purpose | When Used |
|---------|---------|---------|-----------|
| sha1sum | coreutils | Pane content hashing for deduplication | hook-watcher.sh (being removed) |
| grep | GNU grep | Pattern matching in captured panes | All monitoring scripts |
| ~~Python json~~ | ~~stdlib~~ | ~~Recovery registry JSON manipulation~~ | **REMOVED** — jq handles all registry read/write operations |

**Rationale:** All standard Unix tools. No installation needed.

## Development Tools (No Changes)

| Tool | Purpose | Notes |
|------|---------|-------|
| shellcheck | Bash linting | Optional, not required for runtime |
| chmod +x | Script permissions | Required for new stop-hook.sh |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Node.js for hook | Adds dependency, startup latency | Bash (already used everywhere) |
| Python for hook | Slower stdin read, extra process | Bash with jq (2ms vs 50ms) |
| Polling with sleep 1 | CPU waste, 1s delay | Stop hook (0ms event latency) |
| openclaw system event | Broadcasts to all agents | openclaw agent --session-id (precise) |
| Claude Code Plugin hook | Bug: JSON output not captured | Inline settings.json hook (works) |

**Critical:** Do NOT use plugin-based Stop hook. Known bug in Claude Code 2.1.44 where plugin hooks execute but JSON output is not captured. Inline settings.json hooks work correctly.

## Stack Patterns by Variant

**If managing multiple agents:**
- Use recovery registry with unique agent_id per tmux session
- Each agent has its own openclaw_session_id and system_prompt
- Stop hook looks up agent by tmux_session_name

**If single-agent use:**
- Recovery registry optional (Stop hook can exit early if not found)
- Can still use spawn.sh with --system-prompt override
- Stop hook becomes no-op for unregistered sessions

**If remote OpenClaw gateway:**
- No change needed, openclaw agent CLI uses gateway automatically
- Backgrounding prevents hook timeout during network latency

**If local OpenClaw (no gateway):**
- Use openclaw agent --local flag (not recommended, requires API keys in shell)
- Better: keep gateway pattern even for local dev

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| Claude Code 2.1.44 | tmux 3.4 | Confirmed compatible, no known issues |
| Claude Code 2.1.44 | OpenClaw 2026.2.16 | Confirmed compatible, agent CLI stable |
| tmux 3.4 | bash 5.x | Standard compatibility |
| jq 1.7 | bash 5.x | Standard compatibility |

## Integration Checklist

- [ ] Claude Code Stop hook in `~/.claude/settings.json`
- [ ] Stop hook script at `scripts/stop-hook.sh` (chmod +x)
- [ ] menu-driver.sh type action added
- [ ] spawn.sh updated to read system_prompt from registry
- [ ] recover-openclaw-agents.sh updated to pass system_prompt to launch
- [ ] Recovery registry schema includes system_prompt field
- [ ] SessionStart hook removed (gsd-session-hook.sh cleanup)
- [ ] autoresponder.sh and hook-watcher.sh deleted

## Sources

**HIGH confidence:**
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - Official Stop hook stdin/stdout JSON schema, hook configuration format, exit code behavior
- [Claude Code Hooks Guide](https://aiorg.dev/blog/claude-code-hooks) - Stop hook patterns, stop_hook_active guard, infinite loop prevention
- [ClaudeLog Hooks](https://claudelog.com/mechanics/hooks/) - Hook lifecycle, decision control patterns
- [Claude Code Hook Control Flow](https://stevekinney.com/courses/ai-development/claude-code-hook-control-flow) - Hook execution model, JSON parsing
- OpenClaw CLI help output - agent --session-id flag schema, required/optional parameters
- tmux man page - send-keys -l flag behavior, literal mode vs key name mode
- spawn.sh source - Existing --append-system-prompt pattern, printf %q escaping
- hook-watcher.sh source - Existing tmux capture-pane pattern, pane signature deduplication
- recovery-registry.example.json - Current JSON schema, agent entry structure

**MEDIUM confidence:**
- [GitHub Issue #10875](https://github.com/anthropics/claude-code/issues/10875) - Plugin hook JSON output bug (workaround: use inline hooks)

**Version verification:**
- Claude Code: 2.1.44 (confirmed via claude --version)
- OpenClaw: 2026.2.16 (confirmed via openclaw --version)
- tmux: 3.4 (confirmed via tmux -V)
- jq: 1.7 (confirmed via jq --version)

---
*Stack research for: gsd-code-skill Stop hook integration*
*Researched: 2026-02-17*
*Confidence: HIGH - all components verified in production environment*
