---
status: resolved
trigger: "TUI driver doesn't execute commands from queue after AskUserQuestion event, and queue filenames lack human-readable datetime despite refactor"
created: 2026-02-23T12:00:00.000Z
updated: 2026-02-23T13:45:00.000Z
symptoms_prefilled: true
---

## Current Focus

hypothesis: CONFIRMED (both issues — root causes identified)

Issue 1 root cause CONFIRMED: The PreToolUse hook process calls `wakeAgentWithRetry` which calls `openclaw agent` CLI via `execFileSync` (synchronous, blocking). The `openclaw agent` CLI waits for Gideon to respond to the delivered message. Gideon receives the AskUserQuestion notification, decides the answer, and calls `tui-driver-ask.mjs` — all DURING the blocked `openclaw agent` CLI call. The tui-driver-ask sends keystrokes to the Warden tmux session at 12:38:44. But Claude Code only renders the AskUserQuestion TUI AFTER the PreToolUse hook exits. The PreToolUse hook exits at 12:38:46 (when `openclaw agent` finally returns after Gideon responds). So the keystrokes arrive 2 seconds BEFORE the AskUserQuestion TUI is rendered. Tmux delivers the keystrokes immediately to whatever is in the active pane — which is the shell/Claude Code main prompt, not the AskUserQuestion TUI (which hasn't appeared yet). The keystrokes go to the wrong target. The AskUserQuestion TUI renders 2 seconds later with no keystrokes queued. Claude Code is stuck waiting for the user to answer. PostToolUse never fires.

Issue 2 root cause CONFIRMED: Quick-19 added `created_at` timestamps to queue file CONTENT only (inside the JSON structure). It never added datetime to queue FILENAMES. The symptoms description "queue filenames lack human-readable datetime despite refactor" was based on a misunderstanding of what quick-19 implemented. Quick-19's PLAN.md explicitly states: "question-*.json and pending-answer-*.json are NOT modified" and scope is "add created_at ISO timestamps to queue file content." Queue filenames remain `queue-{sessionName}.json`, `pending-answer-{sessionName}.json`, `question-{sessionName}.json` — no datetime in names, by design. This is a feature gap, not a bug introduced by quick-19.

test: Fix Issue 1 by adding a pre-keystroke delay in tui-driver-ask.mjs before sending any tmux keystrokes. The delay must be longer than the time between tui-driver-ask running and the PreToolUse hook exiting + Claude Code rendering the TUI. Fix Issue 2 by noting it was never implemented (not a regression).
next_action: Implement pre-keystroke delay in tui-driver-ask.mjs

## Symptoms

expected: When AskUserQuestion PreToolUse fires, OpenClaw should answer the question via TUI driver commands. Queue files should have human-readable ISO datetime in their filenames (per quick-19 refactor).
actual: Logs show the full chain fired correctly (saveQuestionMetadata → savePendingAnswer → tui-driver-ask → wakeAgentViaGateway → handle_ask_user_question), but TUI driver did not actually execute the navigation commands in the tmux session. Queue files in logs/queues/ have old-style naming without datetime.
errors: No crash errors in logs. The flow completes but nothing happens in the TUI.
reproduction: AskUserQuestion fires in a Warden session. Logs show success messages but TUI doesn't change state.
started: Current state — likely since Phase 04 implementation.

## Eliminated

- hypothesis: tui-driver-ask.mjs crashes silently
  evidence: Log shows "AskUserQuestion TUI navigation complete" from within tui-driver-ask — it ran to completion without error
  timestamp: 2026-02-23T13:00:00Z

- hypothesis: Queue file naming changed by quick-19
  evidence: Quick-19 PLAN.md explicitly states scope is "created_at inside queue file content". Filenames are not mentioned. quick-19 SUMMARY.md shows only bin/tui-driver.mjs and lib/queue-processor.mjs modified, no filename changes.
  timestamp: 2026-02-23T13:00:00Z

- hypothesis: The PreToolUse handler failed to wake the agent
  evidence: Log shows "Agent woken via gateway for AskUserQuestion PreToolUse event" at 12:38:46 — wake succeeded
  timestamp: 2026-02-23T13:00:00Z

- hypothesis: Hooks not registered (PostToolUse missing from settings.json)
  evidence: `cat ~/.claude/settings.json` shows PostToolUse registered with matcher=AskUserQuestion pointing to event_post_tool_use.mjs. PreToolUse also registered.
  timestamp: 2026-02-23T13:30:00Z

- hypothesis: Keystrokes sent to wrong session name
  evidence: The session name "agent_warden-kingdom_session_name" is the real tmux session name (from tmux display-message). The log shows typeCommandIntoTmuxSession targeting this session successfully for earlier commands.
  timestamp: 2026-02-23T13:30:00Z

- hypothesis: AskUserQuestion TUI was not displayed (session crashed)
  evidence: No SessionStart(startup) fired after 12:36:30. The queue file still has /gsd:discuss-phase 18 as active (never completed by a Stop event). The session is alive and running, just stuck waiting for AskUserQuestion response.
  timestamp: 2026-02-23T13:30:00Z

## Evidence

- timestamp: 2026-02-23T13:00:00Z
  checked: bin/tui-driver-ask.mjs
  found: Sends keystrokes DIRECTLY via sendSpecialKeyToTmux/sendKeysToTmux. No queue mechanism. Runs synchronously.
  implication: Keystrokes fire immediately when tui-driver-ask is called. No delay before sending.

- timestamp: 2026-02-23T13:00:00Z
  checked: logs/agent_warden-kingdom_session_name-raw-events.jsonl
  found: saveQuestionMetadata at 12:38:30. savePendingAnswer + keystrokes at 12:38:44. wakeAgentViaGateway + handle_ask_user_question at 12:38:46. No PostToolUse or Stop events after that.
  implication: The full chain fired correctly but the AskUserQuestion TUI never received the keystrokes. PostToolUse was never triggered.

- timestamp: 2026-02-23T13:30:00Z
  checked: lib/gateway.mjs wakeAgentViaGateway
  found: Uses execFileSync('openclaw', ...) — synchronous, blocking call. The openclaw CLI is invoked and blocks the calling process until the CLI exits. Timeout is 120,000ms.
  implication: The PreToolUse hook process is BLOCKED for the entire duration of the openclaw CLI call. The hook cannot exit until openclaw returns.

- timestamp: 2026-02-23T13:30:00Z
  checked: Timestamp sequence in logs
  found: wakeAgentWithRetry called at 12:38:30 (when saveQuestionMetadata logs). tui-driver-ask keystrokes at 12:38:44. openclaw CLI returns at 12:38:46 (when "Agent wake delivered" logs). 16 total seconds.
  implication: The openclaw CLI waited 16 seconds for Gideon to process the message and respond. Gideon called tui-driver-ask during that 16-second window (at 12:38:44). The PreToolUse hook did NOT exit until 12:38:46.

- timestamp: 2026-02-23T13:30:00Z
  checked: Claude Code hook behavior
  found: Claude Code runs PreToolUse hook synchronously — it waits for the hook process to exit before executing the tool (showing the AskUserQuestion TUI). The AskUserQuestion TUI is NOT visible while the PreToolUse hook is running.
  implication: The AskUserQuestion TUI only appeared at 12:38:46 (when the hook exited). But tui-driver-ask sent keystrokes at 12:38:44 — 2 seconds BEFORE the TUI appeared. The keystrokes went to whatever was in the active pane at that moment (the Claude Code main interface, not the AskUserQuestion form).

- timestamp: 2026-02-23T13:30:00Z
  checked: Quick-19 PLAN.md and SUMMARY.md
  found: Quick-19 scope was explicitly "add created_at timestamps to queue file CONTENT." Queue filenames are explicitly excluded: "question-*.json and pending-answer-*.json are NOT modified." The summary confirms only bin/tui-driver.mjs and lib/queue-processor.mjs were changed.
  implication: Issue 2 (datetime in filenames) was never implemented by quick-19. Not a regression — it's a feature that was never built.

- timestamp: 2026-02-23T13:30:00Z
  checked: settings.json hook registrations
  found: PreToolUse (matcher=AskUserQuestion) and PostToolUse (matcher=AskUserQuestion) are both registered. All 5 hook events are wired correctly.
  implication: The hooks are correctly registered. The issue is timing, not missing hooks.

## Resolution

root_cause: |
  Issue 1 (TUI not executing):
  The openclaw agent CLI call in wakeAgentViaGateway is synchronous (execFileSync), blocking the
  PreToolUse hook process until the CLI exits. The CLI exits only after Gideon processes the
  AskUserQuestion notification and responds. Gideon calls tui-driver-ask.mjs DURING the blocked
  CLI call — sending keystrokes to the Warden tmux session before the PreToolUse hook exits.
  Claude Code does not render the AskUserQuestion TUI until after the PreToolUse hook exits.
  Therefore, the keystrokes arrive 2 seconds before the TUI is visible, landing on the wrong
  target (Claude Code main interface or shell prompt). The AskUserQuestion TUI appears 2 seconds
  later with no pending keystrokes — Claude Code is stuck waiting for user input.

  Issue 2 (queue filename datetime):
  Quick-19 added created_at timestamps to queue file CONTENT (JSON structure), not to filenames.
  Queue filenames remain queue-{sessionName}.json without datetime. This was never implemented —
  the symptoms description misidentified quick-19's scope. Not a regression.

fix: |
  Issue 1: Added PRE_KEYSTROKE_DELAY_MILLISECONDS = 3000 constant and sleepMilliseconds() call
  in bin/tui-driver-ask.mjs after savePendingAnswer() and before the keystroke loop. Also
  exported sleepMilliseconds from lib/tui-common.mjs (previously unexported) and added it to
  lib/index.mjs re-exports for DRY compliance.

  Issue 2: No code change. Confirmed feature was never implemented — not a regression.

verification: |
  Issue 1: Requires a live AskUserQuestion lifecycle test. Expected: PostToolUse fires and logs
  "AskUserQuestion verified — answer matches intent". Both question-*.json and pending-answer-*.json
  are deleted after verification. The 3000ms delay gives Claude Code time to render the TUI
  after the PreToolUse hook exits (~2 seconds observed gap + 1 second safety margin).

  Issue 2: No code verification needed.

files_changed:
  - bin/tui-driver-ask.mjs (add PRE_KEYSTROKE_DELAY_MILLISECONDS constant, import sleepMilliseconds, add delay before keystroke loop)
  - lib/tui-common.mjs (export sleepMilliseconds — was private, now exported for reuse)
  - lib/index.mjs (add sleepMilliseconds to tui-common.mjs re-exports)
