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

import { resolve } from 'node:path';
import { SKILL_ROOT } from '../../lib/paths.mjs';
import {
  readHookContext,
  retryWithBackoff,
  wakeAgentViaGateway,
  processQueueForHook,
  cleanupStaleQueueForSession,
  appendJsonlEntry,
} from '../../lib/index.mjs';

async function main() {
  const hookContext = readHookContext('event_session_start');
  if (!hookContext) process.exit(0);
  const { hookPayload, sessionName, resolvedAgent } = hookContext;

  const source = hookPayload.source;
  const promptFilePath = resolve(SKILL_ROOT, 'events', 'stop', 'prompt_stop.md');

  if (source === 'clear') {
    const queueResult = processQueueForHook(sessionName, 'SessionStart', 'clear', null);

    if (queueResult.action === 'awaits-mismatch') {
      appendJsonlEntry({ level: 'debug', source: 'event_session_start', message: 'Queue awaits-mismatch on clear — skipping wake', session: sessionName }, sessionName);
    }

    if (queueResult.action === 'queue-complete') {
      const messageContent = JSON.stringify(queueResult.summary, null, 2);

      await retryWithBackoff(
        () => wakeAgentViaGateway({
          openclawSessionId: resolvedAgent.openclaw_session_id,
          messageContent,
          promptFilePath,
          eventMetadata: {
            eventType: 'SessionStart',
            sessionName,
            timestamp: new Date().toISOString(),
          },
          sessionName,
        }),
        { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: 'wake-on-queue-complete', sessionName },
      );
    }

    process.exit(0);
  }

  if (source === 'startup') {
    const hadStaleQueue = cleanupStaleQueueForSession(sessionName);

    if (hadStaleQueue) {
      const messageContent = 'Previous session had unfinished queue. Stale queue archived.';

      await retryWithBackoff(
        () => wakeAgentViaGateway({
          openclawSessionId: resolvedAgent.openclaw_session_id,
          messageContent,
          promptFilePath,
          eventMetadata: {
            eventType: 'SessionStart',
            sessionName,
            timestamp: new Date().toISOString(),
          },
          sessionName,
        }),
        { maxAttempts: 3, initialDelayMilliseconds: 2000, operationLabel: 'wake-on-stale-archive', sessionName },
      );

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
  appendJsonlEntry({ level: 'debug', source: 'event_session_start', message: `Unhandled source value '${source}' — skipping`, session: sessionName }, sessionName);
  process.exit(0);
}

main().catch((caughtError) => {
  process.stderr.write(`[event_session_start] Error: ${caughtError.message}\n`);
  process.exit(1);
});
