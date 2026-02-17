# Architecture Research: Stop Hook Integration

**Domain:** Hook-driven OpenClaw agent control for Claude Code sessions
**Researched:** 2026-02-17
**Confidence:** HIGH

## Executive Summary

The Stop hook integration replaces polling-based menu detection (autoresponder.sh, hook-watcher.sh) with event-driven agent control. When Claude Code finishes a response, the Stop hook fires, captures the TUI state, and sends it directly to the correct OpenClaw agent via `openclaw agent --session-id`. The agent makes intelligent decisions and responds via menu-driver.sh.

This is a **subsequent milestone** adding to existing architecture. The integration is clean: new hook replaces old polling scripts, existing components (menu-driver.sh, recovery scripts, spawn.sh) get minor enhancements.

## Current Architecture (Before Stop Hook)

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Claude Code Session                          │
│  (tmux pane running Claude Code TUI)                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Interactive Menu Appears                                        │
│         ↓                                                        │
│  ┌──────────────────────┐      ┌──────────────────────┐         │
│  │  autoresponder.sh    │  OR  │  hook-watcher.sh     │         │
│  │  (1s polling)        │      │  (1s polling)        │         │
│  │  Picks option 1      │      │  Wakes all agents    │         │
│  └──────────────────────┘      └──────────────────────┘         │
│         ↓                                ↓                       │
│  tmux send-keys              openclaw system event              │
│  (blind choice)              (broadcast, no context)            │
└─────────────────────────────────────────────────────────────────┘

Supporting Components:
┌──────────────────────────────────────────────────────────────┐
│ spawn.sh          - Session launcher with registry upsert    │
│ menu-driver.sh    - Atomic TUI actions (choose, enter, etc)  │
│ recovery-*.sh     - Multi-agent recovery after reboot/OOM    │
│ registry.json     - Agent metadata, session IDs, config      │
└──────────────────────────────────────────────────────────────┘
```

### Current Flow

1. spawn.sh creates tmux session, launches Claude Code, upserts registry
2. gsd-session-hook.sh (SessionStart hook) spawns hook-watcher.sh background process
3. autoresponder.sh OR hook-watcher.sh polls tmux pane every 1s
4. autoresponder: picks option 1 blindly
5. hook-watcher: wakes ALL OpenClaw agents when menu detected
6. Agent receives broadcast, manually inspects pane via menu-driver.sh snapshot

### Problems

- **Polling overhead:** Two separate 1s polling loops per session
- **Broadcast spam:** hook-watcher wakes ALL agents, not specific owner
- **No context:** autoresponder is blind, watcher provides no TUI snapshot
- **Latency:** 0-1s delay before detection, then agent must request snapshot
- **Duplicate detection:** Complex SHA1 signature tracking to avoid repeat wakes

## New Architecture (Stop Hook Integration)

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Claude Code Session                          │
│  (tmux pane running Claude Code TUI)                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Claude finishes responding                                      │
│         ↓                                                        │
│  Stop hook fires → stop-hook.sh                                  │
│         ↓                                                        │
│  Read stdin JSON (session_id, stop_hook_active guard)           │
│  Check guards (not in tmux? not in registry? → exit 0)          │
│  Capture pane (last 120 lines)                                  │
│  Extract context pressure from statusline                       │
│  Look up agent in registry by tmux_session_name                 │
│         ↓                                                        │
│  openclaw agent --session-id <uuid> --message <snapshot>        │
│  (backgrounded, exits immediately)                              │
└─────────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────┐
│              OpenClaw Agent (Gideon/Warden/Forge)                │
│                                                                   │
│  Receives: pane snapshot + available actions + context pressure │
│  Decides: intelligent choice based on full context              │
│         ↓                                                        │
│  menu-driver.sh <session> choose <n>                             │
│       OR                                                         │
│  menu-driver.sh <session> type <text>                            │
│       OR                                                         │
│  menu-driver.sh <session> clear_then <command>                   │
└─────────────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────┐
│              Claude Code receives input, continues               │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Changes |
|-----------|----------------|---------|
| stop-hook.sh | **NEW** - Stop hook entry point, guards check, pane capture, agent lookup, OpenClaw wake, hybrid mode | Replaces autoresponder.sh + hook-watcher.sh |
| notification-idle-hook.sh | **NEW** - Notification hook for idle_prompt events | Notifies OpenClaw when Claude waits for user input |
| notification-permission-hook.sh | **NEW** - Notification hook for permission_prompt events | Future-proofing for fine-grained permission handling |
| session-end-hook.sh | **NEW** - SessionEnd hook | Notifies OpenClaw immediately when session terminates |
| pre-compact-hook.sh | **NEW** - PreCompact hook | Captures state before context compaction |
| config/default-system-prompt.txt | **NEW** - Default system prompt file | Tracked in git, minimal GSD workflow guidance |
| menu-driver.sh | **MODIFIED** - Atomic TUI actions | Add `type <text>` action for freeform input |
| spawn.sh | **MODIFIED** - Session launcher | Remove autoresponder logic, add --system-prompt flag, read system_prompt from registry, jq replaces Python |
| recover-openclaw-agents.sh | **MODIFIED** - Multi-agent recovery | Extract system_prompt from registry, pass via --append-system-prompt, jq replaces Python |
| recovery-registry.json | **MODIFIED** - Agent metadata store | Add system_prompt field, hook_settings object (global + per-agent) |
| ~/.claude/settings.json | **MODIFIED** - Claude Code global hooks | Add all hooks (Stop, Notification, SessionEnd, PreCompact), remove gsd-session-hook.sh from SessionStart |
| autoresponder.sh | **DELETED** - Polling-based menu responder | Obsolete |
| hook-watcher.sh | **DELETED** - Polling-based menu detector | Obsolete |
| gsd-session-hook.sh | **DELETED** - SessionStart launcher for hook-watcher | Obsolete |

## Integration Points

### 1. Stop Hook → Registry Lookup

**File:** stop-hook.sh (NEW)

**Integration:**
- Reads `$TMUX` env to get tmux session name via `tmux display-message -p '#S'`
- Uses `jq` to query `config/recovery-registry.json` for agent with matching `tmux_session_name`
- Extracts `openclaw_session_id` from matched agent entry
- Exits 0 if no match (non-managed session, fast path)

**Data flow:**
```bash
SESSION="$(tmux display-message -p '#S')"
AGENT_ENTRY="$(jq -r --arg session "$SESSION" \
  '.agents[] | select(.tmux_session_name == $session)' \
  "$REGISTRY_PATH")"
