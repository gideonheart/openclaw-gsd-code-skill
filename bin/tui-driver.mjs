#!/usr/bin/env node
/**
 * bin/tui-driver.mjs — Generic TUI command driver.
 *
 * Called by the orchestrating agent to create a command queue and type the
 * first command into a named tmux session. The hook-driven queue processor
 * in lib/queue-processor.mjs handles all subsequent commands.
 *
 * Usage:
 *   node bin/tui-driver.mjs --session <session-name> '<json-command-array>'
 *
 * Example:
 *   node bin/tui-driver.mjs --session warden-main-4 '["/clear", "/gsd:plan-phase 3"]'
 *
 * The command array is a JSON string of slash commands to execute in order.
 * The awaits hook for each command is resolved automatically from its type:
 *   /clear  -> awaits SessionStart (source: clear)
 *   /gsd:*  -> awaits Stop
 *   other   -> awaits Stop (safe default)
 */

import { writeFileSync, renameSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { typeCommandIntoTmuxSession } from '../lib/tui-common.mjs';
import { appendJsonlEntry } from '../lib/logger.mjs';

const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const QUEUES_DIRECTORY = resolve(SKILL_ROOT, 'logs', 'queues');

/**
 * Resolve the awaits mapping for a slash command.
 *
 * @param {string} commandText - The slash command text (e.g. "/clear", "/gsd:plan-phase 3").
 * @returns {{ hook: string, sub: string|null }} The awaits object for the queue entry.
 */
function resolveAwaitsForCommand(commandText) {
  if (commandText === '/clear') {
    return { hook: 'SessionStart', sub: 'clear' };
  }

  return { hook: 'Stop', sub: null };
}

/**
 * Write queue data atomically: write to .tmp then rename over the target path.
 *
 * @param {string} queueFilePath - Absolute path to the target queue file.
 * @param {Object} queueData - Queue data object to serialize as JSON.
 */
function writeQueueFileAtomically(queueFilePath, queueData) {
  mkdirSync(dirname(queueFilePath), { recursive: true });
  const temporaryFilePath = queueFilePath + '.tmp';
  writeFileSync(temporaryFilePath, JSON.stringify(queueData, null, 2), 'utf8');
  renameSync(temporaryFilePath, queueFilePath);
}

/**
 * Parse CLI arguments from process.argv.
 *
 * @returns {{ sessionName: string|undefined, commandArrayString: string|undefined }}
 */
function parseCommandLineArguments() {
  const { values, positionals } = parseArgs({
    args: process.argv.slice(2),
    options: {
      session: { type: 'string', short: 's' },
    },
    allowPositionals: true,
  });

  return {
    sessionName: values.session,
    commandArrayString: positionals[0],
  };
}

/**
 * Build the queue data structure with proper awaits for each command.
 *
 * @param {string[]} commandTexts - Array of slash command strings.
 * @returns {Object} Queue data object ready for JSON serialization.
 */
function buildQueueData(commandTexts) {
  return {
    commands: commandTexts.map((commandText, index) => ({
      id: index + 1,
      command: commandText,
      status: index === 0 ? 'active' : 'pending',
      awaits: resolveAwaitsForCommand(commandText),
      result: null,
      completed_at: null,
    })),
  };
}

async function main() {
  const { sessionName, commandArrayString } = parseCommandLineArguments();

  if (!sessionName) {
    process.stderr.write('Error: --session <session-name> is required\n');
    process.exit(1);
  }

  if (!commandArrayString) {
    process.stderr.write('Error: JSON command array is required as a positional argument\n');
    process.exit(1);
  }

  let commandTexts;
  try {
    commandTexts = JSON.parse(commandArrayString);
  } catch (parseError) {
    process.stderr.write(`Error: Failed to parse command array as JSON: ${parseError.message}\n`);
    process.exit(1);
  }

  if (!Array.isArray(commandTexts) || commandTexts.length === 0) {
    process.stderr.write('Error: Command array must be a non-empty array of strings\n');
    process.exit(1);
  }

  if (!commandTexts.every(item => typeof item === 'string')) {
    process.stderr.write('Error: All items in the command array must be strings\n');
    process.exit(1);
  }

  const queueData = buildQueueData(commandTexts);
  const queueFilePath = resolve(QUEUES_DIRECTORY, `queue-${sessionName}.json`);

  writeQueueFileAtomically(queueFilePath, queueData);

  appendJsonlEntry({
    level: 'info',
    source: 'tui-driver',
    message: 'Queue created',
    session: sessionName,
    total_commands: commandTexts.length,
    first_command: commandTexts[0],
  }, sessionName);

  typeCommandIntoTmuxSession(sessionName, commandTexts[0]);
}

main().catch((caughtError) => {
  process.stderr.write(`Error: ${caughtError.message}\n`);
  process.exit(1);
});
