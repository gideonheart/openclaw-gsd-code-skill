---
phase: 06-core-extraction-and-delivery-engine
type: verification
status: passed
verified: 2026-02-18
updated: 2026-02-18
---

# Phase 6: Core Extraction and Delivery Engine - Verification

## Phase Goal
Gideon receives clean extracted content -- Claude's response from transcript JSONL (primary) or pane diff (fallback), plus structured AskUserQuestion data forwarded before TUI renders.

## Success Criteria Verification

### 1. Wake message [CONTENT] section contains Claude's actual response text extracted from transcript JSONL
**Status:** PASSED

- `scripts/stop-hook.sh` section 7b extracts `transcript_path` from stdin JSON
- Calls `extract_last_assistant_response` from lib/hook-utils.sh
- Uses `tail -40 | jq -r 'select(.type == "assistant") | (.message.content // [])[] | select(.type == "text") | .text'`
- Type-filtered selection handles thinking/tool_use blocks correctly (not positional indexing)
- Result placed in `CONTENT_SECTION` variable, emitted in v2 `[CONTENT]` section

**Evidence:** `grep 'extract_last_assistant_response' scripts/stop-hook.sh` returns function call; `grep '\[CONTENT\]' scripts/stop-hook.sh` returns section header.

### 2. When transcript extraction fails, hook falls back to pane diff (only new/added lines from last 40 lines)
**Status:** PASSED

- Section 9b checks `EXTRACTED_RESPONSE` — if empty, falls back to `extract_pane_diff`
- Pane diff uses `diff --new-line-format='%L'` to output only added lines
- Takes `tail -40` of PANE_CONTENT for diff input
- Ultimate fallback if lib not loaded: raw `tail -40` of pane content
- Never crashes, never sends empty (first-fire fallback returns last 10 lines)

**Evidence:** `grep 'extract_pane_diff' scripts/stop-hook.sh` returns function call; `grep 'raw_pane_tail' scripts/stop-hook.sh` returns ultimate fallback.

### 3. When Claude calls AskUserQuestion, Gideon receives structured [ASK USER QUESTION] wake
**Status:** PASSED

- `scripts/pre-tool-use-hook.sh` created with AskUserQuestion handling
- Extracts `tool_input` from stdin JSON
- Sources lib/hook-utils.sh and calls `format_ask_user_questions`
- Builds wake message with `[ASK USER QUESTION]` section containing formatted questions
- Always backgrounds openclaw call (`&` at end of line)
- Always exits 0 (never blocks/denies AskUserQuestion)

**Evidence:** `grep '\[ASK USER QUESTION\]' scripts/pre-tool-use-hook.sh` returns section; `grep '&$' scripts/pre-tool-use-hook.sh` confirms backgrounding.

### 4. v1 wake format code removed -- clean v2 format only
**Status:** PASSED

- `[PANE CONTENT]` section completely absent from stop-hook.sh
- v2 section order: [SESSION IDENTITY], [TRIGGER], [CONTENT], [STATE HINT], [CONTEXT PRESSURE], [AVAILABLE ACTIONS]
- No conditional v1/v2 toggle
- No backward compatibility layer

**Evidence:** `grep '\[PANE CONTENT\]' scripts/stop-hook.sh` returns zero matches; section ordering verified by line numbers (183, 188, 191, 194, 197, 200).

### 5. Shared lib/hook-utils.sh provides DRY extraction functions sourced by stop-hook.sh and pre-tool-use-hook.sh only
**Status:** PASSED

- `lib/hook-utils.sh` contains exactly three functions: extract_last_assistant_response, extract_pane_diff, format_ask_user_questions
- Sourcing produces no side effects (no output, no variable pollution)
- Sourced by exactly 2 scripts: stop-hook.sh (section 6b) and pre-tool-use-hook.sh (section 6)
- No other hook scripts source the lib

**Evidence:** `source lib/hook-utils.sh` produces no output; `grep -l 'source.*lib/hook-utils.sh' scripts/*.sh` returns exactly 2 files.

## Requirement Coverage

All 11 Phase 6 requirements verified complete:

| Requirement | Status | Evidence |
|------------|--------|----------|
| LIB-01 | PASSED | lib/hook-utils.sh exists with 3 shared functions |
| LIB-02 | PASSED | Each function has single responsibility |
| EXTRACT-01 | PASSED | transcript JSONL extraction with type-filtered content parsing |
| EXTRACT-02 | PASSED | Pane diff fallback when transcript fails |
| EXTRACT-03 | PASSED | Per-session /tmp state files with flock protection |
| ASK-01 | PASSED | PreToolUse hook for AskUserQuestion (matcher-scoped) |
| ASK-02 | PASSED | Structured question data extraction from tool_input |
| ASK-03 | PASSED | Async delivery (backgrounded, never blocks TUI) |
| WAKE-07 | PASSED | v2 structured format with all 6 sections |
| WAKE-08 | PASSED | v1 [PANE CONTENT] completely removed |
| WAKE-09 | PASSED | [ASK USER QUESTION] section with structured data |

## Syntax Verification

| File | bash -n | Executable |
|------|---------|------------|
| lib/hook-utils.sh | PASSED | Yes |
| scripts/pre-tool-use-hook.sh | PASSED | Yes |
| scripts/stop-hook.sh | PASSED | Yes |

## Functional Verification

| Test | Result |
|------|--------|
| extract_last_assistant_response("") returns empty | PASSED |
| extract_last_assistant_response("/nonexistent") returns empty | PASSED |
| extract_pane_diff first-fire returns content | PASSED |
| extract_pane_diff second-call returns only new lines | PASSED |
| format_ask_user_questions with valid JSON returns formatted text | PASSED |
| Sourcing lib produces no output | PASSED |

## Score

**11/11 must-haves verified.** Phase 6 goal achieved.

---
*Verified: 2026-02-18*