OPENCLAW_SESSION_ID="$(echo "$AGENT_ENTRY" | jq -r '.openclaw_session_id')"
```

### 2. Stop Hook → OpenClaw Agent

**File:** stop-hook.sh (NEW)

**Integration:**
- Captures pane via `tmux capture-pane -pt "$SESSION:0.0" -S -120`
- Extracts context pressure percentage from statusline (same regex as old hook-watcher.sh)
- Builds structured message with pane content + context warning + available menu-driver.sh actions
- Calls `openclaw agent --session-id "$OPENCLAW_SESSION_ID" --message "$MESSAGE"` in background with `&`
- Exits 0 immediately (never blocks)

**Guard sequence:**
1. Check stdin JSON `stop_hook_active` field (infinite loop prevention)
2. Check `$TMUX` env (exit if not in tmux)
3. Check registry match (exit if not a managed session)

### 3. OpenClaw Agent → menu-driver.sh

**File:** menu-driver.sh (MODIFIED)

**New action:**
```bash
type)
  text="${1:-}"
  [ -n "$text" ] || { echo "type requires <text>" >&2; exit 1; }
  tmux send-keys -t "$SESSION:0.0" C-u
  tmux send-keys -t "$SESSION:0.0" -l -- "$text"
  tmux send-keys -t "$SESSION:0.0" Enter
  ;;
```

**Existing actions (unchanged):**
- `snapshot` - Print last 180 lines from pane
- `enter` - Press Enter once
- `esc` - Press Esc once
- `clear_then <command>` - Run /clear then slash command
- `choose <n>` - Type option number + Enter
- `submit` - Tab then Enter

**Integration:** Agent receives available actions in wake message, calls appropriate action based on decision.

### 4. spawn.sh → Registry System Prompt

**File:** spawn.sh (MODIFIED)

**Changes:**
- Remove `--autoresponder` flag and `enable_autoresponder` variable
- Remove hardcoded `strict_prompt()` function
- Add `--system-prompt <text>` flag for explicit override
- After registry upsert, read `system_prompt` field from registry entry
- Fall back to sensible default if registry field empty
- Use jq for registry upsert (replaces Python)

**Default system prompt:**
Stored in `config/default-system-prompt.txt` (tracked in git). Per-agent system_prompt always appends to default, never replaces.

**Data flow:**
```bash
# Read default from external file
DEFAULT_PROMPT="$(cat config/default-system-prompt.txt)"

