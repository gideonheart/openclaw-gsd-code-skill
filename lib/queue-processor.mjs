/**
 * lib/queue-processor.mjs — Hook-agnostic queue read/advance/complete/cancel logic.
 *
 * Shared across all Phase 3 event handlers (Stop, SessionStart, UserPromptSubmit).
 * Reads the queue file for a session, matches the incoming hook against the active
 * command's awaits, and advances or completes the queue.
 *
 * Queue files live at: logs/queues/queue-{sessionName}.json
 * Stale files renamed to: logs/queues/queue-{sessionName}.stale.json
 *
 * Atomic writes: write to .tmp then rename (POSIX-atomic). No flock needed —
 * Claude Code fires events sequentially per session.
 */

import { writeFileSync, renameSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { SKILL_ROOT } from './paths.mjs';
import { typeCommandIntoTmuxSession } from './tui-common.mjs';
import { appendJsonlEntry } from './logger.mjs';

const QUEUES_DIRECTORY = resolve(SKILL_ROOT, 'logs', 'queues');

/**
 * Build the absolute path to the active queue file for a session.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {string} Absolute path to the queue file.
 */
export function resolveQueueFilePath(sessionName) {
  return resolve(QUEUES_DIRECTORY, `queue-${sessionName}.json`);
}

/**
 * Build the absolute path to the stale queue file for a session.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {string} Absolute path to the stale queue file.
 */
function resolveStaleQueueFilePath(sessionName) {
  return resolve(QUEUES_DIRECTORY, `queue-${sessionName}.stale.json`);
}

/**
 * Write queue data atomically: write to .tmp then rename over the target.
 *
 * @param {string} queueFilePath - Absolute path to the target queue file.
 * @param {Object} queueData - Queue data object to serialize as JSON.
 */
export function writeQueueFileAtomically(queueFilePath, queueData) {
  mkdirSync(dirname(queueFilePath), { recursive: true });
  const temporaryFilePath = queueFilePath + '.tmp';
  writeFileSync(temporaryFilePath, JSON.stringify(queueData, null, 2), 'utf8');
  renameSync(temporaryFilePath, queueFilePath);
}

/**
 * Build the queue-complete summary payload for agent wake-up.
 *
 * @param {Object} queueData - Full queue data object with commands array.
 * @returns {Object} JSON-serializable queue-complete payload.
 */
function buildQueueCompleteSummary(queueData) {
  const totalCount = queueData.commands.length;
  const completedCount = queueData.commands.filter(command => command.status === 'done').length;

  return {
    event: 'queue-complete',
    summary: `${completedCount}/${totalCount} commands completed`,
    commands: queueData.commands.map(command => ({
      id: command.id,
      command: command.command,
      status: command.status,
      result: command.result,
      completed_at: command.completed_at,
    })),
  };
}

/**
 * Process the queue for a session when a hook fires.
 *
 * Reads the queue file, finds the active command, checks if the incoming hook
 * matches its awaits, then advances or completes the queue.
 *
 * @param {string} sessionName - tmux session name.
 * @param {string} incomingHookName - The hook that just fired (e.g. "Stop", "SessionStart").
 * @param {string|null} incomingHookSubtype - Hook sub-type if applicable (e.g. "clear", "startup").
 * @param {string|null} lastAssistantMessage - The last assistant message to store as result.
 * @returns {Object} Action result:
 *   { action: 'no-queue' } — no queue file exists
 *   { action: 'no-active-command' } — queue exists but no active command
 *   { action: 'awaits-mismatch' } — hook does not match active command's awaits
 *   { action: 'advanced', command: string } — queue advanced to next command
 *   { action: 'queue-complete', summary: Object } — all commands done
 */
export function processQueueForHook(sessionName, incomingHookName, incomingHookSubtype, lastAssistantMessage) {
  const queueFilePath = resolveQueueFilePath(sessionName);

  if (!existsSync(queueFilePath)) {
    return { action: 'no-queue' };
  }

  const queueData = JSON.parse(readFileSync(queueFilePath, 'utf8'));
  const activeCommand = queueData.commands.find(command => command.status === 'active');

  if (!activeCommand) {
    return { action: 'no-active-command' };
  }

  const hookNameMatches = incomingHookName === activeCommand.awaits.hook;
  const subtypeMatches = activeCommand.awaits.sub === null || incomingHookSubtype === activeCommand.awaits.sub;

  if (!hookNameMatches || !subtypeMatches) {
    return { action: 'awaits-mismatch' };
  }

  // In-place mutation of the parsed JSON object. This is safe because Claude Code
  // fires events sequentially per session — no concurrent readers of queueData.
  // The mutated object is written atomically immediately after.
  activeCommand.status = 'done';
  activeCommand.result = lastAssistantMessage ?? null;
  activeCommand.completed_at = new Date().toISOString();

  const nextPendingCommand = queueData.commands.find(command => command.status === 'pending');

  if (nextPendingCommand) {
    nextPendingCommand.status = 'active';
    writeQueueFileAtomically(queueFilePath, queueData);

    appendJsonlEntry({
      level: 'info',
      source: 'processQueueForHook',
      message: 'Queue advanced to next command',
      session: sessionName,
      completed_command: activeCommand.command,
      next_command: nextPendingCommand.command,
    }, sessionName);

    typeCommandIntoTmuxSession(sessionName, nextPendingCommand.command);

    return { action: 'advanced', command: nextPendingCommand.command };
  }

  writeQueueFileAtomically(queueFilePath, queueData);

  appendJsonlEntry({
    level: 'info',
    source: 'processQueueForHook',
    message: 'Queue complete — all commands done',
    session: sessionName,
    total_commands: queueData.commands.length,
  }, sessionName);

  return { action: 'queue-complete', summary: buildQueueCompleteSummary(queueData) };
}

/**
 * Cancel the active queue for a session by renaming it to .stale.json.
 *
 * Called by the UserPromptSubmit handler when manual input is detected.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {false|Object} false if no queue exists, otherwise:
 *   { cancelled: true, completedCount: number, totalCount: number, remainingCommands: Array }
 */
export function cancelQueueForSession(sessionName) {
  const queueFilePath = resolveQueueFilePath(sessionName);

  if (!existsSync(queueFilePath)) {
    return false;
  }

  const queueData = JSON.parse(readFileSync(queueFilePath, 'utf8'));
  const staleQueueFilePath = resolveStaleQueueFilePath(sessionName);

  renameSync(queueFilePath, staleQueueFilePath);

  const completedCount = queueData.commands.filter(command => command.status === 'done').length;
  const totalCount = queueData.commands.length;
  const remainingCommands = queueData.commands.filter(
    command => command.status === 'pending' || command.status === 'active',
  );

  appendJsonlEntry({
    level: 'info',
    source: 'cancelQueueForSession',
    message: 'Queue cancelled by manual input',
    session: sessionName,
    completed_count: completedCount,
    total_count: totalCount,
    remaining_count: remainingCommands.length,
  }, sessionName);

  return {
    cancelled: true,
    completedCount,
    totalCount,
    remainingCommands,
  };
}

/**
 * Check whether a submitted prompt matches the currently active queue command.
 *
 * Called by the UserPromptSubmit handler to detect whether the "user input" is
 * actually the TUI driver typing an automated command. Claude Code fires
 * UserPromptSubmit for ALL terminal input including tmux send-keys — so when
 * tui-driver.mjs types a command, this hook fires even though no human typed it.
 *
 * Comparison trims both sides because Claude Code appends a trailing space to the
 * prompt after Tab autocomplete (e.g. "/gsd:discuss-phase 18 " vs "/gsd:discuss-phase 18").
 *
 * @param {string} sessionName - tmux session name.
 * @param {string} submittedPrompt - The prompt text from the UserPromptSubmit payload.
 * @returns {boolean} true if the prompt matches the active queue command (TUI driver input).
 */
export function isPromptFromTuiDriver(sessionName, submittedPrompt) {
  const queueFilePath = resolveQueueFilePath(sessionName);

  if (!existsSync(queueFilePath)) {
    return false;
  }

  const queueData = JSON.parse(readFileSync(queueFilePath, 'utf8'));
  const activeCommand = queueData.commands.find(command => command.status === 'active');

  if (!activeCommand) {
    return false;
  }

  return submittedPrompt.trim() === activeCommand.command.trim();
}

/**
 * Clean up a stale queue left from a previous session by renaming it to .stale.json.
 *
 * Called by the SessionStart handler with source "startup" to archive any queue
 * that was active when the session was last interrupted.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {boolean} false if no queue exists, true if queue was renamed to stale.
 */
export function cleanupStaleQueueForSession(sessionName) {
  const queueFilePath = resolveQueueFilePath(sessionName);

  if (!existsSync(queueFilePath)) {
    return false;
  }

  const staleQueueFilePath = resolveStaleQueueFilePath(sessionName);
  renameSync(queueFilePath, staleQueueFilePath);

  appendJsonlEntry({
    level: 'info',
    source: 'cleanupStaleQueueForSession',
    message: 'Stale queue archived on session startup',
    session: sessionName,
  }, sessionName);

  return true;
}
