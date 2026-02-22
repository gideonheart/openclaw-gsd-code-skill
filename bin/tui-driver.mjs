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
 * Examples:
 *   node bin/tui-driver.mjs --session warden-main-4 '["/clear", "/gsd:plan-phase 3"]'
 *   node bin/tui-driver.mjs --session warden-main-4 '["/gsd:quick @logs/prompts/task-123.md"]'
 *
 * Long content (multiline prompts, task descriptions):
 *   Commands are typed into the Claude Code TUI via tmux send-keys. Newlines
 *   in the text act as Enter keypresses, which submits the input prematurely.
 *   For any content longer than a single line, write it to a file and use
 *   Claude Code's @file reference syntax:
 *
 *     1. Write content to:  logs/prompts/<descriptive-name>.md
 *     2. Reference it in the command:  "/gsd:quick @logs/prompts/<descriptive-name>.md"
 *
 *   The logs/prompts/ directory is gitignored (under logs/) and holds
 *   ephemeral prompt files written by OpenClaw before sending to a session.
 *   Claude Code expands @file references at input time, so the full content
 *   reaches the skill as $ARGUMENTS. The tui-driver only types the short
 *   single-line command string.
 *
 *   NEVER pass multiline text directly in the command array — it will break.
 *
 * The command array is a JSON string of slash commands to execute in order.
 * The awaits hook for each command is resolved automatically from its type:
 *   /clear  -> awaits SessionStart (source: clear)
 *   /gsd:*  -> awaits Stop
 *   other   -> awaits Stop (safe default)
 */

import { parseArgs } from 'node:util';
import { existsSync } from 'node:fs';
import { writeQueueFileAtomically, resolveQueueFilePath, typeCommandIntoTmuxSession, appendJsonlEntry } from '../lib/index.mjs';

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
  const createdAt = new Date().toISOString();

  return {
    created_at: createdAt,
    commands: commandTexts.map((commandText, index) => ({
      id: index + 1,
      command: commandText,
      created_at: createdAt,
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
  const queueFilePath = resolveQueueFilePath(sessionName);

  if (existsSync(queueFilePath)) {
    appendJsonlEntry({
      level: 'warn',
      source: 'tui-driver',
      message: 'Overwriting existing queue — previous queue may have been incomplete',
      session: sessionName,
    }, sessionName);
  }

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
