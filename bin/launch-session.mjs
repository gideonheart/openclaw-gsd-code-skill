#!/usr/bin/env node
/**
 * launch-session.mjs
 *
 * Launch a Claude Code session in a named tmux session for a registered agent.
 *
 * Usage:
 *   node bin/launch-session.mjs <agent-id> [--workdir <path>] [--first-command <command>]
 *
 * Reads agent configuration from config/agent-registry.json relative to the skill root.
 * Creates a new tmux session, starts Claude Code with the agent's system prompt,
 * and optionally sends an initial command after startup.
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { parseArgs } from 'node:util';

const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const AGENT_REGISTRY_PATH = resolve(SKILL_ROOT, 'config', 'agent-registry.json');
const TMUX_SESSION_STARTUP_DELAY_MILLISECONDS = 3000;

function logWithTimestamp(message) {
  const isoTimestamp = new Date().toISOString();
  process.stdout.write(`[${isoTimestamp}] ${message}\n`);
}

function parseCommandLineArguments(rawArguments) {
  const { values, positionals } = parseArgs({
    args: rawArguments,
    options: {
      workdir: { type: 'string' },
      'first-command': { type: 'string' },
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

  if (!matchingAgent.enabled) {
    throw new Error(
      `Agent "${agentIdentifier}" is disabled (enabled: false) in the registry.\n` +
      `Set enabled: true in config/agent-registry.json to activate this agent.`
    );
  }

  return matchingAgent;
}

function readSystemPromptFile(systemPromptFilePath) {
  const absoluteSystemPromptPath = resolve(SKILL_ROOT, systemPromptFilePath);

  if (!existsSync(absoluteSystemPromptPath)) {
    throw new Error(
      `System prompt file not found: ${absoluteSystemPromptPath}\n` +
      `Referenced by system_prompt_file field in agent-registry.json`
    );
  }

  return readFileSync(absoluteSystemPromptPath, 'utf8').trim();
}

function checkTmuxSessionExists(sessionName) {
  try {
    execFileSync('tmux', ['has-session', '-t', sessionName], { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

function createTmuxSession(sessionName, workingDirectory) {
  execFileSync('tmux', ['new-session', '-d', '-s', sessionName, '-c', workingDirectory], {
    stdio: 'inherit',
  });
}

function sendTmuxKeys(sessionName, keysToSend) {
  execFileSync('tmux', ['send-keys', '-t', sessionName, keysToSend, 'Enter'], {
    stdio: 'inherit',
  });
}

function sleepMilliseconds(durationInMilliseconds) {
  return new Promise((resolve) => setTimeout(resolve, durationInMilliseconds));
}

function buildClaudeStartCommand(systemPromptText, shouldSkipPermissions) {
  // Single-quote escape: replace each ' with '\'' (end quote, escaped quote, restart quote)
  const shellEscapedPrompt = systemPromptText.replace(/'/g, "'\\''");
  const permissionsFlag = shouldSkipPermissions ? ' --dangerously-skip-permissions' : '';
  return `claude${permissionsFlag} --system-prompt '${shellEscapedPrompt}'`;
}

async function main() {
  const commandLineArguments = process.argv.slice(2);

  const { positionalArguments, namedArguments } = parseCommandLineArguments(commandLineArguments);

  if (positionalArguments.length === 0 || namedArguments.help) {
    process.stdout.write(
      'Usage: node bin/launch-session.mjs <agent-id> [--workdir <path>] [--first-command <command>]\n\n' +
      'Arguments:\n' +
      '  agent-id            ID of the agent to launch (must exist in config/agent-registry.json)\n' +
      '  --workdir <path>    Override the working directory from the registry\n' +
      '  --first-command     Shell command to send to Claude Code after startup (e.g. a /gsd command)\n' +
      '  --help              Show this help message\n'
    );
    process.exit(0);
  }

  const agentIdentifier = positionalArguments[0];
  if (!agentIdentifier) {
    throw new Error('agent-id is required as the first argument');
  }

  const registry = readAgentRegistry();
  const agentConfiguration = findAgentByIdentifier(registry, agentIdentifier);

  const workingDirectory = namedArguments['workdir'] || agentConfiguration.working_directory;
  const sessionName = agentConfiguration.session_name;
  const optionalFirstCommand = namedArguments['first-command'] || null;

  logWithTimestamp(`Launching agent: ${agentIdentifier}`);
  logWithTimestamp(`Session name:    ${sessionName}`);
  logWithTimestamp(`Working dir:     ${workingDirectory}`);

  if (checkTmuxSessionExists(sessionName)) {
    logWithTimestamp(`Session "${sessionName}" already exists. Attach with: tmux attach -t ${sessionName}`);
    process.exit(0);
  }

  const systemPromptText = readSystemPromptFile(agentConfiguration.system_prompt_file);

  logWithTimestamp(`Creating tmux session: ${sessionName}`);
  createTmuxSession(sessionName, workingDirectory);

  logWithTimestamp('Starting Claude Code...');
  const shouldSkipPermissions = agentConfiguration.skip_permissions !== false;
  const claudeStartCommand = buildClaudeStartCommand(systemPromptText, shouldSkipPermissions);
  sendTmuxKeys(sessionName, claudeStartCommand);

  if (optionalFirstCommand !== null) {
    logWithTimestamp(`Waiting ${TMUX_SESSION_STARTUP_DELAY_MILLISECONDS}ms then sending first command...`);
    await sleepMilliseconds(TMUX_SESSION_STARTUP_DELAY_MILLISECONDS);
    sendTmuxKeys(sessionName, optionalFirstCommand);
  }

  logWithTimestamp(`Session ready. Attach with: tmux attach -t ${sessionName}`);
}

main().catch((error) => {
  process.stderr.write(`Error: ${error.message}\n`);
  process.exit(1);
});
