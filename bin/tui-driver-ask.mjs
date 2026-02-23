#!/usr/bin/env node
/**
 * bin/tui-driver-ask.mjs — AskUserQuestion TUI driver.
 *
 * Called by the OpenClaw orchestrating agent to navigate the Claude Code
 * AskUserQuestion TUI and submit the agent's decisions via tmux keystrokes.
 * Separate from bin/tui-driver.mjs (SRP: different inputs, different TUI
 * patterns, different purpose — answers questions vs. types GSD commands).
 *
 * Usage:
 *   node bin/tui-driver-ask.mjs --session <session-name> '<json-decisions-array>'
 *
 * Example (single question, select):
 *   node bin/tui-driver-ask.mjs --session warden-main-4 '[{"action":"select","optionIndex":1}]'
 *
 * Example (multi-question tabbed form):
 *   node bin/tui-driver-ask.mjs --session warden-main-4 '[{"action":"type","text":"use existing pattern"},{"action":"select","optionIndex":0}]'
 *
 * The decisions array index matches the question tab index. One action per question.
 *
 * Action types:
 *   select       — { "action": "select", "optionIndex": N }
 *   type         — { "action": "type", "text": "..." }
 *   multi-select — { "action": "multi-select", "selectedIndices": [0, 2] }
 *   chat         — { "action": "chat", "text": "..." }
 *
 * Reads question metadata from logs/queues/question-{session}.json (saved by
 * PreToolUse handler) to resolve option counts and labels for navigation.
 * Saves pending answer to logs/queues/pending-answer-{session}.json BEFORE
 * typing keystrokes — for PostToolUse verification.
 *
 * Pre-keystroke delay: The PreToolUse hook calls wakeAgentWithRetry which
 * uses execFileSync (synchronous/blocking). The hook process does NOT exit
 * until the openclaw CLI returns. Claude Code only renders the AskUserQuestion
 * TUI AFTER the PreToolUse hook exits. This driver is called by the agent
 * DURING the blocked hook execution — so keystrokes would arrive before the
 * TUI is visible. The PRE_KEYSTROKE_DELAY_MILLISECONDS constant adds a wait
 * after saving the pending answer and before sending keystrokes, giving Claude
 * Code time to render the TUI after the hook exits.
 */

import { parseArgs } from 'node:util';
import { readQuestionMetadata, savePendingAnswer, appendJsonlEntry } from '../lib/index.mjs';
import { sendKeysToTmux, sendSpecialKeyToTmux, sleepMilliseconds } from '../lib/tui-common.mjs';

/**
 * How long to wait (in milliseconds) after saving the pending answer and before
 * sending the first tmux keystroke. This delay allows the PreToolUse hook process
 * to exit and Claude Code to render the AskUserQuestion TUI before keystrokes arrive.
 *
 * From log evidence: keystrokes fired 2 seconds before the PreToolUse hook exited.
 * 3000ms provides a safe margin above that observed gap.
 */
const PRE_KEYSTROKE_DELAY_MILLISECONDS = 3000;

/**
 * Parse CLI arguments from process.argv.
 *
 * @returns {{ sessionName: string|undefined, decisionsArrayString: string|undefined }}
 */
function parseCommandLineArguments() {
  const { values, positionals } = parseArgs({
    args: process.argv.slice(2),
    options: {
      session: { type: 'string', short: 's' },
    },
    allowPositionals: true,
  });

  return {
    sessionName: values.session,
    decisionsArrayString: positionals[0],
  };
}

/**
 * Validate that each decision object has a required action field.
 *
 * @param {Array} decisions - Array of decision objects to validate.
 * @returns {string|null} Error message if invalid, null if valid.
 */
function validateDecisions(decisions) {
  if (!Array.isArray(decisions) || decisions.length === 0) {
    return 'Decisions must be a non-empty array';
  }

  for (const [decisionIndex, decision] of decisions.entries()) {
    if (!decision.action) {
      return `Decision at index ${decisionIndex} is missing required "action" field`;
    }

    const validActions = ['select', 'type', 'multi-select', 'chat'];
    if (!validActions.includes(decision.action)) {
      return `Decision at index ${decisionIndex} has unknown action: "${decision.action}". Valid actions: ${validActions.join(', ')}`;
    }
  }

  return null;
}

