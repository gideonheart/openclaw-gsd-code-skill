/**
 * lib/logger.mjs — Atomic JSONL logging module.
 *
 * Provides appendJsonlEntry() for structured logging to per-session JSONL files.
 * Uses O_APPEND | O_CREAT | O_WRONLY for atomic appends on Linux (guaranteed
 * atomic for writes under PIPE_BUF / 4096 bytes). Matches the safety guarantee
 * of flock-based writes in hook-event-logger.sh for small JSONL records.
 *
 * The logger never throws — expected I/O errors are silently swallowed,
 * unexpected errors emit a single line to stderr for diagnostic visibility.
 */

import { mkdirSync, openSync, writeSync, closeSync, constants } from 'node:fs';
import { resolve } from 'node:path';
import { SKILL_ROOT } from './paths.mjs';

const LOG_DIRECTORY = resolve(SKILL_ROOT, 'logs');
const DEFAULT_LOG_FILE_PREFIX = 'lib-events';

/**
 * Append a single JSONL entry to a per-session log file.
 *
 * @param {Object} logEntry - Arbitrary fields to log as a JSON object.
 * @param {string|null} sessionName - Optional tmux session name. Determines
 *   the log file: `${sessionName}-raw-events.jsonl`. Falls back to
 *   `lib-events.jsonl` when null/undefined.
 */
export function appendJsonlEntry(logEntry, sessionName = null) {
  try {
    mkdirSync(LOG_DIRECTORY, { recursive: true });

    const entryTimestamp = new Date().toISOString();

    const record = { timestamp: entryTimestamp, ...logEntry };
    const serializedLine = JSON.stringify(record) + '\n';

    const logFilePrefix = sessionName || DEFAULT_LOG_FILE_PREFIX;
    const logFilePath = resolve(LOG_DIRECTORY, `${logFilePrefix}-raw-events.jsonl`);

    const fileDescriptor = openSync(
      logFilePath,
      constants.O_APPEND | constants.O_CREAT | constants.O_WRONLY,
    );
    writeSync(fileDescriptor, serializedLine);
    closeSync(fileDescriptor);
  } catch (loggingError) {
    // Swallow expected I/O errors silently — the logger must never crash the caller.
    // For unexpected errors, emit to stderr so the issue surfaces during debugging
    // without breaking the hook process.
    if (loggingError.code === 'ENOENT' || loggingError.code === 'ENOSPC') {
      return;
    }
    if (loggingError.code === undefined) {
      // Non-system errors (e.g. JSON.stringify failures) — also swallow silently.
      return;
    }
    process.stderr.write(`[gsd-code-skill logger] Unexpected error: ${loggingError.message}\n`);
  }
}
