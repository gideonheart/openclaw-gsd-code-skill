/**
 * lib/gateway.mjs — Wake agent via OpenClaw gateway CLI.
 *
 * Provides two exports:
 *
 * - wakeAgentViaGateway() — raw single-attempt delivery via `openclaw agent --agent --session-id`.
 *   Uses execFileSync with argument arrays (Phase 01.1 pattern — never string
 *   interpolation into shell). Intentionally NOT retried internally; callers
 *   wrap with retryWithBackoff when retry is desired.
 *
 * - wakeAgentWithRetry() — convenience wrapper that composes wakeAgentViaGateway
 *   with retryWithBackoff (3 attempts, 2s base delay). Builds eventMetadata
 *   internally. Use this for all handler call sites.
 */

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { appendJsonlEntry } from './logger.mjs';
import { retryWithBackoff } from './retry.mjs';

const GATEWAY_TIMEOUT_MILLISECONDS = 120_000;

/**
 * Wake an agent via the OpenClaw gateway CLI.
 *
 * Reads the prompt file at call time (not cached) so that prompt updates
 * take effect immediately without restarting. Combines event metadata,
 * assistant message content, and prompt instructions into a single message
 * delivered via `openclaw agent --agent --session-id`.
 *
 * @param {Object} wakeParameters - All parameters for the wake call.
 * @param {string} wakeParameters.agentId - The agent identifier (e.g., 'warden', 'gideon').
 * @param {string} wakeParameters.openclawSessionId - The agent's OpenClaw session UUID.
 * @param {string} wakeParameters.messageContent - The last_assistant_message (trimmed whitespace only, no truncation).
 * @param {string} wakeParameters.promptFilePath - Absolute path to the .md prompt file for this event type.
 * @param {Object} wakeParameters.eventMetadata - { eventType, sessionName, timestamp } for agent context.
 * @param {string} [wakeParameters.sessionName] - Optional session name for JSONL logging context.
 * @throws {Error} If required parameters are missing or if the CLI invocation fails.
 */
export function wakeAgentViaGateway(wakeParameters) {
  const {
    agentId,
    openclawSessionId,
    messageContent,
    promptFilePath,
    eventMetadata,
    sessionName,
  } = wakeParameters;

  if (!agentId) {
    throw new Error('wakeAgentViaGateway: agentId is required');
  }

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
    '--agent', agentId,
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
      agent_id: agentId,
      openclaw_session_id: openclawSessionId,
      event_type: eventMetadata.eventType,
    }, sessionName);
  } catch (caughtError) {
    appendJsonlEntry({
      level: 'error',
      source: 'wakeAgentViaGateway',
      message: 'Gateway delivery failed',
      agent_id: agentId,
      openclaw_session_id: openclawSessionId,
      event_type: eventMetadata.eventType,
      error: caughtError.message,
    }, sessionName);

    throw caughtError;
  }
}

/**
 * Wake an agent via gateway with automatic retry on failure.
 *
 * Composes wakeAgentViaGateway with retryWithBackoff (3 attempts, 2s base).
 * Builds eventMetadata internally from the provided eventType and sessionName.
 *
 * @param {Object} params
 * @param {Object} params.resolvedAgent - Agent object with openclaw_session_id.
 * @param {string} params.messageContent - Content to deliver to the agent.
 * @param {string} params.promptFilePath - Absolute path to the prompt .md file.
 * @param {string} params.eventType - Hook event type (e.g. 'Stop', 'SessionStart').
 * @param {string} params.sessionName - tmux session name.
 * @returns {Promise<void>}
 */
export function wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType, sessionName }) {
  return retryWithBackoff(
    () => wakeAgentViaGateway({
      agentId: resolvedAgent.agent_id,
      openclawSessionId: resolvedAgent.openclaw_session_id,
      messageContent,
      promptFilePath,
      eventMetadata: {
        eventType,
        sessionName,
        timestamp: new Date().toISOString(),
      },
      sessionName,
    }),
    { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: `wake-on-${eventType.toLowerCase()}`, sessionName },
  );
}
