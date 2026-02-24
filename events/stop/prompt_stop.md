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
3. **Context awareness:** If the session has run 2 or more commands since the last /clear (or has never had a /clear), always start your command array with `/clear`. High context degrades code quality. When in doubt, clear first.
4. Decide your command array and call the TUI driver:
   ```
   node /home/forge/.openclaw/workspace/skills/gsd-code-skill/bin/tui-driver.mjs --session <session-name> '["/clear", "/gsd:plan-phase 3"]'
   ```
   Note: the session name is provided in the Event Metadata above — use that session value.

5. **Long content (multiline prompts, task descriptions):**
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

## When work appears complete — think before you act

Before reaching for `/clear` and `/gsd:resume-work`, do the analysis:

**Step 1: Check what was actually done.**
Run `git log --oneline -10` and `git diff HEAD~3..HEAD --stat` to see recent commits and changed files.

**Step 2: Ask Claude Code to self-reflect.**
Use `/gsd:quick` with a question like:
- "Review your last commits. What did you do well? What would you do differently if you rewrote it?"
- "Are there any edge cases you didn't handle? Any tech debt introduced?"
- "Look at your most recent changes — is there anything that should be refactored?"

Listen to the response. If Claude Code identifies real issues, ask it to fix them before moving on.

**Step 3: Check the suggested commands.**
If the last assistant message suggested `/gsd:new-milestone`, `/gsd:quick`, or `/gsd:add-phase`, those commands exist for a reason — use them if they fit. These are more specific than a generic resume.

**Step 4: Decide on next work.**
- Is there a clear next phase? Use `/gsd:plan-phase <n>` or `/gsd:add-phase`.
- Is there a specific fix or feature? Use `/gsd:quick`.
- Starting a new major milestone? Use `/gsd:new-milestone`.

**Last resort only:** `/clear` + `/gsd:resume-work` — use this ONLY when you have no specific direction and need Claude Code to orient itself from scratch. It is not a default action. Do not use it if the suggested commands already point to something concrete.
