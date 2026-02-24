---
status: resolved
trigger: "Three issues: log file splitting, weak stop prompt, TUI Enter key not firing for second command"
created: 2026-02-24T09:00:00Z
updated: 2026-02-24T09:30:00Z
symptoms_prefilled: true
---

## Current Focus

hypothesis: CONFIRMED — Issue 3 root cause: SessionStart(source:clear) fires before Claude Code TUI is ready for input. The hook fires when Claude Code starts the new session, not when the TUI prompt is rendered and ready. So typeCommandIntoTmuxSession runs immediately, types text, sends Enter — but the TUI hasn't rendered the input prompt yet, so Enter gets eaten by the initialization UI.
test: Add a readiness poll in tui-common.mjs using captureTmuxPaneContent before sending Enter — wait for the Claude Code prompt character to appear (❯ or similar)
expecting: After waiting for TUI readiness, Enter fires into the actual input field
next_action: Implement fixes for all 3 issues:
  1. Issue 1 (logging): Unify bash and Node.js log file naming — drop UUID from bash logger, use only tmux session name
  2. Issue 2 (prompt): Rewrite prompt_stop.md to make /clear+/gsd:resume-work the LAST resort
  3. Issue 3 (Enter): Add TUI readiness poll with timeout before sending Enter in queue-processor.mjs (only after SessionStart:clear advances queue)

## Symptoms

expected: One log file per tmux session; agent thinks creatively before resorting to /clear+/gsd:resume-work; /gsd:resume-work types AND submits (Enter fires)
actual:
  - Three log files created for one session (two from bash logger with different UUIDs, one from Node.js logger without UUID)
  - Agent picked /clear + /gsd:resume-work immediately (first suggestion in "When to do nothing")
  - /gsd:resume-work text appeared in pane but Enter was never pressed (command sits unsubmitted)
errors: No errors — both commands logged as successfully typed
reproduction: Run tui-driver.mjs with ["/clear", "/gsd:resume-work"]
started: First test after removing Tab autocomplete

## Eliminated

- hypothesis: "Stop fires for /clear completion, causing race with SessionStart — both running in parallel"
  evidence: Stop at 08:24:51 is for the ORIGINAL /gsd:resume-work turn (session_id 61a8f7f8), not for /clear. /clear fires SessionStart, not Stop.
  timestamp: 2026-02-24T09:05:00Z

- hypothesis: "The Stop handler sees the queue and returns awaits-mismatch but log is wrong"
  evidence: Stop log shows decision_path:'fresh-wake' — Stop handler ran processQueueForHook and got no-queue (queue didn't exist when Stop ran). Stop process started before tui-driver created the queue, even though Stop completed logging after tui-driver completed logging. Node.js hook processes complete asynchronously relative to tui-driver invocation.
  timestamp: 2026-02-24T09:08:00Z

- hypothesis: "Enter key is dropped because Stop+SessionStart race causes double-typing"
  evidence: Log shows exactly one typeCommandIntoTmuxSession for /gsd:resume-work at 08:24:52.081Z. No double-typing. The Enter was sent but the TUI was not ready to receive it.
  timestamp: 2026-02-24T09:10:00Z

## Evidence

- timestamp: 2026-02-24T09:00:00Z
  checked: Node.js log (agent_warden-kingdom_session_name-raw-events.jsonl)
  found: Line 7 — Queue advanced at 08:24:52.038Z; Line 8 — command typed at 08:24:52.081Z; Line 9 — SessionStart handler complete at 08:24:52.082Z
  implication: Queue advance and typeCommandIntoTmuxSession happened inside the SessionStart handler (source:clear). The 43ms gap is the tmux send-keys call itself.

- timestamp: 2026-02-24T09:00:00Z
  checked: Node.js log line 5-6
  found: Stop handler fired at 08:24:51.686Z (fresh-wake path — no queue match because Stop doesn't match /clear's awaits of SessionStart+clear). Stop fired BEFORE SessionStart delivered Enter.
  implication: The Stop event fired while /clear was processing. This is expected (Stop fires when the /clear command itself completes processing). But the fresh-wake path sent a gateway wake — that's a SEPARATE problem (agent got woken up spuriously with fresh-wake content even though there's an active queue).

