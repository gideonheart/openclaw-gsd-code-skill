---
status: resolved
trigger: "double-hook-trigger"
created: 2026-02-22T00:00:00Z
updated: 2026-02-22T12:00:00Z
---

## Current Focus

hypothesis: CONFIRMED — UserPromptSubmit fires for TUI driver keystrokes (tmux send-keys), cancels the active queue, wakes Gideon with "remaining: /gsd:discuss-phase 18", Gideon retypes the same command, causing the double-trigger loop
test: Confirmed via JSONL event log — typeCommandIntoTmuxSession at 22:10:54.906 → cancelQueueForSession (UserPromptSubmit) at 22:10:55.438 → second typeCommandIntoTmuxSession at 22:11:03.258
expecting: n/a — root cause confirmed
next_action: Fix event_user_prompt_submit.mjs to check if hookPayload.prompt matches active queue command; if so, skip cancellation (input is from TUI driver, not human)

## Symptoms

expected: Each hook event should trigger exactly one action (one command typed, one answer sent)
actual: Hook events trigger twice — commands like `/gsd:discuss-phase 18` appear twice; user corrections during AskUserQuestion get typed multiple times into tmux
errors: No error messages — the duplicate just happens silently
reproduction:
  1. Run `/clear` then `/gsd:discuss-phase 18` — the discuss-phase command appears twice in the session
  2. During AskUserQuestion flow, answer a question — the correction text gets typed multiple times into tmux
started: Current behavior on v4.0-full-refactor branch. All hook handlers were built in phases 03-04.

## Eliminated

- hypothesis: Duplicate hook entries in settings.json (both logger + handler for same event)
  evidence: settings.json has only handler entries (no logger). hooks.json has both, but install-hooks.mjs defaults to handlers-only. No duplicate entries installed.
  timestamp: 2026-02-22T12:00:00Z

## Evidence

- timestamp: 2026-02-22T12:00:00Z
  checked: config/hooks.json and ~/.claude/settings.json
  found: hooks.json has logger+handler pairs per event; ~/.claude/settings.json only has handler entries (logger was NOT installed). No duplicate entries.
  implication: Duplicate hook registration is NOT the root cause.

- timestamp: 2026-02-22T12:01:00Z
  checked: JSONL event log around 22:10:51-22:11:10 (the /gsd:discuss-phase 18 double-trigger)
  found: Line 76: typeCommandIntoTmuxSession /gsd:discuss-phase 18 at 22:10:54.906. Line 77: cancelQueueForSession fires 0.5s later at 22:10:55.438. Line 78-79: tui-driver creates new queue and types /gsd:discuss-phase 18 a SECOND time at 22:11:03.258.
  implication: UserPromptSubmit fires when TUI driver types commands via tmux send-keys. Claude Code treats all terminal input as user input.

- timestamp: 2026-02-22T12:02:00Z
  checked: UserPromptSubmit payload in all-sample-events.jsonl
  found: payload.prompt contains the exact command text typed (e.g. "/gsd:resume-work " with trailing space from Tab expansion)
  implication: The prompt field can be compared to the active queue command to detect TUI driver input vs human input.

- timestamp: 2026-02-22T12:03:00Z
  checked: Full reproduction pattern in the logs
  found: Every tui-driver typeCommandIntoTmuxSession call triggers UserPromptSubmit → cancelQueueForSession → Gideon notified with "remaining commands" → Gideon retypes → second UserPromptSubmit → repeat until queue is gone
  implication: This explains ALL the cancel/retry chaos in the logs. Fix: skip cancellation when prompt matches active queue command.

## Resolution

root_cause: UserPromptSubmit hook fires for ALL terminal input including automated tmux send-keys from tui-driver.mjs. The handler treats this as human input, cancels the queue, wakes Gideon with "remaining commands: /gsd:discuss-phase 18". Gideon then retypes the same command, creating a double-trigger loop.
fix: In event_user_prompt_submit.mjs, read the active queue command and compare with hookPayload.prompt (trimmed). If they match, the input is from the TUI driver — skip cancellation and exit cleanly. Extract the comparison logic into queue-processor.mjs as isPromptFromTuiDriver().
verification: Syntax checks pass. isPromptFromTuiDriver unit tested with real queue file — exact match returns true, trailing-space match returns true (Tab autocomplete adds space), different command returns false, empty prompt returns false. Logic traced through the logs: the double-trigger at 22:10:54 would now be caught by the guard — prompt "/gsd:discuss-phase 18" matches active queue command, UserPromptSubmit skips cancellation, queue proceeds normally.
files_changed:
  - events/user_prompt_submit/event_user_prompt_submit.mjs
  - lib/queue-processor.mjs
  - lib/index.mjs
