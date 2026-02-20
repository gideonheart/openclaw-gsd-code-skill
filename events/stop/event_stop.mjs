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
 * builds messageContent, and wakes the agent via wakeAgentViaGateway.
 */

import { resolve } from 'node:path';
import { SKILL_ROOT } from '../../lib/paths.mjs';
import {
  readHookContext,
  retryWithBackoff,
  wakeAgentViaGateway,
  processQueueForHook,
  appendJsonlEntry,
} from '../../lib/index.mjs';

async function main() {
  const hookContext = readHookContext('event_stop');
  if (!hookContext) process.exit(0);
  const { hookPayload, sessionName, resolvedAgent } = hookContext;

  const promptFilePath = resolve(SKILL_ROOT, 'events', 'stop', 'prompt_stop.md');

  if (hookPayload.stop_hook_active === true) {
    appendJsonlEntry({ level: 'debug', source: 'event_stop', message: 'Re-entrancy guard — stop_hook_active is true', session: sessionName }, sessionName);
    process.exit(0);
  }

  const lastAssistantMessage = hookPayload.last_assistant_message;

  if (!lastAssistantMessage) {
    appendJsonlEntry({ level: 'debug', source: 'event_stop', message: 'No last_assistant_message — skipping', session: sessionName }, sessionName);
    process.exit(0);
  }

  const queueResult = processQueueForHook(sessionName, 'Stop', null, lastAssistantMessage);

  if (queueResult.action === 'advanced') {
    process.exit(0);
  }

  if (queueResult.action === 'queue-complete') {
    const messageContent = JSON.stringify(queueResult.summary, null, 2);

    await retryWithBackoff(
      () => wakeAgentViaGateway({
        openclawSessionId: resolvedAgent.openclaw_session_id,
        messageContent,
        promptFilePath,
        eventMetadata: {
          eventType: 'Stop',
          sessionName,
          timestamp: new Date().toISOString(),
        },
        sessionName,
      }),
      { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: 'wake-on-queue-complete', sessionName },
    );

    process.exit(0);
  }

  if (queueResult.action === 'awaits-mismatch') {
    appendJsonlEntry({ level: 'debug', source: 'event_stop', message: 'Queue awaits-mismatch — skipping', session: sessionName }, sessionName);
    process.exit(0);
  }

  if (queueResult.action === 'no-active-command') {
    appendJsonlEntry({ level: 'debug', source: 'event_stop', message: 'Queue has no active command — skipping', session: sessionName }, sessionName);
    process.exit(0);
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

  await retryWithBackoff(
    () => wakeAgentViaGateway({
      openclawSessionId: resolvedAgent.openclaw_session_id,
      messageContent,
      promptFilePath,
      eventMetadata: {
        eventType: 'Stop',
        sessionName,
        timestamp: new Date().toISOString(),
      },
      sessionName,
    }),
    { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: 'wake-on-stop', sessionName },
  );

  appendJsonlEntry({
    level: 'info',
    source: 'event_stop',
    message: 'Agent woken via gateway for Stop event',
    session: sessionName,
    suggested_commands_count: suggestedCommands.length,
  }, sessionName);

  process.exit(0);
}

main().catch((caughtError) => {
  process.stderr.write(`[event_stop] Error: ${caughtError.message}\n`);
  process.exit(1);
});
