/**
 * lib/index.mjs — Unified re-export entry point for all shared lib modules.
 *
 * Event handlers import everything they need from this single path:
 *   import { resolveAgentFromSession, wakeAgentViaGateway, ... } from '../lib/index.mjs';
 *
 * No logic, no side effects — re-exports only.
 */

export { formatQuestionsForAgent, saveQuestionMetadata, readQuestionMetadata, deleteQuestionMetadata, savePendingAnswer, readPendingAnswer, deletePendingAnswer, compareAnswerWithIntent } from './ask-user-question.mjs';
export { appendJsonlEntry } from './logger.mjs';
export { extractJsonField } from './json-extractor.mjs';
export { retryWithBackoff } from './retry.mjs';
export { resolveAgentFromSession } from './agent-resolver.mjs';
export { wakeAgentViaGateway, wakeAgentWithRetry, wakeAgentDetached } from './gateway.mjs';
export { typeCommandIntoTmuxSession, spawnDetachedDeferredTyping, sendKeysToTmux, sendSpecialKeyToTmux, sleepMilliseconds } from './tui-common.mjs';
export { processQueueForHook, cancelQueueForSession, cleanupStaleQueueForSession, writeQueueFileAtomically, resolveQueueFilePath, isPromptFromTuiDriver, isSessionInAskUserQuestionFlow } from './queue-processor.mjs';
export { readHookContext } from './hook-context.mjs';
