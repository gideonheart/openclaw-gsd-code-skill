#!/usr/bin/env node
/**
 * rotate-session.mjs
 *
 * Replace an agent's openclaw_session_id with a fresh UUID, archiving the old
 * ID into a session_history array for later reference.
 *
 * Usage:
 *   node bin/rotate-session.mjs <agent-id> [--label <text>]
 *
 * Reads and writes config/agent-registry.json relative to the skill root.
 * The registry file is written atomically (tmp + rename) to prevent corruption.
 */

import { readFileSync, writeFileSync, existsSync, renameSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
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
  const newSessionId = randomUUID();
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
