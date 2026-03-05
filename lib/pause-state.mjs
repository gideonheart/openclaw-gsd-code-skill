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
 * - Exclusive lock: O_CREAT|O_EXCL mutex on .lock file serializes writes
 *   (pause-state.json is shared across ALL sessions, unlike per-session queue files)
 * - Atomic writes: tmp+rename inside the lock prevents partial reads
 * - Zero-noise reads: isSessionPaused does NOT log (runs on every hook invocation)
 */

import { resolve, dirname } from 'node:path';
import { readFileSync, writeFileSync, renameSync, mkdirSync, openSync, closeSync, unlinkSync, statSync, constants } from 'node:fs';
import { SKILL_ROOT } from './paths.mjs';
import { appendJsonlEntry } from './logger.mjs';

export const PAUSE_STATE_FILE_PATH = resolve(SKILL_ROOT, 'logs', 'pause-state.json');

const LOCK_FILE_PATH = PAUSE_STATE_FILE_PATH + '.lock';
const LOCK_MAX_RETRIES = 100;
const LOCK_RETRY_INTERVAL_MILLISECONDS = 10;
const STALE_LOCK_THRESHOLD_MILLISECONDS = 5000;

/**
 * Synchronous sleep using Atomics.wait (zero CPU spin, blocks for exact duration).
 *
 * @param {number} milliseconds - Duration to sleep.
 */
function sleepSyncMilliseconds(milliseconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
}

/**
 * Remove the lock file if it was left behind by a crashed process.
 * A lock older than STALE_LOCK_THRESHOLD_MILLISECONDS is considered stale.
 */
function removeStaleLockFileIfExpired() {
  try {
    const lockFileStats = statSync(LOCK_FILE_PATH);
    if (Date.now() - lockFileStats.mtimeMs > STALE_LOCK_THRESHOLD_MILLISECONDS) {
      try { unlinkSync(LOCK_FILE_PATH); } catch { /* already gone */ }
    }
  } catch {
    // Lock file doesn't exist — nothing to clean
  }
}

/**
 * Acquire an exclusive lock on pause-state.json using O_CREAT|O_EXCL.
 *
 * O_CREAT|O_EXCL is atomic per POSIX — the kernel creates the file only if it
 * does not exist, so exactly one caller wins even under concurrent access.
 * Retries with sleep. Detects and removes stale locks from crashed processes.
 *
 * @returns {boolean} True if lock acquired, false if all retries exhausted.
 */
function acquireExclusiveLockOnPauseStateFile() {
  for (let attempt = 0; attempt < LOCK_MAX_RETRIES; attempt++) {
    try {
      const lockFileDescriptor = openSync(LOCK_FILE_PATH, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY);
      closeSync(lockFileDescriptor);
      return true;
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
    }

    removeStaleLockFileIfExpired();
    sleepSyncMilliseconds(LOCK_RETRY_INTERVAL_MILLISECONDS);
  }
  return false;
}

/**
 * Release the exclusive lock by removing the lock file.
 */
function releaseExclusiveLockOnPauseStateFile() {
  try { unlinkSync(LOCK_FILE_PATH); } catch { /* already gone */ }
}

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
 * Acquires an exclusive file lock, then reads the existing state file (or
 * starts with empty object), updates the entry for the given session, and
 * writes atomically via tmp+rename. The lock serializes concurrent writes
 * from hooks of different sessions to the shared pause-state.json.
 *
 * Fail-open: if the lock cannot be acquired after max retries (~1s), the
 * write proceeds unlocked. Losing a pause-state update is annoying but
 * not dangerous — the next write will succeed.
 *
 * @param {string} sessionName - tmux session name.
 * @param {boolean} paused - Whether the session should be paused.
 */
export function setSessionPauseState(sessionName, paused) {
  const pauseStateDirectory = dirname(PAUSE_STATE_FILE_PATH);
  mkdirSync(pauseStateDirectory, { recursive: true });

  const lockAcquired = acquireExclusiveLockOnPauseStateFile();

  if (!lockAcquired) {
    appendJsonlEntry({
      level: 'warn',
      source: 'pause-state',
      message: 'Failed to acquire exclusive lock — proceeding without lock',
      session: sessionName,
    }, sessionName);
  }

  try {
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
  } finally {
    if (lockAcquired) {
      releaseExclusiveLockOnPauseStateFile();
    }
  }

  appendJsonlEntry({
    level: 'info',
    source: 'pause-state',
    message: 'Session pause state updated',
    session: sessionName,
    paused,
  }, sessionName);
}
