#!/usr/bin/env node
/**
 * bin/type-command-deferred.mjs — Deferred command typer for post-/clear queue advancement.
 *
 * Spawned as a DETACHED background process by processQueueForHook when advancing
 * the queue after a /clear (SessionStart source:clear). Because the hook handler
 * runs synchronously and Claude Code blocks while the hook executes, the new TUI
 * prompt cannot render until the hook returns. Typing from inside the hook causes
 * Enter to be eaten by the still-initializing TUI.
 *
 * This script runs AFTER the hook has returned. It polls the tmux pane until a
 * fresh empty prompt appears (any line starting with the prompt indicator followed
 * only by whitespace), then types the command and presses Enter.
 *
 * Usage (called by processQueueForHook — do not call directly):
 *   node bin/type-command-deferred.mjs --session <name> --command <text>
 *
 * Exit codes:
 *   0 — command typed and Enter sent successfully
 *   1 — argument error
 *   2 — fresh prompt not detected within timeout
 */

import { parseArgs } from 'node:util';
import { execFileSync } from 'node:child_process';
import { appendJsonlEntry } from '../lib/logger.mjs';
import { sleepMilliseconds } from '../lib/tui-common.mjs';

const FRESH_PROMPT_POLL_INTERVAL_MILLISECONDS = 150;
const FRESH_PROMPT_TIMEOUT_MILLISECONDS = 15000;
const PROMPT_INDICATOR = '\u276F';

/**
 * Capture the current visible content of a tmux pane.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @returns {string} The current pane content, trimmed.
 */
function captureTmuxPaneContent(tmuxSessionName) {
  const paneContent = execFileSync('tmux', ['capture-pane', '-t', tmuxSessionName, '-p'], {
    encoding: 'utf8',
  });
  return paneContent.trim();
}

/**
 * Check whether the pane currently shows a fresh empty prompt.
 *
 * A "fresh" prompt means the TUI has fully initialized after /clear and is
 * waiting for input with nothing typed yet. We detect this by finding any line
 * that starts with the prompt indicator and contains only whitespace after it.
 *
 * We cannot rely on the last non-blank line because the TUI renders a status
 * bar (model name, permissions) and a separator line BELOW the prompt line.
 * The prompt itself uses a non-breaking space (\u00a0) after the indicator.
 *
 * We distinguish a "fresh" prompt (❯ with no command) from a "used" prompt
 * (❯ /clear, ❯ /gsd:quick ...) by checking that nothing other than whitespace
 * follows the prompt indicator on that line.
 *
 * @param {string} paneContent - Current pane text (already trimmed).
 * @returns {boolean} True if the pane shows a fresh empty prompt.
 */
function isFreshEmptyPromptVisible(paneContent) {
  const lines = paneContent.split('\n');

  return lines.some((line) => {
    if (!line.startsWith(PROMPT_INDICATOR)) {
      return false;
    }

    const textAfterPrompt = line.slice(PROMPT_INDICATOR.length);

    // Allow only whitespace (regular or non-breaking) after the prompt indicator.
    // Any real characters (like a command being typed) disqualify this line.
    return textAfterPrompt.trim().length === 0;
  });
}

/**
 * Poll the tmux pane until a fresh empty prompt is detected or timeout elapses.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @returns {boolean} True if fresh prompt detected, false on timeout.
 */
function waitForFreshEmptyPrompt(tmuxSessionName) {
  const deadlineMilliseconds = Date.now() + FRESH_PROMPT_TIMEOUT_MILLISECONDS;

  while (Date.now() < deadlineMilliseconds) {
    const paneContent = captureTmuxPaneContent(tmuxSessionName);

    if (isFreshEmptyPromptVisible(paneContent)) {
      return true;
    }

    sleepMilliseconds(FRESH_PROMPT_POLL_INTERVAL_MILLISECONDS);
  }

  return false;
}

/**
 * Type literal text into a tmux session using send-keys -l.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @param {string} textToType - Literal text to send.
 */
function sendLiteralTextToTmux(tmuxSessionName, textToType) {
  execFileSync('tmux', ['send-keys', '-l', '-t', tmuxSessionName, textToType], {
    stdio: 'pipe',
  });
}

/**
 * Send a special key to a tmux session.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @param {string} specialKeyName - The key name tmux recognizes (e.g. "Enter").
 */
function sendSpecialKeyToTmux(tmuxSessionName, specialKeyName) {
  execFileSync('tmux', ['send-keys', '-t', tmuxSessionName, specialKeyName], {
    stdio: 'pipe',
  });
}

/**
 * Parse CLI arguments.
 *
 * @returns {{ sessionName: string|undefined, commandText: string|undefined }}
 */
function parseCommandLineArguments() {
  const { values } = parseArgs({
    args: process.argv.slice(2),
    options: {
      session: { type: 'string', short: 's' },
      command: { type: 'string', short: 'c' },
    },
    allowPositionals: false,
  });

  return {
    sessionName: values.session,
    commandText: values.command,
  };
}

async function main() {
  const { sessionName, commandText } = parseCommandLineArguments();

  if (!sessionName) {
    process.stderr.write('Error: --session <session-name> is required\n');
    process.exit(1);
  }

  if (!commandText) {
    process.stderr.write('Error: --command <text> is required\n');
    process.exit(1);
  }

  const freshPromptDetected = waitForFreshEmptyPrompt(sessionName);

  if (!freshPromptDetected) {
    appendJsonlEntry({
      level: 'error',
      source: 'type-command-deferred',
      message: `Fresh empty prompt not detected within ${FRESH_PROMPT_TIMEOUT_MILLISECONDS}ms — command not typed`,
      session: sessionName,
      command: commandText,
    }, sessionName);
    process.exit(2);
  }

  sendLiteralTextToTmux(sessionName, commandText);
  sendSpecialKeyToTmux(sessionName, 'Enter');

  appendJsonlEntry({
    level: 'info',
    source: 'type-command-deferred',
    message: 'Deferred command typed and submitted after fresh prompt detected',
    session: sessionName,
    command: commandText,
  }, sessionName);
}

main().catch((caughtError) => {
  process.stderr.write(`Error: ${caughtError.message}\n`);
  process.exit(1);
});
