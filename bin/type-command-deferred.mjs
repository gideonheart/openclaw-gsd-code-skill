#!/usr/bin/env node
/**
 * bin/type-command-deferred.mjs — Two-phase verified deferred command typer.
 *
 * Spawned as a DETACHED background process by processQueueForHook when advancing
 * the queue after a /clear (SessionStart source:clear). Because the hook handler
 * runs synchronously and Claude Code blocks while the hook executes, the new TUI
 * prompt cannot render until the hook returns. Typing from inside the hook causes
 * Enter to be eaten by the still-initializing TUI.
 *
 * This script runs AFTER the hook has returned. It uses a closed-loop two-phase
 * verification approach:
 *
 *   Phase 0: Poll until a fresh empty prompt appears in the tmux pane.
 *   Phase 1: Type text → verify text visible in pane → retry with C-u + retype on failure.
 *   Phase 2: Snapshot activeCommandId → send Enter → poll queue file for confirmed_at.
 *            Retry Enter on failure (text stays in input field).
 *
 * The old open-loop 500ms stabilization delay is eliminated. Instead, the
 * verification loop inherently waits for the TUI to be ready — if text doesn't
 * appear in the pane, the TUI wasn't ready yet, and we retry.
 *
 * Usage (called by processQueueForHook — do not call directly):
 *   node bin/type-command-deferred.mjs --session <name> --command <text>
 *
 * Exit codes:
 *   0 — command typed, verified, submitted, and confirmed
 *   1 — argument error
 *   2 — fresh prompt not detected within timeout
 *   3 — text verification failed after all retries
 *   4 — submission confirmation failed after all retries
 */

import { parseArgs } from 'node:util';
import { readFileSync, existsSync, writeFileSync, renameSync } from 'node:fs';
import { appendJsonlEntry } from '../lib/logger.mjs';
import { sleepMilliseconds, captureTmuxPaneContent, sendKeysToTmux, sendSpecialKeyToTmux } from '../lib/tui-common.mjs';
import { resolveQueueFilePath } from '../lib/queue-processor.mjs';

const FRESH_PROMPT_POLL_INTERVAL_MILLISECONDS = 150;
const FRESH_PROMPT_TIMEOUT_MILLISECONDS = 15000;
const TEXT_VERIFICATION_TIMEOUT_MILLISECONDS = 1000;
const TEXT_VERIFICATION_POLL_INTERVAL_MILLISECONDS = 200;
const SUBMIT_VERIFICATION_TIMEOUT_MILLISECONDS = 3000;
const SUBMIT_VERIFICATION_POLL_INTERVAL_MILLISECONDS = 200;
const MAXIMUM_TEXT_RETRIES = 2;
const MAXIMUM_ENTER_RETRIES = 3;
const PROMPT_INDICATOR = '\u276F';

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
 * Check whether the typed command text is visible on a prompt line in the pane.
 *
 * Looks for any line that starts with the prompt indicator and contains the
 * command text. This confirms that send-keys -l successfully delivered the
 * text into the TUI input field.
 *
 * @param {string} paneContent - Current pane text (already trimmed).
 * @param {string} commandText - The command text that should be visible.
 * @returns {boolean} True if a prompt line contains the command text.
 */
