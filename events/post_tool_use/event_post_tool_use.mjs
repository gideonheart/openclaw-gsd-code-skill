/**
 * events/post_tool_use/event_post_tool_use.mjs — PostToolUse hook handler entry point.
 *
 * Invoked by Claude Code after a tool has been used (PostToolUse hook).
 * Reads the hook payload from stdin, resolves the session and agent context,
 * then dispatches to the appropriate domain handler by tool_name.
 *
 * Currently handles: AskUserQuestion (verification of TUI driver answer)
 * Extensible: add a folder + one `if` branch for each new tool_name.
 */

import { readHookContext, appendJsonlEntry } from '../../lib/index.mjs';
import { handlePostAskUserQuestion } from './ask_user_question/handle_post_ask_user_question.mjs';

async function main() {
  const hookContext = readHookContext('event_post_tool_use');
  if (!hookContext) process.exit(0);
  const { hookPayload, sessionName, resolvedAgent } = hookContext;

  const toolName = hookPayload.tool_name;

  if (toolName === 'AskUserQuestion') {
    await handlePostAskUserQuestion({ hookPayload, sessionName, resolvedAgent });
    process.exit(0);
  }

  // No handler registered for this tool — exit cleanly
  appendJsonlEntry({
    level: 'debug',
    source: 'event_post_tool_use',
    message: `No handler for tool_name: ${toolName}`,
    session: sessionName,
  }, sessionName);
  process.exit(0);
}

main().catch((caughtError) => {
  process.stderr.write(`[event_post_tool_use] Error: ${caughtError.message}\n`);
  process.exit(1);
});
