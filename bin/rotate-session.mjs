#!/usr/bin/env node
/**
 * rotate-session.mjs
 *
 * Rotate an agent's openclaw_session_id by reading the actual current sessionId
 * from the agent's sessions.json (the most recently updated session for that agent),
 * then archiving the old ID into session_history.
 *
 * Usage:
 *   node bin/rotate-session.mjs <agent-id> [--label <text>]
 *
 * Reads and writes config/agent-registry.json relative to the skill root.
 * The registry file is written atomically (tmp + rename) to prevent corruption.
 *
 * The new openclaw_session_id is the actual sessionId from the agent's OpenClaw
 * session store — NOT a random UUID. This keeps the registry in sync with
 * OpenClaw's own session tracking so --session-id routing is accurate.
 */

import { readFileSync, writeFileSync, existsSync, renameSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const AGENT_REGISTRY_PATH = resolve(SKILL_ROOT, 'config', 'agent-registry.json');
const OPENCLAW_AGENTS_BASE_PATH = '/home/forge/.openclaw/agents';

function logWithTimestamp(message) {
  const isoTimestamp = new Date().toISOString();
  process.stdout.write(`[${isoTimestamp}] ${message}\n`);
}

function parseCommandLineArguments(rawArguments) {
  const { values, positionals } = parseArgs({
    args: rawArguments,
    options: {
      label: { type: 'string' },
      help: { type: 'boolean' },
    },
    allowPositionals: true,
    strict: false,
  });
  return { positionalArguments: positionals, namedArguments: values };
}

function readAgentRegistry() {
  if (!existsSync(AGENT_REGISTRY_PATH)) {
    throw new Error(
      `Agent registry not found at: ${AGENT_REGISTRY_PATH}\n` +
      `Copy config/agent-registry.example.json to config/agent-registry.json and fill in your values.`
    );
  }

  const registryFileContents = readFileSync(AGENT_REGISTRY_PATH, 'utf8');
  let registry;
  try {
    registry = JSON.parse(registryFileContents);
  } catch (parseError) {
    throw new Error(`Failed to parse agent registry JSON: ${parseError.message}`);
  }

  if (!Array.isArray(registry.agents)) {
    throw new Error('Agent registry is missing the required "agents" array');
  }

  return registry;
}

function findAgentByIdentifier(registry, agentIdentifier) {
  const matchingAgent = registry.agents.find(
    (agent) => agent.agent_id === agentIdentifier
  );

  if (matchingAgent === undefined) {
    const knownAgentIdentifiers = registry.agents.map((agent) => agent.agent_id).join(', ');
    throw new Error(
      `Agent "${agentIdentifier}" not found in registry.\n` +
      `Known agents: ${knownAgentIdentifiers}`
    );
  }

  return matchingAgent;
}

/**
 * Read the most recently updated sessionId for an agent from OpenClaw's sessions.json.
 *
 * OpenClaw stores session metadata in agents/{agentId}/sessions/sessions.json as a
 * map of session keys to session objects. Each session object has a sessionId (UUID)
 * that matches the JSONL conversation log filename. This function finds the session
 * with the highest updatedAt timestamp — that is the currently active conversation.
 *
 * Falls back to null if the sessions.json file does not exist or has no entries.
 *
 * @param {string} agentIdentifier - Agent ID (e.g. 'warden').
 * @returns {string|null} The active sessionId UUID, or null if not found.
 */
function resolveActiveOpenclawSessionId(agentIdentifier) {
  const sessionsFilePath = `${OPENCLAW_AGENTS_BASE_PATH}/${agentIdentifier}/sessions/sessions.json`;

  if (!existsSync(sessionsFilePath)) {
    return null;
  }

  let sessionsData;
  try {
    sessionsData = JSON.parse(readFileSync(sessionsFilePath, 'utf8'));
  } catch {
    return null;
  }

  if (typeof sessionsData !== 'object' || sessionsData === null) {
    return null;
  }

  const sessionEntries = Object.values(sessionsData);
  if (sessionEntries.length === 0) {
    return null;
  }

  const mostRecentSession = sessionEntries.reduce((mostRecent, current) => {
    const currentUpdatedAt = current.updatedAt ?? 0;
    const mostRecentUpdatedAt = mostRecent.updatedAt ?? 0;
    return currentUpdatedAt > mostRecentUpdatedAt ? current : mostRecent;
  });

  return mostRecentSession.sessionId ?? null;
}

function buildSessionHistoryEntry(oldSessionId, agentIdentifier, optionalLabel) {
  const sessionFilePath =
    `${OPENCLAW_AGENTS_BASE_PATH}/${agentIdentifier}/sessions/${oldSessionId}.jsonl`;

  const historyEntry = {
    session_id: oldSessionId,
    session_file: sessionFilePath,
    rotated_at: new Date().toISOString(),
  };

  if (optionalLabel !== undefined && optionalLabel !== null) {
    historyEntry.label = optionalLabel;
  }

  return historyEntry;
}

function writeRegistryAtomically(registry) {
  const registryJsonContents = JSON.stringify(registry, null, 2);
  const temporaryFilePath = `${AGENT_REGISTRY_PATH}.tmp`;
  writeFileSync(temporaryFilePath, registryJsonContents, 'utf8');
  renameSync(temporaryFilePath, AGENT_REGISTRY_PATH);
}

function main() {
  const commandLineArguments = process.argv.slice(2);
  const { positionalArguments, namedArguments } = parseCommandLineArguments(commandLineArguments);

  if (positionalArguments.length === 0 || namedArguments.help) {
    process.stdout.write(
      'Usage: node bin/rotate-session.mjs <agent-id> [--label <text>]\n\n' +
      'Arguments:\n' +
      '  agent-id         ID of the agent whose session to rotate\n' +
      '  --label <text>   Optional label/reason for the rotation\n' +
      '  --help           Show this help message\n'
    );
    process.exit(0);
  }

  const agentIdentifier = positionalArguments[0];

  const registry = readAgentRegistry();
  const agentConfiguration = findAgentByIdentifier(registry, agentIdentifier);

  const oldSessionId = agentConfiguration.openclaw_session_id;

  const newSessionId = resolveActiveOpenclawSessionId(agentIdentifier);
  if (!newSessionId) {
    throw new Error(
      `Could not resolve active OpenClaw session for agent "${agentIdentifier}".\n` +
      `Expected sessions.json at: ${OPENCLAW_AGENTS_BASE_PATH}/${agentIdentifier}/sessions/sessions.json\n` +
      `Ensure the agent has an active OpenClaw session before rotating.`
    );
  }

  if (newSessionId === oldSessionId) {
    logWithTimestamp(`Session already up to date for agent: ${agentIdentifier}`);
    logWithTimestamp(`  Current: ${oldSessionId}`);
    logWithTimestamp(`  No rotation needed.`);
    process.exit(0);
  }

  const optionalLabel = namedArguments['label'] || undefined;

  const historyEntry = buildSessionHistoryEntry(oldSessionId, agentIdentifier, optionalLabel);

  if (!Array.isArray(agentConfiguration.session_history)) {
    agentConfiguration.session_history = [];
  }
  agentConfiguration.session_history.push(historyEntry);
  agentConfiguration.openclaw_session_id = newSessionId;

  writeRegistryAtomically(registry);

  logWithTimestamp(`Rotated session for agent: ${agentIdentifier}`);
  logWithTimestamp(`  Old: ${oldSessionId}`);
  logWithTimestamp(`  New: ${newSessionId}`);
  logWithTimestamp(`  History: ${agentConfiguration.session_history.length} entries`);
  logWithTimestamp(`  Old session file: ${historyEntry.session_file}`);
}

main();
