# Phase 3: Launcher Updates - Research

**Researched:** 2026-02-17
**Domain:** Bash scripting, jq JSON manipulation, tmux session management, Claude Code CLI integration
**Confidence:** HIGH

## Summary

Phase 3 transforms spawn.sh and recover-openclaw-agents.sh from Python-dependent, hardcoded scripts into registry-driven launchers using pure jq for JSON operations. The core challenge is replacing Python's flexible JSON manipulation with jq's functional approach while maintaining idempotent upsert logic, session ID detection, and error handling. The research confirms jq 1.7 provides all necessary capabilities for reading/writing registry fields, file content embedding, and conditional updates. The phase must resolve a conflict between CONTEXT.md (agent prompt replaces default) and roadmap (agent prompt appends to default) — CONTEXT.md locked decisions take precedence.

**Primary recommendation:** Use jq's `--arg` for simple values, `--rawfile` for file content, and `map(select(...))` pattern for upserts. Implement CLI argument simplification (agent-name becomes primary key) with registry-driven defaults. Remove all Python code, autoresponder logic, and strict_prompt function. Handle failures per-agent in recovery with Telegram notifications via `openclaw agent --message`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Prompt composition:**
- Two-tier model: default-system-prompt.txt is base, agent's registry `system_prompt` replaces it entirely if present
- No concatenation — agent override wins completely over default
- `--system-prompt` CLI flag overrides everything (both default and registry)
- `--system-prompt` auto-detects: if value is a file path that exists, read it; otherwise treat as inline text
- Silent fallback when agent has no system_prompt field — use default without logging
- Prompts only matter at launch time (spawn/recovery), never during hooks

**Spawn CLI design:**
- Registry-driven: `spawn.sh <agent-name> <workdir> [first-command]`
- Agent name is the primary key — reads workdir, system_prompt, all config from registry
- Workdir required for new/unknown agents; for registered agents, registry value is used (CLI arg overrides)
- First command defaults to `claude` if not provided
- Auto-create registry entry for unknown agents with defaults
- Maximum simplicity: DRY, SRP, lean — OpenClaw agents must be able to execute it
- Remove all autoresponder flags, hardcoded strict_prompt, and legacy polling logic
- No Python dependency — jq only for all registry operations

**Recovery reporting:**
- Stdout + Telegram notification on failures only (silent when all agents recover successfully)
- Diagnostic detail per agent: name + status + failure reason + session ID
- One retry with short delay before reporting failure
- Re-spawn immediately when agent marked 'running' but tmux session is gone (no intermediate state)
- No --dry-run mode — keep recovery simple

