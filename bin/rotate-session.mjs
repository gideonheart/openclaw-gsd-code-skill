#!/usr/bin/env node
/**
 * rotate-session.mjs
 *
 * Rotate an agent's openclaw_session_id by creating a NEW OpenClaw session
 * via the `openclaw agent` CLI, then archiving the old ID into session_history.
 *
 * Usage:
 *   node bin/rotate-session.mjs <agent-id> [--label <text>]
 *
 * Reads and writes config/agent-registry.json relative to the skill root.
 * The registry file is written atomically (tmp + rename) to prevent corruption.
 *
 * The new openclaw_session_id is obtained by calling:
 *   openclaw agent --agent <agentId> --message "<label>" --json
 * which starts a fresh session and returns JSON containing the new session ID.
 */

import { readFileSync, writeFileSync, existsSync, renameSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { execFileSync } from 'node:child_process';

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
 * Create a new OpenClaw session for an agent via the `openclaw agent` CLI.
 *
 * Calls: openclaw agent --agent <agentIdentifier> --message <initialMessage> --json
 *
 * The CLI returns a JSON object with the new session ID at:
 *   response.result.meta.agentMeta.sessionId
 *
 * @param {string} agentIdentifier - Agent ID (e.g. 'warden').
 * @param {string} initialMessage  - Message to start the new session with.
 * @returns {string} The newly created session ID (UUID).
 * @throws {Error} If the CLI call fails or the session ID is missing from the response.
 */
function createNewOpenclawSession(agentIdentifier, initialMessage) {
  let rawOutput;
  try {
    rawOutput = execFileSync(
      'openclaw',
      ['agent', '--agent', agentIdentifier, '--message', initialMessage, '--json'],
      { encoding: 'utf8' }
    );
  } catch (execError) {
    throw new Error(
      `openclaw agent CLI call failed for agent "${agentIdentifier}":\n${execError.message}`
    );
  }

  let parsedResponse;
  try {
    parsedResponse = JSON.parse(rawOutput);
  } catch (parseError) {
    throw new Error(
      `Failed to parse openclaw agent response as JSON: ${parseError.message}\n` +
      `Raw output: ${rawOutput}`
    );
  }

  const newSessionId = parsedResponse?.result?.meta?.agentMeta?.sessionId;
  if (!newSessionId || typeof newSessionId !== 'string') {
    throw new Error(
      `openclaw agent response is missing session ID at response.result.meta.agentMeta.sessionId.\n` +
      `Parsed response: ${JSON.stringify(parsedResponse, null, 2)}`
    );
  }

  return newSessionId;
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
      '  --label <text>   Optional label/reason for the rotation (used as the initial message)\n' +
      '  --help           Show this help message\n\n' +
      'Creates a new OpenClaw session for the agent via the openclaw CLI and updates\n' +
      'agent-registry.json with the new session ID, archiving the old one to session_history.\n'
    );
    process.exit(0);
  }

  const agentIdentifier = positionalArguments[0];
  const optionalLabel = namedArguments['label'] || undefined;

  const registry = readAgentRegistry();
  const agentConfiguration = findAgentByIdentifier(registry, agentIdentifier);

  const oldSessionId = agentConfiguration.openclaw_session_id;

  const initialMessage = optionalLabel ?? 'Session rotated';
  const newSessionId = createNewOpenclawSession(agentIdentifier, initialMessage);

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
