/**
 * lib/gateway.mjs — Wake agent via OpenClaw gateway CLI.
 *
 * Provides wakeAgentViaGateway() that invokes `openclaw agent --session-id`
 * to deliver content, prompt, and event metadata to a managed agent. Uses
 * execFileSync with argument arrays (Phase 01.1 pattern — never string
 * interpolation into shell).
 *
 * This function is intentionally NOT wrapped with retryWithBackoff internally.
 * Retry is a separate utility — the caller wraps with
 * `retryWithBackoff(() => wakeAgentViaGateway(params))` when retry is desired.
 */

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { appendJsonlEntry } from './logger.mjs';

const GATEWAY_TIMEOUT_MILLISECONDS = 120_000;

/**
 * Wake an agent via the OpenClaw gateway CLI.
 *
 * Reads the prompt file at call time (not cached) so that prompt updates
 * take effect immediately without restarting. Combines event metadata,
 * assistant message content, and prompt instructions into a single message
 * delivered via `openclaw agent --session-id`.
 *
 * @param {Object} wakeParameters - All parameters for the wake call.
 * @param {string} wakeParameters.openclawSessionId - The agent's OpenClaw session UUID.
 * @param {string} wakeParameters.messageContent - The last_assistant_message (trimmed whitespace only, no truncation).
 * @param {string} wakeParameters.promptFilePath - Absolute path to the .md prompt file for this event type.
 * @param {Object} wakeParameters.eventMetadata - { eventType, sessionName, timestamp } for agent context.
 * @param {string} [wakeParameters.sessionName] - Optional session name for JSONL logging context.
 * @throws {Error} If required parameters are missing or if the CLI invocation fails.
 */
export function wakeAgentViaGateway(wakeParameters) {
  const {
    openclawSessionId,
    messageContent,
    promptFilePath,
    eventMetadata,
    sessionName,
  } = wakeParameters;

  if (!openclawSessionId) {
    throw new Error('wakeAgentViaGateway: openclawSessionId is required');
  }

  if (typeof messageContent !== 'string') {
    throw new Error('wakeAgentViaGateway: messageContent must be a string');
  }

  if (!promptFilePath) {
    throw new Error('wakeAgentViaGateway: promptFilePath is required');
  }

  const promptContent = readFileSync(promptFilePath, 'utf8').trim();

  const combinedMessage = [
    '## Event Metadata',
    `- Event: ${eventMetadata.eventType}`,
    `- Session: ${eventMetadata.sessionName}`,
    `- Timestamp: ${eventMetadata.timestamp}`,
    '',
    '## Last Assistant Message',
    messageContent,
    '',
    '## Instructions',
    promptContent,
  ].join('\n');

  const openclawArguments = [
    'agent',
    '--session-id', openclawSessionId,
    '--message', combinedMessage,
  ];

  try {
    execFileSync('openclaw', openclawArguments, {
      stdio: 'pipe',
      timeout: GATEWAY_TIMEOUT_MILLISECONDS,
    });

    appendJsonlEntry({
      level: 'info',
      source: 'wakeAgentViaGateway',
      message: 'Agent wake delivered',
      openclaw_session_id: openclawSessionId,
      event_type: eventMetadata.eventType,
    }, sessionName);
  } catch (caughtError) {
    appendJsonlEntry({
      level: 'error',
      source: 'wakeAgentViaGateway',
      message: 'Gateway delivery failed',
      openclaw_session_id: openclawSessionId,
      event_type: eventMetadata.eventType,
      error: caughtError.message,
    }, sessionName);

    throw caughtError;
  }
}
