---
phase: 04-askuserquestion-lifecycle-full-stack
verified: 2026-02-22T12:15:00Z
status: human_needed
score: 9/9 must-haves verified
re_verification: false
human_verification:
  - test: "chat action TUI navigation — verify 'Chat about this' Down count"
    expected: "optionCount + 2 Down presses lands on 'Chat about this' option"
    why_human: "Exact TUI layout (whether separator is navigable) cannot be verified without a live Claude Code session presenting an AskUserQuestion TUI"
  - test: "End-to-end AskUserQuestion lifecycle — fire a real PreToolUse event and confirm question metadata is saved, agent is woken, tui-driver-ask.mjs submits answer, PostToolUse reads pending answer and confirms match"
    expected: "logs/queues/question-{session}.json created on PreToolUse, logs/queues/pending-answer-{session}.json created before keystrokes sent, PostToolUse logs 'AskUserQuestion verified — answer matches intent', both files deleted after verification"
    why_human: "Full lifecycle requires a live tmux session running Claude Code with AskUserQuestion enabled — cannot mock the full tmux/hook chain in a static check"
---

# Phase 4: AskUserQuestion Lifecycle Full-Stack Verification Report

**Phase Goal:** The full PreToolUse -> PostToolUse verification loop works end-to-end — PreToolUse handler extracts questions/options/multiSelect, wakes agent with prompt, TUI driver navigates and submits the answer, PostToolUse handler verifies the answer matches. Testable and validated before proceeding.
**Verified:** 2026-02-22T12:15:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

