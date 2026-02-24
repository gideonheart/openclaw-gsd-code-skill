/**
 * lib/gateway.mjs — Wake agent via OpenClaw gateway CLI.
 *
 * Provides three exports:
 *
 * - wakeAgentViaGateway() — raw single-attempt delivery via `openclaw agent --agent --session-id`.
 *   Uses execFileSync with argument arrays (Phase 01.1 pattern — never string
 *   interpolation into shell). Intentionally NOT retried internally; callers
 *   wrap with retryWithBackoff when retry is desired.
 *
 * - wakeAgentWithRetry() — convenience wrapper that composes wakeAgentViaGateway
 *   with retryWithBackoff (3 attempts, 2s base delay). Builds eventMetadata
 *   internally. Use this for all handler call sites.
 *
 * - wakeAgentDetached() — fire-and-forget variant that spawns the openclaw CLI as a
 *   fully detached background process. The caller returns immediately without waiting
 *   for delivery. Required for PreToolUse(AskUserQuestion): the hook must exit before
 *   Claude Code renders the AskUserQuestion TUI — using execFileSync here would block
 *   the hook, preventing the TUI from appearing until after keystrokes are sent.
 */

import { execFileSync, spawn } from 'node:child_process';
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

/**
 * Wake an agent via gateway as a fully detached background process.
 *
 * Spawns the openclaw CLI with stdio ignored and detached:true, then unrefs so
 * the parent process can exit immediately without waiting for delivery.
 *
 * WHEN TO USE: Any PreToolUse handler that must exit before the Claude Code TUI
 * renders. Using wakeAgentWithRetry (execFileSync) from a PreToolUse hook blocks
 * the hook process, which blocks Claude Code, which prevents the TUI from
 * appearing until after the hook exits — causing any TUI polling in the agent's
 * response to time out and send keystrokes into the wrong state.
 *
 * TRADE-OFF: No retry on delivery failure (fire-and-forget). Acceptable for
 * AskUserQuestion because the hook must yield to let the TUI render.
 *
 * @param {Object} params
 * @param {Object} params.resolvedAgent - Agent object with agent_id and openclaw_session_id.
 * @param {string} params.messageContent - Content to deliver to the agent.
 * @param {string} params.promptFilePath - Absolute path to the prompt .md file.
 * @param {string} params.eventType - Hook event type (e.g. 'PreToolUse').
 * @param {string} params.sessionName - tmux session name (for logging).
 */
export function wakeAgentDetached({ resolvedAgent, messageContent, promptFilePath, eventType, sessionName }) {
  const promptContent = readFileSync(promptFilePath, 'utf8').trim();

  const combinedMessage = [
    '## Event Metadata',
    `- Event: ${eventType}`,
    `- Session: ${sessionName}`,
    `- Timestamp: ${new Date().toISOString()}`,
    '',
    '## Last Assistant Message',
    messageContent,
    '',
    '## Instructions',
    promptContent,
  ].join('\n');

  const openclawArguments = [
    'agent',
    '--agent', resolvedAgent.agent_id,
    '--session-id', resolvedAgent.openclaw_session_id,
    '--message', combinedMessage,
  ];

  appendJsonlEntry({
    level: 'info',
    source: 'wakeAgentDetached',
    message: 'Spawning detached openclaw wake — hook will exit immediately',
    agent_id: resolvedAgent.agent_id,
    openclaw_session_id: resolvedAgent.openclaw_session_id,
    event_type: eventType,
    session: sessionName,
  }, sessionName);

  const childProcess = spawn(
    'openclaw',
    openclawArguments,
    {
      detached: true,
      stdio: 'ignore',
    },
  );

  childProcess.unref();
}
