/**
 * events/session_start/event_session_start.mjs — SessionStart hook handler entry point.
 *
 * Invoked by Claude Code when a session starts. Handles two distinct scenarios:
 *
 * source:clear — /clear was issued; the session restarted. Advances the active
 *   queue to the next command if the active command was awaiting SessionStart+clear.
 *   If the queue is now complete, wakes the agent with a completion summary.
 *
 * source:startup — Claude Code launched fresh. Archives any stale queue left over
 *   from a previous interrupted session and notifies the agent.
 *
 * All other source values are silently ignored — no queue interaction needed.
 */

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  resolveAgentFromSession,
  wakeAgentViaGateway,
  processQueueForHook,
  cleanupStaleQueueForSession,
  appendJsonlEntry,
} from '../../lib/index.mjs';

async function main() {
  const rawStdin = readFileSync('/dev/stdin', 'utf8').trim();
  let hookPayload;
  try {
    hookPayload = JSON.parse(rawStdin);
  } catch {
    process.exit(0);
  }

  const sessionName = execFileSync('tmux', ['display-message', '-p', '#S'], { encoding: 'utf8' }).trim();

  if (!sessionName) {
    process.exit(0);
  }

  const resolvedAgent = resolveAgentFromSession(sessionName);

  if (!resolvedAgent) {
    process.exit(0);
  }

  const source = hookPayload.source;
  const promptFilePath = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'stop', 'prompt_stop.md');

  if (source === 'clear') {
    const queueResult = processQueueForHook(sessionName, 'SessionStart', 'clear', null);

    if (queueResult.action === 'queue-complete') {
      const messageContent = JSON.stringify(queueResult.summary, null, 2);

      wakeAgentViaGateway({
        openclawSessionId: resolvedAgent.openclaw_session_id,
        messageContent,
        promptFilePath,
        eventMetadata: {
          eventType: 'SessionStart',
          sessionName,
          timestamp: new Date().toISOString(),
        },
        sessionName,
      });
    }

    process.exit(0);
  }

  if (source === 'startup') {
    const hadStaleQueue = cleanupStaleQueueForSession(sessionName);

    if (hadStaleQueue) {
      const messageContent = 'Previous session had unfinished queue. Stale queue archived.';

      wakeAgentViaGateway({
        openclawSessionId: resolvedAgent.openclaw_session_id,
        messageContent,
        promptFilePath,
        eventMetadata: {
          eventType: 'SessionStart',
          sessionName,
          timestamp: new Date().toISOString(),
        },
        sessionName,
      });

      appendJsonlEntry({
        level: 'info',
        source: 'event_session_start',
        message: 'Stale queue archived on startup — agent notified',
        session: sessionName,
      }, sessionName);
    }

    process.exit(0);
  }

  // Any other source value — no queue interaction needed
  process.exit(0);
}

main().catch((caughtError) => {
  process.stderr.write(`[event_session_start] Error: ${caughtError.message}\n`);
  process.exit(1);
});