function normalizeForMatch(value) {
  return value
    .replace(/\u00a0/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractLastToken(commandText) {
  const normalized = normalizeForMatch(commandText);
  const tokens = normalized.split(' ').filter(Boolean);
  return tokens.length ? tokens[tokens.length - 1] : '';
}

function isCommandTextVisibleInPane(paneContent, commandText) {
  const lines = paneContent.split('\n');
  const normalizedCommand = normalizeForMatch(commandText);
  const lastToken = extractLastToken(commandText);

  // 1) Strong match: full normalized command on any prompt line.
  const promptFullMatch = lines.some((line) => {
    if (!line.startsWith(PROMPT_INDICATOR)) return false;
    return normalizeForMatch(line).includes(normalizedCommand);
  });
  if (promptFullMatch) return true;

  // 2) Pragmatic fallback: last token visible in prompt/input area.
  if (!lastToken) return false;

  const promptTokenMatch = lines.some((line) => {
    if (!line.startsWith(PROMPT_INDICATOR)) return false;
    return normalizeForMatch(line).includes(lastToken);
  });
  if (promptTokenMatch) return true;

  // 3) Final fallback: input field can render outside prompt line in some TUI states.
  const tail = normalizeForMatch(lines.slice(-10).join(' '));
  return tail.includes(lastToken);
}

/**
 * Poll the tmux pane until the command text appears on a prompt line.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 * @param {string} commandText - The command text to look for.
 * @returns {boolean} True if text verified in pane, false on timeout.
 */
function verifyTextAppearedInPane(tmuxSessionName, commandText) {
  const deadlineMilliseconds = Date.now() + TEXT_VERIFICATION_TIMEOUT_MILLISECONDS;

  while (Date.now() < deadlineMilliseconds) {
    const paneContent = captureTmuxPaneContent(tmuxSessionName);

    if (isCommandTextVisibleInPane(paneContent, commandText)) {
      return true;
    }

    sleepMilliseconds(TEXT_VERIFICATION_POLL_INTERVAL_MILLISECONDS);
  }

  return false;
}

/**
 * Clear the TUI input field by sending Ctrl-U (kill line backward).
 *
 * Used before retrying text entry to ensure no partial or garbled text
 * remains in the input field from a failed attempt.
 *
 * @param {string} tmuxSessionName - Target tmux session.
 */
function clearTuiInputField(tmuxSessionName) {
  sendSpecialKeyToTmux(tmuxSessionName, 'C-u');
}

/**
 * Read the active command from the queue file for a session.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {{ id: number, command: string }|null} The active command, or null if none.
 */
function readActiveCommandFromQueueFile(sessionName) {
  const queueFilePath = resolveQueueFilePath(sessionName);

  if (!existsSync(queueFilePath)) {
    return null;
  }

  const queueData = JSON.parse(readFileSync(queueFilePath, 'utf8'));
  const activeCommand = queueData.commands.find(command => command.status === 'active');

  if (!activeCommand) {
    return null;
  }

  return { id: activeCommand.id, command: activeCommand.command };
}

/**
 * Update delivery telemetry fields on the active queue command.
 *
 * @param {string} sessionName - tmux session name.
 * @param {number} commandId - Active command id.
 * @param {Object} patch - Partial delivery patch.
 */
function updateCommandDeliveryFields(sessionName, commandId, patch) {
  const queueFilePath = resolveQueueFilePath(sessionName);
  if (!existsSync(queueFilePath)) return;

  const queueData = JSON.parse(readFileSync(queueFilePath, 'utf8'));
  const targetCommand = queueData.commands.find(command => command.id === commandId);
  if (!targetCommand) return;

  if (!targetCommand.delivery) {
    targetCommand.delivery = {
      typed_at: null,
      enter_sent_at: null,
      enter_attempts: 0,
      submit_confirmed_at: null,
    };
  }

  targetCommand.delivery = {
    ...targetCommand.delivery,
    ...patch,
  };

  const temporaryFilePath = queueFilePath + '.tmp';
  writeFileSync(temporaryFilePath, JSON.stringify(queueData, null, 2), 'utf8');
  renameSync(temporaryFilePath, queueFilePath);
}

/**
 * Poll the queue file until the active command has confirmed_at set or status is 'done'.
 *
 * The UserPromptSubmit handler writes confirmed_at when it detects that the
 * submitted prompt came from the TUI driver. Alternatively, if the command
 * completes very quickly, its status may already be 'done' by the time we poll.
 *
 * @param {string} sessionName - tmux session name.
 * @param {number} commandId - The id of the command we expect to be confirmed.
 * @returns {boolean} True if confirmed, false on timeout.
 */
function verifySubmissionConfirmed(sessionName, commandId) {
  const deadlineMilliseconds = Date.now() + SUBMIT_VERIFICATION_TIMEOUT_MILLISECONDS;
  const queueFilePath = resolveQueueFilePath(sessionName);

  while (Date.now() < deadlineMilliseconds) {
    if (!existsSync(queueFilePath)) {
      // Queue file disappeared (cancelled or stale-archived) — treat as confirmed
      // because something external handled it.
      return true;
    }

    const queueData = JSON.parse(readFileSync(queueFilePath, 'utf8'));
    const targetCommand = queueData.commands.find(command => command.id === commandId);

    if (!targetCommand) {
      // Command disappeared from queue — treat as confirmed.
      return true;
    }

    if (targetCommand.confirmed_at || targetCommand.status === 'done') {
      return true;
    }

    sleepMilliseconds(SUBMIT_VERIFICATION_POLL_INTERVAL_MILLISECONDS);
  }

  return false;
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

  // --- Phase 0: Wait for fresh empty prompt ---
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

  // --- Phase 1: Type text and verify it appeared in the pane ---
  let textVerified = false;

  for (let textAttempt = 0; textAttempt <= MAXIMUM_TEXT_RETRIES; textAttempt++) {
    if (textAttempt > 0) {
      // If verification was a false negative and text is already present,
      // do NOT retype (prevents duplicate pasted commands).
      if (verifyTextAppearedInPane(sessionName, commandText)) {
        textVerified = true;
        break;
      }

      appendJsonlEntry({
        level: 'warn',
        source: 'type-command-deferred',
        message: `Text verification failed — retrying (attempt ${textAttempt + 1}/${MAXIMUM_TEXT_RETRIES + 1})`,
        session: sessionName,
        command: commandText,
        attempt: textAttempt + 1,
      }, sessionName);

      clearTuiInputField(sessionName);
      sleepMilliseconds(TEXT_VERIFICATION_POLL_INTERVAL_MILLISECONDS);
    }

    sendKeysToTmux(sessionName, commandText);

    if (verifyTextAppearedInPane(sessionName, commandText)) {
      textVerified = true;
      break;
    }
  }

  if (!textVerified) {
    appendJsonlEntry({
      level: 'error',
      source: 'type-command-deferred',
      message: `Text not visible in pane after ${MAXIMUM_TEXT_RETRIES + 1} attempts — aborting`,
      session: sessionName,
      command: commandText,
    }, sessionName);
    process.exit(3);
  }

  // --- Phase 2: Send Enter and verify submission was confirmed ---
  const activeCommand = readActiveCommandFromQueueFile(sessionName);
  const activeCommandId = activeCommand ? activeCommand.id : null;

  if (activeCommandId !== null) {
    updateCommandDeliveryFields(sessionName, activeCommandId, {
      typed_at: new Date().toISOString(),
    });
  }

  if (activeCommandId === null) {
    // No queue file or no active command — can't verify via queue, send Enter once optimistically.
    sendSpecialKeyToTmux(sessionName, 'Enter');

    appendJsonlEntry({
      level: 'info',
      source: 'type-command-deferred',
      message: 'Command typed, verified, and Enter sent (no queue to confirm against)',
      session: sessionName,
      command: commandText,
    }, sessionName);
    return;
  }

  let submissionConfirmed = false;

  for (let enterAttempt = 0; enterAttempt <= MAXIMUM_ENTER_RETRIES; enterAttempt++) {
    if (enterAttempt > 0) {
      appendJsonlEntry({
        level: 'warn',
        source: 'type-command-deferred',
        message: `Enter verification failed — retrying (attempt ${enterAttempt + 1}/${MAXIMUM_ENTER_RETRIES + 1})`,
        session: sessionName,
        command: commandText,
        attempt: enterAttempt + 1,
      }, sessionName);
    }

    sendSpecialKeyToTmux(sessionName, 'Enter');

    updateCommandDeliveryFields(sessionName, activeCommandId, {
      enter_sent_at: new Date().toISOString(),
      enter_attempts: enterAttempt + 1,
    });

    if (verifySubmissionConfirmed(sessionName, activeCommandId)) {
      submissionConfirmed = true;
      break;
    }
  }

  if (!submissionConfirmed) {
    appendJsonlEntry({
      level: 'error',
      source: 'type-command-deferred',
      message: `Submission not confirmed after ${MAXIMUM_ENTER_RETRIES + 1} Enter attempts — command may not have been accepted`,
      session: sessionName,
      command: commandText,
      command_id: activeCommandId,
    }, sessionName);
    process.exit(4);
  }

  updateCommandDeliveryFields(sessionName, activeCommandId, {
    submit_confirmed_at: new Date().toISOString(),
  });

  appendJsonlEntry({
    level: 'info',
    source: 'type-command-deferred',
    message: 'Command typed, verified, and submission confirmed (two-phase)',
    session: sessionName,
    command: commandText,
    command_id: activeCommandId,
  }, sessionName);
}

main().catch((caughtError) => {
  process.stderr.write(`Error: ${caughtError.message}\n`);
  process.exit(1);
});
