/**
 * events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs — AskUserQuestion PreToolUse domain handler.
 *
 * Thin plumbing handler — all domain logic delegated to lib/ask-user-question.mjs.
 * Receives the question from Claude Code, saves question metadata for the TUI driver,
 * formats the question for the OpenClaw agent, and wakes the agent via gateway.
 *
 * Uses wakeAgentDetached (fire-and-forget, detached process) instead of wakeAgentWithRetry.
 * Reason: the PreToolUse hook blocks Claude Code while it runs. Claude Code will not render
 * the AskUserQuestion TUI until the hook process exits. If the agent responds and calls
 * tui-driver-ask.mjs before the hook exits, the TUI is not yet visible in the pane, causing
 * keystroke polling to time out. wakeAgentDetached spawns openclaw as a detached child and
 * returns immediately, letting the hook exit and the TUI render before the agent acts.
 *
 * Follows the "handlers are thin plumbing, ~5-10 lines of logic" principle from CONTEXT.md.
 * All domain knowledge (formatting, file I/O) lives in lib/ask-user-question.mjs.
 */

import { resolve } from 'node:path';
import { SKILL_ROOT } from '../../../lib/paths.mjs';
import {
  formatQuestionsForAgent,
  saveQuestionMetadata,
  wakeAgentDetached,
} from '../../../lib/index.mjs';

/**
 * Handle an AskUserQuestion PreToolUse hook event.
 *
 * Saves question metadata to disk (for TUI driver correlation), formats the questions
 * into a readable agent prompt, and wakes the OpenClaw agent via detached gateway process.
 * Returns immediately after spawning the detached wake — does not await delivery.
 *
 * @param {Object} params
 * @param {Object} params.hookPayload - The parsed PreToolUse hook payload.
 * @param {string} params.sessionName - The tmux session name.
 * @param {Object} params.resolvedAgent - The resolved agent object with openclaw_session_id.
 * @returns {{decisionPath: string, outcome: Object}}
 */
export function handleAskUserQuestion({ hookPayload, sessionName, resolvedAgent }) {
  const toolInput = hookPayload.tool_input;
  const toolUseId = hookPayload.tool_use_id;

  saveQuestionMetadata(sessionName, toolInput, toolUseId);

  const formattedQuestions = formatQuestionsForAgent(toolInput, sessionName);

  const promptFilePath = resolve(SKILL_ROOT, 'events', 'pre_tool_use', 'ask_user_question', 'prompt_ask_user_question.md');

  wakeAgentDetached({ resolvedAgent, messageContent: formattedQuestions, promptFilePath, eventType: 'PreToolUse', sessionName });

  return {
    decisionPath: 'ask-user-question',
    outcome: {
      tool_use_id: toolUseId,
      question_count: toolInput.questions.length,
    },
  };
}
