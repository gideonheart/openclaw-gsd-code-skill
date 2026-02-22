/**
 * events/user_prompt_submit/event_user_prompt_submit.mjs — UserPromptSubmit hook handler entry point.
 *
 * Invoked by Claude Code when the user submits a prompt. Claude Code fires this
 * event for ALL terminal input — including automated tmux send-keys from
 * tui-driver.mjs and tui-driver-ask.mjs. Before cancelling the queue, we check
 * two guards:
 *
 * 1. isPromptFromTuiDriver: submitted text matches the active queue command →
 *    tui-driver.mjs typed a /gsd:* command — skip cancellation.
 *
 * 2. isSessionInAskUserQuestionFlow: pending-answer-{session}.json exists →
 *    tui-driver-ask.mjs is answering an AskUserQuestion TUI (typing Down/Enter/
 *    Space/text keystrokes) — those keystrokes fire UserPromptSubmit but are NOT
 *    a human manual takeover. Skip cancellation.
 *
 * If neither guard matches and a queue exists, it was cancelled by genuine human
 * input. The agent is woken with a cancellation summary.
 */

import { resolve } from 'node:path';
import { SKILL_ROOT } from '../../lib/paths.mjs';
import {
  readHookContext,
  wakeAgentWithRetry,
  cancelQueueForSession,
  isPromptFromTuiDriver,
  isSessionInAskUserQuestionFlow,
  appendJsonlEntry,
} from '../../lib/index.mjs';

async function main() {
  const hookContext = readHookContext('event_user_prompt_submit');
  if (!hookContext) process.exit(0);
  const { hookPayload, sessionName, resolvedAgent } = hookContext;

  const submittedPrompt = hookPayload.prompt ?? '';

  if (isPromptFromTuiDriver(sessionName, submittedPrompt)) {
    appendJsonlEntry({ level: 'debug', source: 'event_user_prompt_submit', message: 'Prompt matches active queue command — TUI driver input, skipping cancellation', session: sessionName }, sessionName);
    process.exit(0);
  }

  if (isSessionInAskUserQuestionFlow(sessionName)) {
    appendJsonlEntry({ level: 'debug', source: 'event_user_prompt_submit', message: 'Pending answer file exists — AskUserQuestion TUI input, skipping cancellation', session: sessionName }, sessionName);
    process.exit(0);
  }

  const cancellationResult = cancelQueueForSession(sessionName);

  if (!cancellationResult) {
    appendJsonlEntry({ level: 'debug', source: 'event_user_prompt_submit', message: 'No active queue to cancel — skipping', session: sessionName }, sessionName);
    process.exit(0);
  }

  const { completedCount, totalCount, remainingCommands } = cancellationResult;
  const remainingCommandList = remainingCommands.map(queuedCommand => queuedCommand.command).join(', ');

  const messageContent = [
    'Queue cancelled by manual input.',
    `Completed: ${completedCount}/${totalCount} commands.`,
    `Remaining commands: ${remainingCommandList}`,
  ].join('\n');

  const promptFilePath = resolve(SKILL_ROOT, 'events', 'stop', 'prompt_stop.md');

  await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'UserPromptSubmit', sessionName });

  appendJsonlEntry({
    level: 'info',
    source: 'event_user_prompt_submit',
    message: 'Queue cancelled by manual input — agent notified',
    session: sessionName,
    completed_count: completedCount,
    total_count: totalCount,
    remaining_count: remainingCommands.length,
  }, sessionName);

  process.exit(0);
}

main().catch((caughtError) => {
  process.stderr.write(`[event_user_prompt_submit] Error: ${caughtError.message}\n`);
  process.exit(1);
});