# Read per-agent override from registry via jq
AGENT_PROMPT="$(jq -r --arg agent_id "$effective_agent_id" \
  '.agents[] | select(.agent_id == $agent_id) | .system_prompt // ""' \
  "$registry_path")"

# Combine: default always included, per-agent appended
FULL_PROMPT="${DEFAULT_PROMPT}"
[ -n "$AGENT_PROMPT" ] && FULL_PROMPT="${FULL_PROMPT}\n\n${AGENT_PROMPT}"

claude_cmd="claude --dangerously-skip-permissions --append-system-prompt $(printf %q "$FULL_PROMPT")"
```

### 5. recover-openclaw-agents.sh → System Prompt Injection

**File:** recover-openclaw-agents.sh (MODIFIED)

**Changes:**
- Extract `system_prompt` from each agent's registry entry via jq (replaces Python parser)
- Pass system_prompt to `ensure_claude_is_running_in_tmux()` function
- Append via `--append-system-prompt` when launching Claude (default + per-agent combined)
- Keep existing post-launch command logic (`/resume` or `/gsd:resume-work`)
- Simplify `send_recovery_instruction_to_openclaw_session` note that Stop hook now active

**Data flow:**
```bash
# Extract per-agent system_prompt via jq (replaces Python parser)
AGENT_PROMPT="$(echo "$AGENT_JSON" | jq -r '.system_prompt // ""')"

# In ensure_claude_is_running_in_tmux (new parameter)
local system_prompt="$4"  # New parameter
local default_prompt="$(cat config/default-system-prompt.txt)"
local full_prompt="${default_prompt}"
[ -n "$system_prompt" ] && full_prompt="${full_prompt}\n\n${system_prompt}"

local claude_cmd="${base_claude_launch_command} --append-system-prompt $(printf %q "$full_prompt")"
```

### 6. ~/.claude/settings.json → Hook Registration

**File:** ~/.claude/settings.json (MODIFIED)

**Changes:**
- Add Stop hook calling stop-hook.sh
- Remove gsd-session-hook.sh from SessionStart hooks

**Before:**
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "node \"/home/forge/.claude/hooks/gsd-check-update.js\"" },
          { "type": "command", "command": "bash \"/home/forge/.claude/hooks/gsd-session-hook.sh\"" }
        ]
      }
    ]
  }
}
```

**After:**
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "node \"/home/forge/.claude/hooks/gsd-check-update.js\"" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/stop-hook.sh\"" }
        ]
      }
    ]
  },
  "statusLine": { "type": "command", "command": "node \"/home/forge/.claude/hooks/gsd-statusline.js\"" },
  "enabledPlugins": { "coderabbit@claude-plugins-official": true },
  "skipDangerousModePermissionPrompt": true
}
```

## Data Flow Changes

### Old Flow (Polling-Based)

```
Claude Code displays menu
         ↓
1s passes (polling interval)
         ↓
hook-watcher.sh detects "Enter to select" pattern
         ↓
Computes SHA1 signature to prevent duplicates
         ↓
Broadcasts openclaw system event to ALL agents
         ↓
Agent receives broadcast (no context)
         ↓
Agent calls menu-driver.sh snapshot (separate round-trip)
         ↓
Agent decides
         ↓
Agent calls menu-driver.sh choose <n>
         ↓
Claude Code receives input
```

**Latency:** 0-1000ms (polling interval) + agent wake time + snapshot request round-trip

### New Flow (Event-Driven)

```
Claude Code finishes responding
         ↓
Stop hook fires immediately (0ms delay)
         ↓
stop-hook.sh captures pane (single tmux call)
         ↓
Looks up agent in registry by tmux_session_name
         ↓
Sends pane snapshot + actions directly to SPECIFIC agent via openclaw agent --session-id
         ↓
Agent receives full context in one message
         ↓
Agent decides
         ↓
Agent calls menu-driver.sh choose <n> | type <text> | clear_then <cmd>
         ↓
