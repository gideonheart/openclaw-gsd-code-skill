Plan: Hook-Driven OpenClaw Agent Control for Claude Code Sessions

Context

The gsd-code-skill currently uses two polling-based scripts to handle Claude Code sessions:
- autoresponder.sh — 1s polling loop that picks option 1/recommended (no AI, no context awareness)
- hook-watcher.sh — polls tmux pane every 1s, broadcasts system events to all OpenClaw agents when menu detected

Problems:
- Polling overhead: Two 1s polling loops per session
- Broadcast spam: hook-watcher wakes ALL agents, not the specific session owner
- No context: autoresponder is blind; hook-watcher provides no TUI snapshot in wake message
- Latency: 0-1s detection delay + separate round-trip for agent to request snapshot
- Imprecise: Neither enables intelligent agent decisions

Solution: Replace both with Claude Code's native hook system (5 hook event types: Stop, Notification idle_prompt, Notification permission_prompt, SessionEnd, PreCompact). When hooks fire, they capture TUI state and send structured wake messages directly to the correct OpenClaw agent via openclaw agent --session-id. The agent makes intelligent decisions and responds via menu-driver.sh.

Additionally:
- Per-agent configurable system prompts via recovery registry (not hardcoded)
- Hybrid hook mode: async by default (fast), bidirectional per-agent for instruction injection
- hook_settings nested object with three-tier config fallback (per-agent > global > hardcoded)
- External default system prompt file tracked in git (config/default-system-prompt.txt)
- All registry operations use jq (no Python dependency, cross-platform compatible)

Architecture

Claude Code finishes responding / fires notification event / session ends / pre-compact
        |
        v
Hook fires (stop-hook.sh, notification-idle-hook.sh, etc.)
  - Consumes stdin JSON immediately (prevent pipe blocking)
  - Guards: stop_hook_active check? not in $TMUX? not in registry? → exit 0
  - Captures pane (configurable depth via hook_settings.pane_capture_lines)
  - Extracts context pressure from statusline (configurable threshold via hook_settings.context_pressure_threshold)
  - Looks up agent in registry by tmux_session_name (jq query, no Python)
  - Builds structured wake message with sections:
      [SESSION IDENTITY] agent_id, tmux_session_name
      [TRIGGER] response_complete | idle_prompt | permission_prompt | session_terminated | pre_compact
      [STATE HINT] menu | idle | permission_prompt | error | working
      [PANE CONTENT] last N lines from tmux pane
      [CONTEXT PRESSURE] percentage + warning level (e.g., "72% [WARNING]", "45% [OK]")
      [AVAILABLE ACTIONS] menu-driver.sh commands
        |
        v
  - Hybrid mode check (hook_settings.hook_mode: "async" | "bidirectional"):
      ASYNC (default): Background openclaw agent call, exit 0 immediately
      BIDIRECTIONAL: Wait for OpenClaw response, return { "decision": "block", "reason": "..." }
        |
        v
OpenClaw agent (Gideon/Warden/Forge)
  - Receives: full context in one message (pane snapshot + context pressure + available actions)
  - Decides: intelligent choice based on session state and agent role
  - Calls: menu-driver.sh <session> choose <n>
       OR: menu-driver.sh <session> type <text>
       OR: menu-driver.sh <session> clear_then <command>
        |
        v
Claude Code receives input, continues working


Changes

This section documents ALL components affected by the hook-driven architecture migration. 17 total changes across 5 hook scripts, menu-driver, spawn/recovery, registry schema, settings.json, and cleanup. All registry operations use jq (no Python).

1. NEW: scripts/stop-hook.sh

Core Stop hook. Fires when Claude Code finishes responding. Guards: consume stdin (prevent pipe blocking), check stop_hook_active (infinite loop prevention), check $TMUX env (non-tmux sessions exit in ~1ms), registry lookup via jq (non-managed sessions exit in ~5ms). Capture pane content (configurable depth via hook_settings.pane_capture_lines, default 120 lines). Extract context pressure percentage from statusline (configurable threshold via hook_settings.context_pressure_threshold). Build structured wake message with sections (SESSION IDENTITY, TRIGGER, STATE HINT, PANE CONTENT, CONTEXT PRESSURE, AVAILABLE ACTIONS). Support hybrid mode: async (background openclaw call + exit 0) or bidirectional (wait for OpenClaw response, return decision:block with instruction). Use jq for all registry reads.

