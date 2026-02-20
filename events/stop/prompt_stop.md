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
   ```
   node /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver.mjs --session <session-name> '["/clear", "/gsd:plan-phase 3"]'
   ```
   Note: the session name is provided in the Event Metadata above — use that session value.

## Command types and their awaits
- `/gsd:*` commands -> Claude responds -> awaits Stop
- `/clear` -> clears context -> awaits SessionStart(source:clear)
- The TUI driver handles awaits automatically.

## When to do nothing
- If the work is complete and no next phase exists, respond with no commands.
- If you received a queue-complete summary, review the results and decide if more work is needed.
- The queue will not be created and the session stays idle.
