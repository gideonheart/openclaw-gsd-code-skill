# Phase 3 Context: Stop Event (Full Stack)

## Overview

Phase 3 delivers the complete Stop event pipeline: when Claude Code's assistant turn ends, the handler wakes the OpenClaw agent with context, the agent decides what command to run next, and a generic TUI driver executes the command sequence in the tmux pane via an event-driven queue.

---

## 1. Wake-Up Filtering

### When to wake the agent
- Stop fires AND `stop_hook_active: false` AND no queue exists for this session AND `last_assistant_message` is present (non-empty)
- Handler wakes the OpenClaw agent via gateway with content + prompt

### When to skip
- `stop_hook_active: true` — re-entrancy guard from Claude Code. Exit silently (exit 0). Logging is at Claude's discretion.
- Session not in `agent-registry.json` — `resolveAgentFromSession()` returns null. Exit silently. Agent resolver already handles this (Phase 2).
- `last_assistant_message` is empty/missing — nothing for the agent to act on. Exit silently.

### When queue exists
- Stop handler delegates to the shared queue processor instead of waking the agent. Queue processor checks if the active command's `awaits` matches `{ hook: "Stop" }` — if yes, advance. Details in Section 4.

---

## 2. Content Delivered to Agent

### Established pattern (Phase 2 — do not re-ask)
- Content = `last_assistant_message` + extracted structured data
- Instructions = the event's prompt `.md` file (read at call time, not cached)
- Combined format: metadata first, content second, instructions last

### Stop-specific content
The handler extracts suggested commands from `last_assistant_message` as a convenience (not decision-making):

```javascript
const commands = message.match(/\/(?:gsd:[a-z-]+(?:\s+[^\s`]+)?|clear)/g) || [];
const suggestedCommands = [...new Set(commands)]; // deduplicate
```

Agent receives:
- `last_assistant_message` — full text of Claude Code's response
- `suggested_commands` — array of `/gsd:*` and `/clear` commands found in the text (suggestions only, agent decides)

### Agent autonomy
The agent is the decision-maker. `suggested_commands` are convenience extractions, not instructions. The agent may use them as-is, reorder, skip, or choose entirely different commands.

---

## 3. Agent Decision Prompt (`prompt_stop.md`)

### Structure
```markdown
# Stop Event

Claude Code has stopped and is waiting for input.

## What you received
- `last_assistant_message`: Claude Code's final response before stopping
- `suggested_commands`: Commands extracted from the response (any /gsd:* and /clear found in the text)

## What to do
1. Read the message. Understand what Claude Code just finished or why it stopped.
2. Review `suggested_commands` — these are what Claude Code recommended, but you decide.
   - You may use them as-is, reorder them, skip some, or choose entirely different commands.
   - They are suggestions, not instructions.
3. Decide your command array and call the TUI driver:
   node bin/tui-driver.mjs '{ "session": "...", "commands": ["/clear", "/gsd:plan-phase 3"] }'

## Command types and their awaits
- `/gsd:*` commands -> Claude responds -> awaits Stop
- `/clear` -> clears context -> awaits SessionStart(source:clear)
- The TUI driver handles awaits automatically.

## When to do nothing
- If the work is complete and no next phase exists, respond with no commands.
- The queue will not be created and the session stays idle.
```

### Key principles
- Relevant command subset only — no duplication of full GSD system (agent already has AGENT.md and SOUL.md)
- Instructions for how to drive TUI in this specific event
- Link to the TUI driver script the agent calls
- Decision rules for common scenarios, but agent retains autonomy to override

---

## 4. TUI Driver and Queue System

### Architecture: Agent = Brain, Script = Hands

The agent NEVER types raw keystrokes. The agent NEVER interacts with tmux directly. The agent:
1. Reads Claude Code's response
2. Decides what commands to run
3. Prepares structured data (command array)
4. Calls the generic TUI driver script

The TUI driver script handles all TUI mechanics: typing, tab completion, delays, Enter.

### Generic TUI Driver (`bin/tui-driver.mjs`)

- Accepts a JSON argument with session name and command array
- Creates the queue file with proper `awaits` per command type
- Types the first command into tmux via `lib/tui-common.mjs`
- Exits (fire-and-forget)
- The hook-driven queue processor handles all subsequent commands

### Command-to-awaits mapping
| Command pattern | Awaits hook | Awaits sub |
|----------------|-------------|------------|
| `/clear` | `SessionStart` | `clear` (source field) |
| `/gsd:*` | `Stop` | `null` |

### Queue file schema

Location: `logs/queues/queue-{session_name}.json` (gitignored, runtime artifact)

```json
{
  "commands": [
    {
      "id": 1,
      "command": "/clear",
      "status": "active",
      "trigger": { "hook": "Stop", "sub": null },
      "awaits": { "hook": "SessionStart", "sub": "clear" },
      "result": null,
      "completed_at": null
    },
    {
      "id": 2,
      "command": "/gsd:plan-phase 3",
      "status": "pending",
      "trigger": { "hook": "SessionStart", "sub": "clear" },
      "awaits": { "hook": "Stop", "sub": null },
      "result": null,
      "completed_at": null
    }
  ]
}
```

### Status flow
```
pending -> active -> done
                  -> failed (future — not implemented in Phase 3)
