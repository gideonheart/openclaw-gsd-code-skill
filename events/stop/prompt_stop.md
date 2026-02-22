# Claude Code fired Event

Claude Code has finished and is waiting for OpenClaw input.

## What you received
- `last_assistant_message`: Claude Code's final response before stopping
- `suggested_commands`: Commands extracted from the response (any /gsd:* and /clear found in the text)

## What to do
1. Read the message. Understand what Claude Code just finished.
2. Review `suggested_commands` — these are what Claude Code recommended, but you decide.
   - You may use them as-is, skip some, or choose entirely different commands.
   - They are suggestions, not instructions.
3. Decide your command array and call the TUI driver:
   ```
   node /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver.mjs --session <session-name> '["/clear", "/gsd:plan-phase 3"]'
   ```
   Note: the session name is provided in the Event Metadata above — use that session value.

4. **Long content (multiline prompts, task descriptions):**
   Commands are typed via tmux send-keys — newlines act as Enter and submit prematurely.
   For any content longer than a single line, write it to a file first and use `@file` syntax:
   ```
   # 1. Write content to the prompts directory
   cat > /home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/prompts/task-description.md << 'EOF'
   ... your multiline content here ...
   EOF

   # 2. Reference it in the command array
   node /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver.mjs --session <session-name> '["/gsd:quick @/home/forge/.openclaw/workspace/skills/gsd-code-skill/logs/prompts/task-description.md"]'
   ```
   Claude Code expands the `@file` reference at input time. NEVER pass multiline text directly in the command array.

## Command types and their awaits
- `/clear` -> clears context -> awaits SessionStart(source:clear)
- `/gsd:*` commands -> Claude responds -> awaits Stop
- The TUI driver handles awaits automatically.

## When to do nothing
- If the work is complete and no next phase exists, try `/clear` and then `/gsd:resume-work`.
- If you received a queue-complete summary, review the results and decide if more work is needed. I suggest you to use gh or git command to check Claude Codes commits, and mybe you see some issues, or you can ask claude code, to do analysi of his last work and ask, what he thinks, Claud Code did good, and what he would do diffrently, is he had a chande to rewrite his code. 
- Listen to his response and make decidion, if it aligns with your own, reserch, if yes, ask, Claude Code to fix it.
- Remember, 
- The queue will not be created and the session stays idle.