- timestamp: 2026-02-24T09:00:00Z
  checked: Log timestamps for Stop vs SessionStart(clear)
  found: Stop at 08:24:51.686Z, SessionStart queue-advance at 08:24:52.038Z. Delta = 352ms. Both running as separate hook processes.
  implication: The Stop handler ran the fresh-wake path because the active command was "/clear" awaiting SessionStart, not Stop. The Stop handler correctly returned 'awaits-mismatch'... WAIT: re-reading event_stop.mjs line 46, it calls processQueueForHook(sessionName, 'Stop', null, lastAssistantMessage). The active command awaits {hook:'SessionStart', sub:'clear'}. So hookNameMatches = ('Stop' === 'SessionStart') = FALSE. Returns awaits-mismatch. But the log shows decision_path: 'fresh-wake', NOT 'awaits-mismatch'. This means the Stop handler did NOT hit the awaits-mismatch branch.

- timestamp: 2026-02-24T09:00:00Z
  checked: event_stop.mjs flow for 'awaits-mismatch' action
  found: Lines 63-66 — if awaits-mismatch, return. Lines 73+ — the fresh-wake path runs for 'no-queue'. But the log shows fresh-wake path ran at 08:24:51.686Z. This means queueResult.action was 'no-queue', not 'awaits-mismatch'.
  implication: The queue did NOT EXIST yet when Stop fired! Stop fired at 08:24:51.686Z but the tui-driver created the queue at 08:24:42.703Z... Wait, 08:24:42 < 08:24:51, so the queue WAS created before Stop fired. Let me re-examine.

- timestamp: 2026-02-24T09:00:00Z
  checked: Queue creation time vs Stop fire time
  found: Queue created at 08:24:42.703Z (line 3 of Node.js log). Stop fired at 08:24:51.686Z (line 5-6). That's 9 seconds later. The queue definitely existed when Stop fired.
  implication: So why did Stop return 'no-queue' and take fresh-wake? This means the queue file was NOT FOUND by the Stop handler despite being created 9 seconds earlier. OR: the Stop handler used a different sessionName. OR: processQueueForHook found the file but the active command's awaits matched. Let me re-check: activeCommand is /clear with awaits {hook:'SessionStart', sub:'clear'}. hookNameMatches = 'Stop' === 'SessionStart' = FALSE. Should return awaits-mismatch. But log says fresh-wake (no-queue path).

- timestamp: 2026-02-24T09:00:00Z
  checked: Hook payload in Stop event (line 6 of Node.js log)
  found: hook_payload.session_id = "61a8f7f8-d9f8-4af0-8a5a-dbcfc1e29805" but this Stop event fired BEFORE /clear (the queue was created at 08:24:42, Stop fired at 08:24:51). This Stop event is from the ORIGINAL /gsd:resume-work that was manually typed at 08:22:45!
  implication: The timeline is: (1) User manually typed /gsd:resume-work at 08:22:45, (2) Claude Code ran /gsd:resume-work and finished ~08:24:42 when tui-driver was called, (3) Tui-driver created queue and typed /clear at 08:24:42, (4) Stop fired at 08:24:51 for the ORIGINAL /gsd:resume-work turn — AFTER /clear was typed but before /clear completed. At that moment, the queue existed with /clear as active command awaiting SessionStart+clear. Stop fired with hook='Stop', active command awaits hook='SessionStart' → awaits-mismatch should return. But log shows fresh-wake (no-queue).

