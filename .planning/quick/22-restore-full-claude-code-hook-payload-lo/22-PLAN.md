---
phase: quick-22
plan: 22
type: execute
wave: 1
depends_on: []
files_modified:
  - bin/install-hooks.mjs
  - ~/.claude/settings.json
autonomous: true
requirements: []

must_haves:
  truths:
    - "hook-event-logger.sh is registered for all 15 Claude Code hook events in settings.json"
    - "Running install-hooks.mjs with no flags installs both handlers AND logger by default"
    - "A --no-logger flag exists to explicitly suppress logger installation when desired"
  artifacts:
    - path: "bin/install-hooks.mjs"
      provides: "Hook installer with logger-on-by-default behavior"
      contains: "--no-logger"
    - path: "~/.claude/settings.json"
      provides: "Active hook configuration with all 15 logger entries + 5 handler entries"
  key_links:
    - from: "bin/install-hooks.mjs"
      to: "config/hooks.json"
      via: "readCanonicalHooks reads all hook definitions"
      pattern: "readCanonicalHooks"
    - from: "bin/install-hooks.mjs"
      to: "~/.claude/settings.json"
      via: "writeSettingsAtomically merges hooks into settings"
      pattern: "writeSettingsAtomically"
---

<objective>
Restore full Claude Code hook payload logging and flip the install-hooks.mjs default so logger is always installed unless explicitly suppressed.

Purpose: hook-event-logger.sh was silently dropped from settings.json when install-hooks.mjs was run without --logger. Raw payload logging is critical debugging infrastructure — losing it silently is unacceptable. The default must include the logger.

Output: Updated install-hooks.mjs with inverted default + restored settings.json with all 15 logger entries.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@bin/install-hooks.mjs
@config/hooks.json
@bin/hook-event-logger.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Flip install-hooks.mjs default — logger ON, add --no-logger flag</name>
  <files>bin/install-hooks.mjs</files>
  <action>
    Invert the logger default in bin/install-hooks.mjs so that running `node bin/install-hooks.mjs` (no flags) installs BOTH handlers AND logger entries.

    Specific changes:

    1. Replace `--logger` flag detection with `--no-logger`:
       - Change: `const includeLogger = process.argv.includes('--logger');`
       - To: `const excludeLogger = process.argv.includes('--no-logger');`

    2. Invert the filter logic in the install section (around line 153):
       - Change: `const keepFilter = includeLogger ? () => true : (entry) => isHandlerEntry(entry);`
       - To: `const keepFilter = excludeLogger ? (entry) => isHandlerEntry(entry) : () => true;`

    3. Update the modeLabel (around line 160):
       - Change: `const modeLabel = includeLogger ? 'handlers + logger' : 'handlers';`
       - To: `const modeLabel = excludeLogger ? 'handlers only' : 'handlers + logger';`

    4. Update the --handlers flag guard message (around line 146-148) — keep it as-is, it already correctly rejects `--handlers` without `--remove`.

    5. Update the selective remove section: replace references to `includeLogger` with `excludeLogger` in the remove logic:
       - Line 103: `const selectiveRemove = handlersFlag || includeLogger;`
       - Change to: `const selectiveRemove = handlersFlag || excludeLogger;`
       - The remove logic for `--remove --logger` should become `--remove --no-logger` (removes the logger entries). BUT actually, for the remove path the semantics are different — `--remove --logger` means "remove the logger entries". This is already clear and correct. So for the remove path:
         - Keep the `--logger` flag for `--remove --logger` (remove logger entries)
         - The `includeLogger` variable is used in remove mode to mean "targeting the logger for removal"
         - Rename carefully: keep a `loggerRemoveTarget` for the remove path

    Actually, cleaner approach — have TWO flag variables to avoid confusion between install and remove semantics:
       - `const noLoggerOnInstall = process.argv.includes('--no-logger');` — for install mode
       - Keep `const includeLogger = process.argv.includes('--logger');` — only used in `--remove` mode (means "target logger for removal")
       - This preserves the existing `--remove --logger` / `--remove --handlers` semantics unchanged

    6. Update the JSDoc comment block at the top of the file:
       - `node bin/install-hooks.mjs                  # Install handlers + logger (default)`
       - `node bin/install-hooks.mjs --no-logger      # Install handlers only (no debug logger)`
       - Keep all `--remove` lines exactly as they are

    7. Also update the `--handlers` flag guard (line 145-148) — it currently only fires when `handlersFlag` is true. No change needed since `--handlers` is still only valid with `--remove`.

    Do NOT change: config/hooks.json, hook-event-logger.sh, or any remove-mode logic beyond renaming the variable. The remove path (`--remove --logger`, `--remove --handlers`) keeps its existing semantics.
  </action>
  <verify>
    <automated>cd /home/forge/.openclaw/workspace/skills/gsd-code-skill && node bin/install-hooks.mjs --dry-run 2>&1 | grep -q "handlers + logger" && node bin/install-hooks.mjs --no-logger --dry-run 2>&1 | grep -q "handlers only" && echo "PASS: defaults inverted correctly"</automated>
    <manual>Verify --dry-run output shows "handlers + logger" by default and "handlers only" with --no-logger</manual>
  </verify>
  <done>Default install mode includes logger. --no-logger flag suppresses logger. --remove flags unchanged. --dry-run confirms both modes.</done>
