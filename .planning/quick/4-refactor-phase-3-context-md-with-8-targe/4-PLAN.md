---
phase: quick-4
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - .planning/phases/03-stop-event-full-stack/03-CONTEXT.md
autonomous: true
requirements: []

must_haves:
  truths:
    - "Queue schema has no trigger field — only id, command, status, awaits, result, completed_at"
    - "TUI driver call signature uses --session flag and array argument, not a JSON blob"
    - "All event handler files in Section 5 and Section 6 use .mjs extension, not .js"
    - "Queue-complete payload definition exists as a subsection in Section 4"
    - "Agent prompt section (Section 3) mentions queue-complete context"
    - "Hook registration is in Phase 3 scope (Section 5), not deferred (Section 7)"
    - "UserPromptSubmit cancellation trade-off is documented in Section 4"
    - "idle_prompt is flagged as potential Phase 3.5 need in Section 7"
  artifacts:
    - path: ".planning/phases/03-stop-event-full-stack/03-CONTEXT.md"
      provides: "Refined Phase 3 architecture document with all 8 improvements"
      contains: "queue-complete"
  key_links: []
---

<objective>
Apply 8 targeted improvements to Phase 3 CONTEXT.md before planning begins.

Purpose: Correct inaccuracies and add missing definitions discovered during the discuss-phase session, so the plan-phase operates on a clean, complete spec.
Output: Updated 03-CONTEXT.md with all 8 refactors applied.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/03-stop-event-full-stack/03-CONTEXT.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Apply all 8 targeted refactors to 03-CONTEXT.md</name>
  <files>.planning/phases/03-stop-event-full-stack/03-CONTEXT.md</files>
  <action>
Read the full file, then apply these 8 edits in order. Each is a surgical text change.

**Refactor 1 — Drop `trigger` field from queue schema (Section 4)**
In the queue file schema JSON example (around lines 117-139), remove the `"trigger"` field from BOTH command objects. The queue schema should only contain: `id`, `command`, `status`, `awaits`, `result`, `completed_at`. The `trigger` field is redundant — each command's `awaits` is sufficient for the queue processor to know when to advance.

**Refactor 2 — Fix TUI driver call signature (Section 3 + Section 4)**
The TUI driver should NOT accept a single JSON string argument. Change to flag-based CLI:
- In Section 3 prompt (around line 67), change the example from:
  `node bin/tui-driver.mjs '{ "session": "...", "commands": ["/clear", "/gsd:plan-phase 3"] }'`
  to:
  `node bin/tui-driver.mjs --session <name> /clear "/gsd:plan-phase 3"`
- In Section 4 "Generic TUI Driver" description (around line 101), change "Accepts a JSON argument with session name and command array" to "Accepts a `--session <name>` flag followed by commands as positional arguments"
- In Section 4 queue lifecycle "Creation" step 1 (around line 153), change the example from:
  `node bin/tui-driver.mjs '{ "session": "warden-main-4", "commands": [...] }'`
  to:
  `node bin/tui-driver.mjs --session warden-main-4 /clear "/gsd:plan-phase 3"`

**Refactor 3 — Fix file extensions `.mjs` everywhere (Section 5 + Section 6)**
In Section 5 handler table (around lines 196-198), rename all `.js` to `.mjs`:
- `events/stop/event_stop.js` -> `events/stop/event_stop.mjs`
- `events/session_start/event_session_start.js` -> `events/session_start/event_session_start.mjs`
- `events/user_prompt_submit/event_user_prompt_submit.js` -> `events/user_prompt_submit/event_user_prompt_submit.mjs`

In Section 6 file tree (around lines 226-231), rename all `.js` to `.mjs`:
- `event_stop.js` -> `event_stop.mjs`
- `event_session_start.js` -> `event_session_start.mjs`
- `event_user_prompt_submit.js` -> `event_user_prompt_submit.mjs`

Also update the tree comments to match (e.g., "Stop hook entry point" stays the same, just the filename changes).

**Refactor 4 — Add queue-complete payload definition (new subsection in Section 4)**
After the "Completion" subsection (after line 167, before "Cancellation"), add a new subsection:

```
### Queue-complete payload

When all commands are done, the agent is woken with this content structure:

\`\`\`json
{
  "event": "queue-complete",
  "session": "warden-main-4",
  "summary": "3/3 commands completed",
  "commands": [
    { "id": 1, "command": "/clear", "status": "done", "result": null, "completed_at": "..." },
    { "id": 2, "command": "/gsd:plan-phase 3", "status": "done", "result": "Plan created...", "completed_at": "..." },
    { "id": 3, "command": "/gsd:execute-phase 3", "status": "done", "result": "Phase executed...", "completed_at": "..." }
  ]
}
\`\`\`

The agent receives this via the standard gateway delivery pattern (content + instructions). The queue file itself is also available on disk for full detail.
```

