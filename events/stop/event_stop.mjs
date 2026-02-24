/**
 * events/stop/event_stop.mjs — Stop hook handler entry point.
 *
 * Invoked by Claude Code when an assistant turn ends (Stop hook).
 * Reads the hook payload from stdin, guards against re-entrancy and
 * unmanaged sessions, then either advances an existing command queue
 * or wakes the agent via the OpenClaw gateway with the response content.
 *
 * Queue-present path: delegates to processQueueForHook — hook processor
 * marks the active command done and types the next command into tmux.
 *
 * Fresh-wake path: extracts last_assistant_message + suggested commands,
 * builds messageContent, and wakes the agent via wakeAgentWithRetry.
 */

import { resolve } from 'node:path';
import { SKILL_ROOT } from '../../lib/paths.mjs';
import {
  readHookContext,
  wakeAgentWithRetry,
  processQueueForHook,
  appendJsonlEntry,
} from '../../lib/index.mjs';

/**
 * Build a human-readable message for the agent when a command queue completes.
 *
 * The message leads with the full last_assistant_message (what Claude Code actually
 * said for the final command), preceded by a compact header listing all commands that
 * ran. This avoids sending a bloated JSON wrapper — the agent reads the output
 * directly, not a JSON blob with results nested inside.
 *
 * @param {Object} queueSummary - The summary object from buildQueueCompleteSummary.
 * @param {string} lastAssistantMessage - The full last assistant message for the final command.
 * @returns {string} Human-readable message content for the agent.
 */
function buildQueueCompleteMessageContent(queueSummary, lastAssistantMessage) {
  const commandList = queueSummary.commands
    .map(command => `- \`${command.command}\` (${command.status})`)
    .join('\n');

  return [
    `## Queue Complete — ${queueSummary.summary}`,
    '',
    '### Commands ran',
    commandList,
    '',
    '### Last command output',
    lastAssistantMessage,
  ].join('\n');
}

async function main() {
  const hookContext = readHookContext('event_stop');
  if (!hookContext) process.exit(0);
  const { hookPayload, sessionName, resolvedAgent } = hookContext;

  const promptFilePath = resolve(SKILL_ROOT, 'events', 'stop', 'prompt_stop.md');
  const handlerTrace = { decisionPath: null, outcome: {} };

  try {
    if (hookPayload.stop_hook_active === true) {
      handlerTrace.decisionPath = 'reentrancy-guard';
      return;
    }

    const lastAssistantMessage = hookPayload.last_assistant_message;

    if (!lastAssistantMessage) {
      handlerTrace.decisionPath = 'no-message';
      return;
    }

    const queueResult = processQueueForHook(sessionName, 'Stop', null, lastAssistantMessage);

    if (queueResult.action === 'advanced') {
      handlerTrace.decisionPath = 'queue-advanced';
      return;
    }

    if (queueResult.action === 'queue-complete') {
      const messageContent = buildQueueCompleteMessageContent(queueResult.summary, lastAssistantMessage);

      await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'Stop', sessionName });

      handlerTrace.decisionPath = 'queue-complete';
      handlerTrace.outcome = { summary: queueResult.summary };
      return;
    }

    if (queueResult.action === 'awaits-mismatch') {
      handlerTrace.decisionPath = 'awaits-mismatch';
      return;
    }

    if (queueResult.action === 'no-active-command') {
      handlerTrace.decisionPath = 'no-active-command';
      return;
    }

    // queueResult.action === 'no-queue' — fresh wake path
    const commandMatches = lastAssistantMessage.match(/\/(?:gsd:[a-z-]+(?:\s+[^\s`]+)?|clear)/g) || [];
    const suggestedCommands = [...new Set(commandMatches)];

    const messageContent = [
      lastAssistantMessage,
      '',
      '## Suggested Commands',
      suggestedCommands.length > 0
        ? suggestedCommands.map(command => `- \`${command}\``).join('\n')
        : '_No commands detected in response._',
    ].join('\n');

    await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'Stop', sessionName });

    handlerTrace.decisionPath = 'fresh-wake';
    handlerTrace.outcome = { suggested_commands: suggestedCommands };
  } finally {
    appendJsonlEntry({
      level: 'info',
      source: 'event_stop',
      message: `Handler complete: ${handlerTrace.decisionPath}`,
      session: sessionName,
      hook_payload: hookPayload,
      decision_path: handlerTrace.decisionPath,
      outcome: handlerTrace.outcome,
    }, sessionName);
  }
}

main().catch((caughtError) => {
  process.stderr.write(`[event_stop] Error: ${caughtError.message}\n`);
  process.exit(1);
});