/**
 * Build the pending answers map from decisions and question metadata.
 *
 * For select: stores the option index (comparison logic resolves label from toolInput).
 * For type/chat: stores the text string.
 * For multi-select: stores the selectedIndices array (comparison verifies each label).
 *
 * @param {Array} decisions - Array of decision objects from CLI.
 * @param {Object} questionMetadata - Question metadata from readQuestionMetadata.
 * @returns {Object} Answers map keyed by question index string (e.g. { "0": 1, "1": "text" }).
 */
function buildPendingAnswers(decisions, questionMetadata) {
  const pendingAnswers = {};

  for (const [questionIndex, decision] of decisions.entries()) {
    const questionIndexString = String(questionIndex);

    if (decision.action === 'select') {
      pendingAnswers[questionIndexString] = decision.optionIndex;
    } else if (decision.action === 'type') {
      pendingAnswers[questionIndexString] = decision.text;
    } else if (decision.action === 'multi-select') {
      pendingAnswers[questionIndexString] = decision.selectedIndices;
    } else if (decision.action === 'chat') {
      pendingAnswers[questionIndexString] = decision.text;
    }
  }

  return pendingAnswers;
}

/**
 * Navigate the AskUserQuestion TUI and select an option by pressing Down N times then Enter.
 *
 * @param {string} sessionName - Target tmux session name.
 * @param {number} optionIndex - Zero-based index of the option to select.
 */
function executeSelectAction(sessionName, optionIndex) {
  for (let downPressCount = 0; downPressCount < optionIndex; downPressCount++) {
    sendSpecialKeyToTmux(sessionName, 'Down');
  }
  sendSpecialKeyToTmux(sessionName, 'Enter');
}

/**
 * Navigate to the "Type something" field and type text then submit.
 *
 * "Type something" appears at position options.length (0-indexed, after all payload options).
 * Pressing Enter after navigating to "Type something" activates the text input.
 * A second Enter submits the typed text.
 *
 * @param {string} sessionName - Target tmux session name.
 * @param {number} questionOptionCount - Number of options in the question payload.
 * @param {string} textToType - The text the agent wants to type.
 */
function executeTypeAction(sessionName, questionOptionCount, textToType) {
  // Navigate to "Type something" — it is at position options.length (after all payload options)
  for (let downPressCount = 0; downPressCount < questionOptionCount; downPressCount++) {
    sendSpecialKeyToTmux(sessionName, 'Down');
  }
  sendSpecialKeyToTmux(sessionName, 'Enter'); // Activate text input
  sendKeysToTmux(sessionName, textToType);
  sendSpecialKeyToTmux(sessionName, 'Enter'); // Submit typed text
}

/**
 * Navigate to each selected option index and press Space to toggle, then Enter to submit.
 *
 * Navigates in ascending order from current cursor position to avoid back-navigation.
 * After toggling all selections, presses Enter to submit the multi-select.
 *
 * @param {string} sessionName - Target tmux session name.
 * @param {number[]} selectedIndices - Array of option indices to select (in any order).
 */
function executeMultiSelectAction(sessionName, selectedIndices) {
  const sortedSelectedIndices = [...selectedIndices].sort((firstIndex, secondIndex) => firstIndex - secondIndex);
  let currentCursorPosition = 0;

  for (const targetOptionIndex of sortedSelectedIndices) {
    const downPressesNeeded = targetOptionIndex - currentCursorPosition;
    for (let downPressCount = 0; downPressCount < downPressesNeeded; downPressCount++) {
      sendSpecialKeyToTmux(sessionName, 'Down');
    }
    sendSpecialKeyToTmux(sessionName, 'Space'); // Toggle selection
    currentCursorPosition = targetOptionIndex;
  }

  // After toggling all selections, press Enter to submit the multi-select form
  sendSpecialKeyToTmux(sessionName, 'Enter');
}

/**
 * Navigate to the "Chat about this" field and type text then submit.
 *
 * TUI layout per CONTEXT.md:
 *   0 .. options.length-1   — payload options
 *   options.length          — "Type something" (not in payload)
 *   separator line          — visual only, may or may not be navigable
 *   options.length + 2      — "Chat about this" (LOW CONFIDENCE — needs live testing)
 *
 * Assumption: separator does count as a navigable position.
 * If live testing shows otherwise, change + 2 to + 1 in downPressCount.
 *
 * @param {string} sessionName - Target tmux session name.
 * @param {number} questionOptionCount - Number of options in the question payload.
 * @param {string} textToType - The agent's chat message explaining what is wrong.
 */
