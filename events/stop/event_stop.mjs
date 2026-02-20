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

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  resolveAgentFromSession,
  wakeAgentViaGateway,
  processQueueForHook,
  appendJsonlEntry,
} from '../../lib/index.mjs';

async function main() {
  const rawStdin = readFileSync('/dev/stdin', 'utf8').trim();
  let hookPayload;
  try {
    hookPayload = JSON.parse(rawStdin);
  } catch {
    process.exit(0);
  }

  if (hookPayload.stop_hook_active === true) {
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

  const lastAssistantMessage = hookPayload.last_assistant_message;

  if (!lastAssistantMessage) {
    process.exit(0);
  }

  const queueResult = processQueueForHook(sessionName, 'Stop', null, lastAssistantMessage);

  if (queueResult.action === 'advanced') {
    process.exit(0);
  }

  if (queueResult.action === 'queue-complete') {
    const messageContent = JSON.stringify(queueResult.summary, null, 2);
    const promptFilePath = resolve(dirname(fileURLToPath(import.meta.url)), 'prompt_stop.md');

    wakeAgentViaGateway({
      openclawSessionId: resolvedAgent.openclaw_session_id,
      messageContent,
      promptFilePath,
      eventMetadata: {
        eventType: 'Stop',
        sessionName,
        timestamp: new Date().toISOString(),
      },
      sessionName,
    });

    process.exit(0);
  }

  if (queueResult.action === 'awaits-mismatch' || queueResult.action === 'no-active-command') {
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

  const promptFilePath = resolve(dirname(fileURLToPath(import.meta.url)), 'prompt_stop.md');

  wakeAgentViaGateway({
    openclawSessionId: resolvedAgent.openclaw_session_id,
    messageContent,
    promptFilePath,
    eventMetadata: {
      eventType: 'Stop',
      sessionName,
      timestamp: new Date().toISOString(),
    },
    sessionName,
  });

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