Claude Code receives input
```

**Latency:** 0ms (immediate hook fire) + agent wake time

**Improvements:**
- No polling overhead
- No duplicate detection needed (hook fires once per completion)
- Targeted wake (specific agent, not broadcast)
- Context included in wake message (no separate snapshot request)
- 0-1s faster response time

## Registry Schema Changes

### Old Schema

```json
{
  "global_status_openclaw_session_id": "uuid",
  "global_status_openclaw_session_key": "agent:...",
  "agents": [
    {
      "agent_id": "warden",
      "enabled": true,
      "auto_wake": true,
      "topic_id": 1,
      "openclaw_session_id": "uuid",
      "working_directory": "/path",
      "tmux_session_name": "warden-main",
      "claude_resume_target": "",
      "claude_launch_command": "claude --dangerously-skip-permissions",
      "claude_post_launch_mode": "resume_then_agent_pick"
    }
  ]
}
```

### New Schema

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
      "openclaw_session_id": "uuid",
      "working_directory": "/path",
      "tmux_session_name": "warden-main",
      "claude_resume_target": "",
      "claude_launch_command": "claude --dangerously-skip-permissions",
      "claude_post_launch_mode": "resume_then_agent_pick",
      "system_prompt": "Prefer /gsd:quick for small tasks, /gsd:debug for bugs.",
      "hook_settings": {
        "pane_capture_lines": 150,
        "hook_mode": "bidirectional"
      }
    }
  ]
}
```

**New fields:**
- `system_prompt` (top-level per agent, string, defaults to empty string)
- `hook_settings` (global at root, nested object with strict known fields)
- `hook_settings` (per agent, overrides global on per-field basis)
- Three-tier fallback: per-agent > global > hardcoded defaults

## Build Order and Dependencies

### Phase 1: Additive Changes (No Breakage)

**Goal:** Add new components without disrupting existing sessions

1. **Create stop-hook.sh** (NEW file)
   - Dependencies: None
   - Creates: `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/stop-hook.sh`
   - Make executable: `chmod +x`
   - No existing sessions affected (hook not registered yet)

2. **Add type action to menu-driver.sh** (MODIFY)
   - Dependencies: Read current menu-driver.sh
   - Changes: Add new `type)` case to action switch, update usage()
   - Backward compatible: existing actions unchanged
   - No existing sessions affected (new action not called yet)

3. **Add system_prompt field to registry** (MODIFY)
   - Dependencies: None
   - Changes: Edit `config/recovery-registry.json` and `config/recovery-registry.example.json`
   - Backward compatible: new field ignored by old scripts
   - No existing sessions affected (field not read yet)

**Verification:** All files added/modified, no sessions disrupted

### Phase 2: Hook Registration (Minimal Risk)

**Goal:** Wire Stop hook, remove SessionStart launcher

4. **Add Stop hook to ~/.claude/settings.json** (MODIFY)
   - Dependencies: stop-hook.sh exists and is executable
   - Changes: Add Stop hook array calling stop-hook.sh
   - Impact: New Claude Code sessions will fire Stop hook
   - Existing sessions: Unaffected (hooks registered at session start)

5. **Remove gsd-session-hook.sh from SessionStart** (MODIFY)
   - Dependencies: None
   - Changes: Remove gsd-session-hook.sh entry from SessionStart hooks array
   - Impact: New Claude Code sessions will NOT launch hook-watcher.sh
   - Existing sessions: hook-watcher.sh still running (background process)
   - Overlap period: Both old (hook-watcher) and new (Stop hook) may run briefly (harmless duplicate wakes)

**Verification:** New sessions use Stop hook, old hook-watcher processes die when sessions end

### Phase 3: Launcher Updates (Registry Reader Changes)

**Goal:** Update spawn.sh and recover-openclaw-agents.sh to use system_prompt

6. **Modify spawn.sh** (MODIFY)
   - Dependencies: system_prompt field exists in registry
   - Changes:
     - Remove `--autoresponder` flag parsing (lines 236-242)
     - Remove `enable_autoresponder` variable and autoresponder launch block (lines 315-326)
     - Remove `strict_prompt()` function (lines 202-211)
     - Add `--system-prompt <text>` flag
     - Read system_prompt from registry after upsert
     - Update Python upsert to `setdefault("system_prompt", "")`
     - Build claude_cmd with system prompt
   - Impact: New sessions launched with custom system prompts
   - Existing sessions: Unaffected
   - Note: Removes autoresponder launch, but autoresponder.sh still exists (deleted in Phase 4)

