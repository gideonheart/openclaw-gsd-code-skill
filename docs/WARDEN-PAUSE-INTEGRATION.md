# Warden Integration: Per-Session Hooks Pause Toggle

How to expose `bin/pause-session.mjs` as a per-agent toggle on [warden.kingdom.lv](https://warden.kingdom.lv).

> **Principle:** One data source, one toggle endpoint. No new polling hooks or parallel fetches.

---

## Architecture Overview

```
┌─────────────────────────┐       ┌──────────────────────────────────┐
│  warden.kingdom.lv      │       │  gsd-code-skill                  │
│                         │       │                                  │
│  AgentsTab.tsx          │       │  logs/pause-state.json           │
│    └─ "Hooks Paused"   │◄──────│    └─ { session: { paused } }   │
│       toggle button     │       │                                  │
│                         │       │  bin/pause-session.mjs           │
│  live-status endpoint   │───────│    └─ on / off / status          │
│    └─ reads file direct │       │                                  │
│                         │       │  readHookContext (step 2.5)      │
│  PATCH endpoint         │───────│    └─ isSessionPaused() gate     │
│    └─ shells out to CLI │       │                                  │
└─────────────────────────┘       └──────────────────────────────────┘
```

**Data flow:**
1. `GET /api/gsd/agents/live-status` already polls per agent — add `hooksPaused` field by reading `pause-state.json` directly (zero subprocess cost, read-only = no lock needed)
2. `PATCH /api/gsd/sessions/:session/hooks-paused` toggles state via `bin/pause-session.mjs` (one subprocess on click, CLI handles exclusive locking internally)
3. `AgentsTab.tsx` renders toggle using data already in `useAgentLiveStatus` — no new React hook

**Concurrency safety:** Writes go through `setSessionPauseState` which acquires an exclusive file lock (O_CREAT|O_EXCL mutex) before the read-modify-write cycle. Reads are lock-free (fail-open). Warden never needs to implement its own locking — the CLI handles it.

---

## Step 1: Shared Types

**File:** `src/shared/gsdTypes.ts`

The live-status response already returns per-agent data. No new interface needed — just extend the existing response shape where it's constructed.

---

## Step 2: Server — Read pause state in live-status (zero-cost piggyback)

**File:** `src/server/routes/gsdRoutes.ts`

### 2a. Add file read helper at top of file

```typescript
const PAUSE_STATE_FILE_PATH = '/home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/pause-state.json';

/**
 * Read the pause-state.json file and return the parsed map.
 * Returns empty object on any error (fail-open, matches gsd-code-skill behavior).
 */
async function readPauseStateMap(): Promise<Record<string, { paused: boolean; updatedAt: string }>> {
  try {
    const rawContent = await readFile(PAUSE_STATE_FILE_PATH, 'utf-8');
    return JSON.parse(rawContent);
  } catch {
    return {};
  }
}
```

**Why `readFile` (async) instead of `readFileSync`:** The live-status handler is already async and uses `Promise.allSettled`. Blocking the event loop with `readFileSync` would stall all concurrent requests. The async read is a single file read that happens once per poll, not per agent.

### 2b. Add `hooksPaused` to live-status response

Inside the `GET /api/gsd/agents/live-status` handler, read the pause state once before the agent map:

```typescript
router.get('/api/gsd/agents/live-status', async (_request, response) => {
  try {
    const registry = await gsdRegistryService.getRegistry();
    const pauseStateMap = await readPauseStateMap();  // ← ADD THIS

    const results = await Promise.allSettled(
      registry.agents.map(async (agent) => {
        // ... existing tmux capture-pane logic unchanged ...
        const hooksPaused = pauseStateMap[agent.tmux_session_name]?.paused === true;  // ← ADD THIS

        return {
          agentId: agent.agent_id,
          sessionName: agent.tmux_session_name,
          state,
          contextPressure,
          contextPressureLevel,
          hooksPaused,  // ← ADD THIS
        };
      }),
    );

    // ... rest unchanged ...
  }
});
```

For the null-session case (no `tmux_session_name`), add `hooksPaused: false` alongside the other null fields.

### 2c. Add PATCH endpoint for toggling

Add below the existing `POST /api/gsd/sessions/:session/command` handler:

```typescript
const PAUSE_SESSION_SCRIPT = '/home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/pause-session.mjs';

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
    const action = paused ? 'on' : 'off';
    const { stdout } = await execFileAsync('node', [PAUSE_SESSION_SCRIPT, session, action]);
    const result = JSON.parse(stdout);
    response.json(result);
  } catch (error) {
    console.error(`[GsdRoutes] Failed to toggle hooks-paused for ${session}:`, error);
    response.status(500).json({ error: 'Failed to toggle pause state' });
  }
});
```

The CLI outputs JSON: `{ "session": "...", "paused": true }` — parse with `JSON.parse(stdout)`.

**Why shell out to `bin/pause-session.mjs` instead of reading/writing the file directly:**
- SRP — warden is the UI layer, gsd-code-skill owns the state format
- Exclusive file lock (O_CREAT|O_EXCL mutex) serializes concurrent writes — warden doesn't need to implement locking
- Atomic write logic (tmp+rename inside lock) stays in one place
- JSONL audit log entry is written automatically by `setSessionPauseState`
- If the file format ever changes, warden doesn't need updating

---

## Step 3: Client — Extend existing hook return type

**File:** `src/client/hooks/useAgentLiveStatus.ts`

The live-status hook already returns a `Map<string, { state, contextPressure, contextPressureLevel }>`. Add `hooksPaused: boolean` to the value type. No new hook needed.

```typescript
// Wherever the live-status response is typed, add:
hooksPaused: boolean;
```

---

## Step 4: Client — Add toggle to AgentsTab

**File:** `src/client/components/AgentsTab.tsx`

### 4a. Add optimistic toggle state (same pattern as `toggleEnabled` in `useGsdRegistry`)

```typescript
const [optimisticHooksPaused, setOptimisticHooksPaused] = useState<Record<string, boolean>>({});

const toggleHooksPaused = useCallback(async (sessionName: string, currentPaused: boolean) => {
  const newPaused = !currentPaused;
  setOptimisticHooksPaused((previous) => ({ ...previous, [sessionName]: newPaused }));
  try {
    const response = await fetch(`/api/gsd/sessions/${sessionName}/hooks-paused`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ paused: newPaused }),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    // Clear optimistic overlay — next live-status poll picks up real state
    setOptimisticHooksPaused((previous) => {
      const next = { ...previous };
      delete next[sessionName];
      return next;
    });
  } catch {
    // Revert on error
    setOptimisticHooksPaused((previous) => ({ ...previous, [sessionName]: currentPaused }));
  }
}, []);
```

### 4b. Compute effective value in the agent card render

```typescript
const serverHooksPaused = agentStatus?.hooksPaused ?? false;
const effectiveHooksPaused = optimisticHooksPaused[agent.tmux_session_name] ?? serverHooksPaused;
```

### 4c. Render toggle button in the bottom row (next to Enabled/Disabled)

Replace the existing bottom row `<div>` with:

```tsx
{/* Bottom row: session name + hooks toggle + enabled toggle */}
<div className="flex items-center justify-between gap-2 pt-2 border-t border-warden-border/50">
  <span className="text-xs text-warden-text-dim font-mono truncate">
    {agent.tmux_session_name || '\u2014'}
  </span>
  <div className="flex items-center gap-1.5">
    {agent.tmux_session_name && (
      <button
        onClick={() => toggleHooksPaused(agent.tmux_session_name, effectiveHooksPaused)}
        className={`px-2 py-0.5 rounded text-xs transition-colors flex-shrink-0 ${
          effectiveHooksPaused
            ? 'bg-amber-500/20 text-amber-400 hover:bg-amber-500/30'
            : 'bg-warden-success/20 text-warden-success hover:bg-warden-success/30'
        }`}
      >
        {effectiveHooksPaused ? 'Hooks Paused' : 'Hooks Active'}
      </button>
    )}
    <button
      onClick={() => toggleEnabled(agent.agent_id, effectiveEnabled)}
      className={`px-2 py-0.5 rounded text-xs transition-colors flex-shrink-0 ${
        effectiveEnabled
          ? 'bg-warden-success/20 text-warden-success hover:bg-warden-success/30'
          : 'bg-warden-error/20 text-warden-error hover:bg-warden-error/30'
      }`}
    >
      {effectiveEnabled ? 'Enabled' : 'Disabled'}
    </button>
  </div>
</div>
```

**Why amber/yellow for paused:** Visually distinct from enabled (green) and disabled (red). Amber means "degraded but intentional" — the agent is running, hooks fire, but auto-drive is paused.

---

## Summary of Changes Per File

| File | Change | Lines |
|------|--------|-------|
| `src/shared/gsdTypes.ts` | No change needed (response shape is inline) | 0 |
| `src/server/routes/gsdRoutes.ts` | Add `readPauseStateMap()`, extend live-status response, add PATCH endpoint | ~35 |
| `src/client/hooks/useAgentLiveStatus.ts` | Add `hooksPaused` to return type | ~2 |
| `src/client/components/AgentsTab.tsx` | Add `optimisticHooksPaused` state + `toggleHooksPaused` + render button | ~30 |

**Total: ~67 lines across 3 files. No new files, no new hooks, no new polling loops.**

---

## Why This Is DRYer Than Separate Endpoints + Hook

The plan's original approach suggested:
1. Separate `GET /api/gsd/sessions/:session/hooks-paused` polling endpoint
2. Separate `useSessionPauseState` React hook with its own 10s polling interval
3. Per-session fetch calls (N sessions = N fetch calls per interval)

**Problems with that approach:**
- **Duplicate polling** — live-status already polls every 5s per agent. Adding another 10s poll per session doubles network traffic for no reason.
- **New React hook** — creates a parallel data source for the same agent card. Now `AgentsTab` imports from two hooks that poll independently. State can desync.
- **N+1 requests** — querying pause state per-session means N requests. Reading `pause-state.json` once in live-status is O(1).

**The piggyback approach:**
- One file read (`readPauseStateMap()`) piggybacked on the existing live-status poll
- Data arrives in the same response `AgentsTab` already consumes
- Optimistic toggle uses the same pattern as the existing `toggleEnabled`
- Zero new polling infrastructure
