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
  wakeAgentWithRetry,
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
  const handlerTrace = { decisionPath: null, outcome: {} };

  try {
    if (source === 'clear') {
      const queueResult = processQueueForHook(sessionName, 'SessionStart', 'clear', null);

      if (queueResult.action === 'awaits-mismatch') {
        handlerTrace.decisionPath = 'clear-awaits-mismatch';
        return;
      }

      if (queueResult.action === 'queue-complete') {
        const messageContent = JSON.stringify(queueResult.summary, null, 2);

        await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'SessionStart', sessionName });

        handlerTrace.decisionPath = 'clear-queue-complete';
        handlerTrace.outcome = { summary: queueResult.summary };
        return;
      }

      if (queueResult.action === 'advanced') {
        handlerTrace.decisionPath = 'clear-queue-advanced';
        return;
      }

      handlerTrace.decisionPath = 'clear-other';
      handlerTrace.outcome = { queue_action: queueResult.action };
      return;
    }

    if (source === 'startup') {
      const hadStaleQueue = cleanupStaleQueueForSession(sessionName);

      if (hadStaleQueue) {
        const messageContent = 'Previous session had unfinished queue. Stale queue archived.';

        await wakeAgentWithRetry({ resolvedAgent, messageContent, promptFilePath, eventType: 'SessionStart', sessionName });

        handlerTrace.decisionPath = 'startup-stale-queue';
        handlerTrace.outcome = { had_stale_queue: true };
        return;
      }

      handlerTrace.decisionPath = 'startup-clean';
      return;
    }

    // Any other source value — no queue interaction needed
    handlerTrace.decisionPath = 'unhandled-source';
    handlerTrace.outcome = { source };
  } finally {
    appendJsonlEntry({
      level: 'info',
      source: 'event_session_start',
      message: `Handler complete: ${handlerTrace.decisionPath}`,
      session: sessionName,
      hook_payload: hookPayload,
      decision_path: handlerTrace.decisionPath,
      outcome: handlerTrace.outcome,
    }, sessionName);
  }
}

main().catch((caughtError) => {
  process.stderr.write(`[event_session_start] Error: ${caughtError.message}\n`);
  process.exit(1);
});
