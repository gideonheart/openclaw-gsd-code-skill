/**
 * lib/tui-common.mjs — tmux send-keys wrapper for typing slash commands.
 *
 * Provides typeCommandIntoTmuxSession() that handles all tmux TUI mechanics:
 * typing command text, Tab completion for /gsd:* commands, and Enter to submit.
 *
 * Uses execFileSync with argument arrays (Phase 01.1 pattern — never string
 * interpolation into shell). Includes delay after Tab to let Claude Code
 * process autocomplete before Enter is sent.
 */

import { execFileSync } from 'node:child_process';
import { appendJsonlEntry } from './logger.mjs';

const TAB_AUTOCOMPLETE_DELAY_MILLISECONDS = 500;

/**
 * Synchronous sleep using Atomics.wait on a SharedArrayBuffer.
 * Used between Tab and Enter to let Claude Code process autocomplete.
 *
 * @param {number} durationMilliseconds - How long to sleep.
 */
function sleepMilliseconds(durationMilliseconds) {
  const sharedBuffer = new SharedArrayBuffer(4);
  const int32Array = new Int32Array(sharedBuffer);
  Atomics.wait(int32Array, 0, 0, durationMilliseconds);
}

/**
 * Type a slash command into a named tmux session pane.
 *
 * For /gsd:* commands: types the command name, sends Tab for autocomplete,
 * waits for autocomplete to resolve, types any arguments, then sends Enter.
 * For /clear and other non-/gsd: commands: types the full text then sends Enter.
 *
 * @param {string} tmuxSessionName - The tmux session to type into (e.g. "warden-main-4").
 * @param {string} commandText - The full command text (e.g. "/gsd:plan-phase 3" or "/clear").
 * @throws {Error} If tmuxSessionName or commandText is missing/empty.
 */
export function typeCommandIntoTmuxSession(tmuxSessionName, commandText) {
  if (!tmuxSessionName) {
    throw new Error('typeCommandIntoTmuxSession: tmuxSessionName is required');
  }

  if (!commandText) {
    throw new Error('typeCommandIntoTmuxSession: commandText is required');
  }

  if (commandText.startsWith('/gsd:')) {
    typeGsdCommandWithTabCompletion(tmuxSessionName, commandText);
  } else {
    typePlainCommandWithEnter(tmuxSessionName, commandText);
  }

  appendJsonlEntry({
    level: 'info',
    source: 'typeCommandIntoTmuxSession',
    message: 'Command typed into tmux session',
    session: tmuxSessionName,
    command: commandText,
  }, tmuxSessionName);
}

/**
 * Type a /gsd:* command using Tab completion, then Enter.
 * Includes a delay after Tab to let Claude Code process autocomplete
 * before Enter is sent — without this, Enter arrives before the
 * autocomplete popup resolves and the command is never submitted.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @param {string} commandText - Full /gsd:* command including any arguments.
 */
function typeGsdCommandWithTabCompletion(tmuxSessionName, commandText) {
  const spaceIndex = commandText.indexOf(' ');
  const hasArguments = spaceIndex !== -1;

  if (hasArguments) {
    const commandName = commandText.slice(0, spaceIndex);
    const commandArguments = commandText.slice(spaceIndex + 1);

    sendKeysToTmux(tmuxSessionName, commandName);
    sendSpecialKeyToTmux(tmuxSessionName, 'Tab');
    sleepMilliseconds(TAB_AUTOCOMPLETE_DELAY_MILLISECONDS);
    sendKeysToTmux(tmuxSessionName, ' ' + commandArguments);
  } else {
    sendKeysToTmux(tmuxSessionName, commandText);
    sendSpecialKeyToTmux(tmuxSessionName, 'Tab');
    sleepMilliseconds(TAB_AUTOCOMPLETE_DELAY_MILLISECONDS);
  }

  sendSpecialKeyToTmux(tmuxSessionName, 'Enter');
}

/**
 * Type plain text (e.g. /clear) followed by Enter without Tab completion.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @param {string} commandText - Full command text to type literally.
 */
function typePlainCommandWithEnter(tmuxSessionName, commandText) {
  sendKeysToTmux(tmuxSessionName, commandText);
  sendSpecialKeyToTmux(tmuxSessionName, 'Enter');
}

/**
 * Send literal text to a tmux session via send-keys.
 * Uses -l flag to prevent tmux from interpreting text as key names.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @param {string} textToType - Literal text to send.
 */
export function sendKeysToTmux(tmuxSessionName, textToType) {
  execFileSync('tmux', ['send-keys', '-l', '-t', tmuxSessionName, textToType], {
    stdio: 'pipe',
  });
}

/**
 * Send a special key (Tab, Enter, etc.) to a tmux session.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @param {string} specialKeyName - The key name tmux recognizes (e.g. "Tab", "Enter").
 */
export function sendSpecialKeyToTmux(tmuxSessionName, specialKeyName) {
  execFileSync('tmux', ['send-keys', '-t', tmuxSessionName, specialKeyName], {
    stdio: 'pipe',
  });
}