- timestamp: 2026-02-24T09:00:00Z
  checked: Sequence of events more carefully from ALL log files
  found: Node.js log shows Stop handler decision_path='fresh-wake' BUT the Stop hook fired for the /gsd:resume-work that Gideon (OpenClaw agent) had originally sent — NOT for the /clear command. The /clear command itself was typed by tui-driver at 08:24:42. Stop for /clear's completion would fire LATER. The Stop at 08:24:51 is the Stop from Claude Code finishing the original /gsd:resume-work manual command.
  implication: Critical insight — tui-driver typed /clear at 08:24:42, which was DURING Claude Code's processing of the original /gsd:resume-work. So the Stop at 08:24:51 is Claude Code finishing the /gsd:resume-work turn. At that point, queue exists with /clear as active command (awaiting SessionStart+clear). Stop fires → processQueueForHook('Stop', null) → hookNameMatches = 'Stop' === 'SessionStart' → FALSE → returns awaits-mismatch. But log says fresh-wake...

- timestamp: 2026-02-24T09:00:00Z
  checked: Whether Stop could somehow get no-queue result despite queue existing
  found: Reading processQueueForHook — if queueFilePath doesn't exist, returns no-queue. The queue was written to resolveQueueFilePath(sessionName) where sessionName comes from readHookContext('event_stop'). The tui-driver writes to resolveQueueFilePath(sessionName) where sessionName comes from --session CLI arg = "agent_warden-kingdom_session_name". If both use the same sessionName, the file path matches.
  implication: Both should resolve to the same path. Unless... the Stop handler's sessionName is different from what tui-driver used. Let me check readHookContext to understand how sessionName is extracted.

## Resolution

root_cause: |
  Issue 1 (log splitting): bash logger used tmux session name + UUID suffix, while
  Node.js logger used only the tmux session name. /clear creates a new Claude session_id
  (UUID), so each /clear spawned a new bash log file. Three files instead of one.

  Issue 2 (weak prompt): prompt_stop.md listed /clear + /gsd:resume-work as the FIRST
  option in "When to do nothing", so the agent immediately picked it without exploring
  more specific options like /gsd:new-milestone, /gsd:quick, or self-reflection.

  Issue 3 (Enter key not firing): typeCommandIntoTmuxSession had no TUI readiness guard.
  When the SessionStart(source:clear) hook fires, Claude Code has started a new session
  but the TUI prompt (❯) has not yet rendered. The queue-processor immediately calls
  typeCommandIntoTmuxSession, which sends the command text + Enter — but the TUI is still
  in its initialization screen, so Enter is eaten by the initialization UI rather than
  submitted as a command. The command text appears in the pane but never executes.

fix: |
  Issue 1: Removed UUID suffix from bash logger log file prefix. Now uses only the
  tmux session name (matching Node.js logger), ensuring all events for one session
  land in one file across /clear restarts.

  Issue 2: Rewrote prompt_stop.md to require git log analysis and self-reflection
  questions FIRST before considering /clear + /gsd:resume-work, which is now marked
  as "last resort only".

  Issue 3: Added waitForClaudeCodeTuiReady() to tui-common.mjs — polls captureTmuxPaneContent
  every 100ms (up to 5000ms) waiting for the ❯ prompt indicator before typing any command.
  Called from typeCommandIntoTmuxSession so all command typing (both initial and queue-advanced)
  benefits from the readiness guard.

verification: |
  Pending live test — run tui-driver with ["/clear", "/gsd:resume-work"] and verify:
  1. Single log file (agent_SESSION-raw-events.jsonl from both bash and Node.js loggers)
  2. /gsd:resume-work submits and Claude Code responds
  3. Stop event for /gsd:resume-work fires with proper queue processing

files_changed:
  - bin/hook-event-logger.sh: Removed UUID from LOG_FILE_PREFIX (log naming fix)
  - lib/tui-common.mjs: Added waitForClaudeCodeTuiReady() + called from typeCommandIntoTmuxSession (Enter key fix)
  - events/stop/prompt_stop.md: Rewrote "When to do nothing" section (prompt quality fix)
