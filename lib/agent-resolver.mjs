/**
 * lib/agent-resolver.mjs — Session-to-agent lookup via agent-registry.json.
 *
 * Provides resolveAgentFromSession() that maps a tmux session name to its
 * agent configuration. Returns null silently for unrecognized or disabled
 * sessions — not every tmux session running Claude Code is a managed agent.
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { appendJsonlEntry } from './logger.mjs';
import { SKILL_ROOT } from './paths.mjs';
const AGENT_REGISTRY_PATH = resolve(SKILL_ROOT, 'config', 'agent-registry.json');

/**
 * Look up an agent configuration by its tmux session name.
 *
 * @param {string} tmuxSessionName - The tmux session name to look up.
 * @returns {Object|null} The full agent configuration object, or null if not
 *   found, disabled, or the registry is unavailable.
 */
export function resolveAgentFromSession(tmuxSessionName) {
  if (!tmuxSessionName) {
    return null;
  }

  if (!existsSync(AGENT_REGISTRY_PATH)) {
    return null;
  }

  let registry;
  try {
    const registryFileContents = readFileSync(AGENT_REGISTRY_PATH, 'utf8');
    registry = JSON.parse(registryFileContents);
  } catch (parseError) {
    appendJsonlEntry({
      level: 'warn',
      source: 'resolveAgentFromSession',
      message: 'Failed to parse agent-registry.json',
      error: parseError.message,
    });
    return null;
  }

  if (!Array.isArray(registry.agents)) {
    appendJsonlEntry({
      level: 'warn',
      source: 'resolveAgentFromSession',
      message: 'Agent registry missing agents array',
    });
    return null;
  }

  const matchingAgent = registry.agents.find(
    (agent) => agent.session_name === tmuxSessionName,
  );

  if (!matchingAgent) {
    return null;
  }

  if (matchingAgent.enabled === false) {
    return null;
  }

  return matchingAgent;
}
