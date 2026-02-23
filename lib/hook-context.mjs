/**
 * lib/hook-context.mjs — Shared hook handler context reader.
 *
 * Order of operations matters:
 * 1. Check tmux (cheap, no stdin) — bail if not in tmux
 * 2. Check agent registry (cheap, JSON read) — bail if not a managed session
 * 3. Read stdin (may fail) — error is REAL if we got this far
 *
 * Non-managed sessions exit instantly with no side effects.
 * Managed sessions that fail get visible error logging.
 */

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolveAgentFromSession } from './agent-resolver.mjs';
import { appendJsonlEntry } from './logger.mjs';

/**
 * Read and validate the hook context from stdin + tmux environment.
 *
 * Checks tmux session and agent registry BEFORE reading stdin.
 * Non-managed sessions bail immediately (no stdin read, no logging).
 * Managed sessions log errors visibly when something goes wrong.
 *
 * @param {string} handlerSource - Handler name for log entries (e.g. 'event_stop').
 * @returns {{ hookPayload: Object, sessionName: string, resolvedAgent: Object }|null}
 *   The hook context object, or null if any guard check fails.
 */
export function readHookContext(handlerSource) {
  // 1. Resolve tmux session name — not in tmux means not a managed agent session
  if (!process.env.TMUX) return null;

  let sessionName;
  try {
    sessionName = execFileSync('tmux', ['display-message', '-p', '#S'], {
      encoding: 'utf8',
      timeout: 5000,
    }).trim();
  } catch {
    return null;
  }
  if (!sessionName) return null;

  // 2. Check agent registry — unknown sessions are not ours to handle
  const resolvedAgent = resolveAgentFromSession(sessionName);
  if (!resolvedAgent) return null;

  // --- From here, this IS a managed agent session. Failures are real problems. ---

  // 3. Read stdin payload — use fd 0 directly (not /dev/stdin device file which may ENXIO)
  let rawStdin;
  try {
    rawStdin = readFileSync(0, 'utf8').trim();
  } catch (stdinError) {
    appendJsonlEntry({
      level: 'error',
      source: handlerSource,
      message: `Stdin read failed: ${stdinError.code || stdinError.message}`,
      session: sessionName,
    }, sessionName);
    return null;
  }

  if (!rawStdin) {
    appendJsonlEntry({
      level: 'error',
      source: handlerSource,
      message: 'Empty stdin payload from Claude Code',
      session: sessionName,
    }, sessionName);
    return null;
  }

  // 4. Parse JSON payload
  let hookPayload;
  try {
    hookPayload = JSON.parse(rawStdin);
  } catch {
    appendJsonlEntry({
      level: 'error',
      source: handlerSource,
      message: 'Invalid JSON on stdin',
      session: sessionName,
      stdin_bytes: rawStdin.length,
    }, sessionName);
    return null;
  }

  return { hookPayload, sessionName, resolvedAgent };
}
