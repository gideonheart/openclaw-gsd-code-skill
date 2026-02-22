/**
 * events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs — AskUserQuestion PreToolUse domain handler.
 *
 * Thin plumbing handler — all domain logic delegated to lib/ask-user-question.mjs.
 * Receives the question from Claude Code, saves question metadata for the TUI driver,
 * formats the question for the OpenClaw agent, and wakes the agent via gateway.
 *
 * Follows the "handlers are thin plumbing, ~5-10 lines of logic" principle from CONTEXT.md.
 * All domain knowledge (formatting, file I/O) lives in lib/ask-user-question.mjs.
 */

import { resolve } from 'node:path';
import { SKILL_ROOT } from '../../../lib/paths.mjs';
import {
  formatQuestionsForAgent,
  saveQuestionMetadata,
  wakeAgentWithRetry,
  appendJsonlEntry,
} from '../../../lib/index.mjs';

/**
 * Handle an AskUserQuestion PreToolUse hook event.
 *
 * Saves question metadata to disk (for TUI driver correlation), formats the questions
 * into a readable agent prompt, and wakes the OpenClaw agent via gateway — fire-and-forget.
 *
 * @param {Object} params
 * @param {Object} params.hookPayload - The parsed PreToolUse hook payload.
 * @param {string} params.sessionName - The tmux session name.
 * @param {Object} params.resolvedAgent - The resolved agent object with openclaw_session_id.
 * @returns {Promise<void>}
 */
export async function handleAskUserQuestion({ hookPayload, sessionName, resolvedAgent }) {
  const toolInput = hookPayload.tool_input;
  const toolUseId = hookPayload.tool_use_id;

  saveQuestionMetadata(sessionName, toolInput, toolUseId);

  const formattedQuestions = formatQuestionsForAgent(toolInput, sessionName);

  const promptFilePath = resolve(SKILL_ROOT, 'events', 'pre_tool_use', 'ask_user_question', 'prompt_ask_user_question.md');

  await wakeAgentWithRetry({ resolvedAgent, messageContent: formattedQuestions, promptFilePath, eventType: 'PreToolUse', sessionName });

  appendJsonlEntry({
    level: 'info',
    source: 'handle_ask_user_question',
    message: 'Agent woken via gateway for AskUserQuestion PreToolUse event',
    session: sessionName,
    tool_use_id: toolUseId,
    question_count: toolInput.questions.length,
  }, sessionName);
}