7. **Modify recover-openclaw-agents.sh** (MODIFY)
   - Dependencies: system_prompt field exists in registry
   - Changes:
     - Update Python parser to include system_prompt in agent JSON
     - Add system_prompt parameter to `ensure_claude_is_running_in_tmux()`
     - Build claude_cmd with --append-system-prompt if system_prompt non-empty
     - Simplify `send_recovery_instruction_to_openclaw_session()` note about Stop hook
   - Impact: Recovered agents launch with custom system prompts
   - Existing sessions: Unaffected
   - Note: Keep resume wait logic, still needed for getting past startup menu

**Verification:** New spawns and recoveries use system_prompt, no autoresponder launches

### Phase 4: Cleanup (Script Deletions)

**Goal:** Remove obsolete polling scripts

8. **Delete autoresponder.sh** (DELETE)
   - Dependencies: spawn.sh no longer launches it (Phase 3)
   - Impact: None (not launched by any script)
   - Existing background processes: Will continue running until session ends (harmless)

9. **Delete hook-watcher.sh** (DELETE)
   - Dependencies: gsd-session-hook.sh removed from hooks (Phase 2)
   - Impact: None (not launched by SessionStart hook)
   - Existing background processes: Will continue running until session ends (harmless overlap with Stop hook)

10. **Delete ~/.claude/hooks/gsd-session-hook.sh** (DELETE)
    - Dependencies: Removed from settings.json SessionStart (Phase 2)
    - Impact: None (not called by any hook)

**Verification:** No script launches deleted files, existing processes terminate naturally

### Phase 5: Documentation (No Code Impact)

11. **Update SKILL.md** (MODIFY)
    - Document new architecture, Stop hook flow, system_prompt configuration
    - Update script list (remove autoresponder/hook-watcher, add stop-hook)

12. **Update README.md** (MODIFY)
    - Update registry schema docs with system_prompt field
    - Update recovery flow description (mention Stop hook)

**Verification:** Documentation matches implementation

## Dependency Graph

```
Phase 1 (Additive):
  stop-hook.sh ← (creates new file)
  menu-driver.sh ← (adds type action)
  registry.json ← (adds system_prompt field)
  ↓
Phase 2 (Hook wiring):
  settings.json ← stop-hook.sh (depends on script existing)
  ↓
Phase 3 (Launcher updates):
  spawn.sh ← registry.json (depends on system_prompt field)
  recover-openclaw-agents.sh ← registry.json (depends on system_prompt field)
  ↓
Phase 4 (Cleanup):
  DELETE autoresponder.sh ← spawn.sh (safe after spawn no longer launches it)
  DELETE hook-watcher.sh ← settings.json (safe after SessionStart no longer launches it)
  DELETE gsd-session-hook.sh ← settings.json (safe after hook removed)
  ↓
Phase 5 (Docs):
  SKILL.md, README.md ← (no dependencies, pure documentation)
```

## Edge Cases and Migration Concerns

### Non-Managed Sessions

**Scenario:** User runs Claude Code outside tmux or in non-registered tmux session

**Behavior:**
- Stop hook fires (always registered globally)
- stop-hook.sh checks `$TMUX` env → exits 0 if not in tmux (~1ms overhead)
- If in tmux but not in registry → jq query returns empty → exits 0 (~5ms overhead)
- No OpenClaw wake, no side effects

**Safety:** Fast exit path, minimal overhead for non-managed sessions

### Infinite Loop Prevention

**Scenario:** OpenClaw agent calls menu-driver.sh, which triggers new Claude response, which fires Stop hook again

**Behavior:**
- Stop hook reads stdin JSON, checks `stop_hook_active` field
- Claude Code sets this to `true` if hook is being called during hook processing
- stop-hook.sh exits 0 if `stop_hook_active == true`

**Safety:** Guard prevents recursive hook calls

**Note:** Our hook never returns `decision: "block"`, so this guard may never trigger, but it's there for safety

### Stale hook-watcher Processes

**Scenario:** hook-watcher.sh background processes running from old sessions during migration

**Behavior:**
- Old hook-watcher processes continue polling until tmux session ends
- New Stop hook also fires for same session
- Brief period of duplicate wakes (both hook-watcher broadcast + Stop hook targeted wake)
- hook-watcher dies when session ends (while loop checks `tmux has-session`)

**Safety:** Harmless overlap, duplicate wakes are idempotent, natural cleanup

**Duration:** Until all pre-migration sessions are closed or server reboots