function executeChatAction(sessionName, questionOptionCount, textToType) {
  // "Chat about this" is below "Type something" (options.length) + separator
  // LOW CONFIDENCE: exact Down count needs live verification (options.length + 2 assumed)
  const downPressCount = questionOptionCount + 2;
  for (let downPress = 0; downPress < downPressCount; downPress++) {
    sendSpecialKeyToTmux(sessionName, 'Down');
  }
  sendSpecialKeyToTmux(sessionName, 'Enter'); // Activate chat input
  sendKeysToTmux(sessionName, textToType);
  sendSpecialKeyToTmux(sessionName, 'Enter'); // Submit chat text
}

/**
 * Dispatch a single decision to the appropriate TUI action function.
 *
 * @param {string} sessionName - Target tmux session name.
 * @param {Object} decision - The decision object from the CLI decisions array.
 * @param {Object} questionData - The question data from questionMetadata.questions[i].
 */
function dispatchDecisionToTuiAction(sessionName, decision, questionData) {
  const optionCount = questionData.options.length;

  if (decision.action === 'select') {
    executeSelectAction(sessionName, decision.optionIndex);
    return;
  }

  if (decision.action === 'type') {
    executeTypeAction(sessionName, optionCount, decision.text);
    return;
  }

  if (decision.action === 'multi-select') {
    executeMultiSelectAction(sessionName, decision.selectedIndices);
    return;
  }

  if (decision.action === 'chat') {
    executeChatAction(sessionName, optionCount, decision.text);
  }
}

async function main() {
  const { sessionName, decisionsArrayString } = parseCommandLineArguments();

  if (!sessionName) {
    process.stderr.write('Error: --session <session-name> is required\n');
    process.exit(1);
  }

  if (!decisionsArrayString) {
    process.stderr.write('Error: JSON decisions array is required as a positional argument\n');
    process.exit(1);
  }

  let decisions;
  try {
    decisions = JSON.parse(decisionsArrayString);
  } catch (parseError) {
    process.stderr.write(`Error: Failed to parse decisions array as JSON: ${parseError.message}\n`);
    process.exit(1);
  }

  const validationError = validateDecisions(decisions);
  if (validationError) {
    process.stderr.write(`Error: ${validationError}\n`);
    process.exit(1);
  }

  const questionMetadata = readQuestionMetadata(sessionName);
  if (!questionMetadata) {
    process.stderr.write(`Error: No question metadata found for session "${sessionName}". PreToolUse handler may not have saved it.\n`);
    process.exit(1);
  }

  if (decisions.length !== questionMetadata.questions.length) {
    process.stderr.write(`Error: Decisions array length (${decisions.length}) does not match questions array length (${questionMetadata.questions.length}). One decision per question is required.\n`);
    process.exit(1);
  }

  const pendingAnswers = buildPendingAnswers(decisions, questionMetadata);

  // For single-question: action field is the first decision's action.
  // For multi-question: action field stores the full decisions array (PostToolUse handles both).
  const pendingAnswerAction = decisions.length === 1 ? decisions[0].action : decisions.map(decision => decision.action);

  savePendingAnswer(sessionName, pendingAnswers, pendingAnswerAction, questionMetadata.tool_use_id);

  // Wait for the AskUserQuestion TUI to render before sending keystrokes.
  // The PreToolUse hook process blocks on openclaw agent CLI (execFileSync).
  // This driver runs while that hook is still blocked — meaning Claude Code
  // has not yet rendered the AskUserQuestion TUI (it renders AFTER the hook exits).
  // Without this delay, keystrokes arrive before the TUI appears and go to the void.
  sleepMilliseconds(PRE_KEYSTROKE_DELAY_MILLISECONDS);

  // Type keystrokes for each question
  for (const [questionIndex, decision] of decisions.entries()) {
    if (questionIndex > 0) {
      // Advance to next question tab in multi-question tabbed form
      sendSpecialKeyToTmux(sessionName, 'Tab');
    }

    dispatchDecisionToTuiAction(sessionName, decision, questionMetadata.questions[questionIndex]);
  }

  appendJsonlEntry({
    level: 'info',
    source: 'tui-driver-ask',
    message: 'AskUserQuestion TUI navigation complete',
    session: sessionName,
    question_count: decisions.length,
    actions: decisions.map(decision => decision.action),
  }, sessionName);
}

main().catch((caughtError) => {
  process.stderr.write(`Error: ${caughtError.message}\n`);
  process.exit(1);
});
