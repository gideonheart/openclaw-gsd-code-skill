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
  const handlerTrace = { decisionPath: null, outcome: {} };

  try {
    if (toolName === 'AskUserQuestion') {
      const domainResult = await handlePostAskUserQuestion({ hookPayload, sessionName, resolvedAgent });
      handlerTrace.decisionPath = domainResult.decisionPath;
      handlerTrace.outcome = domainResult.outcome;
      return;
    }

    // No handler registered for this tool — exit cleanly
    handlerTrace.decisionPath = 'no-handler';
    handlerTrace.outcome = { tool_name: toolName };
  } finally {
    const warnPaths = ['ask-user-question-mismatch', 'ask-user-question-no-pending', 'ask-user-question-missing-response'];
    const logLevel = warnPaths.includes(handlerTrace.decisionPath) ? 'warn' : 'info';

    appendJsonlEntry({
      level: logLevel,
      source: 'event_post_tool_use',
      message: `Handler complete: ${handlerTrace.decisionPath}`,
      session: sessionName,
      hook_payload: hookPayload,
      decision_path: handlerTrace.decisionPath,
      outcome: handlerTrace.outcome,
    }, sessionName);
  }
}

main().catch((caughtError) => {
  process.stderr.write(`[event_post_tool_use] Error: ${caughtError.message}\n`);
  process.exit(1);
});
