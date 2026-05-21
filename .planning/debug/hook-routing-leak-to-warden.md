---
status: investigating
trigger: "hook-routing-leak-to-warden"
created: 2026-02-23T00:00:00Z
updated: 2026-02-23T10:55:00Z
---

## Current Focus

hypothesis: CONFIRMED — hook-context.mjs calls `tmux display-message -p '#S'` without first checking if $TMUX env var is set. When Claude Code runs outside tmux (direct TUI session), the tmux server still responds with the attached session name (agent_warden-kingdom_session_name), causing resolveAgentFromSession to match and route to Warden.
test: Verified by running `tmux display-message -p '#S'` from a non-tmux shell — returns 'agent_warden-kingdom_session_name' even with $TMUX unset.
expecting: Fix is to add `process.env.TMUX` guard in hook-context.mjs before calling tmux display-message (same pattern already used in hook-event-logger.sh)
next_action: ROOT CAUSE CONFIRMED — ready to report

## Symptoms

expected: Hooks fire but route to the correct agent based on the actual session, not always to Warden
actual: All hook events from direct TUI sessions route to Warden's agent/session files and trigger Warden's workflows with wrong context
errors: No crash errors — the routing silently goes to the wrong agent
reproduction: Talk directly in Claude Code TUI in the gsd-code-skill directory — hooks fire and events appear in Warden's JSONL files
started: Not sure exactly when — possibly since hooks were installed

## Eliminated

- hypothesis: hook-event-logger.sh is the source of the routing bug
  evidence: hook-event-logger.sh CORRECTLY checks `if [ -n "${TMUX:-}" ]` before calling tmux display-message. The logger is fine.
  timestamp: 2026-02-23T10:55:00Z

- hypothesis: agent-registry.json has wrong session_name config
  evidence: Registry is correct — session_name 'agent_warden-kingdom_session_name' is legitimately Warden's session. The problem is hook-context.mjs resolves to this name even when NOT in that tmux session.
  timestamp: 2026-02-23T10:55:00Z

- hypothesis: hooks are only installed locally for this project
  evidence: Hooks are in /home/forge/.claude/settings.json (GLOBAL), so they fire for ALL Claude Code sessions on this machine — including direct TUI sessions not in tmux.
  timestamp: 2026-02-23T10:55:00Z

## Evidence

- timestamp: 2026-02-23T10:50:00Z
  checked: /home/forge/.claude/settings.json
  found: Hooks registered GLOBALLY (not per-project). All 5 hook types (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop) fire for every Claude Code session.
  implication: Any Claude Code session on this machine fires the GSD hooks — including direct TUI sessions.

- timestamp: 2026-02-23T10:51:00Z
  checked: lib/hook-context.mjs lines 31-39
  found: readHookContext() calls `execFileSync('tmux', ['display-message', '-p', '#S'])` with NO check on process.env.TMUX first. The comment says "not in tmux means not a managed agent session" but the guard does NOT actually check for the tmux env variable — it just catches execFileSync errors.
  implication: If tmux server is running and has a session, display-message succeeds and returns a session name even when called from outside a tmux client.

- timestamp: 2026-02-23T10:52:00Z
  checked: bin/hook-event-logger.sh lines 42-45
  found: The bash logger CORRECTLY uses `if [ -n "${TMUX:-}" ]` to guard the tmux display-message call. If $TMUX is not set, TMUX_SESSION_NAME stays empty and log files use 'session-{short_id}' prefix instead of Warden's session name.
  implication: The bash script has the correct pattern. hook-context.mjs is missing the equivalent Node.js guard.

- timestamp: 2026-02-23T10:53:00Z
  checked: Shell environment + tmux behavior
  found: Running `tmux display-message -p '#S'` from a non-tmux shell (where $TMUX is unset) returns 'agent_warden-kingdom_session_name' — the single attached tmux session. tmux 3.4 resolves to the attached/most-recent session when no client context is specified.
  implication: hook-context.mjs resolveAgentFromSession('agent_warden-kingdom_session_name') returns the Warden agent config, and every hook routes to Warden.

- timestamp: 2026-02-23T10:54:00Z
  checked: lib/agent-resolver.mjs
  found: resolveAgentFromSession() correctly looks up by exact session_name match. It returns null for unknown sessions. The bug is upstream — hook-context.mjs passes a session name that DOES match Warden even though the calling process is not in Warden's session.
  implication: Fix belongs in hook-context.mjs, not in agent-resolver.mjs.

## Resolution

root_cause: lib/hook-context.mjs readHookContext() calls `tmux display-message -p '#S'` without first checking `process.env.TMUX`. When a direct TUI Claude Code session (not running inside tmux) fires hooks, the tmux server still responds with the currently-attached session name ('agent_warden-kingdom_session_name'). This matches Warden's entry in agent-registry.json, so all events are routed to Warden. The fix is a single guard: check `process.env.TMUX` before calling tmux — if it's not set, the hook is running outside a tmux session and should return null immediately. This is the exact same pattern hook-event-logger.sh already uses correctly.

fix: Add `if (!process.env.TMUX) return null;` as the first check in readHookContext(), before the tmux display-message call.

verification:
files_changed:
  - lib/hook-context.mjs
