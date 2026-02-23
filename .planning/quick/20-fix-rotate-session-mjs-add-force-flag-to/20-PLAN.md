---
phase: quick-20
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - bin/rotate-session.mjs
autonomous: true
requirements: [QUICK-20]

must_haves:
  truths:
    - "Running rotate-session.mjs with --force proceeds even when stored and active session IDs match"
    - "A forced rotation with matching IDs archives the current session into session_history and writes the registry"
    - "Help text documents the --force flag"
  artifacts:
    - path: "bin/rotate-session.mjs"
      provides: "--force flag support for session rotation"
      contains: "force"
  key_links:
    - from: "parseCommandLineArguments"
      to: "main equality check"
      via: "namedArguments.force boolean"
      pattern: "force.*type.*boolean"
---

<objective>
Add --force flag to bin/rotate-session.mjs so rotation proceeds even when the stored session ID matches the active OpenClaw session ID.

Purpose: When a user wants to mark a rotation point in history (e.g., context window full, starting fresh topic) but the underlying OpenClaw session has not changed, --force allows archiving the current session into session_history and re-writing the registry.

Output: Updated bin/rotate-session.mjs with --force support.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@bin/rotate-session.mjs
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add --force flag to rotate-session.mjs</name>
  <files>bin/rotate-session.mjs</files>
  <action>
Three changes to bin/rotate-session.mjs:

1. **parseCommandLineArguments** — Add `force: { type: 'boolean' }` to the `parseArgs` options object (alongside `label` and `help`).

2. **main() equality check (lines 186-191)** — Modify the `if (newSessionId === oldSessionId)` block to respect `--force`. When `namedArguments.force` is true, do NOT exit early. Instead, log that force rotation is proceeding and continue to the archival/write logic below. When force is false (default), keep the existing early-exit behavior unchanged.

   The modified block should look like:
   ```js
   if (newSessionId === oldSessionId) {
     if (!namedArguments.force) {
       logWithTimestamp(`Session already up to date for agent: ${agentIdentifier}`);
       logWithTimestamp(`  Current: ${oldSessionId}`);
       logWithTimestamp(`  No rotation needed. Use --force to rotate anyway.`);
       process.exit(0);
     }
     logWithTimestamp(`Force rotating session for agent: ${agentIdentifier} (session ID unchanged)`);
   }
   ```

   Note the hint about `--force` added to the "No rotation needed" message — helps discoverability.

3. **Help text (lines 160-167)** — Add `--force` to the arguments list:
   ```
   '  --force          Force rotation even if session ID is unchanged\n' +
   ```

Also update the file header doc comment (line 10) to include `--force` in the Usage line:
   ```
   *   node bin/rotate-session.mjs <agent-id> [--label <text>] [--force]
   ```

Do NOT change any other behavior. The archival logic (buildSessionHistoryEntry, writeRegistryAtomically) already handles the case where newSessionId equals oldSessionId — it will archive the old ID and set the "new" ID to the same value, which is the intended --force behavior.
  </action>
  <verify>
Run the script with --help and confirm --force appears in the output:
```
node bin/rotate-session.mjs --help
```

Run the script without --force on an agent whose session is already current — confirm it exits with "No rotation needed. Use --force to rotate anyway." message:
```
node bin/rotate-session.mjs warden 2>&1 || true
```

Run the script WITH --force — confirm it proceeds and logs "Force rotating session":
```
node bin/rotate-session.mjs warden --force --label="force test" 2>&1
```

After the force rotation, read config/agent-registry.json and confirm session_history has a new entry with label "force test".
  </verify>
  <done>
--force flag accepted by parseArgs. Without --force, matching IDs exit early with hint message. With --force, matching IDs proceed through archival and registry write. Help text documents --force. Header comment updated.
  </done>
</task>

</tasks>

<verification>
- `node bin/rotate-session.mjs --help` shows --force in arguments list
- `node bin/rotate-session.mjs warden` (when already current) prints "Use --force to rotate anyway"
- `node bin/rotate-session.mjs warden --force --label="test"` succeeds and adds history entry
</verification>

<success_criteria>
The --force flag allows rotate-session.mjs to proceed with rotation even when session IDs match, creating a history entry and re-writing the registry. Existing behavior (no --force) is unchanged except for the added hint in the "no rotation needed" message.
</success_criteria>

<output>
After completion, create `.planning/quick/20-fix-rotate-session-mjs-add-force-flag-to/20-SUMMARY.md`
</output>