</task>

<task type="auto">
  <name>Task 2: Run installer to restore settings.json with all hooks</name>
  <files>~/.claude/settings.json</files>
  <action>
    Run `node bin/install-hooks.mjs` (no flags — now defaults to handlers + logger) to restore the full hook configuration in ~/.claude/settings.json.

    After running, verify the output confirms both handler and logger counts:
    - Should show 15 hook events (all events get logger)
    - Should show 5 handlers (SessionStart, UserPromptSubmit, PreToolUse[AskUserQuestion], PostToolUse[AskUserQuestion], Stop)
    - Should show 15+ loggers (one per event, plus Notification matchers)

    Then verify settings.json still has its non-hook settings intact (statusLine, enabledPlugins, skipDangerousModePermissionPrompt).
  </action>
  <verify>
    <automated>cd /home/forge/.openclaw/workspace/skills/gsd-code-skill && node -e "const s = JSON.parse(require('fs').readFileSync(process.env.HOME + '/.claude/settings.json', 'utf8')); const events = Object.keys(s.hooks); const loggerCount = events.filter(e => s.hooks[e].some(entry => entry.hooks?.some(h => h.command?.includes('hook-event-logger')))).length; console.log('Events with logger:', loggerCount); if (loggerCount >= 15) console.log('PASS'); else { console.log('FAIL: expected >= 15 events with logger'); process.exit(1); }"</automated>
    <manual>Check ~/.claude/settings.json has hook-event-logger.sh in all 15 event types and non-hook settings are preserved</manual>
  </verify>
  <done>settings.json has hook-event-logger.sh for all 15 hook events. All 5 Node.js handlers present. Non-hook settings (statusLine, enabledPlugins) preserved.</done>
</task>

</tasks>

<verification>
1. `node bin/install-hooks.mjs --dry-run` shows "handlers + logger" mode with 15+ events
2. `node bin/install-hooks.mjs --no-logger --dry-run` shows "handlers only" mode with 5 events
3. `~/.claude/settings.json` has hook-event-logger.sh in all 15 hook event types
4. `~/.claude/settings.json` retains statusLine, enabledPlugins, skipDangerousModePermissionPrompt
</verification>

<success_criteria>
- hook-event-logger.sh is active for all 15 Claude Code hook events
- Default install behavior includes logger (no flags needed)
- --no-logger opt-out exists for suppressing logger when desired
- --remove --logger and --remove --handlers semantics unchanged
</success_criteria>

<output>
After completion, create `.planning/quick/22-restore-full-claude-code-hook-payload-lo/22-SUMMARY.md`
</output>
