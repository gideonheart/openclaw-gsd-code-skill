/**
 * events/pre_tool_use/event_pre_tool_use.mjs — PreToolUse hook handler entry point.
 *
 * Invoked by Claude Code before a tool is used (PreToolUse hook).
 * Reads the hook payload from stdin, resolves the session and agent context,
 * then dispatches to the appropriate domain handler by tool_name.
 *
 * Currently handles: AskUserQuestion
 * Extensible: add a folder + one `if` branch for each new tool_name.
 */

import { readHookContext, appendJsonlEntry } from '../../lib/index.mjs';
import { handleAskUserQuestion } from './ask_user_question/handle_ask_user_question.mjs';

async function main() {
  const hookContext = readHookContext('event_pre_tool_use');
  if (!hookContext) process.exit(0);
  const { hookPayload, sessionName, resolvedAgent } = hookContext;

  appendJsonlEntry({ level: 'debug', source: 'event_pre_tool_use', message: 'Hook payload received', session: sessionName, hook_payload: hookPayload }, sessionName);

  const toolName = hookPayload.tool_name;

  if (toolName === 'AskUserQuestion') {
    await handleAskUserQuestion({ hookPayload, sessionName, resolvedAgent });
    process.exit(0);
  }

  // No handler registered for this tool — exit cleanly
  appendJsonlEntry({
    level: 'debug',
    source: 'event_pre_tool_use',
    message: `No handler for tool_name: ${toolName}`,
    session: sessionName,
  }, sessionName);
  process.exit(0);
}

main().catch((caughtError) => {
  process.stderr.write(`[event_pre_tool_use] Error: ${caughtError.message}\n`);
  process.exit(1);
});
