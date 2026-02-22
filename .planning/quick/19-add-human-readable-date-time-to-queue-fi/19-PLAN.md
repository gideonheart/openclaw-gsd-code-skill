---
phase: quick-19
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - bin/tui-driver.mjs
  - lib/queue-processor.mjs
autonomous: true
requirements: [QUICK-19]

must_haves:
  truths:
    - "Queue files contain a top-level created_at ISO timestamp"
    - "Each command entry in a queue file contains a created_at ISO timestamp"
    - "completed_at continues to work as before (set when command finishes)"
    - "Queue complete summary includes created_at per command"
    - "question-*.json and pending-answer-*.json are NOT modified"
  artifacts:
    - path: "bin/tui-driver.mjs"
      provides: "Queue creation with top-level and per-command created_at timestamps"
      contains: "created_at"
    - path: "lib/queue-processor.mjs"
      provides: "Queue complete summary includes created_at"
      contains: "created_at"
  key_links:
    - from: "bin/tui-driver.mjs"
      to: "lib/queue-processor.mjs"
      via: "buildQueueData creates structure, buildQueueCompleteSummary reads it"
      pattern: "created_at"
---

<objective>
Add human-readable ISO timestamps (created_at) to queue files so they sort correctly and show when commands were queued.

Purpose: Queue files currently lack creation timestamps, making it impossible to determine when a queue was created or when individual commands were enqueued. The question-*.json and pending-answer-*.json files already have `saved_at` — queue files are the gap.

Output: Modified `bin/tui-driver.mjs` and `lib/queue-processor.mjs` with timestamp fields.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@bin/tui-driver.mjs
@lib/queue-processor.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add created_at timestamps to queue file creation</name>
  <files>bin/tui-driver.mjs</files>
  <action>
Modify the `buildQueueData()` function in `bin/tui-driver.mjs` to add timestamps:

1. Add a top-level `created_at` field with value `new Date().toISOString()`. This goes as a sibling to `commands` in the returned object. Place it BEFORE the `commands` key so it appears first in the JSON output.

2. Add a `created_at` field to each command entry with the same ISO timestamp value. This goes alongside the existing fields (`id`, `command`, `status`, `awaits`, `result`, `completed_at`). Place it after `id` and `command` for readability.

Generate the timestamp ONCE at the top of `buildQueueData()` and reuse it for both the top-level field and all command entries (they are all created at the same instant).

The resulting queue JSON should look like:
```json
{
  "created_at": "2026-02-22T12:34:56.789Z",
  "commands": [
    {
      "id": 1,
      "command": "/clear",
      "created_at": "2026-02-22T12:34:56.789Z",
      "status": "active",
      "awaits": { "hook": "SessionStart", "sub": "clear" },
      "result": null,
      "completed_at": null
    }
  ]
}
```

Do NOT modify any other function in tui-driver.mjs. Do NOT change the import list, CLI parsing, or main() logic.
  </action>
  <verify>Run `node bin/tui-driver.mjs --session test-timestamp-check '["echo hello"]' 2>/dev/null; cat logs/queues/queue-test-timestamp-check.json | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log('top-level:', typeof d.created_at === 'string' && d.created_at.includes('T')); console.log('command:', typeof d.commands[0].created_at === 'string' && d.commands[0].created_at.includes('T')); console.log('match:', d.created_at === d.commands[0].created_at);"` — all three should print `true`. Then clean up: `rm logs/queues/queue-test-timestamp-check.json`</verify>
  <done>Queue files created by tui-driver have a top-level `created_at` ISO timestamp and each command entry has its own `created_at` ISO timestamp, all sharing the same value from creation time.</done>
</task>

<task type="auto">
  <name>Task 2: Include created_at in queue-complete summary</name>
  <files>lib/queue-processor.mjs</files>
  <action>
Modify the `buildQueueCompleteSummary()` function in `lib/queue-processor.mjs` to include `created_at` in the per-command output.

Currently the summary maps each command to: `{ id, command, status, result, completed_at }`.

Add `created_at: command.created_at` to the mapped object, placed after `command` and before `status`. This ensures the queue-complete payload sent to the orchestrating agent includes the creation timestamp for each command.

Do NOT modify any other function in queue-processor.mjs. The `writeQueueFileAtomically()`, `processQueueForHook()`, `cancelQueueForSession()`, `cleanupStaleQueueForSession()`, and `isPromptFromTuiDriver()` functions remain unchanged — they already pass through whatever fields exist in the queue JSON.
  </action>
  <verify>Read `lib/queue-processor.mjs` and confirm `buildQueueCompleteSummary` maps `created_at` in its command output. Grep for `created_at` in the function — should appear exactly once in the map callback.</verify>
  <done>The queue-complete summary payload includes `created_at` per command, so the orchestrating agent can see when each command was originally enqueued.</done>
</task>

</tasks>

<verification>
1. Create a test queue: `node bin/tui-driver.mjs --session verify-q19 '["echo test"]'`
2. Inspect the file: `cat logs/queues/queue-verify-q19.json` — must show `created_at` at top level and inside each command entry
3. Both timestamps must be valid ISO 8601 strings (contain "T" and "Z")
4. Both timestamps must be identical (same creation instant)
5. `completed_at` must still be `null` for unfinished commands
6. Clean up: `rm logs/queues/queue-verify-q19.json`
7. Verify question-*.json and pending-answer-*.json files were NOT modified (git diff should show no changes to `lib/ask-user-question.mjs`)
</verification>

<success_criteria>
- Queue files have top-level `created_at` ISO timestamp
- Each command entry has `created_at` ISO timestamp
- Queue-complete summary includes `created_at` per command
- No changes to question or pending-answer file formats
- Existing queue processing (advance, cancel, cleanup, stale) still works — these functions pass through JSON fields transparently
</success_criteria>

<output>
After completion, create `.planning/quick/19-add-human-readable-date-time-to-queue-fi/19-SUMMARY.md`
</output>
