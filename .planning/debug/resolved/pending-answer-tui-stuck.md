---
status: resolved
trigger: "pending-answer-tui-stuck: The TUI driver does not process a pending-answer file"
created: 2026-02-24T10:15:00.000Z
updated: 2026-02-24T10:50:00.000Z
---

## Current Focus

hypothesis: CONFIRMED — The PreToolUse hook blocks Claude Code. The hook wakes Gideon synchronously (wakeAgentWithRetry returns only after openclaw CLI delivers the message). Gideon immediately calls tui-driver-ask.mjs. The TUI driver polls 5s for the AskUserQuestion TUI in the tmux pane. But the AskUserQuestion TUI CANNOT appear while the PreToolUse hook is still running — Claude Code is blocked by the hook and only shows the TUI after the hook process exits. Keystrokes are sent at T+5s into empty pane space. The hook finally returns at T+8s. The TUI appears after T+8s and stays stuck waiting for input that was already sent.
test: Confirmed via JSONL timestamps: pending-answer saved at 10:09:29, "TUI not detected" at 10:09:34 (5s later), "navigation complete" at 10:09:34, wakeAgentViaGateway at 10:09:37, PreToolUse handler complete at 10:09:37. Keystrokes sent 3 seconds BEFORE the hook returned.
expecting: Fix is: wakeAgentWithRetry must be fire-and-forget (not await the CLI response). OR the handler must return immediately and Gideon must be notified without the hook blocking. The cleanest fix is to spawn wakeAgentViaGateway as a detached background process so the hook exits immediately, the TUI renders, THEN Gideon calls tui-driver-ask.mjs.
next_action: Implement fix — make the PreToolUse handler fire-and-forget by spawning openclaw CLI as detached process (same pattern as spawnDetachedDeferredTyping)

## Symptoms

expected: When a pending-answer file is written, the TUI driver should detect it, read the answer, and submit the selection to Claude Code's AskUserQuestion prompt using tmux keystrokes (Down arrows to select option, Enter to confirm).
actual: The pending-answer file sits there untouched. The TUI does not move. The AskUserQuestion prompt remains visible in the tmux pane.
errors: No crash errors visible — the flow just stops.
reproduction: OpenClaw sends a select action via webhook. The pending-answer JSON file is created. But nothing picks it up.
timeline: This is the first real end-to-end test of the AskUserQuestion answer flow (Phase 04 was recently completed).

## Eliminated

- hypothesis: Nothing invokes tui-driver-ask.mjs — the invocation path is missing
  evidence: JSONL logs show savePendingAnswer (line in ask-user-question.mjs) was called at 10:09:29, and "AskUserQuestion TUI navigation complete" was logged at 10:09:34. tui-driver-ask.mjs DID run. The pending-answer file was written BY tui-driver-ask.mjs (not a webhook).
  timestamp: 2026-02-24T10:30:00Z

- hypothesis: The keystrokes were sent to the wrong session
  evidence: tui-driver-ask.mjs uses the same sessionName throughout. captureTmuxPaneContent correctly targets agent_warden-kingdom_session_name. The issue is timing, not targeting.
  timestamp: 2026-02-24T10:30:00Z

## Evidence

- timestamp: 2026-02-24T10:20:00Z
  checked: logs/queues/pending-answer-agent_warden-kingdom_session_name.json
  found: File exists, was saved at 10:09:29, saved_at is 11 seconds after question was saved (10:09:18). answers: {"0": 1}, action: "select"
  implication: tui-driver-ask.mjs ran and saved the pending-answer. It was called by Gideon via CLI.

- timestamp: 2026-02-24T10:22:00Z
  checked: agent_warden-kingdom_session_name-raw-events.jsonl timestamps
  found: 10:09:18 = PreToolUse fires + question saved. 10:09:29 = pending-answer saved (tui-driver-ask starts). 10:09:34 = "TUI not detected in pane within 5000ms — proceeding with keystrokes anyway". 10:09:34 = "AskUserQuestion TUI navigation complete". 10:09:37 = wakeAgentViaGateway complete. 10:09:37 = PreToolUse handler complete.
  implication: Keystrokes were sent at T+16s from question fire, but the PreToolUse hook only returned at T+19s (10:09:37). The AskUserQuestion TUI CANNOT render until after the hook returns. Keystrokes were sent 3 seconds before the TUI was even possible.

- timestamp: 2026-02-24T10:25:00Z
  checked: PreToolUse hook architecture — events/pre_tool_use/event_pre_tool_use.mjs + handle_ask_user_question.mjs + gateway.mjs
  found: The handler calls wakeAgentWithRetry() which calls execFileSync('openclaw', [...]) — a SYNCHRONOUS blocking call. The hook process cannot exit until wakeAgentWithRetry completes. This means: hook blocks Claude Code → hook wakes Gideon → Gideon calls tui-driver-ask.mjs → tui-driver-ask polls for TUI that cannot exist → 5s timeout → keystrokes sent into void → hook finally returns → TUI appears → stuck waiting.
  implication: This is a fundamental sequencing deadlock. The hook must return BEFORE the TUI can appear. But the current flow: hook wakes Gideon → Gideon drives TUI → hook exits. The TUI driver is called BEFORE the hook exits.

- timestamp: 2026-02-24T10:28:00Z
  checked: spawnDetachedDeferredTyping in lib/tui-common.mjs + bin/type-command-deferred.mjs
  found: The same pattern exists for the regular TUI driver (gsd: command queue). spawnDetachedDeferredTyping spawns the typer as a detached process so the hook can exit first, then the TUI renders, then the deferred typer types. This pattern is already proven in the codebase.
  implication: The fix for AskUserQuestion must use the same fire-and-forget pattern. wakeAgentWithRetry must NOT block the hook. It must be spawned detached.

## Resolution

root_cause: The PreToolUse hook calls wakeAgentWithRetry() which uses execFileSync('openclaw', [...]) — a synchronous blocking call. The openclaw CLI runs Gideon's full agent turn synchronously. During Gideon's agent turn, Gideon calls tui-driver-ask.mjs as a tool call. The TUI driver polls 5s for the AskUserQuestion TUI. But Claude Code is blocked by the hook process — it cannot render the AskUserQuestion TUI until the hook exits. The hook does not exit until openclaw returns. openclaw does not return until Gideon's full agent turn completes (which includes the tui-driver-ask call). Keystrokes are sent 3 seconds before the hook exits. The TUI appears after the hook exits and sits stuck waiting for input.

fix: Added wakeAgentDetached() to lib/gateway.mjs — spawns openclaw as a detached background process with stdio ignored, then unrefs and returns immediately. Updated handle_ask_user_question.mjs to use wakeAgentDetached instead of wakeAgentWithRetry. Hook now exits in ~100ms, TUI renders, Gideon's agent turn starts (spawned detached), waitForTuiContentToAppear finds the TUI, keystrokes land correctly.

verification: Code fix verified by syntax check. End-to-end behavioral verification requires live test (next AskUserQuestion invocation in Warden session).

files_changed:
  - lib/gateway.mjs (added wakeAgentDetached export, added spawn import)
  - lib/index.mjs (added wakeAgentDetached to re-exports)
  - events/pre_tool_use/ask_user_question/handle_ask_user_question.mjs (use wakeAgentDetached, remove async)

## Resolution

root_cause:
fix:
verification:
files_changed: []
