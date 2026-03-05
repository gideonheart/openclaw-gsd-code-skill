---
phase: quick-27
plan: 27
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/pause-state.mjs
  - lib/index.mjs
  - lib/hook-context.mjs
  - bin/pause-session.mjs
autonomous: true
requirements: []
must_haves:
  truths:
    - "A paused session logs hook events but does NOT type commands or wake agents"
    - "An unpaused session behaves exactly as before (no regression)"
    - "CLI can set, clear, and query pause state per session"
    - "Pause state persists across hook invocations (file-backed)"
    - "Pause gate lives in ONE place (readHookContext) — zero handler duplication"
  artifacts:
    - path: "lib/pause-state.mjs"
      provides: "isSessionPaused and setSessionPauseState functions"
      exports: ["isSessionPaused", "setSessionPauseState"]
    - path: "bin/pause-session.mjs"
      provides: "CLI to toggle and query pause state"
    - path: "logs/pause-state.json"
      provides: "Runtime pause-state storage (created on first write)"
  key_links:
    - from: "lib/hook-context.mjs"
      to: "lib/pause-state.mjs"
      via: "isSessionPaused check inside readHookContext after agent resolution"
      pattern: "isSessionPaused\\(sessionName\\)"
    - from: "lib/index.mjs"
      to: "lib/pause-state.mjs"
      via: "re-export"
      pattern: "export.*from.*pause-state"
---

<objective>
Add a per-session pause flag that disables auto-drive behavior (TUI typing and gateway wakes) while keeping hook event logging intact.

Purpose: Allow Rolands or Warden's dashboard to pause a session's auto-drive hooks without disabling the agent or stopping Claude Code — useful for debugging, manual intervention, or temporarily silencing a session.

Output: `lib/pause-state.mjs` library + pause gate inside `readHookContext` + `bin/pause-session.mjs` CLI.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@lib/index.mjs
@lib/paths.mjs
@lib/hook-context.mjs
@lib/logger.mjs
@bin/pause-session.mjs (new)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create pause-state library, integrate into readHookContext, and build CLI</name>
  <files>
    lib/pause-state.mjs
    lib/hook-context.mjs
    lib/index.mjs
    bin/pause-session.mjs
  </files>
  <action>
**1a. Create `lib/pause-state.mjs`**

Two exported functions:

1. `isSessionPaused(sessionName)` — Returns boolean. Reads `logs/pause-state.json` (resolve via `SKILL_ROOT` from `lib/paths.mjs`). The file stores a JSON object mapping session names to `{ paused: boolean, updatedAt: string }`. If the file does not exist or the session has no entry, return `false` (default = unpaused). Wrap the file read in try/catch — if read or parse fails, return `false` (fail-open, never block hooks due to corrupt state file). No logging on reads (this runs on every hook invocation — must be zero-noise).

2. `setSessionPauseState(sessionName, paused)` — Reads the existing file (or starts with empty object `{}`), sets `state[sessionName] = { paused, updatedAt: new Date().toISOString() }`, writes atomically (write to `.tmp` then rename, same pattern as `writeQueueFileAtomically` in queue-processor.mjs). Use `mkdirSync(dirname(pauseStateFilePath), { recursive: true })` to ensure `logs/` directory exists. Log one JSONL entry via `appendJsonlEntry` when state changes: `{ level: 'info', source: 'pause-state', message: 'Session pause state updated', session: sessionName, paused }`.

Export the constant `PAUSE_STATE_FILE_PATH` (built from `resolve(SKILL_ROOT, 'logs', 'pause-state.json')`) for use by the CLI and tests.

Import pattern — follow existing lib conventions:
```javascript
import { resolve } from 'node:path';
import { readFileSync, writeFileSync, renameSync, mkdirSync } from 'node:fs';
import { SKILL_ROOT } from './paths.mjs';
import { appendJsonlEntry } from './logger.mjs';
```

**1b. Integrate pause gate into `readHookContext` (DRY — one place, all handlers get it for free)**

In `lib/hook-context.mjs`, add the pause check AFTER step 2 (agent registry resolved — we have `sessionName`) and BEFORE step 3 (stdin read — skip wasted I/O for paused sessions).