```

Queue-level status: `cancelled` (when manual input detected via UserPromptSubmit)

### Queue lifecycle

**Creation:**
1. Agent calls `node bin/tui-driver.mjs '{ "session": "warden-main-4", "commands": [...] }'`
2. TUI driver writes queue file (atomic: write .tmp, rename)
3. TUI driver marks first command as `active`, types it into tmux
4. TUI driver exits

**Advancement (hook-driven, no polling):**
5. Claude Code processes command -> fires the expected hook (Stop or SessionStart)
6. Hook handler calls shared queue processor
7. Queue processor: incoming hook matches active command's `awaits`? -> mark `done`, save `last_assistant_message` as `result`, save `completed_at`
8. Next pending command? -> mark `active`, type it into tmux via `lib/tui-common.mjs`
9. Repeat from step 5

**Completion:**
10. Queue empty -> wake agent with FYI: "Queue complete. N/N commands executed. Results attached."
11. The queue file itself is the attachment — agent reads all results

**Cancellation (manual input):**
- `UserPromptSubmit` fires while queue exists -> rename queue to `.stale.json`, wake agent: "Queue cancelled by manual input. Completed: X/Y. Remaining: [...]"

**Stale cleanup (session restart):**
- `SessionStart` fires with `source: "startup"` -> check for existing queue file
  - Exists -> rename to `.stale.json`, wake agent: "Previous session had unfinished queue"
  - Does not exist -> clean start, do nothing

### Concurrency model
- Session isolation: each session has its own queue file. No cross-session writes.
- Atomic writes: write to `.tmp`, rename. POSIX-atomic. No flock needed.
- Claude Code fires events sequentially per session — no concurrent Stop events for the same session.

### Idle state
- Agent decides not to act -> does not call TUI driver -> no queue file created -> session stays idle at input prompt
- No explicit "idle" signal needed. No queue = idle.

---

## 5. Hook Handlers and Shared Modules

### Phase 3 delivers three hook handlers

All are thin entry points (~10-15 lines each) that call the shared queue processor.

| Handler | Hook | Behavior |
|---------|------|----------|
| `events/stop/event_stop.js` | Stop | Queue exists? Advance. No queue? Wake agent with content + prompt. |
| `events/session_start/event_session_start.js` | SessionStart | `source: "clear"` -> advance queue. `source: "startup"` -> stale cleanup. |
| `events/user_prompt_submit/event_user_prompt_submit.js` | UserPromptSubmit | Queue exists? Cancel it. No queue? Ignore. |

### Phase 3 adds two new lib modules

| Module | Responsibility |
|--------|---------------|
| `lib/queue-processor.mjs` | Read queue, match incoming hook against active command's `awaits`, advance/complete/cancel. Shared across all handlers. |
| `lib/tui-common.mjs` | tmux send-keys wrapper. Types text, handles Tab, Enter. Used by both `bin/tui-driver.mjs` and `lib/queue-processor.mjs`. |

### Existing lib modules used (from Phase 2)

| Module | Used for |
|--------|----------|
| `lib/agent-resolver.mjs` | Resolve session name to agent config |
| `lib/gateway.mjs` | Wake agent via OpenClaw gateway |
| `lib/index.mjs` | Unified import entry point |

---

## 6. File/Folder Structure

```
bin/
  tui-driver.mjs                         <- generic: parse commands, create queue, type first
  hook-event-logger.sh                   <- existing debug tool

events/
  stop/
    event_stop.js                        <- Stop hook entry point
    prompt_stop.md                       <- agent prompt for Stop events
  session_start/
    event_session_start.js               <- /clear completion + stale cleanup
  user_prompt_submit/
    event_user_prompt_submit.js          <- cancel queue on manual input

lib/
  queue-processor.mjs                    <- shared: read/advance/complete queue
  tui-common.mjs                         <- shared: tmux send-keys wrapper
  agent-resolver.mjs                     <- existing (Phase 2)
  gateway.mjs                            <- existing (Phase 2)
  logger.mjs                             <- existing (Phase 2)
  retry.mjs                              <- existing (Phase 2)
  json-extractor.mjs                     <- existing (Phase 2)
  paths.mjs                              <- existing (Phase 2)
  index.mjs                              <- existing entry point

logs/
  queues/                                <- runtime, gitignored
    queue-{session}.json                 <- active queue
    queue-{session}.stale.json           <- crashed/interrupted/cancelled queue

config/
  agent-registry.json                    <- existing
```

### Convention: `events/{hook_name}/` mirrors `settings.json`
If it's a hook in `~/.claude/settings.json`, it gets a folder in `events/`. If it's shared logic, it goes in `lib/`. Entry points are tiny — they parse stdin and call shared modules.

### Extension: `.mjs` everywhere
Follows existing Phase 2 convention. All ESM, all `.mjs`. No mixing.

---

## 7. Deferred Items (Out of Phase 3 Scope)

| Item | Target Phase | Notes |
|------|-------------|-------|
| AskUserQuestion TUI driver (multiSelect + single-select) | Phase 4 | Complex TUI navigation: arrows, space, free text input, submit |
| Notification (idle_prompt) queue processing | Phase 4+ | Queue processor is extensible via `awaits` |
| Hook registration in `~/.claude/settings.json` | Phase 5 | All three Phase 3 handlers need registration |
| Error/failure status in queue | Future | Keep plumbing dumb for now. Agent evaluates results. |

---

## 8. Key Design Principles

1. **Handler = dumb plumbing.** Deliver mail. Don't make decisions.
2. **Agent = brain.** Reads context, decides commands, calls scripts. Retains full autonomy.
3. **Script = hands.** Receives structured data, handles all TUI mechanics. Agent never touches tmux.
4. **Queue processor is hook-agnostic.** Same function called by Stop, SessionStart, UserPromptSubmit. Just matches `awaits`.
5. **Event-driven, no polling.** Claude Code hooks are the synchronization mechanism. No timers, no delays, no pane watching.
6. **Atomic writes, no locks.** Write to `.tmp`, rename. Session-scoped files eliminate cross-session races.
7. **Keep the plumbing dumb.** No error detection heuristics in the queue processor. Agent evaluates all results.

---

*Created: 2026-02-20 after discuss-phase session*
