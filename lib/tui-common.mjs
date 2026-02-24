/**
 * lib/tui-common.mjs — tmux send-keys wrapper for typing commands.
 *
 * Provides typeCommandIntoTmuxSession() that types full command text into a
 * tmux session and presses Enter. All commands — slash commands, /gsd:* with
 * args, /clear, plain text — are typed as literal text without Tab completion.
 *
 * Uses execFileSync with argument arrays (Phase 01.1 pattern — never string
 * interpolation into shell).
 */

import { execFileSync } from 'node:child_process';
import { appendJsonlEntry } from './logger.mjs';

const TUI_PROMPT_INDICATOR = '❯';
const TUI_READINESS_POLL_INTERVAL_MILLISECONDS = 100;
const TUI_READINESS_TIMEOUT_MILLISECONDS = 5000;

/**
 * Synchronous sleep using Atomics.wait on a SharedArrayBuffer.
 * Used by tui-driver-ask.mjs to wait for the AskUserQuestion TUI to render.
 *
 * @param {number} durationMilliseconds - How long to sleep.
 */
export function sleepMilliseconds(durationMilliseconds) {
  const sharedBuffer = new SharedArrayBuffer(4);
  const int32Array = new Int32Array(sharedBuffer);
  Atomics.wait(int32Array, 0, 0, durationMilliseconds);
}

/**
 * Poll the tmux pane until the Claude Code prompt indicator appears or timeout elapses.
 *
 * Claude Code's TUI shows a ❯ prompt indicator when it is ready to accept input.
 * After a /clear restart, the new session takes a moment to initialize before the
 * prompt renders. Typing commands before the prompt appears causes Enter to be eaten
 * by the initialization UI rather than submitted as a command.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 */
function waitForClaudeCodeTuiReady(tmuxSessionName) {
  const deadlineMilliseconds = Date.now() + TUI_READINESS_TIMEOUT_MILLISECONDS;

  while (Date.now() < deadlineMilliseconds) {
    const paneContent = captureTmuxPaneContent(tmuxSessionName);

    if (paneContent.includes(TUI_PROMPT_INDICATOR)) {
      return;
    }

    sleepMilliseconds(TUI_READINESS_POLL_INTERVAL_MILLISECONDS);
  }

  appendJsonlEntry({
    level: 'warn',
    source: 'waitForClaudeCodeTuiReady',
    message: `TUI prompt indicator not seen within ${TUI_READINESS_TIMEOUT_MILLISECONDS}ms — typing anyway`,
    session: tmuxSessionName,
  }, tmuxSessionName);
}

/**
 * Type a command into a named tmux session pane and press Enter.
 *
 * Waits for the Claude Code TUI prompt indicator (❯) before typing, ensuring
 * the TUI is ready to receive input. This handles the post-/clear case where
 * SessionStart fires before the new session's prompt has rendered.
 *
 * Types the full command text as literal characters then sends Enter.
 * No Tab completion — the full text is sent exactly as provided.
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

  waitForClaudeCodeTuiReady(tmuxSessionName);
  typePlainCommandWithEnter(tmuxSessionName, commandText);

  appendJsonlEntry({
    level: 'info',
    source: 'typeCommandIntoTmuxSession',
    message: 'Command typed into tmux session',
    session: tmuxSessionName,
    command: commandText,
  }, tmuxSessionName);
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

/**
 * Capture the current visible content of a tmux pane.
 * Used for TUI readiness detection — polling whether the Claude Code prompt or
 * AskUserQuestion prompt has rendered before sending keystrokes. This is NOT
 * pane scraping for content extraction; it reads UI state to time keystrokes correctly.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @returns {string} The current pane content, trimmed.
 */
export function captureTmuxPaneContent(tmuxSessionName) {
  const paneContent = execFileSync('tmux', ['capture-pane', '-t', tmuxSessionName, '-p'], {
    encoding: 'utf8',
  });
  return paneContent.trim();
}
