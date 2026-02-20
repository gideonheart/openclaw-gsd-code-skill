/**
 * lib/paths.mjs — Shared path constants for all lib modules.
 *
 * Computes SKILL_ROOT once and exports it. All lib modules that need
 * filesystem paths relative to the skill root import from here instead
 * of computing dirname(dirname(fileURLToPath(import.meta.url))) independently.
 */

import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
