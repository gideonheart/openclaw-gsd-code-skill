/**
 * lib/ask-user-question.mjs — AskUserQuestion domain module.
 *
 * Single source of truth for all AskUserQuestion domain knowledge:
 * question metadata file I/O, pending answer file I/O, agent prompt
 * formatting, and answer verification comparison.
 *
 * Used by:
 *   - events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs
 *   - events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs
 *   - bin/tui-driver-ask.mjs
 *
 * File I/O uses atomic tmp+rename writes (POSIX-atomic). No flock needed —
 * AskUserQuestion is blocking: Claude Code waits for the answer before
 * the next question can fire.
 *
 * Files live at:
 *   logs/queues/question-{session}.json        — PreToolUse creates, PostToolUse deletes
 *   logs/queues/pending-answer-{session}.json  — TUI driver creates, PostToolUse deletes
 */

import { writeFileSync, renameSync, readFileSync, unlinkSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { SKILL_ROOT } from './paths.mjs';
import { appendJsonlEntry } from './logger.mjs';

const QUEUES_DIRECTORY = resolve(SKILL_ROOT, 'logs', 'queues');

/**
 * Build the absolute path to the question metadata file for a session.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {string} Absolute path to the question file.
 */
function resolveQuestionFilePath(sessionName) {
  return resolve(QUEUES_DIRECTORY, `question-${sessionName}.json`);
}

/**
 * Build the absolute path to the pending answer file for a session.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {string} Absolute path to the pending answer file.
 */
function resolvePendingAnswerFilePath(sessionName) {
  return resolve(QUEUES_DIRECTORY, `pending-answer-${sessionName}.json`);
}

/**
 * Write data atomically: write to .tmp then rename over the target file.
 * Creates parent directories as needed.
 *
 * @param {string} filePath - Absolute path to the target file.
 * @param {Object} data - Data object to serialize as JSON.
 */
function writeFileAtomically(filePath, data) {
  mkdirSync(dirname(filePath), { recursive: true });
  const temporaryFilePath = filePath + '.tmp';
  writeFileSync(temporaryFilePath, JSON.stringify(data, null, 2), 'utf8');
  renameSync(temporaryFilePath, filePath);
}

/**
 * Format AskUserQuestion tool_input into a readable markdown string for the OpenClaw agent.
 *
 * Produces the exact gateway message format from CONTEXT.md — the message the OpenClaw
 * agent receives when Claude Code asks a question. Includes question headers, numbered
 * options with descriptions, and the "How to answer" instruction block with CLI call.
 *
 * @param {Object} toolInput - The tool_input object from the PreToolUse hook payload.
 *   Expected shape: { questions: Array<{ question: string, header?: string, multiSelect: boolean, options: Array<{ label: string, description: string }> }> }
 * @param {string} sessionName - tmux session name, used in session line and CLI call.
 * @returns {string} Markdown-formatted message for the OpenClaw agent.
 */
export function formatQuestionsForAgent(toolInput, sessionName) {
  const questionLines = toolInput.questions.map((questionItem, questionIndex) => {
    const questionNumber = questionIndex + 1;
    const headerText = questionItem.header || `Question ${questionNumber}`;
    const selectionMode = questionItem.multiSelect ? 'multi-select' : 'single-select';

    const optionLines = questionItem.options.map((option, optionIndex) => {
      return `  ${optionIndex}. ${option.label} — ${option.description}`;
    });

    return [
      `### Question ${questionNumber}: ${headerText} (${selectionMode})`,
      ...optionLines,
    ].join('\n');
  });

  const tuiDriverPath = resolve(SKILL_ROOT, 'bin', 'tui-driver-ask.mjs');

  return [
    '## AskUserQuestion from Claude Code',
    '',
    `**Session:** ${sessionName}`,
    '',
    questionLines.join('\n\n'),
    '',
    '## How to answer',
    'Read each question. Read the option descriptions. Cross-reference with your project context',
    '(STATE.md, ROADMAP.md, CONTEXT.md — already in your conversation).',
    '',
    'For EVERY question, decide:',
    '- Does one option clearly align with project direction? -> select it',
    '- Is an option close but missing nuance? -> use "Type something" to give the right answer',
    '  with your reasoning',
    '- Does Claude Code\'s recommended option (first) actually make sense? -> verify against',
    '  ROADMAP.md and STATE.md before accepting. Claude Code can hallucinate.',
    '- Is the question itself wrong (contradicts project state, wrong phase)? -> use "Chat about',
    '  this" to redirect Claude Code',
    '- For multi-select: which items are relevant to current phase? Select only what matters.',
    '',
    'Answer format per question:',
    '  Pick option:    { "action": "select", "optionIndex": N }',
    '  Type answer:    { "action": "type", "text": "your reasoned answer" }',
    '  Multi-select:   { "action": "multi-select", "selectedIndices": [0, 2] }',
    '  Redirect:       { "action": "chat", "text": "explanation of what\'s wrong" }',
    '',
    'Call:',
    `  node ${tuiDriverPath} --session ${sessionName} '<json array>'`,
  ].join('\n');
}

/**
 * Save question metadata to logs/queues/question-{session}.json.
 *
 * Called by the PreToolUse handler immediately after receiving an AskUserQuestion
 * tool call. The TUI driver reads this file to know option counts and labels.
 *
 * @param {string} sessionName - tmux session name.
 * @param {Object} toolInput - The tool_input from the hook payload (contains questions array).
 * @param {string} toolUseId - The tool_use_id from the hook payload for correlation.
 */
export function saveQuestionMetadata(sessionName, toolInput, toolUseId) {
  const questionFilePath = resolveQuestionFilePath(sessionName);

  const questionMetadata = {
    tool_use_id: toolUseId,
    saved_at: new Date().toISOString(),
    session: sessionName,
    questions: toolInput.questions,
  };

  writeFileAtomically(questionFilePath, questionMetadata);

  appendJsonlEntry({
    level: 'info',
    source: 'saveQuestionMetadata',
    message: 'Question metadata saved',
    session: sessionName,
    tool_use_id: toolUseId,
    question_count: toolInput.questions.length,
  }, sessionName);
}

/**
 * Read question metadata from logs/queues/question-{session}.json.
 *
 * Called by the TUI driver before typing keystrokes, to resolve option counts
 * and labels from the question payload saved by the PreToolUse handler.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {Object|null} Parsed question metadata object, or null if file does not exist.
 */
export function readQuestionMetadata(sessionName) {
  const questionFilePath = resolveQuestionFilePath(sessionName);

  try {
    return JSON.parse(readFileSync(questionFilePath, 'utf8'));
  } catch (readError) {
    if (readError.code === 'ENOENT') {
      return null;
    }
    throw readError;
  }
}

/**
 * Delete the question metadata file for a session.
 *
 * Called by the PostToolUse handler after verification is complete (match or mismatch).
 * Silently ignores ENOENT — file may have already been cleaned up.
 *
 * @param {string} sessionName - tmux session name.
 */
export function deleteQuestionMetadata(sessionName) {
  const questionFilePath = resolveQuestionFilePath(sessionName);

  try {
    unlinkSync(questionFilePath);
  } catch (deleteError) {
    if (deleteError.code !== 'ENOENT') {
      throw deleteError;
    }
  }

  appendJsonlEntry({
    level: 'debug',
    source: 'deleteQuestionMetadata',
    message: 'Question metadata deleted',
    session: sessionName,
  }, sessionName);
}

/**
 * Save the TUI driver's intended answer to logs/queues/pending-answer-{session}.json.
 *
 * Called by the TUI driver BEFORE typing keystrokes. Records what the driver intends
 * to submit, so the PostToolUse handler can verify the answer was received correctly.
 *
 * @param {string} sessionName - tmux session name.
 * @param {Object} answers - The agent's intended answers keyed by question index (e.g. { "0": "Option A" }).
 * @param {string} action - The action type string (select, type, multi-select, chat).
 * @param {string} toolUseId - The tool_use_id for correlation with the PostToolUse payload.
 */
export function savePendingAnswer(sessionName, answers, action, toolUseId) {
  const pendingAnswerFilePath = resolvePendingAnswerFilePath(sessionName);

  const pendingAnswerData = {
    tool_use_id: toolUseId,
    saved_at: new Date().toISOString(),
    session: sessionName,
    answers,
    action,
  };

  writeFileAtomically(pendingAnswerFilePath, pendingAnswerData);

  appendJsonlEntry({
    level: 'info',
    source: 'savePendingAnswer',
    message: 'Pending answer saved',
    session: sessionName,
    tool_use_id: toolUseId,
    action,
  }, sessionName);
}

/**
 * Read the pending answer from logs/queues/pending-answer-{session}.json.
 *
 * Called by the PostToolUse handler to retrieve what the TUI driver intended to submit.
 *
 * @param {string} sessionName - tmux session name.
 * @returns {Object|null} Parsed pending answer object, or null if file does not exist.
 */
export function readPendingAnswer(sessionName) {
  const pendingAnswerFilePath = resolvePendingAnswerFilePath(sessionName);

  try {
    return JSON.parse(readFileSync(pendingAnswerFilePath, 'utf8'));
  } catch (readError) {
    if (readError.code === 'ENOENT') {
      return null;
    }
    throw readError;
  }
}

/**
 * Delete the pending answer file for a session.
 *
 * Called by the PostToolUse handler after verification is complete (match or mismatch).
 * Silently ignores ENOENT — file may have already been cleaned up.
 *
 * @param {string} sessionName - tmux session name.
 */
export function deletePendingAnswer(sessionName) {
  const pendingAnswerFilePath = resolvePendingAnswerFilePath(sessionName);

  try {
    unlinkSync(pendingAnswerFilePath);
  } catch (deleteError) {
    if (deleteError.code !== 'ENOENT') {
      throw deleteError;
    }
  }

  appendJsonlEntry({
    level: 'debug',
    source: 'deletePendingAnswer',
    message: 'Pending answer deleted',
    session: sessionName,
  }, sessionName);
}

/**
 * Resolve the tool_response.answers value for a question by index.
 *
 * The PostToolUse payload answers keys can be either string indices ("0", "1") or
 * question text (from real logs: "question text": "selected answer"). This function
 * tries string index first, then falls back to matching by question text.
 *
 * @param {Object} toolResponseAnswers - The answers map from tool_response.
 * @param {number} questionIndex - Zero-based question index.
 * @param {Array} questions - The questions array from tool_input for text-based key fallback.
 * @returns {{ value: string|undefined, keyFormat: 'index'|'text'|'not-found' }}
 */
function resolveAnswerValueForQuestion(toolResponseAnswers, questionIndex, questions) {
  const stringIndexKey = String(questionIndex);

  if (stringIndexKey in toolResponseAnswers) {
    return { value: toolResponseAnswers[stringIndexKey], keyFormat: 'index' };
  }

  const questionText = questions[questionIndex]?.question;
  if (questionText && questionText in toolResponseAnswers) {
    return { value: toolResponseAnswers[questionText], keyFormat: 'text' };
  }

  return { value: undefined, keyFormat: 'not-found' };
}

/**
 * Compare what the TUI driver intended with what Claude Code recorded in PostToolUse.
 *
 * Handles 4 action types: select, type, multi-select, chat.
 * Returns matched:true when the answer aligns with intent, matched:false with a specific
 * reason when there is a mismatch.
 *
 * Answer key format flexibility: tool_response.answers keys may be string indices ("0", "1")
 * or question text. Tries string index first, falls back to question text match.
 *
 * @param {Object} pendingAnswer - The object from readPendingAnswer (has answers, action, tool_use_id).
 * @param {Object} toolResponse - The tool_response from the PostToolUse hook payload (has answers map).
 * @param {Object} toolInput - The tool_input from the PostToolUse hook payload (has questions array).
 * @returns {{ matched: true } | { matched: false, reason: string }}
 */
export function compareAnswerWithIntent(pendingAnswer, toolResponse, toolInput) {
  const { answers: intendedAnswers, action, tool_use_id: pendingToolUseId } = pendingAnswer;
  const { answers: receivedAnswers } = toolResponse;
  const { questions } = toolInput;

  // Warn if tool_use_id does not match — log but proceed (per RESEARCH.md Pitfall 4).
  if (pendingToolUseId && toolResponse.tool_use_id && pendingToolUseId !== toolResponse.tool_use_id) {
    appendJsonlEntry({
      level: 'warn',
      source: 'compareAnswerWithIntent',
      message: 'tool_use_id mismatch between pending answer and tool_response — proceeding with comparison',
      pending_tool_use_id: pendingToolUseId,
      response_tool_use_id: toolResponse.tool_use_id,
    }, null);
  }

  // chat action breaks normal answer flow — skip verification entirely.
  if (action === 'chat') {
    return { matched: true };
  }

  if (action === 'select') {
    return compareSelectAction(intendedAnswers, receivedAnswers, questions);
  }

  if (action === 'type') {
    return compareTypeAction(intendedAnswers, receivedAnswers, questions);
  }

  if (action === 'multi-select') {
    return compareMultiSelectAction(intendedAnswers, receivedAnswers, questions);
  }

  return { matched: false, reason: `Unknown action type: ${action}` };
}

/**
 * Compare a select action: verify the received answer matches the intended option label.
 *
 * @param {Object} intendedAnswers - Answers map from pending answer (e.g. { "0": 1 } for optionIndex).
 * @param {Object} receivedAnswers - Answers map from tool_response.
 * @param {Array} questions - Questions array from tool_input.
 * @returns {{ matched: true } | { matched: false, reason: string }}
 */
function compareSelectAction(intendedAnswers, receivedAnswers, questions) {
  for (const [questionIndexString, optionIndex] of Object.entries(intendedAnswers)) {
    const questionIndex = Number(questionIndexString);
    const question = questions[questionIndex];

    if (!question) {
      return { matched: false, reason: `Question index ${questionIndex} not found in tool_input` };
    }

    const intendedOptionLabel = question.options[optionIndex]?.label;

    if (!intendedOptionLabel) {
      return { matched: false, reason: `Option index ${optionIndex} not found in question ${questionIndex}` };
    }

    const { value: receivedValue, keyFormat } = resolveAnswerValueForQuestion(receivedAnswers, questionIndex, questions);

    appendJsonlEntry({
      level: 'debug',
      source: 'compareSelectAction',
      message: `Answer key format detected: ${keyFormat}`,
      question_index: questionIndex,
      key_format: keyFormat,
    }, null);

    if (receivedValue === undefined) {
      return { matched: false, reason: `No answer found for question ${questionIndex} in tool_response` };
    }

    const normalizedIntended = intendedOptionLabel.trim().toLowerCase();
    const normalizedReceived = receivedValue.trim().toLowerCase();

    if (normalizedIntended !== normalizedReceived) {
      return {
        matched: false,
        reason: `Question ${questionIndex}: intended "${intendedOptionLabel}" but received "${receivedValue}"`,
      };
    }
  }

  return { matched: true };
}

/**
 * Compare a type action: verify the received answer contains the intended typed text.
 *
 * Typed text may appear with additional formatting — substring match is used.
 *
 * @param {Object} intendedAnswers - Answers map from pending answer (e.g. { "0": "my typed answer" }).
 * @param {Object} receivedAnswers - Answers map from tool_response.
 * @param {Array} questions - Questions array from tool_input.
 * @returns {{ matched: true } | { matched: false, reason: string }}
 */
function compareTypeAction(intendedAnswers, receivedAnswers, questions) {
  for (const [questionIndexString, intendedText] of Object.entries(intendedAnswers)) {
    const questionIndex = Number(questionIndexString);

    const { value: receivedValue, keyFormat } = resolveAnswerValueForQuestion(receivedAnswers, questionIndex, questions);

    appendJsonlEntry({
      level: 'debug',
      source: 'compareTypeAction',
      message: `Answer key format detected: ${keyFormat}`,
      question_index: questionIndex,
      key_format: keyFormat,
    }, null);

    if (receivedValue === undefined) {
      return { matched: false, reason: `No answer found for question ${questionIndex} in tool_response` };
    }

    const normalizedIntended = String(intendedText).trim().toLowerCase();
    const normalizedReceived = receivedValue.trim().toLowerCase();

    if (!normalizedReceived.includes(normalizedIntended)) {
      return {
        matched: false,
        reason: `Question ${questionIndex}: intended text "${intendedText}" not found in received "${receivedValue}"`,
      };
    }
  }

  return { matched: true };
}

/**
 * Compare a multi-select action: verify ALL selected option labels appear in the received answer.
 *
 * @param {Object} intendedAnswers - Answers map from pending answer (e.g. { "0": [0, 2] } for selectedIndices).
 * @param {Object} receivedAnswers - Answers map from tool_response.
 * @param {Array} questions - Questions array from tool_input.
 * @returns {{ matched: true } | { matched: false, reason: string }}
 */
function compareMultiSelectAction(intendedAnswers, receivedAnswers, questions) {
  for (const [questionIndexString, selectedIndices] of Object.entries(intendedAnswers)) {
    const questionIndex = Number(questionIndexString);
    const question = questions[questionIndex];

    if (!question) {
      return { matched: false, reason: `Question index ${questionIndex} not found in tool_input` };
    }

    const { value: receivedValue, keyFormat } = resolveAnswerValueForQuestion(receivedAnswers, questionIndex, questions);

    appendJsonlEntry({
      level: 'debug',
      source: 'compareMultiSelectAction',
      message: `Answer key format detected: ${keyFormat}`,
      question_index: questionIndex,
      key_format: keyFormat,
    }, null);

    if (receivedValue === undefined) {
      return { matched: false, reason: `No answer found for question ${questionIndex} in tool_response` };
    }

    const normalizedReceived = receivedValue.trim().toLowerCase();

    for (const selectedIndex of selectedIndices) {
      const intendedOptionLabel = question.options[selectedIndex]?.label;

      if (!intendedOptionLabel) {
        return { matched: false, reason: `Option index ${selectedIndex} not found in question ${questionIndex}` };
      }

      const normalizedIntended = intendedOptionLabel.trim().toLowerCase();

      if (!normalizedReceived.includes(normalizedIntended)) {
        return {
          matched: false,
          reason: `Question ${questionIndex}: selected option "${intendedOptionLabel}" not found in received "${receivedValue}"`,
        };
      }
    }
  }

  return { matched: true };
}
