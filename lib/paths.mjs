/**
 * lib/paths.mjs — Shared path constants for all lib modules.
 *
 * Computes SKILL_ROOT once and exports it. All lib modules that need
 * filesystem paths relative to the skill root import from here instead
 * of computing dirname(dirname(fileURLToPath(import.meta.url))) independently.
 *
 * Also exports QUEUES_DIRECTORY and resolvePendingAnswerFilePath — the canonical
 * location for all queue-related path helpers shared across lib modules.
 */

import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));

export const QUEUES_DIRECTORY = resolve(SKILL_ROOT, 'logs', 'queues');

/**
 * Build the absolute path to the pending answer file for a session.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {string} Absolute path to the pending answer file.
 */
export function resolvePendingAnswerFilePath(sessionName) {
  return resolve(QUEUES_DIRECTORY, `pending-answer-${sessionName}.json`);
}
