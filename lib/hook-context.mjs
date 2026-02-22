/**
 * lib/hook-context.mjs — Shared hook handler context reader.
 *
 * Extracts the boilerplate shared by all event handlers: read stdin,
 * parse JSON payload, resolve tmux session name, resolve agent from registry.
 * Returns null (with debug log) if any step fails — caller exits 0.
 */

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolveAgentFromSession } from './agent-resolver.mjs';
import { appendJsonlEntry } from './logger.mjs';

/**
 * Read and validate the hook context from stdin + tmux environment.
 *
 * Reads raw stdin, parses as JSON, resolves the tmux session name via
 * `tmux display-message`, and resolves the agent from the session registry.
 * Logs a debug JSONL entry for each guard failure and returns null.
 *
 * @param {string} handlerSource - Handler name for log entries (e.g. 'event_stop').
 * @returns {{ hookPayload: Object, sessionName: string, resolvedAgent: Object }|null}
 *   The hook context object, or null if any guard check fails.
 */
export function readHookContext(handlerSource) {
  let rawStdin;
  try {
    rawStdin = readFileSync('/dev/stdin', 'utf8').trim();
  } catch {
    // ENXIO: stdin not connected (e.g. Stop hook without piped input)
    return null;
  }

  let hookPayload;
  try {
    hookPayload = JSON.parse(rawStdin);
  } catch {
    appendJsonlEntry({
      level: 'debug',
      source: handlerSource,
      message: 'Invalid JSON on stdin — skipping',
    });
    return null;
  }

  const sessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();

  if (!sessionName) {
    appendJsonlEntry({
      level: 'debug',
      source: handlerSource,
      message: 'No tmux session name — skipping',
    });
    return null;
  }

  const resolvedAgent = resolveAgentFromSession(sessionName);

  if (!resolvedAgent) {
    appendJsonlEntry({
      level: 'debug',
      source: handlerSource,
      message: 'Session not in agent registry — skipping',
      session: sessionName,
    });
    return null;
  }

  return { hookPayload, sessionName, resolvedAgent };
}
