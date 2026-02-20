/**
 * lib/retry.mjs — Exponential backoff retry wrapper.
 *
 * Provides retryWithBackoff() that wraps any async function with configurable
 * exponential backoff retry logic. Logs each retry attempt as N/M to JSONL
 * for visibility into retry state.
 *
 * Default: 10 attempts, starting at 5s delay, doubling each time.
 * Delay sequence: 5s, 10s, 20s, 40s, 80s, 160s, 320s, 640s, 1280s, 2560s
 */

import { appendJsonlEntry } from './logger.mjs';

/**
 * Retry an async function with exponential backoff.
 *
 * @param {Function} asyncFunction - The async function to retry.
 * @param {Object} options - Configuration options.
 * @param {number} options.maxAttempts - Maximum number of attempts (default: 10).
 * @param {number} options.initialDelayMilliseconds - Base delay in ms (default: 5000).
 * @param {string} options.operationLabel - Human-readable label for log messages (default: 'operation').
 * @param {string|null} options.sessionName - Optional session name for JSONL log routing.
 * @returns {Promise<*>} The result of the async function on success.
 * @throws {Error} The last error if all attempts fail.
 */
export async function retryWithBackoff(asyncFunction, options = {}) {
  if (typeof asyncFunction !== 'function') {
    throw new TypeError('retryWithBackoff requires a function as the first argument');
  }

  const {
    maxAttempts = 10,
    initialDelayMilliseconds = 5000,
    operationLabel = 'operation',
    sessionName = null,
  } = options;

  for (let attemptNumber = 1; attemptNumber <= maxAttempts; attemptNumber++) {
    try {
      const result = await asyncFunction();
      return result;
    } catch (caughtError) {
      if (attemptNumber === maxAttempts) {
        throw caughtError;
      }

      const delayMilliseconds = initialDelayMilliseconds * Math.pow(2, attemptNumber - 1);

      appendJsonlEntry(
        {
          level: 'warn',
          source: 'retryWithBackoff',
          message: `Retry ${attemptNumber}/${maxAttempts} for ${operationLabel}`,
          delay_ms: delayMilliseconds,
          error: caughtError.message,
        },
        sessionName,
      );

      await new Promise((resolve) => setTimeout(resolve, delayMilliseconds));
    }
  }
}
