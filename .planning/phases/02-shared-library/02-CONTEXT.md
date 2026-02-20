# Phase 2: Shared Library - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the Node.js shared lib at `lib/` with agent resolution, gateway delivery, JSON field extraction, retry utility, and JSONL logging — importable by any event handler with no code duplication across handlers. This phase delivers the library only; event handlers that consume it are Phase 3 and Phase 4.

</domain>

<decisions>
## Implementation Decisions

### Session-to-agent matching
- Lookup key is the **tmux session name** — hook reads the current tmux session name and matches against `session_name` field in `config/agent-registry.json`
- Session names are dynamic (e.g., `agent_warden-kingdom_session_name`) — matching must handle any registered value
- **Unrecognized sessions silently skip (exit 0)** — not every tmux session running Claude Code is a managed agent
- No error, no log for unrecognized sessions — clean exit

### Failure behavior
- **Gateway failures use exponential backoff:** starting at 5s, doubling each attempt (5s, 10s, 20s, 40s...), up to 10 attempts
- Each retry attempt logged to JSONL: `1/10`, `2/10`, etc.
- After all 10 attempts fail, throw error (handler catches)
- **Retry is a separate utility** (`retryWithBackoff`) — not baked into `wakeAgentViaGateway()`. Any lib function can be wrapped with it.
- `extractJsonField()` returns null + logs warning to JSONL for both invalid JSON and missing fields

### Wake call content
- Three things sent to the agent when woken:
  1. **Content:** `last_assistant_message` from the Claude Code session (trimmed whitespace only, no truncation)
  2. **Prompt:** A structured `.md` file per event type/subtype — contains TUI driver script references, keystroke instructions (up, down, space, tab, enter), and event-specific guidance
  3. **Event metadata:** event_type, session_name, timestamp — included in the wake call for agent context
- The per-event prompt is the single source of TUI driving instructions — no separate TUI field needed

### Module structure
- **Split files with re-export from `lib/index.mjs`** — one file per concern (agent-resolver, gateway, json-extractor, retry, logger)
- `lib/index.mjs` re-exports everything — event handlers import from one entry point

### JSONL logging
- Lib has its **own JSONL logging implementation** — self-contained, no dependency on `bin/hook-event-logger.sh`
- Writes to the **same JSONL log file** as hook-event-logger — unified timeline of all events
- Must use **atomic writes** (`flock -x` or Node.js equivalent) for concurrent hook safety
- When Phase 3+ event handlers use the lib logger, the bash hook-event-logger becomes redundant and can be disabled (no double logging)

### Claude's Discretion
- Best method to read tmux session name from a hook process (tmux display-message, TMUX env var parsing, or other)
- Whether `resolveAgentFromSession()` checks the `enabled` field internally or returns the full config for the handler to decide
- Best CLI invocation format for `openclaw agent` (flag-based, JSON payload, piped content) — considering prompts are `.md` files
- Best way to pass prompt content to OpenClaw (file reference vs inline content)

</decisions>

<specifics>
## Specific Ideas

- Retry logging should show progress like `1/10`, `2/10` — user wants visibility into retry state
- JSONL logger should be designed as the long-term replacement for the bash hook-event-logger — same file, same atomic guarantees, Node.js native
- The atomic JSONL write pattern (`flock -x`) from Phase 1 must be preserved in the Node.js implementation
- Timestamp captured once per log entry (avoid redundant date calls — lesson from Phase 01.1)

</specifics>

<deferred>
## Deferred Ideas

- Disabling/removing `bin/hook-event-logger.sh` once Node.js event handlers fully replace it — Phase 3+ concern
- Any event-specific handler logic — Phase 3 (Stop) and Phase 4 (AskUserQuestion)

</deferred>

---

*Phase: 02-shared-library*
*Context gathered: 2026-02-20*
