/**
 * events/user_prompt_submit/event_user_prompt_submit.mjs — UserPromptSubmit hook handler entry point.
 *
 * Invoked by Claude Code when the user submits a prompt manually. Manual input
 * means the user is taking direct control — any active command queue should be
 * cancelled immediately so automated commands do not fire after the user acts.
 *
 * If a queue was cancelled, the agent is woken with a cancellation summary
 * describing how many commands completed and which commands remain.
 */

import { resolve } from 'node:path';
import { SKILL_ROOT } from '../../lib/paths.mjs';
import {
  readHookContext,
  retryWithBackoff,
  wakeAgentViaGateway,
  cancelQueueForSession,
  appendJsonlEntry,
} from '../../lib/index.mjs';

async function main() {
  const hookContext = readHookContext('event_user_prompt_submit');
  if (!hookContext) process.exit(0);
  // hookPayload is validated by readHookContext but unused — session is resolved via tmux
  const { sessionName, resolvedAgent } = hookContext;

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

  await retryWithBackoff(
    () => wakeAgentViaGateway({
      openclawSessionId: resolvedAgent.openclaw_session_id,
      messageContent,
      promptFilePath,
      eventMetadata: {
        eventType: 'UserPromptSubmit',
        sessionName,
        timestamp: new Date().toISOString(),
      },
      sessionName,
    }),
    { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: 'wake-on-queue-cancel', sessionName },
  );

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