2. NEW: scripts/notification-idle-hook.sh

Notification hook for idle_prompt events. Fires when Claude waits for user input. Same guard pattern as stop-hook.sh (stdin consumption, $TMUX check, registry lookup via jq). Captures pane (configurable depth), sends structured wake message with trigger: idle_prompt. Always async (no bidirectional for notification hooks — Claude does not support decision:block from Notification hooks). Enables OpenClaw to detect session idle state and inject /resume or /gsd:resume-work commands.

3. NEW: scripts/notification-permission-hook.sh

Notification hook for permission_prompt events. Future-proofing for fine-grained permission handling (currently --dangerously-skip-permissions bypasses this, but architecture supports selective permission routing). Same guard pattern. Sends wake with trigger: permission_prompt. Always async. Uses matcher "permission_prompt" (Note: Stop and Notification idle_prompt do NOT support matchers — they always fire).

4. NEW: scripts/session-end-hook.sh

SessionEnd hook. Fires when Claude Code session terminates. Notifies OpenClaw immediately (faster recovery than daemon polling alone). Minimal message: session identity + trigger: session_terminated. No pane capture needed (session already ended). Enables instant recovery initiation via recover-openclaw-agents.sh or intelligent cleanup decisions.

5. NEW: scripts/pre-compact-hook.sh

PreCompact hook. Fires before Claude Code context compaction. Captures state before compaction (pane content, current task context). Sends wake with trigger: pre_compact. If bidirectional mode enabled (hook_settings.hook_mode: "bidirectional"), OpenClaw can return decision:block with context preservation instructions (e.g., "Summarize your progress before compacting" or "Note key decisions in CONTEXT.md"). If async mode, OpenClaw receives notification but cannot inject instructions. Configurable per-agent via hook_settings.

6. NEW: config/default-system-prompt.txt

External default system prompt file tracked in git. Minimal GSD workflow guidance (prefer /gsd:* commands, make atomic commits). No role/personality content (agents get that from SOUL.md and AGENTS.md in OpenClaw workspace). No mention of managed tmux session or orchestration layer (pure workflow guidance). Used by spawn.sh and recover-openclaw-agents.sh via --append-system-prompt-file or --append-system-prompt. Per-agent system_prompt from registry always appends to (never replaces) default prompt.

7. MODIFY: scripts/menu-driver.sh

Add type <text> action for freeform text input via tmux send-keys -l (literal mode, no shell expansion). Enables OpenClaw agents to send arbitrary text responses to Claude prompts (not just menu choices). Update usage() to document new action.

Implementation:
```bash
type)
  text="${1:-}"
  [ -n "$text" ] || { echo "type requires <text>" >&2; exit 1; }
  tmux send-keys -t "$SESSION:0.0" C-u        # Clear current line
  tmux send-keys -t "$SESSION:0.0" -l -- "$text"  # Send literal text
  tmux send-keys -t "$SESSION:0.0" Enter
  ;;
```

Existing actions unchanged: snapshot, enter, esc, clear_then, choose, submit.

8. MODIFY: scripts/spawn.sh

Remove --autoresponder flag and all autoresponder launch logic. Remove enable_autoresponder variable. Remove hardcoded strict_prompt() function. Add --system-prompt <text> flag for explicit override. Read system_prompt from registry after upsert (jq query, no Python). Replace Python upsert with jq-based atomic registry update using flock for safe concurrent writes. Read default prompt from config/default-system-prompt.txt. Combine default + per-agent system_prompt (per-agent always appends, never replaces). Pass combined prompt via --append-system-prompt or --append-system-prompt-file. Preserve all existing functionality: tmux session creation, Claude launch with --dangerously-skip-permissions, registry upsert, project directory handling.

