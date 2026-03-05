/**
 * lib/pause-state.mjs — Per-session pause state management.
 *
 * Provides a file-backed pause flag that disables auto-drive behavior
 * (TUI typing and gateway wakes) while keeping hook event logging intact.
 *
 * State is stored in logs/pause-state.json as a JSON object mapping
 * session names to { paused: boolean, updatedAt: string }.
 *
 * Design choices:
 * - Fail-open: missing or corrupt state file = unpaused (never blocks hooks)
 * - Atomic writes: tmp+rename pattern prevents corruption from concurrent hooks
 * - Zero-noise reads: isSessionPaused does NOT log (runs on every hook invocation)
 */

import { resolve, dirname } from 'node:path';
import { readFileSync, writeFileSync, renameSync, mkdirSync } from 'node:fs';
import { SKILL_ROOT } from './paths.mjs';
import { appendJsonlEntry } from './logger.mjs';

export const PAUSE_STATE_FILE_PATH = resolve(SKILL_ROOT, 'logs', 'pause-state.json');

/**
 * Check whether a session is currently paused.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {boolean} True if the session is paused, false otherwise.
 *   Returns false (unpaused) if the file does not exist, the session has
 *   no entry, or the file cannot be read/parsed (fail-open).
 */
export function isSessionPaused(sessionName) {
  try {
    const rawContent = readFileSync(PAUSE_STATE_FILE_PATH, 'utf8');
    const pauseStateMap = JSON.parse(rawContent);
    return pauseStateMap[sessionName]?.paused === true;
  } catch {
    return false;
  }
}

/**
 * Set the pause state for a session.
 *
 * Reads the existing state file (or starts with empty object), updates the
 * entry for the given session, and writes atomically via tmp+rename.
 *
 * @param {string} sessionName - tmux session name.
 * @param {boolean} paused - Whether the session should be paused.
 */
export function setSessionPauseState(sessionName, paused) {
  const pauseStateDirectory = dirname(PAUSE_STATE_FILE_PATH);
  mkdirSync(pauseStateDirectory, { recursive: true });

  let pauseStateMap = {};
  try {
    const rawContent = readFileSync(PAUSE_STATE_FILE_PATH, 'utf8');
    pauseStateMap = JSON.parse(rawContent);
  } catch {
    // File missing or corrupt — start fresh
  }

  pauseStateMap[sessionName] = {
    paused,
    updatedAt: new Date().toISOString(),
  };

  const temporaryFilePath = PAUSE_STATE_FILE_PATH + '.tmp';
  writeFileSync(temporaryFilePath, JSON.stringify(pauseStateMap, null, 2), 'utf8');
  renameSync(temporaryFilePath, PAUSE_STATE_FILE_PATH);

  appendJsonlEntry({
    level: 'info',
    source: 'pause-state',
    message: 'Session pause state updated',
    session: sessionName,
    paused,
  }, sessionName);
}