**Refactor 5 — Add queue-complete prompt note (Section 3)**
In Section 3, after the prompt code block closing (after line 77), before "### Key principles" (line 79), add a paragraph:

```
### Queue-complete context
When the Stop handler fires after the last command in a queue completes, the agent is NOT given the standard `prompt_stop.md`. Instead, it receives a queue-complete payload (see Section 4) summarizing all results. The agent then decides whether to start a new command sequence or stay idle.
```

**Refactor 6 — Move hook registration into Phase 3 scope (Section 7 -> Section 5)**
Remove the "Hook registration in `~/.claude/settings.json`" row from the Section 7 deferred items table (the row that says "Phase 5 | All three Phase 3 handlers need registration").

In Section 5, after the "Existing lib modules used" subsection (after line 213), add a new subsection:

```
### Hook registration

Phase 3 registers its three handlers in `~/.claude/settings.json` as part of delivery. Each handler entry specifies the hook name and the absolute path to the entry point script. Registration is idempotent — running it twice does not create duplicate entries.

This was originally deferred to Phase 5, but registering handlers at delivery time makes the phase self-contained and testable without depending on a later registration sweep.
```

**Refactor 7 — Document UserPromptSubmit cancellation as known trade-off (Section 4)**
After the "Cancellation (manual input)" subsection (around line 170), before "Stale cleanup", add a paragraph:

```
**Trade-off:** UserPromptSubmit fires for ANY manual input, including follow-up messages that complement (rather than override) the queue's intent. Cancelling on every manual input is aggressive but safe — it guarantees the agent re-evaluates rather than blindly continuing a stale plan. If this proves too disruptive in practice, a future refinement could add a grace window or confirmation, but the conservative approach ships first.
```

**Refactor 8 — Flag idle_prompt as potential Phase 3.5 need (Section 7)**
In the Section 7 deferred items table, update the "Notification (idle_prompt) queue processing" row:
- Change "Phase 4+" to "Phase 3.5"
- Change the Notes to: "May be needed if agent requires a wake-up prompt when session goes idle after queue completes. Evaluate after Phase 3 testing."

Write the complete updated file.
  </action>
  <verify>
Verify all 8 refactors applied correctly:
1. `grep -c "trigger" .planning/phases/03-stop-event-full-stack/03-CONTEXT.md` should return 0 (trigger field removed everywhere)
2. `grep "\\-\\-session" .planning/phases/03-stop-event-full-stack/03-CONTEXT.md` should show the new flag-based call signature in at least 3 places
3. `grep "event_stop\\.js\\|event_session_start\\.js\\|event_user_prompt_submit\\.js" .planning/phases/03-stop-event-full-stack/03-CONTEXT.md` should return 0 matches (all renamed to .mjs)
4. `grep "queue-complete" .planning/phases/03-stop-event-full-stack/03-CONTEXT.md` should return matches (payload definition added)
5. `grep "Queue-complete context" .planning/phases/03-stop-event-full-stack/03-CONTEXT.md` should return 1 match (prompt note added)
6. `grep "Hook registration" .planning/phases/03-stop-event-full-stack/03-CONTEXT.md` should appear in Section 5 area
7. `grep "Trade-off" .planning/phases/03-stop-event-full-stack/03-CONTEXT.md` should return 1 match
8. `grep "Phase 3.5" .planning/phases/03-stop-event-full-stack/03-CONTEXT.md` should return 1 match for idle_prompt
  </verify>
  <done>
All 8 refactors applied to 03-CONTEXT.md: trigger field removed from queue schema, TUI driver uses --session flag, all event handlers use .mjs extension, queue-complete payload defined, queue-complete prompt note added, hook registration moved into Phase 3 scope, UserPromptSubmit trade-off documented, idle_prompt flagged as Phase 3.5.
  </done>
</task>

</tasks>

<verification>
- File parses as valid markdown with no broken formatting
- All 8 refactors verifiable via grep checks listed in task verify section
- No unintended changes to sections not mentioned in the refactors
</verification>

<success_criteria>
- 03-CONTEXT.md contains all 8 improvements
- Queue schema is clean (no trigger field)
- TUI driver signature is flag-based throughout
- All handler filenames use .mjs consistently
- Queue-complete payload and prompt note exist
- Hook registration is in-scope, not deferred
- UserPromptSubmit trade-off is documented
- idle_prompt targets Phase 3.5
</success_criteria>

<output>
After completion, create `.planning/quick/4-refactor-phase-3-context-md-with-8-targe/4-SUMMARY.md`
</output>