Registry upsert pattern (jq, no Python):
```bash
flock "$registry_path.lock" jq \
  --arg agent_id "$effective_agent_id" \
  --arg system_prompt "" \
  '.agents |= map(if .agent_id == $agent_id then . + {system_prompt: ($system_prompt // .system_prompt // "")} else . end)' \
  "$registry_path" > "$registry_path.tmp" && mv "$registry_path.tmp" "$registry_path"
```

9. MODIFY: scripts/recover-openclaw-agents.sh

Extract system_prompt per agent via jq (replace Python JSON parser). Pass system_prompt via --append-system-prompt on Claude launch. Combine default + per-agent prompt (same pattern as spawn.sh). Handle missing system_prompt gracefully (fallback to default). Keep per-agent error handling (no set -e abort, partial recovery sends summary). Keep post-launch command logic (/resume or /gsd:resume-work) — still needed to get past Claude Code startup menu. Simplify send_recovery_instruction_to_openclaw_session note that Stop hook now active (agents receive automatic wake on response_complete, no manual pane polling needed).

Per-agent system_prompt extraction (jq, no Python):
```bash
AGENT_PROMPT="$(echo "$AGENT_JSON" | jq -r '.system_prompt // ""')"
DEFAULT_PROMPT="$(cat config/default-system-prompt.txt)"
FULL_PROMPT="${DEFAULT_PROMPT}"
[ -n "$AGENT_PROMPT" ] && FULL_PROMPT="${FULL_PROMPT}\n\n${AGENT_PROMPT}"
claude_cmd="${base_claude_launch_command} --append-system-prompt $(printf %q "$FULL_PROMPT")"
```

10. MODIFY: config/recovery-registry.json

Add system_prompt field (top-level per agent, string type, defaults to empty string). Add hook_settings nested object (global at root level + per-agent override). Strict known fields only: pane_capture_lines, context_pressure_threshold, autocompact_pct, hook_mode. Three-tier fallback: per-agent hook_settings > global hook_settings > hardcoded defaults. Per-field merge: if per-agent has pane_capture_lines but not context_pressure_threshold, use per-agent for first field and global for second. Auto-populate hook_settings with defaults when creating new agent entries (spawn.sh handles this during upsert). No open-ended keys (strict schema prevents typos and ensures consistent behavior).

Schema:
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
      "system_prompt": "Prefer /gsd:quick for small tasks, /gsd:debug for bugs. Make atomic commits.",
      "hook_settings": {
        "pane_capture_lines": 150,
        "hook_mode": "bidirectional"
      }
    }
  ]
}
```

11. MODIFY: config/recovery-registry.example.json

Show realistic multi-agent setup (Gideon, Warden, Forge). Document system_prompt field per agent with different prompts showing personality/role differences. Document global hook_settings at root level with all 4 fields (pane_capture_lines, context_pressure_threshold, autocompact_pct, hook_mode). Document per-agent hook_settings overrides showing different configurations (e.g., Warden with bidirectional mode and deeper pane capture, Forge with async mode and shallower capture). Show three-tier fallback in comments explaining which fields come from which tier. Include inline documentation for each field explaining purpose and valid values.

12. MODIFY: ~/.claude/settings.json

Register ALL hooks:
- Stop: calls scripts/stop-hook.sh
- Notification (idle_prompt): calls scripts/notification-idle-hook.sh (Note: Stop and Notification idle_prompt do NOT support matchers — they always fire)
- Notification (permission_prompt): calls scripts/notification-permission-hook.sh with matcher "permission_prompt"
- SessionEnd: calls scripts/session-end-hook.sh
- PreCompact: calls scripts/pre-compact-hook.sh

Remove gsd-session-hook.sh from SessionStart hooks (only purpose was launching hook-watcher.sh, now obsolete). Keep gsd-check-update.js in SessionStart (version check functionality still needed). Hooks snapshot at startup: changes to settings.json require session restart to take effect.

Complete settings.json:
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
    ],
    "Notification": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-idle-hook.sh\"" }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          { "type": "command", "command": "bash \"/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-permission-hook.sh\"" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/session-end-hook.sh\"" }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/pre-compact-hook.sh\"" }
        ]
      }
    ]
  },
  "statusLine": { "type": "command", "command": "node \"/home/forge/.claude/hooks/gsd-statusline.js\"" },
  "enabledPlugins": { "coderabbit@claude-plugins-official": true },
  "skipDangerousModePermissionPrompt": true
}
```

