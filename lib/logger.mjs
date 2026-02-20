/**
 * lib/logger.mjs — Atomic JSONL logging module.
 *
 * Provides appendJsonlEntry() for structured logging to per-session JSONL files.
 * Uses O_APPEND | O_CREAT | O_WRONLY for atomic appends on Linux (guaranteed
 * atomic for writes under PIPE_BUF / 4096 bytes). Matches the safety guarantee
 * of flock-based writes in hook-event-logger.sh for small JSONL records.
 *
 * The logger never throws — all errors are silently swallowed to prevent
 * crashing the caller (matches hook-event-logger.sh's `|| true` pattern).
 */

import { mkdirSync, openSync, writeSync, closeSync, constants } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
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
  } catch {
    // Silently swallow all errors — the logger must never crash the caller.
  }
}
