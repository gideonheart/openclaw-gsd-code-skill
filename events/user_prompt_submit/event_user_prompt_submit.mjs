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

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  resolveAgentFromSession,
  wakeAgentViaGateway,
  cancelQueueForSession,
  appendJsonlEntry,
} from '../../lib/index.mjs';

async function main() {
  const rawStdin = readFileSync('/dev/stdin', 'utf8').trim();
  // UserPromptSubmit payload is read but session resolution uses tmux
  try {
    JSON.parse(rawStdin);
  } catch {
    process.exit(0);
  }

  const sessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();

  if (!sessionName) {
    process.exit(0);
  }

  const resolvedAgent = resolveAgentFromSession(sessionName);

  if (!resolvedAgent) {
    process.exit(0);
  }

  const cancellationResult = cancelQueueForSession(sessionName);

  if (!cancellationResult) {
    process.exit(0);
  }

  const { completedCount, totalCount, remainingCommands } = cancellationResult;
  const remainingCommandList = remainingCommands.map(queuedCommand => queuedCommand.command).join(', ');

  const messageContent = [
    'Queue cancelled by manual input.',
    `Completed: ${completedCount}/${totalCount} commands.`,
    `Remaining commands: ${remainingCommandList}`,
  ].join('\n');

  const promptFilePath = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'stop', 'prompt_stop.md');

  wakeAgentViaGateway({
    openclawSessionId: resolvedAgent.openclaw_session_id,
    messageContent,
    promptFilePath,
    eventMetadata: {
      eventType: 'UserPromptSubmit',
      sessionName,
      timestamp: new Date().toISOString(),
    },
    sessionName,
  });

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