13. DELETE: scripts/autoresponder.sh

Replaced by hook system + OpenClaw agent decision-making. Polling-based menu responder (1s loop, picks option 1 blindly) is obsolete. Stop hook provides intelligent, context-aware agent control.

14. DELETE: scripts/hook-watcher.sh

Replaced by hook system. Polling-based menu detector (1s loop, broadcasts system events to all agents) is obsolete. Stop hook provides targeted wakes with full context.

15. DELETE: ~/.claude/hooks/gsd-session-hook.sh

Only purpose was launching hook-watcher.sh. No longer needed with hook system.

16. MODIFY: SKILL.md

Update with new hook architecture: document all 5 hook scripts (stop-hook, notification-idle-hook, notification-permission-hook, session-end-hook, pre-compact-hook), hybrid mode (async vs bidirectional), hook_settings configuration (global + per-agent with three-tier fallback), system_prompt configuration (default + per-agent append), structured wake message format, jq-only registry operations. Update script list to reflect removed scripts (autoresponder, hook-watcher, gsd-session-hook) and added hook scripts. Update architecture diagrams showing event-driven flow instead of polling.

17. MODIFY: README.md

Update registry schema docs with system_prompt field and hook_settings object (show complete example with all fields, document three-tier fallback, explain per-field merge). Update recovery flow description to mention Stop hook automatic wakes (no manual polling needed). Document structured wake message format. Update integration points section showing openclaw agent --session-id targeted wakes.


Registry Schema

Before:
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

After:
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
      "system_prompt": "Prefer /gsd:quick for small tasks, /gsd:debug for bugs. Make atomic commits.",
      "hook_settings": {
        "pane_capture_lines": 150,
        "hook_mode": "bidirectional"
      }
    }
  ]
}
```

New fields:
- system_prompt (top-level per agent): Custom system prompt text appended to default prompt from config/default-system-prompt.txt
- hook_settings (global at root): Default hook configuration for all agents
- hook_settings (per agent): Per-agent overrides, per-field merge with global settings

Three-tier fallback (per-field):
1. Check per-agent hook_settings for field
2. If missing, check global hook_settings for field
3. If missing, use hardcoded default

Example: Warden has hook_settings.pane_capture_lines = 150 and hook_settings.hook_mode = "bidirectional", but no context_pressure_threshold. Warden gets pane_capture_lines=150 (per-agent), context_pressure_threshold=50 (global), hook_mode="bidirectional" (per-agent), autocompact_pct=50 (global).


Structured Wake Message Format

All hooks send wake messages with structured sections (plain text with clear headers, optimized for LLM parsing):

```
[SESSION IDENTITY]
agent_id: warden
tmux_session_name: warden-main

[TRIGGER]
response_complete

[STATE HINT]
menu

[PANE CONTENT]
<last N lines from tmux pane, configurable via hook_settings.pane_capture_lines>

[CONTEXT PRESSURE]
72% [WARNING]