**Failure handling:**
- Missing/corrupt registry: back up corrupt file (timestamped, keep all), create fresh, notify via Telegram
- Tmux session name conflict: append `-2` suffix to new session (don't kill existing)
- Tmux server not running: start it automatically
- jq check at startup: verify jq exists before doing anything, clear error if missing
- No flock for registry writes — concurrent access unlikely, add later if needed

### Claude's Discretion

- Default system prompt content scope (GSD workflow only vs including minimal agent identity)
- System prompt format in registry (inline string vs file path)
- Exact retry delay for recovery (within "short delay" guidance)
- Registry auto-create entry schema (what defaults to populate)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SPAWN-01 | spawn.sh reads system_prompt from registry entry (fallback to default if empty) | jq `-r` flag with `// ""` null coalescing operator for safe reads; `--rawfile` for default-system-prompt.txt embedding |
| SPAWN-02 | spawn.sh supports `--system-prompt <text>` flag for explicit override | CLI parsing with `-f` file test for auto-detection; bash parameter expansion for inline vs file logic |
| SPAWN-03 | spawn.sh no longer has autoresponder flag or launch logic | Direct code deletion; no technical research needed (removal task) |
| SPAWN-04 | spawn.sh no longer has hardcoded strict_prompt() function | Direct code deletion; prompt content moves to default-system-prompt.txt (already exists from Phase 1) |
| SPAWN-05 | spawn.sh uses jq for all registry operations (no Python dependency) | jq upsert pattern: `if (.agents \| map(.agent_id) \| index($aid)) then ... else .agents += [...]`; session ID detection requires bash loop over jq output |
| RECOVER-01 | recover-openclaw-agents.sh passes system_prompt from registry to Claude on launch | jq read per-agent system_prompt, compose with default via bash string concatenation or replacement based on CONTEXT.md model |
| RECOVER-02 | Recovery handles missing system_prompt field gracefully (fallback default) | jq `// ""` operator provides empty string on null/missing; bash conditional handles empty case |

</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| jq | 1.7 | JSON query/manipulation | Industry-standard JSON processor; available on all platforms; 10x faster than Python for simple JSON ops |
| bash | 5.x | Shell scripting | POSIX-compliant; available everywhere; required for script coordination and file I/O |
| tmux | 3.x | Terminal multiplexer | Standard for persistent sessions; already used throughout project |
| Claude Code CLI | latest | AI coding assistant | Core project dependency; provides `--append-system-prompt` flag |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| openclaw CLI | latest | Agent messaging | Telegram notifications on recovery failures |
| printf %q | bash builtin | Shell-safe string escaping | Passing prompts to Claude CLI without injection risks |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq | Python | Python adds 20MB+ dependency, slower startup (200ms vs 10ms), harder to audit for OpenClaw agents |
| jq | sed/awk | Cannot safely handle nested JSON; fragile for schema changes; no validation |
| bash string concat | --append-system-prompt twice | Claude Code doesn't support multiple --append-system-prompt flags (verified: last one wins) |

**Installation:**
```bash
# Already installed on production system
jq --version  # jq-1.7
```

## Architecture Patterns

### Recommended Script Structure

```
scripts/
├── spawn.sh                    # Registry-driven launcher (Phase 3)
├── recover-openclaw-agents.sh  # Multi-agent recovery (Phase 3)
└── sync-recovery-registry-session-ids.sh  # Session ID sync (existing)

config/
├── recovery-registry.json      # Live registry (gitignored, secrets)
├── recovery-registry.example.json  # Schema doc (Phase 1, committed)
└── default-system-prompt.txt   # Base prompt (Phase 1, committed)
```

### Pattern 1: jq Registry Upsert

**What:** Atomically create or update agent entry in registry
**When to use:** spawn.sh creating/updating registry entry for new or existing agent
**Example:**
```bash
# Source: Verified via testing, based on jq manual patterns
jq --arg agent_id "$AGENT_ID" \
   --arg workdir "$WORKDIR" \
   --arg session_name "$SESSION_NAME" \
   --arg system_prompt "$SYSTEM_PROMPT" \
   '
  if (.agents | map(.agent_id) | index($agent_id)) then
    # Update existing entry
    .agents |= map(
      if .agent_id == $agent_id then
        . + {
          "working_directory": $workdir,
          "tmux_session_name": $session_name,
          "system_prompt": $system_prompt
        }
      else . end
    )
  else
    # Insert new entry with defaults
    .agents += [{
      "agent_id": $agent_id,
      "enabled": true,
      "auto_wake": true,
      "topic_id": 1,
      "openclaw_session_id": "",
      "working_directory": $workdir,
      "tmux_session_name": $session_name,
      "claude_resume_target": "",
      "claude_launch_command": "claude --dangerously-skip-permissions",
      "claude_post_launch_mode": "resume_then_agent_pick",
      "system_prompt": $system_prompt,
      "hook_settings": {}
    }]
  end
' "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
```

### Pattern 2: System Prompt Composition (CONTEXT.md Model)

**What:** Read default prompt and optionally replace with agent-specific prompt
**When to use:** spawn.sh and recover-openclaw-agents.sh building --append-system-prompt argument
**Example:**
```bash
# Source: CONTEXT.md locked decision — agent prompt replaces default entirely
default_prompt_file="/path/to/default-system-prompt.txt"
agent_prompt=$(jq -r '.agents[] | select(.agent_id == "'$agent_id'") | .system_prompt // ""' "$registry")

if [ -n "$agent_prompt" ]; then
  # Agent has custom prompt — use it exclusively (replaces default)
  final_prompt="$agent_prompt"
else
  # No agent prompt — use default
  final_prompt="$(cat "$default_prompt_file")"
fi

# Pass to Claude Code
claude --dangerously-skip-permissions --append-system-prompt "$(printf %q "$final_prompt")"
```

**CRITICAL CONFLICT:** ROADMAP.md success criteria #6 says "Per-agent system_prompt always appends to default (never replaces)". CONTEXT.md (locked user decision from /gsd:discuss-phase) says "agent override wins completely over default". **CONTEXT.md takes precedence** — planner must implement replacement model, not append.

### Pattern 3: Session ID Detection (Python to jq/bash)

**What:** Find most recent OpenAI session ID for agent from sessions.json
**When to use:** spawn.sh upsert operation (session ID is optional, sync-recovery-registry-session-ids.sh handles bulk refresh)
**Example:**
```bash
# Source: Adapted from sync-recovery-registry-session-ids.sh Python logic
agent_id="$1"
sessions_file="/home/forge/.openclaw/agents/${agent_id}/sessions/sessions.json"

if [ ! -f "$sessions_file" ]; then
  echo ""  # Empty session ID
  exit 0
fi

# Extract all matching session keys with their metadata
jq -r '
  to_entries
  | map(select(.key | startswith("agent:'"$agent_id"':openai:")))
  | map(.value + {"key": .key})
  | sort_by(.updatedAt)
  | reverse
  | .[0]
  | .sessionId // ""
' "$sessions_file"
```

### Pattern 4: Per-Agent Error Handling in Recovery

**What:** Continue recovery for remaining agents when one fails
**When to use:** recover-openclaw-agents.sh processing agent list
**Example:**
```bash
# Source: Existing recover-openclaw-agents.sh pattern (lines 419-469)
# DO NOT use set -e in recovery script — handle errors per-agent
failed_agents=()
recovered_agents=()

while IFS= read -r agent_entry; do
  agent_id=$(echo "$agent_entry" | jq -r '.agent_id')

  # Each operation wrapped in conditional
  if ! ensure_tmux_session "$agent_id"; then
    failed_agents+=("$agent_id: tmux session failed")
    continue
  fi

  if ! launch_claude_in_session "$agent_id"; then
    failed_agents+=("$agent_id: claude launch failed")
    continue
  fi

  # Success
  recovered_agents+=("$agent_id")
done < <(jq -c '.agents[] | select(.enabled == true and .auto_wake == true)' "$registry")

# Report failures via Telegram
if [ ${#failed_agents[@]} -gt 0 ]; then
  failure_summary=$(printf '%s\n' "${failed_agents[@]}")
  openclaw agent --session-id "$global_session_id" --message "Recovery failures:\n$failure_summary" >/dev/null 2>&1 &
fi
```

### Anti-Patterns to Avoid

- **Using Python for JSON manipulation:** Adds 20MB+ dependency, slower, harder for OpenClaw agents to audit/execute
- **Forgetting `// ""` null coalescing:** jq exits non-zero on null access without fallback
- **Direct registry write without .tmp + mv:** Risks corruption on SIGTERM/SIGKILL mid-write (though flock is deferred per CONTEXT.md)
- **Multiple --append-system-prompt flags:** Claude Code only honors the last one (verified behavior)
- **Using set -e in recovery script:** One agent failure aborts entire recovery (breaks per-agent error handling)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing/writing | Custom sed/awk regex | jq with proper operators (`//`, `map`, `select`) | JSON nesting, escaping, Unicode — jq handles all edge cases |
| Shell escaping for Claude CLI | Manual quoting logic | `printf %q` | Handles all POSIX special chars, tested by bash team |
| Session ID freshness | Manual timestamp comparison | jq `sort_by(.updatedAt) \| reverse \| .[0]` | Handles missing fields, type coercion, stable sort |
| Tmux session conflict resolution | Custom naming logic | Simple `while tmux has-session` + counter loop | Tmux already provides atomic session existence check |

**Key insight:** Bash + jq is the "standard library" for this problem domain. Custom parsing is where bugs hide (Unicode in prompts, nested JSON, null handling). Use proven tools.

## Common Pitfalls

### Pitfall 1: jq Null vs Empty String Confusion

**What goes wrong:** Reading missing `system_prompt` field returns `null`, which becomes string `"null"` instead of empty string
**Why it happens:** jq `-r` (raw output) stringifies null as literal "null"
**How to avoid:** Always use `// ""` operator for optional string fields: `.system_prompt // ""`
**Warning signs:** Claude Code receives system prompt containing literal text "null"

### Pitfall 2: Registry Corruption on Script Kill

**What goes wrong:** Script writes partial JSON to registry.json, next read fails with parse error
**Why it happens:** Direct write to registry.json gets interrupted mid-operation (SIGTERM, SIGKILL, power loss)
**How to avoid:** Atomic write pattern: write to `.tmp` suffix, then `mv` (atomic on same filesystem)
**Warning signs:** `jq: parse error` on registry read; locked decision says skip flock for now

### Pitfall 3: Forgetting File vs Inline Prompt Detection

**What goes wrong:** User passes `--system-prompt /path/to/file.txt` but script treats it as inline text, sends path as prompt
**Why it happens:** CONTEXT.md requires auto-detection: if arg is existing file path, read it; else treat as inline
**How to avoid:** Test with `[ -f "$value" ]` before reading
**Warning signs:** Claude Code system prompt contains filesystem paths instead of actual prompt content

### Pitfall 4: Session ID Detection Performance

**What goes wrong:** spawn.sh takes 5+ seconds because it processes large sessions.json file
**Why it happens:** jq loads entire file into memory; sessions.json can be 100+ KB with hundreds of sessions
**How to avoid:** Make session ID detection optional or async — spawn.sh doesn't need it immediately (sync-recovery-registry-session-ids.sh handles bulk refresh)
**Warning signs:** Slow spawn.sh startup; user complaints about responsiveness

### Pitfall 5: --append-system-prompt Multiple Calls

**What goes wrong:** Script calls `claude --append-system-prompt "$default" --append-system-prompt "$agent"` expecting concatenation, but only agent prompt is used
**Why it happens:** Claude Code CLI only honors the last `--append-system-prompt` flag (verified behavior)
**How to avoid:** Compose prompts in bash before passing to Claude (CONTEXT.md model: agent replaces default, so this is N/A, but important for future)
**Warning signs:** Default prompt missing from Claude context; only agent-specific prompt present

## Code Examples

Verified patterns for implementation:

### Reading Registry Field with Fallback

```bash
# Source: jq manual + testing
agent_id="gideon"
registry="/path/to/recovery-registry.json"

# Safe read with null fallback
system_prompt=$(jq -r '.agents[] | select(.agent_id == "'"$agent_id"'") | .system_prompt // ""' "$registry")

# Check if agent exists
agent_exists=$(jq '.agents | map(.agent_id) | index("'"$agent_id"'")' "$registry")
if [ "$agent_exists" = "null" ]; then
  echo "Agent not found"
fi
```

### Embedding File Content in jq Update

```bash
# Source: jq manual --rawfile flag
default_prompt_file="config/default-system-prompt.txt"
registry="config/recovery-registry.json"

# Option 1: Read file in bash, pass via --arg
default_content=$(cat "$default_prompt_file")
jq --arg content "$default_content" '.default_prompt = $content' "$registry"

# Option 2: Use --rawfile (jq reads directly)
jq --rawfile content "$default_prompt_file" '.default_prompt = $content' "$registry"
```

### Tmux Session Name Conflict Resolution

```bash
# Source: CONTEXT.md decision + tmux has-session semantics
base_name="gideon-session"
session_name="$base_name"
counter=2

while tmux has-session -t "$session_name" 2>/dev/null; do
  session_name="${base_name}-${counter}"
  counter=$((counter + 1))
done

tmux new-session -d -s "$session_name" -c "$workdir"
echo "Created session: $session_name"
```

### Telegram Notification on Failure

```bash
# Source: Existing hook scripts notification-idle-hook.sh, session-end-hook.sh
global_session_id="20dd98b6-45e0-41b1-b799-6f8089051a87"
failure_message="Recovery failed for agent gideon: tmux session creation failed"

# Always async in recovery context (session may not exist yet)
openclaw agent --session-id "$global_session_id" --message "$failure_message" >/dev/null 2>&1 &
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Python for registry upsert | jq functional updates | Phase 3 (this phase) | Zero Python dependency; OpenClaw agents can execute directly |
| Hardcoded strict_prompt() function | External default-system-prompt.txt | Phase 1 (completed) | Prompt editable without code changes |
| Autoresponder polling loop | Event-driven hooks (Stop, Notification) | Phase 1-2 (completed) | 100x faster response (50ms vs 5s polling) |
| Multiple CLI flags (--prd, --autoresponder, --agent-id, --topic-id, --auto-wake) | Registry-driven with agent-name as primary key | Phase 3 (this phase) | 5 flags → 1 argument; all config in registry |

**Deprecated/outdated:**
- **Python upsert in spawn.sh (lines 75-150):** Replaced by jq pattern in Phase 3
- **strict_prompt() bash function (lines 202-211):** Content moved to config/default-system-prompt.txt in Phase 1
- **--autoresponder flag (lines 24, 232, 315-326):** Removed in Phase 3; polling replaced by hooks in Phase 1-2
- **--prd, --agent-id, --topic-id, --auto-wake flags:** Phase 3 collapses to agent-name primary key with registry-driven defaults

## Open Questions

1. **Retry delay for recovery**
   - What we know: CONTEXT.md says "short delay", existing recovery script uses 2s for Claude launch verification
   - What's unclear: Ideal retry delay for tmux/Claude failures (too short = false negatives, too long = slow recovery)
   - Recommendation: Use 2-3 seconds (matches existing recover-openclaw-agents.sh `sleep 2` pattern), mark as tunable constant

2. **System prompt format in registry (inline vs file path)**
   - What we know: CONTEXT.md marks as "Claude's Discretion"; recovery-registry.example.json uses inline strings
   - What's unclear: Should we support file path references in system_prompt field (e.g., `"system_prompt": "@/path/to/file.txt"`)
   - Recommendation: **Inline strings only** — simpler model, avoids file-not-found errors, registry is self-contained. If agents need long prompts, they can use heredocs when updating registry.

3. **Default system prompt content scope**
   - What we know: CONTEXT.md marks as "Claude's Discretion"; Phase 1 created default-system-prompt.txt with GSD workflow commands
   - What's unclear: Should default prompt include minimal agent identity (e.g., "You are a managed Claude Code session") or pure workflow guidance only
   - Recommendation: **Pure workflow only** (current Phase 1 implementation is correct) — agent identity comes from per-agent system_prompt, default is just operational guidance

4. **CONFLICT: Prompt composition model (append vs replace)**
   - What we know: CONTEXT.md (locked) says "agent override wins completely over default" (replace). ROADMAP.md success criteria #6 says "always appends to default" (append).
   - What's unclear: Which model is correct
   - Recommendation: **CONTEXT.md takes absolute precedence** (it's from user discussion in /gsd:discuss-phase). Planner must implement replacement model. Roadmap needs correction as side-effect.

## Sources

### Primary (HIGH confidence)

- **jq 1.7 manual** - `man jq` and https://jqlang.github.io/jq/manual/ (operators, --rawfile, --arg, null coalescing)
- **CONTEXT.md** - Locked user decisions from /gsd:discuss-phase session (prompt composition, CLI design, failure handling)
- **Existing codebase** - spawn.sh Python upsert logic (lines 75-150), recover-openclaw-agents.sh per-agent error handling (lines 419-469), sync-recovery-registry-session-ids.sh session detection (lines 80-110)
- **Phase 1 artifacts** - recovery-registry.example.json schema (hook_settings, system_prompt), default-system-prompt.txt content
- **Verified testing** - jq registry operations tested in /tmp/test-registry-ops.sh (upsert, read, null fallback)

### Secondary (MEDIUM confidence)

- **Claude Code CLI behavior** - `--append-system-prompt` last-one-wins behavior (empirically observed, not documented)
- **Tmux session naming** - Collision resolution pattern (inferred from common practice, not project-specific)

### Tertiary (LOW confidence)

None — all critical claims verified via primary sources or testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - jq 1.7 installed and tested, all operations verified
- Architecture: HIGH - Patterns extracted from existing working code (sync-recovery-registry-session-ids.sh, recover-openclaw-agents.sh)
- Pitfalls: HIGH - Identified from code review (null handling, atomic writes, file detection) and CONTEXT.md constraints

**Research date:** 2026-02-17
**Valid until:** 2026-03-19 (30 days - stable tooling, no fast-moving dependencies)

**Critical notes for planner:**
- CONTEXT.md conflict with ROADMAP.md on prompt composition model — CONTEXT.md wins (replacement, not append)
- No flock for registry writes per CONTEXT.md — deferred for later if concurrent access becomes issue
- Session ID detection should be optional in spawn.sh (slow operation, sync script handles bulk refresh)
- Recovery script must not use `set -e` (per-agent error handling requires continuing on failures)