All automated checks pass. The full lifecycle is implemented and wired. Two items require live human testing: the chat action navigation count (documented as LOW CONFIDENCE in the code itself) and the end-to-end hook chain with a real tmux session.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | `formatQuestionsForAgent` produces a readable markdown string with numbered options, question headers, multiSelect flags, and the 'How to answer' instruction block — matching the exact gateway message format from CONTEXT.md | VERIFIED | Live node test produced correct markdown with `## AskUserQuestion from Claude Code`, session name, numbered options, `## How to answer` block, and absolute path CLI call instruction |
| 2 | `saveQuestionMetadata` writes an atomic JSON file at logs/queues/question-{session}.json with tool_use_id, saved_at, session, and questions array | VERIFIED | Implementation: `writeFileAtomically` (tmp+rename), file path `resolve(QUEUES_DIRECTORY, 'question-' + sessionName + '.json')`, correct JSON shape with all 4 required fields |
| 3 | `readQuestionMetadata` returns the parsed JSON object or null if file does not exist | VERIFIED | Implementation wraps `readFileSync` in try/catch — ENOENT returns null, other errors rethrow |
| 4 | `savePendingAnswer` writes an atomic JSON file at logs/queues/pending-answer-{session}.json with tool_use_id, saved_at, session, answers, and action fields | VERIFIED | Implementation: same atomic pattern, correct path prefix `pending-answer-`, correct 5-field JSON shape |
| 5 | `compareAnswerWithIntent` returns `{ matched: true }` when pending answer aligns with tool_response.answers, and `{ matched: false, reason }` with specific mismatch details otherwise | VERIFIED | Live node test: select match returns `{ matched: true }`, select mismatch returns `{ matched: false, reason: 'Question 0: intended "Option A" but received "Option B"' }`, chat always returns `{ matched: true }` |
| 6 | `lib/index.mjs` re-exports all 8 new functions from ask-user-question.mjs | VERIFIED | Line 10 of lib/index.mjs: explicit named re-export of all 8 functions; live import test confirmed `formatQuestionsForAgent`, `compareAnswerWithIntent` resolve as functions |
| 7 | PreToolUse handler saves question metadata and wakes OpenClaw agent via wakeAgentWithRetry with formatted questions and prompt instructions | VERIFIED | `handle_ask_user_question.mjs`: calls `saveQuestionMetadata` then `formatQuestionsForAgent` then `wakeAgentWithRetry` with `promptFilePath` pointing to `prompt_ask_user_question.md` |
| 8 | `tui-driver-ask.mjs` reads question metadata, saves pending answer before typing, and sends correct tmux keystrokes per action type | VERIFIED | 300-line file: reads metadata at line 258, saves pending answer at line 275 (before keystroke loop starts at line 278), implements all 4 action types with correct navigation functions |
| 9 | PostToolUse handler reads pending-answer file, compares with tool_response.answers, and handles all 3 outcomes (match silent, mismatch wake, missing file warn+heal) | VERIFIED | `handle_post_ask_user_question.mjs`: null-pending guard at line 45 (warn+return), missing tool_response.answers guard at line 61 (warn+return), matched path at line 77 (log+cleanup), mismatch path wakes agent at line 102 |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/ask-user-question.mjs` | All AskUserQuestion domain logic — 8 exported functions | VERIFIED | 511 lines, 8 exports confirmed by live import test |
| `lib/index.mjs` | Updated re-export entry point including ask-user-question.mjs functions | VERIFIED | 18 lines, line 10 re-exports all 8 functions, all 8 plus pre-existing exports resolve correctly |
| `events/pre_tool_use/event_pre_tool_use.mjs` | PreToolUse router — readHookContext, dispatch by tool_name | VERIFIED | 40 lines (min_lines: 25), dispatches `AskUserQuestion` to `handleAskUserQuestion`, else logs debug and exits 0 |
| `events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs` | AskUserQuestion PreToolUse domain handler | VERIFIED | 53 lines, exports `handleAskUserQuestion`, thin plumbing (~5 logical lines) |
| `events/pre_tool_use/ask_user_question/prompt_ask_user_question.md` | Agent prompt for answering AskUserQuestion questions | VERIFIED | 23 lines, 6-category decision framework, GSD phase awareness table, tells agent to "Call the TUI driver as shown in the instructions above" |
| `bin/tui-driver-ask.mjs` | AskUserQuestion TUI driver — reads question file, saves pending answer, types keystrokes | VERIFIED | 300 lines (min_lines: 80), shebang present, all 4 action types implemented |
| `events/post_tool_use/event_post_tool_use.mjs` | PostToolUse router — readHookContext, dispatch by tool_name | VERIFIED | 40 lines (min_lines: 25), mirrors PreToolUse router structure exactly |
| `events/post_tool_use/ask_user_question/handle_post_ask_user_question.mjs` | AskUserQuestion PostToolUse verification handler | VERIFIED | 181 lines, exports `handlePostAskUserQuestion`, all 3 outcome paths implemented |
| `events/post_tool_use/ask_user_question/prompt_post_ask_mismatch.md` | Agent prompt for AskUserQuestion mismatch correction | VERIFIED | 20 lines (within 15-25 expected range), actionable correction instructions, references Chat/Type actions |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `events/pre_tool_use/event_pre_tool_use.mjs` | `handle_ask_user_question.mjs` | import + `if (toolName === 'AskUserQuestion')` dispatch | WIRED | Line 13 imports, line 23 calls `handleAskUserQuestion` |
| `handle_ask_user_question.mjs` | `lib/ask-user-question.mjs` | `formatQuestionsForAgent` + `saveQuestionMetadata` | WIRED | Both imported from `lib/index.mjs` (line 15-16), both called in handler body (lines 37, 39) |
| `handle_ask_user_question.mjs` | `lib/gateway.mjs` | `wakeAgentWithRetry` | WIRED | Imported line 17, called at line 43 with `messageContent` + `promptFilePath` |
| `bin/tui-driver-ask.mjs` | `lib/ask-user-question.mjs` | `readQuestionMetadata` + `savePendingAnswer` | WIRED | Both imported from `lib/index.mjs` (line 34), called at lines 258 and 275 |
| `bin/tui-driver-ask.mjs` | `lib/tui-common.mjs` | `sendKeysToTmux` + `sendSpecialKeyToTmux` | WIRED | Direct import from `lib/tui-common.mjs` (line 35), both used extensively in action functions |
| `lib/index.mjs` | `lib/ask-user-question.mjs` | named re-exports | WIRED | Line 10 re-exports all 8 functions |
| `events/post_tool_use/event_post_tool_use.mjs` | `handle_post_ask_user_question.mjs` | import + dispatch | WIRED | Line 13 imports, line 23 calls `handlePostAskUserQuestion` |
| `handle_post_ask_user_question.mjs` | `lib/ask-user-question.mjs` | `readPendingAnswer` + `compareAnswerWithIntent` + `deletePendingAnswer` + `deleteQuestionMetadata` | WIRED | All 4 imported (lines 21-24), all called in handler body |
| `handle_post_ask_user_question.mjs` | `lib/gateway.mjs` | `wakeAgentWithRetry` (mismatch only) | WIRED | Imported line 25, called at line 102 in mismatch path |
| `lib/tui-common.mjs` | (exports) | `sendKeysToTmux` + `sendSpecialKeyToTmux` now exported | WIRED | Both functions have `export` keyword (lines 92 and 106), also re-exported from `lib/index.mjs` line 16 |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| ASK-01 | 04-01, 04-02 | PreToolUse(AskUserQuestion) handler extracts `tool_input.questions` array with question text, options, and multiSelect flag | SATISFIED | `handle_ask_user_question.mjs` line 34: `const toolInput = hookPayload.tool_input`, passed to `saveQuestionMetadata` and `formatQuestionsForAgent` which iterates `toolInput.questions` including `multiSelect` flag |
| ASK-02 | 04-02 | PreToolUse prompt template instructs agent to read the question, decide the answer, and call the AskUserQuestion TUI driver | SATISFIED | `prompt_ask_user_question.md` line 23: "Call the TUI driver as shown in the instructions above" — the CLI call instruction is produced by `formatQuestionsForAgent` in the message content above the prompt |
| ASK-03 | 04-01, 04-03 | PostToolUse(AskUserQuestion) handler extracts `tool_response.answers` and the original `tool_input.questions` | SATISFIED | `handle_post_ask_user_question.mjs` lines 58-59: `const toolResponse = hookPayload.tool_response` and `const toolInput = hookPayload.tool_input`, both passed to `compareAnswerWithIntent` |
| ASK-04 | 04-03 | PostToolUse prompt template instructs agent to verify submitted answer matches what agent decided, and report any mismatch | SATISFIED | `prompt_post_ask_mismatch.md` instructs agent to use "Chat about this" or "Type something" on the next question to correct the mismatch — this is the specified correction mechanism per CONTEXT.md |
| TUI-03 | 04-02 | AskUserQuestion TUI driver knows how to navigate options (arrow keys), select (space for multiSelect, enter for single-select), and submit | SATISFIED | `bin/tui-driver-ask.mjs` implements: `executeSelectAction` (Down x N + Enter), `executeMultiSelectAction` (Down + Space per index + Enter), `executeTypeAction` (navigate to Type something + Enter + text + Enter) |
| TUI-04 | 04-02 | TUI drivers replace monolithic menu-driver.sh for hook-driven interactions | SATISFIED | `bin/` directory contains `tui-driver.mjs` and `tui-driver-ask.mjs` — two standalone TUI drivers replacing the old monolithic shell script (menu-driver.sh deleted in Phase 1) |

No orphaned requirements — all 6 IDs from plan frontmatter are present in REQUIREMENTS.md and covered above.

### Anti-Patterns Found

| File | Lines | Pattern | Severity | Impact |
|------|-------|---------|----------|--------|
| `bin/tui-driver-ask.mjs` | 180, 191 | `LOW CONFIDENCE: exact Down count needs live verification (options.length + 2 assumed)` | Warning | The `chat` action navigation assumes the TUI separator is navigable (`optionCount + 2` Down presses). This assumption is documented in both comment and JSDoc. If wrong, the chat action will land on the wrong option. Needs live verification. |

No blockers found. No `TODO`/`FIXME`/`PLACEHOLDER` patterns. No empty implementations. No stubs.

### Human Verification Required

#### 1. Chat Action TUI Navigation Count

**Test:** In a live Claude Code session with AskUserQuestion enabled, call `tui-driver-ask.mjs` with `{"action": "chat", "text": "test"}` on a question with 2 options. Observe whether the TUI cursor lands on "Chat about this".

**Expected:** The TUI navigates down `optionCount + 2` positions and "Chat about this" becomes active input. If the separator is not navigable, it would require `optionCount + 1` instead.

**Why human:** The TUI layout (whether the visual separator counts as a navigable position) can only be verified with a live Claude Code session that presents an AskUserQuestion TUI. Static analysis cannot determine the actual rendered layout.

#### 2. End-to-End AskUserQuestion Lifecycle

**Test:** In a live GSD session with PreToolUse/PostToolUse hooks registered in `~/.claude/settings.json`, trigger a real AskUserQuestion tool use. Observe the full chain: hook fires -> question file created -> agent woken -> agent calls tui-driver-ask.mjs -> answer submitted -> PostToolUse fires -> verification logged -> both files deleted.

**Expected:**
- `logs/queues/question-{session}.json` created with correct structure before agent is woken
- `logs/queues/pending-answer-{session}.json` created before tmux keystrokes are sent
- PostToolUse logs `AskUserQuestion verified — answer matches intent` (or mismatch message)
- Both files deleted after PostToolUse completes
- Session continues normally after answer submission

**Why human:** Requires hooks registered in `settings.json` (Phase 5 work — REG-02 is still pending), a live tmux session running Claude Code, and a real AskUserQuestion tool invocation. The static code analysis confirms the lifecycle is wired correctly, but live behavior depends on timing, Claude Code TUI rendering, and actual hook registration.

### Gaps Summary

No automated gaps found. All 9 must-haves are verified, all 6 requirements are satisfied, all key links are wired, and no blocker anti-patterns exist.

The `human_needed` status reflects two items:

1. The `chat` action navigation count (`optionCount + 2`) is acknowledged as LOW CONFIDENCE in the code itself — it is the correct assumption based on CONTEXT.md analysis but cannot be confirmed without a live TUI session.

2. The full end-to-end lifecycle requires hook registration (REG-02, Phase 5) before it can be exercised. The code is complete and correct; what is missing is the hook registration in `~/.claude/settings.json`.

The phase goal — "full PreToolUse -> PostToolUse verification loop works end-to-end" — is implemented and ready for live validation. All code paths exist, are wired, and handle the documented cases.

---

_Verified: 2026-02-22T12:15:00Z_
_Verifier: Claude (gsd-verifier)_