[AVAILABLE ACTIONS]
menu-driver.sh warden-main choose <n>
menu-driver.sh warden-main type <text>
menu-driver.sh warden-main clear_then <command>
menu-driver.sh warden-main enter
menu-driver.sh warden-main esc
menu-driver.sh warden-main submit
menu-driver.sh warden-main snapshot
```

Trigger types:
- response_complete (Stop hook)
- idle_prompt (Notification idle hook)
- permission_prompt (Notification permission hook)
- session_terminated (SessionEnd hook)
- pre_compact (PreCompact hook)

State hints (simple pattern matching):
- menu: "Enter to select" or numbered options detected
- idle: No clear menu, no error, Claude waiting
- permission_prompt: Permission dialog detected
- error: Red text or error patterns detected
- working: Default if no other state matches

Context pressure format: <percentage> [OK|WARNING|CRITICAL]
- OK: below threshold (default threshold 50%)
- WARNING: above threshold but below 80%
- CRITICAL: above 80%

Threshold configurable via hook_settings.context_pressure_threshold per agent.


Hybrid Hook Mode

Hook mode controls whether hooks wait for OpenClaw response or exit immediately. Configured per-agent via hook_settings.hook_mode.

Async mode (default):
- Hook captures pane, sends wake message to OpenClaw agent
- Backgrounds openclaw agent call with & (fire-and-forget)
- Exits 0 immediately (never blocks Claude Code)
- OpenClaw agent receives wake asynchronously
- Agent responds via menu-driver.sh when ready
- Fast, no blocking, recommended for most agents

Bidirectional mode (opt-in per agent):
- Hook captures pane, sends wake message to OpenClaw agent
- Waits for OpenClaw response (synchronous call, no &)
- OpenClaw returns JSON: { "decision": "block", "reason": "Continue with task X" }
- Hook returns decision:block to Claude Code
- Claude receives "reason" text as next instruction and continues working
- Enables direct instruction injection (no tmux send-keys needed)
- Use cases: PreCompact hook (inject context preservation instructions), Stop hook (inject next task without menu choice)
- Timeout: 10 minutes (hook timeout, configurable per hook in settings.json)
- Only works with Stop and PreCompact hooks (Notification and SessionEnd do NOT support decision:block)

Example bidirectional flow (PreCompact hook):
1. Claude about to compact context (70% pressure)
2. PreCompact hook fires, sends wake with trigger: pre_compact
3. OpenClaw agent receives context state
4. Agent decides: "User wants detailed SUMMARY.md, preserve key decisions"
5. Agent returns: { "decision": "block", "reason": "Before compacting, create .planning/SUMMARY.md with key decisions from conversation. Then continue." }
6. Hook returns decision:block with reason to Claude
7. Claude creates SUMMARY.md before compacting
8. No menu interaction needed, no tmux send-keys, direct instruction injection

Configuration:
```json
{
  "agent_id": "warden",
  "hook_settings": {
    "hook_mode": "bidirectional"
  }
}
```


Implementation Phases

Phases must match ROADMAP.md exactly. 5 phases total, numeric order (1 → 2 → 3 → 4 → 5).

Phase 1: Additive Changes
Goal: Create all new components without disrupting existing workflows
Scope: Create 5 hook scripts (stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh, pre-compact-hook.sh), add type action to menu-driver.sh, add system_prompt and hook_settings to registry schema, create config/default-system-prompt.txt
Impact: Zero — new files not used until Phase 2 (hooks not registered), existing autoresponder/hook-watcher continue working
Verification: All new files exist, chmod +x on hook scripts, registry schema valid JSON, existing sessions unaffected

Phase 2: Hook Wiring
Goal: Register all hooks globally, remove SessionStart hook watcher launcher
Scope: Add Stop, Notification (idle_prompt, permission_prompt), SessionEnd, PreCompact hooks to ~/.claude/settings.json, remove gsd-session-hook.sh from SessionStart hooks
Impact: New Claude Code sessions fire hooks instead of launching hook-watcher.sh, existing sessions with running hook-watcher.sh continue (brief overlap tolerated)
Verification: New sessions use hooks (check /tmp/ logs or openclaw wake), old hook-watcher processes die when sessions end, no duplicate wakes after all pre-migration sessions closed

Phase 3: Launcher Updates
Goal: Update spawn and recovery scripts for system prompt support (jq-only)
Scope: Modify spawn.sh (remove autoresponder, add system_prompt via jq, read default-system-prompt.txt), modify recover-openclaw-agents.sh (extract system_prompt via jq, pass to Claude on launch), use jq for all registry operations (no Python)
Impact: New spawns and recoveries use custom system prompts, no autoresponder launches, existing sessions unaffected
Verification: New sessions launched with system_prompt from registry, jq queries work, no Python calls in spawn or recovery scripts

Phase 4: Cleanup
Goal: Remove obsolete polling scripts
Scope: Delete scripts/autoresponder.sh, scripts/hook-watcher.sh, ~/.claude/hooks/gsd-session-hook.sh, kill existing hook-watcher processes via pkill, remove watcher state files from /tmp
Impact: Zero code impact (scripts no longer launched), cleanup only
Verification: Deleted scripts no longer exist, no background hook-watcher processes, /tmp clean

Phase 5: Documentation
Goal: Update skill documentation with new architecture
Scope: Update SKILL.md (hook architecture, all 5 hook scripts, hybrid mode, hook_settings, system_prompt), update README.md (registry schema with system_prompt and hook_settings, recovery flow with hooks)
Impact: Documentation only, no code changes
Verification: SKILL.md and README.md accurately reflect implementation, script list current, architecture diagrams show event-driven flow


Edge Cases

Non-managed sessions
Scenario: User runs Claude Code outside tmux or in non-registered tmux session
Behavior: All hook scripts check $TMUX env → exit 0 if not in tmux (~1ms overhead). If in tmux but not in registry, jq query returns empty → exit 0 (~5ms overhead). No OpenClaw wake, no side effects.
Safety: Fast exit path, minimal overhead for non-managed sessions

Infinite loops
Scenario: OpenClaw agent calls menu-driver.sh, triggers new Claude response, fires Stop hook again
Behavior: Stop hook reads stdin JSON, checks stop_hook_active field (Claude sets to true if hook called during hook processing). Hook exits 0 if stop_hook_active == true.
Safety: Guard prevents recursive hook calls
Note: Our hooks never return decision: "block" in async mode, so this guard may never trigger, but it's there for safety

Stale hook-watcher processes during migration
Scenario: hook-watcher.sh background processes running from old sessions during Phase 2-3 migration
Behavior: Old hook-watcher processes continue polling until tmux session ends. New Stop hook also fires for same session. Brief period of duplicate wakes (both hook-watcher broadcast + Stop hook targeted wake). hook-watcher dies when session ends (while loop checks tmux has-session).
Safety: Harmless overlap, duplicate wakes are idempotent, natural cleanup
Duration: Until all pre-migration sessions closed or server reboots

Empty system_prompt in registry
Scenario: Agent entry has system_prompt: "" or field missing
Behavior: spawn.sh and recover-openclaw-agents.sh read empty string, fall back to config/default-system-prompt.txt only (no per-agent append). Claude launches with default system prompt.
Safety: Graceful fallback, no broken sessions

Registry unreadable
Scenario: recovery-registry.json corrupted or missing during hook execution
Behavior: jq call wrapped in || true, returns empty on error. Hook sees no matching agent. Exits 0 (treats as non-managed session). No OpenClaw wake, no crash.
Safety: Fail-safe, never blocks Claude Code operation

OpenClaw agent call fails
Scenario: openclaw agent --session-id call fails (agent offline, network issue)
Behavior: In async mode, call backgrounded with openclaw agent ... & . Exit status ignored (hook always exits 0). No retry, no blocking. In bidirectional mode, synchronous call waits up to hook timeout (10 minutes default), returns empty decision if timeout.
Safety: Never blocks Claude Code (async), graceful timeout (bidirectional)
Trade-off: Missed wake if agent offline (acceptable, agent can poll /gsd:resume-work later)

Hybrid mode timeout
Scenario: Bidirectional mode hook waits for OpenClaw response, agent takes >10 minutes
Behavior: Hook timeout (configurable per hook in settings.json, default 10 minutes). Hook exits with error. Claude Code continues normally (timeout treated as hook failure, not blocking).
Safety: Never hangs Claude indefinitely
Mitigation: Set realistic timeout based on expected agent response time, or use async mode for slow agents

Multiple hooks firing simultaneously
Scenario: Claude Code triggers multiple hook events at once (e.g., Stop + Notification)
Behavior: Claude Code runs all matching hooks in parallel. Identical hook handlers are deduplicated (same script path = single execution). Different scripts run concurrently.
Safety: Hooks designed to be idempotent, concurrent execution safe
Note: Stop and Notification(idle_prompt) do NOT support matchers — they always fire. Use script guard logic to handle non-relevant events.

Hook settings missing fields
Scenario: Per-agent hook_settings has some fields but not all (e.g., pane_capture_lines present, context_pressure_threshold missing)
Behavior: Three-tier fallback provides defaults. For each field: check per-agent → check global → use hardcoded default. Per-field merge (not all-or-nothing).
Safety: Never fails due to partial configuration
Example: Warden has hook_settings.hook_mode = "bidirectional" but no pane_capture_lines. Warden gets hook_mode="bidirectional" (per-agent), pane_capture_lines=120 (global default).

Notification hooks without matchers
Scenario: Stop and Notification(idle_prompt) always fire (no matcher support), including for non-managed sessions
Behavior: Guard logic in hook scripts handles this. Check $TMUX env first (exit if not in tmux). Check registry lookup second (exit if not managed session). Fast exit path ensures minimal overhead.
Safety: Non-managed sessions exit in <5ms, no false wakes
Note: Only Notification(permission_prompt) uses matcher — Stop and Notification(idle_prompt) rely on script guards, not matchers.

Session ID mismatch after recovery
Scenario: Agent recovery creates new OpenClaw session ID, registry still has old ID
Behavior: Stop hook sends wake to old session ID. Wake fails (session not found). Agent does not receive pane snapshot.
Mitigation: Run scripts/sync-recovery-registry-session-ids.sh after recovery to refresh registry with new session IDs. Or agent polls OpenClaw messages and picks up system event fallback.
Future improvement: Auto-sync session IDs during recovery script run


Verification

Full system verification steps covering all hooks, modes, and integration points.

1. Stop hook fires in managed tmux session
   Test: Start Claude Code in managed session, wait for response complete, verify Stop hook fires (check /tmp/ logs or openclaw agent wake message received)
   Expected: Hook fires immediately after Claude response, OpenClaw agent receives structured wake message with trigger: response_complete

2. Notification idle hook fires on idle state
   Test: Leave Claude Code idle (waiting for user input), verify Notification idle hook fires
   Expected: Hook fires on idle state, OpenClaw agent receives wake with trigger: idle_prompt

3. Notification permission hook fires on permission prompt (when enabled)
   Test: Trigger permission dialog (remove --dangerously-skip-permissions temporarily), verify hook fires
   Expected: Hook fires with matcher "permission_prompt", OpenClaw agent receives wake with trigger: permission_prompt

4. SessionEnd hook fires on session termination
   Test: Exit Claude Code session (Ctrl+D or /exit), verify SessionEnd hook fires
   Expected: Hook fires immediately on exit, OpenClaw agent receives wake with trigger: session_terminated

5. PreCompact hook fires before context compaction
   Test: Fill context to trigger autocompact (via CLAUDE_AUTOCOMPACT_PCT_OVERRIDE or natural 50% threshold), verify PreCompact hook fires
   Expected: Hook fires before compaction starts, OpenClaw agent receives wake with trigger: pre_compact

6. Non-managed sessions unaffected (all hooks exit cleanly)
   Test: Run Claude Code outside tmux, verify no OpenClaw wakes, no errors, normal operation
   Expected: All hooks exit 0 in <5ms, zero side effects

7. Menu-driver type action works
   Test: Call menu-driver.sh <session> type "hello world", verify text sent literally to Claude
   Expected: Text appears in Claude input, Enter pressed, Claude processes input

8. System prompt from registry used by spawn.sh
   Test: Set system_prompt in registry, run spawn.sh, verify Claude receives combined default + per-agent prompt
   Expected: Claude shows custom system prompt in initial context

9. System prompt from registry used by recovery
   Test: Set system_prompt in registry, run recover-openclaw-agents.sh, verify recovered sessions have custom prompt
   Expected: Recovered Claude sessions show custom system prompt

10. Hybrid mode: async sends background wake
    Test: Set hook_settings.hook_mode = "async", trigger Stop hook, verify hook exits immediately and openclaw call backgrounded
    Expected: Hook execution <100ms, openclaw agent receives wake asynchronously

11. Hybrid mode: bidirectional returns decision:block
    Test: Set hook_settings.hook_mode = "bidirectional", trigger Stop or PreCompact hook, OpenClaw agent returns decision:block, verify Claude receives instruction
    Expected: Hook waits for response, returns decision:block, Claude continues with injected instruction (no menu interaction)

12. Three-tier hook_settings fallback resolves correctly
    Test: Configure global hook_settings, per-agent partial override (e.g., only hook_mode), verify hook uses per-agent for overridden fields and global for others
    Expected: Per-field merge works, hook uses correct values from three-tier fallback
