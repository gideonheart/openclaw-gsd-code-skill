/**
 * events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs — AskUserQuestion PostToolUse domain handler.
 *
 * Thin plumbing handler — all domain logic delegated to lib/ask-user-question.mjs.
 * Reads the pending answer file (TUI driver's intent), compares with tool_response.answers
 * (what Claude Code recorded), and handles 3 outcomes:
 *
 *   1. Match (95%): silent verification + cleanup — zero agent tokens burned.
 *   2. Mismatch (5%): wake agent with specific mismatch details + cleanup.
 *   3. Missing file: log warning and self-heal — no crash, no block.
 *
 * Both question-{session}.json and pending-answer-{session}.json are deleted
 * on ALL paths (match, mismatch, missing file) to keep logs/queues clean.
 *
 * Follows the "handlers are thin plumbing" principle from CONTEXT.md.
 */

import { resolve } from 'node:path';
import { SKILL_ROOT } from '../../../lib/paths.mjs';
import {
  readPendingAnswer,
  deletePendingAnswer,
  deleteQuestionMetadata,
  compareAnswerWithIntent,
  wakeAgentWithRetry,
  appendJsonlEntry,
} from '../../../lib/index.mjs';

/**
 * Handle an AskUserQuestion PostToolUse hook event.
 *
 * Compares the TUI driver's intended answer (from pending-answer file) with what
 * Claude Code recorded (from tool_response.answers). Deletes both metadata files
 * on every path. Wakes the OpenClaw agent only on mismatch.
 *
 * @param {Object} params
 * @param {Object} params.hookPayload - The parsed PostToolUse hook payload.
 * @param {string} params.sessionName - The tmux session name.
 * @param {Object} params.resolvedAgent - The resolved agent object with openclaw_session_id.
 * @returns {Promise<void>}
 */
export async function handlePostAskUserQuestion({ hookPayload, sessionName, resolvedAgent }) {
  const pendingAnswer = readPendingAnswer(sessionName);

  if (!pendingAnswer) {
    appendJsonlEntry({
      level: 'warn',
      source: 'handle_post_ask_user_question',
      message: `No pending-answer file for session ${sessionName} — TUI driver may not have been called or file was already cleaned up`,
      session: sessionName,
    }, sessionName);

    // Cleanup question metadata in case it was left behind
    deleteQuestionMetadata(sessionName);
    return;
  }

  const toolResponse = hookPayload.tool_response;
  const toolInput = hookPayload.tool_input;

  if (!toolResponse || !toolResponse.answers) {
    appendJsonlEntry({
      level: 'warn',
      source: 'handle_post_ask_user_question',
      message: 'PostToolUse payload missing tool_response.answers',
      session: sessionName,
      tool_use_id: pendingAnswer.tool_use_id,
    }, sessionName);

    deletePendingAnswer(sessionName);
    deleteQuestionMetadata(sessionName);
    return;
  }

  const comparisonResult = compareAnswerWithIntent(pendingAnswer, toolResponse, toolInput);

  if (comparisonResult.matched) {
    appendJsonlEntry({
      level: 'info',
      source: 'handle_post_ask_user_question',
      message: 'AskUserQuestion verified — answer matches intent',
      session: sessionName,
      tool_use_id: pendingAnswer.tool_use_id,
    }, sessionName);

    deletePendingAnswer(sessionName);
    deleteQuestionMetadata(sessionName);
    return;
  }

  // Mismatch path — wake agent with specific correction details
  const mismatchMessageContent = buildMismatchMessageContent({
    sessionName,
    pendingAnswer,
    toolResponse,
    toolInput,
    comparisonResult,
  });

  const promptFilePath = resolve(SKILL_ROOT, 'events', 'post_tool_use', 'ask_user_question', 'prompt_post_ask_mismatch.md');

  await wakeAgentWithRetry({
    resolvedAgent,
    messageContent: mismatchMessageContent,
    promptFilePath,
    eventType: 'PostToolUse',
    sessionName,
  });

  appendJsonlEntry({
    level: 'warn',
    source: 'handle_post_ask_user_question',
    message: 'AskUserQuestion mismatch detected',
    session: sessionName,
    tool_use_id: pendingAnswer.tool_use_id,
    reason: comparisonResult.reason,
  }, sessionName);

  deletePendingAnswer(sessionName);
  deleteQuestionMetadata(sessionName);
}

/**
 * Build the mismatch notification message content for the OpenClaw agent.
 *
 * Formats intended vs actual answer details along with the original question
 * context so the agent has full information to assess the correction needed.
 *
 * @param {Object} params
 * @param {string} params.sessionName - tmux session name.
 * @param {Object} params.pendingAnswer - The pending answer object (intent from TUI driver).
 * @param {Object} params.toolResponse - The tool_response from the PostToolUse payload.
 * @param {Object} params.toolInput - The tool_input from the PostToolUse payload (has questions array).
 * @param {Object} params.comparisonResult - Result from compareAnswerWithIntent ({ matched: false, reason }).
 * @returns {string} Formatted mismatch message for gateway delivery.
 */
function buildMismatchMessageContent({ sessionName, pendingAnswer, toolResponse, toolInput, comparisonResult }) {
  const questionContextLines = formatQuestionsForMismatchContext(toolInput);

  return [
    '## AskUserQuestion Verification — MISMATCH',
    '',
    `**Session:** ${sessionName}`,
    `**tool_use_id:** ${pendingAnswer.tool_use_id}`,
    '',
    `**You intended:** action="${pendingAnswer.action}", answers=${JSON.stringify(pendingAnswer.answers)}`,
    `**Claude Code received:** answers=${JSON.stringify(toolResponse.answers)}`,
    `**Reason:** ${comparisonResult.reason}`,
    '',
    '### Original Question',
    questionContextLines,
  ].join('\n');
}

/**
 * Format tool_input questions into a readable context block for the mismatch message.
 *
 * @param {Object} toolInput - The tool_input from the PostToolUse payload.
 * @returns {string} Formatted question context string.
 */
function formatQuestionsForMismatchContext(toolInput) {
  if (!toolInput || !Array.isArray(toolInput.questions)) {
    return '(question data not available)';
  }

  return toolInput.questions.map((questionItem, questionIndex) => {
    const questionNumber = questionIndex + 1;
    const headerText = questionItem.header || `Question ${questionNumber}`;
    const selectionMode = questionItem.multiSelect ? 'multi-select' : 'single-select';

    const optionLines = questionItem.options.map((option, optionIndex) => {
      return `  ${optionIndex}. ${option.label} — ${option.description}`;
    });

    return [
      `**Question ${questionNumber}: ${headerText} (${selectionMode})**`,
      questionItem.question,
      ...optionLines,
    ].join('\n');
  }).join('\n\n');
}