### Empty system_prompt in Registry

**Scenario:** Agent entry has `system_prompt: ""`

**Behavior:**
- spawn.sh reads empty string from registry
- Falls back to default prompt: "You are a GSD-driven development agent..."
- Claude launches with default system prompt

**Safety:** Graceful fallback, no broken sessions

### Registry Unreadable

**Scenario:** registry.json corrupted or missing during Stop hook execution

**Behavior:**
- jq call wrapped in `|| true`, returns empty on error
- stop-hook.sh sees no matching agent
- Exits 0 (treats as non-managed session)
- No OpenClaw wake, no crash

**Safety:** Fail-safe, never blocks Claude Code operation

### OpenClaw Agent Call Fails

**Scenario:** openclaw agent --session-id call fails (agent offline, network issue, etc)

**Behavior:**
- Call is backgrounded with `openclaw agent ... & `
- Exit status ignored (always exits 0)
- No retry, no blocking

**Safety:** Never blocks Claude Code, agent wakes when available

**Trade-off:** Missed wake if agent offline (acceptable, agent can poll /gsd:resume-work later)

### Session ID Mismatch After Recovery

**Scenario:** Agent recovery creates new OpenClaw session ID, registry still has old ID

**Behavior:**
- Stop hook sends wake to old session ID
- Wake fails (session not found)
- Agent does not receive pane snapshot

**Mitigation:**
- Run `scripts/sync-recovery-registry-session-ids.sh` after recovery
- Or manually update registry with new session ID
- Or agent polls OpenClaw messages and picks up system event fallback

**Future improvement:** Auto-sync session IDs during recovery

## Architectural Patterns

### Pattern 1: Event-Driven Hook with Fast Guards

**What:** Check multiple fast exit conditions before doing expensive work

**Implementation:**
```bash
# stdin JSON check (almost free, piped input)
stop_hook_active="$(jq -r '.stop_hook_active // false')"
[ "$stop_hook_active" = "true" ] && exit 0

# Environment check (free)
[ -n "$TMUX" ] || exit 0

# Registry lookup (5-10ms, jq + file read)
agent_entry="$(jq ... registry.json)"
[ -n "$agent_entry" ] || exit 0

# Expensive work only if all guards pass
pane_content="$(tmux capture-pane ...)"
openclaw agent --session-id ... &
```

**When to use:** Hooks that fire frequently but only apply to subset of sessions

**Trade-offs:**
- Pro: Minimal overhead for non-managed sessions (1-5ms)
- Pro: No false wakes, no side effects outside managed sessions
- Con: Requires registry maintenance

### Pattern 2: Background OpenClaw Wake with Immediate Exit

**What:** Fire-and-forget OpenClaw agent wake, never block caller

**Implementation:**
```bash
openclaw agent --session-id "$SESSION_ID" --message "$MESSAGE" >/dev/null 2>&1 &
exit 0
```

**When to use:** When hook must return quickly (Claude Code hooks have timeouts)

**Trade-offs:**
- Pro: Never blocks Claude Code operation
- Pro: Continues even if OpenClaw agent offline
- Con: No delivery confirmation
- Con: Wake lost if agent crashes before processing

**Mitigation:** Agent can poll missed wakes, use system event fallback

### Pattern 3: Registry as Source of Truth

**What:** Single JSON file stores all agent metadata, read by multiple scripts

**Location:** `config/recovery-registry.json`

**Readers:**
- stop-hook.sh (looks up agent by tmux_session_name)
- spawn.sh (upserts agent entry, reads system_prompt)
- recover-openclaw-agents.sh (reads all agents for recovery)
- sync-recovery-registry-session-ids.sh (updates session IDs)

**Writers:**
- spawn.sh (upserts on session creation)
- sync-recovery-registry-session-ids.sh (updates session IDs)

**Schema evolution:**
- Use jq with `// default` for missing fields (no Python)
- Old readers ignore new fields (forward compatibility)
- New readers provide defaults for missing fields (backward compatibility)
- Strict known fields only — no open-ended keys in hook_settings

**Trade-offs:**
- Pro: Single source of truth, no sync issues
- Pro: Easy to inspect/debug (plain JSON)
- Con: File lock not enforced (relies on atomic upsert)
- Con: Manual sync needed after recovery (session ID refresh)

### Pattern 4: Signature-Based Duplicate Prevention (Removed)

**What:** OLD pattern in autoresponder.sh and hook-watcher.sh, now obsolete