Why here and not in each handler: all 5 event handlers call `readHookContext` as their first guard. Putting the pause check here means zero handler files change. If we put it in each handler, we'd copy-paste the exact same block into 5 files — DRY violation.

```javascript
import { isSessionPaused } from './pause-state.mjs';

// Inside readHookContext, after resolvedAgent check, before stdin read:

// 2.5. Check pause state — paused sessions skip all auto-drive processing
if (isSessionPaused(sessionName)) {
  appendJsonlEntry({
    level: 'info',
    source: handlerSource,
    message: 'Session paused — skipping auto-drive',
    session: sessionName,
  }, sessionName);
  return null;
}
```

When `readHookContext` returns `null`, every handler already does `if (!hookContext) process.exit(0)` — so paused sessions exit cleanly with zero handler changes.

Note: The pause log entry does NOT include `hookPayload` because stdin hasn't been read yet. This is intentional — the bash `hook-event-logger.sh` already captures the raw event before the Node handler runs. The pause log just records that the session was paused.

**1c. Add re-exports to `lib/index.mjs`**

Add: `export { isSessionPaused, setSessionPauseState } from './pause-state.mjs';`

**1d. Create `bin/pause-session.mjs` (executable CLI)**

```
#!/usr/bin/env node
```

Parse argv: `bin/pause-session.mjs <session-name> <on|off|status>`

- `on` — calls `setSessionPauseState(sessionName, true)`, prints `Session '<sessionName>' paused.`
- `off` — calls `setSessionPauseState(sessionName, false)`, prints `Session '<sessionName>' unpaused.`
- `status` — calls `isSessionPaused(sessionName)`, prints `Session '<sessionName>' is paused.` or `Session '<sessionName>' is not paused.`
- Invalid args — print usage and exit 1.
- Import from `../lib/index.mjs` (same pattern as other bin/ scripts).
- Run `chmod +x` on the file.
  </action>
  <verify>
    <automated>node bin/pause-session.mjs test-session on && node bin/pause-session.mjs test-session status && node bin/pause-session.mjs test-session off && node bin/pause-session.mjs test-session status && node --check lib/pause-state.mjs && node --check lib/hook-context.mjs && node --check bin/pause-session.mjs</automated>
    <manual>Verify output shows: paused, "is paused", unpaused, "is not paused" in sequence. Check logs/pause-state.json exists with test-session entry. Verify readHookContext has the pause gate between agent-registry check and stdin read.</manual>
  </verify>
  <done>
    - `lib/pause-state.mjs` exports `isSessionPaused`, `setSessionPauseState`, and `PAUSE_STATE_FILE_PATH`
    - `lib/hook-context.mjs` has pause gate at step 2.5 (after agent resolution, before stdin read)
    - `lib/index.mjs` re-exports both functions
    - `bin/pause-session.mjs` is executable and handles on/off/status subcommands
    - `logs/pause-state.json` is created on first write with correct schema
    - Atomic writes (tmp+rename) prevent corruption
    - Fail-open: corrupt or missing state file = unpaused (never blocks hooks)
    - ALL 5 event handlers get pause behavior with ZERO handler file changes
  </done>
</task>

</tasks>

<warden_integration_instructions>
## How to hook this into warden.kingdom.lv

The gsd-code-skill side is self-contained — `bin/pause-session.mjs` is the CLI interface.
Warden needs 3 things to expose this as a per-session toggle:

### 1. API endpoint (server side)

Add to `src/server/routes/gsdRoutes.ts`, following the existing `PATCH /api/gsd/registry/agents/:agentId` pattern:

```typescript
// PATCH /api/gsd/sessions/:session/hooks-paused — toggle auto-drive hooks pause state
router.patch('/api/gsd/sessions/:session/hooks-paused', async (request, response) => {
  const session = String(request.params.session);

  if (!SESSION_NAME_RE.test(session)) {
    response.status(400).json({ error: 'Invalid session name' });
    return;
  }

  const { paused } = request.body as { paused?: unknown };

  if (typeof paused !== 'boolean') {
    response.status(400).json({ error: 'paused must be a boolean' });
    return;
  }

  try {
    const PAUSE_SESSION_SCRIPT = '/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/pause-session.mjs';
    const action = paused ? 'on' : 'off';
    await execFileAsync('node', [PAUSE_SESSION_SCRIPT, session, action]);
    response.json({ session, paused });
  } catch (error) {
    console.error(`[GsdRoutes] Failed to toggle hooks-paused for ${session}:`, error);
    response.status(500).json({ error: 'Failed to toggle pause state' });
  }
});

// GET /api/gsd/sessions/:session/hooks-paused — query pause state
router.get('/api/gsd/sessions/:session/hooks-paused', async (request, response) => {
  const session = String(request.params.session);

  if (!SESSION_NAME_RE.test(session)) {
    response.status(400).json({ error: 'Invalid session name' });
    return;
  }

  try {
    const PAUSE_SESSION_SCRIPT = '/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/pause-session.mjs';
    const { stdout } = await execFileAsync('node', [PAUSE_SESSION_SCRIPT, session, 'status']);
    const paused = stdout.includes('is paused');
    response.json({ session, paused });
  } catch (error) {
    console.error(`[GsdRoutes] Failed to query hooks-paused for ${session}:`, error);
    response.status(500).json({ error: 'Failed to query pause state' });
  }
});
```

### 2. React hook (client side)

Create `src/client/hooks/useSessionPauseState.ts` — follows the same optimistic-update pattern as `useGsdRegistry.ts`:

```typescript
// Hook shape:
// const { isPaused, togglePaused } = useSessionPauseState(sessionName);
//
// - isPaused: boolean (optimistic, updates immediately on click)
// - togglePaused: () => void (PATCHes the API, reverts on error)
//
// Polls GET /api/gsd/sessions/:session/hooks-paused every 10s to sync state.
```

### 3. UI toggle (AgentsTab.tsx)

Add a "Hooks Paused" / "Hooks Active" toggle button next to the existing "Enabled"/"Disabled" button in the agent card's bottom row. Same visual style, but orange/yellow when paused:

```tsx
<button
  onClick={() => togglePaused()}
  className={`px-2 py-0.5 rounded text-xs transition-colors flex-shrink-0 ${
    isPaused
      ? 'bg-amber-500/20 text-amber-400 hover:bg-amber-500/30'
      : 'bg-warden-success/20 text-warden-success hover:bg-warden-success/30'
  }`}
>
  {isPaused ? 'Hooks Paused' : 'Hooks Active'}
</button>
```

### Live-status integration (optional enhancement)

The existing `GET /api/gsd/agents/live-status` endpoint could include `hooksPaused` per agent — read `logs/pause-state.json` directly alongside the tmux pane capture. This avoids per-session polling from the client and gives the AgentsTab a single data source.

</warden_integration_instructions>

<verification>
Full integration check:

1. Pause a test session: `node bin/pause-session.mjs test-session on`
2. Verify state file: `cat logs/pause-state.json` shows `test-session` with `paused: true`
3. Query status: `node bin/pause-session.mjs test-session status` prints "is paused"
4. Unpause: `node bin/pause-session.mjs test-session off`
5. Verify unpaused: `node bin/pause-session.mjs test-session status` prints "is not paused"
6. Code review: `readHookContext` has pause gate at step 2.5 (after agent resolution, before stdin read)
7. Code review: NO event handler files were modified (DRY — readHookContext handles it all)
8. Syntax check: `node --check lib/pause-state.mjs && node --check lib/hook-context.mjs && node --check bin/pause-session.mjs`
</verification>

<success_criteria>
- `lib/pause-state.mjs` exists with `isSessionPaused` and `setSessionPauseState` exports
- `bin/pause-session.mjs` is executable and handles on/off/status
- Pause gate is inside `readHookContext` at step 2.5 — ONE location, all handlers get it
- Zero event handler files modified (DRY compliance)
- Paused sessions still get raw event logging (via bash logger) but skip all Node handler logic
- Default state is unpaused — missing file or missing entry = not paused (fail-open)
- Atomic writes prevent corruption from concurrent hook invocations
- No abbreviations in any function or variable names (CLAUDE.md rule)
- Warden integration path documented with concrete endpoint, hook, and UI examples
</success_criteria>

<output>
After completion, create `.planning/quick/27-add-per-session-auto-drive-hooks-toggle-/27-SUMMARY.md`
</output>
