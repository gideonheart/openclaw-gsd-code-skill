# Phase 2: Hook Wiring - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Register all 5 hook scripts (stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh, pre-compact-hook.sh) globally in `~/.claude/settings.json` and remove the obsolete `gsd-session-hook.sh` from SessionStart hooks. This is configuration wiring only — no new scripts, no launcher changes.

</domain>

<decisions>
## Implementation Decisions

### SessionEnd scope
- Fire on ALL exit reasons (logout, /clear, prompt_input_exit, other) — no matcher filtering
- OpenClaw agent decides relevance based on the `reason` field in stdin JSON
- Use the same `/hooks/wake` webhook with a `session_end` trigger type

### SessionStart cleanup
- Keep `gsd-check-update.js` in SessionStart hooks array — only remove `gsd-session-hook.sh`
- No new SessionStart hook registration in this phase — scope is wiring the 5 Phase 1 hooks only

### Claude's Discretion
- **PreCompact trigger scope** — Claude decides whether to match auto-only, manual-only, or both (recommendation: both, synchronous)
- **Stop hook blocking behavior** — Claude decides whether bidirectional agents use the blocking mechanism (decision:block) or fire-and-forget (recommendation: blocking for bidirectional, async for default)
- **Hook registration approach** — Claude decides whether to create a registration script or directly edit settings.json in plan tasks (recommendation: registration script for idempotency/portability)
- **Hook async/timeout configuration** — Claude decides appropriate timeout values and async flags per hook type
- **Notification hook matchers** — Claude decides exact matcher values (idle_prompt, permission_prompt)

</decisions>

<specifics>
## Specific Ideas

- The existing settings.json already has the hooks structure with SessionStart — add new event types alongside it
- Hook scripts are at absolute paths under `/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/`
- Claude Code hook format: `{"type": "command", "command": "bash \"/path/to/script.sh\""}` inside event arrays

</specifics>

<deferred>
## Deferred Ideas

- SessionStart context injection (inject agent identity/state on startup) — could be a future enhancement
- Hook health monitoring / observability — v2 requirements (OBS-01, OBS-02)

</deferred>

---

*Phase: 02-hook-wiring*
*Context gathered: 2026-02-17*