**How it worked:** Compute SHA1 of pane content, store in /tmp, skip if signature matches

**Why removed:** Stop hook fires once per completion, no need for duplicate detection

**Lesson:** Event-driven hooks eliminate need for stateful duplicate tracking

## Anti-Patterns Avoided

### Anti-Pattern 1: Polling in Hooks

**What people might do:** Poll tmux pane inside Stop hook to wait for state change

**Why it's wrong:**
- Hooks have timeouts
- Blocks Claude Code operation
- Defeats event-driven design

**Do this instead:**
- Capture pane snapshot once
- Send to agent
- Exit immediately
- Agent makes decision asynchronously

### Anti-Pattern 2: Synchronous OpenClaw Calls in Hooks

**What people might do:** Wait for openclaw agent call to complete before exiting hook

**Why it's wrong:**
- Hook timeout if agent takes >5s to respond
- Blocks Claude Code TUI
- Creates tight coupling

**Do this instead:**
- Background openclaw call with `&`
- Exit 0 immediately
- Agent responds asynchronously via menu-driver.sh

### Anti-Pattern 3: Hardcoded System Prompts

**What people might do:** Keep strict_prompt() function, apply same prompt to all agents

**Why it's wrong:**
- Different agents need different personalities/constraints
- No per-agent customization
- Forces prompt override flags everywhere

**Do this instead:**
- Store system_prompt in registry per agent
- Provide sensible default if empty
- Allow --system-prompt override for testing

### Anti-Pattern 4: Broadcast System Events

**What hook-watcher did:** Sent openclaw system event (broadcast to all agents)

**Why it's wrong:**
- Wakes irrelevant agents
- No context in wake message
- Requires separate snapshot request
- Higher latency

**Do this instead:**
- Look up specific agent by tmux_session_name
- Send targeted wake via openclaw agent --session-id
- Include pane snapshot in wake message
- Single round-trip

## Session Continuity During Migration

### Active Sessions

**Scenario:** Sessions running when migration scripts are deployed

**Impact per phase:**

**Phase 1 (Additive):** No impact, new files ignored
**Phase 2 (Hook registration):**
- Existing sessions still have hook-watcher.sh running
- New sessions will use Stop hook instead
- Brief overlap possible (both watcher and hook wake agent)
- Overlap is harmless (duplicate wakes are idempotent)

**Phase 3 (Launcher updates):**
- Existing sessions unaffected (already launched)
- New spawn.sh calls use system_prompt
- No autoresponder launch for new sessions

**Phase 4 (Cleanup):**
- Existing autoresponder/hook-watcher processes continue until session ends
- Deleted scripts no longer launched

**Recommendation:**
- Deploy during low-activity period
- Let existing sessions complete naturally
- OR manually restart sessions after Phase 3 to pick up new behavior
- OR force restart via recover-openclaw-agents.sh after full deployment

### Recovery After Deployment

**Scenario:** Server reboots after Phase 2 but before Phase 3

**Behavior:**
- recover-openclaw-agents.sh runs (still old version)
- Launches Claude without system_prompt (uses old hardcoded strict_prompt)
- Stop hook fires (already registered in settings.json)
- Works correctly (Stop hook is backward compatible)

**Safety:** Each phase is independently functional

**Scenario:** Server reboots after full deployment

**Behavior:**
- recover-openclaw-agents.sh runs (new version)
- Reads system_prompt from registry
- Launches Claude with custom system prompt
- Stop hook fires, sends wake to agent
- Full new architecture active

**Recommendation:** Complete all phases before next reboot, or deploy during maintenance window

## Sources

- PRD.md (project requirements)
- scripts/spawn.sh (343 lines, session launcher architecture)
- scripts/recover-openclaw-agents.sh (484 lines, recovery flow)
- scripts/autoresponder.sh (112 lines, polling pattern being replaced)
- scripts/hook-watcher.sh (50 lines, polling pattern being replaced)
- scripts/menu-driver.sh (64 lines, existing atomic action interface)
- ~/.claude/settings.json (current hook configuration)
- config/recovery-registry.example.json (registry schema)
- Claude Code Stop hook documentation (event-driven hook pattern, stdin JSON format)

---
*Architecture research for: Hook-driven OpenClaw agent control*
*Researched: 2026-02-17*
*Confidence: HIGH (all source files read, integration points verified, existing architecture well-documented)*
