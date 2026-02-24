---
status: resolved
trigger: "Queue has 2 commands (/clear then /gsd:quick ...) but only /clear executes. Queue processing stops after the first command."
created: 2026-02-24T00:00:00Z
updated: 2026-02-24T00:05:00Z
---

## Current Focus

hypothesis: CONFIRMED — isFreshEmptyPromptVisible checks last non-blank line, but TUI has status bar below the prompt
test: Captured actual TUI pane content, traced through the detection logic
expecting: Fix by checking any line starting with prompt indicator with only whitespace after it
next_action: COMPLETE — fix applied and verified

## Symptoms

expected: Queue processor should advance through both commands. After /clear completes (which fires SessionEnd+SessionStart hooks), the SessionStart handler should detect the active queue and type the next command.
actual: Only /clear executes. The TUI shows /clear → (no content) → fresh prompt. Then nothing — the second command is never typed.
errors: No visible crash errors. Flow stops silently after /clear.
reproduction: OpenClaw agent sends a 2-command queue starting with /clear. The /clear runs but queue doesn't advance to command 2.
started: Happening now. Previous fix changed PreToolUse handler to use wakeAgentDetached instead of wakeAgentWithRetry.

## Eliminated

- hypothesis: Stop handler or processQueueForHook failed to advance the queue
  evidence: Logs show "Queue advanced to next command" at 10:54:01.515Z and "spawnDetachedDeferredTyping" spawned with PID 43408 at 10:54:01.519Z. The queue advancement worked perfectly. SessionStart also fired and the handler completed with decision "clear-queue-advanced".
  timestamp: 2026-02-24T00:03:00Z

- hypothesis: Race condition in the detached wake
  evidence: The PreToolUse change (wakeAgentDetached) is unrelated. The deferred typer PID 43408 was spawned successfully. The failure is entirely inside the deferred typer itself.
  timestamp: 2026-02-24T00:03:00Z

## Evidence

- timestamp: 2026-02-24T00:02:00Z
  checked: logs/agent_warden-kingdom_session_name-raw-events.jsonl — last 100 entries
  found: At 10:54:16.602Z, error log: "Fresh empty prompt not detected within 15000ms — command not typed". The deferred typer (PID 43408) timed out and exited with code 2.
  implication: The problem is inside isFreshEmptyPromptVisible — it never returns true even though the prompt is visible.

- timestamp: 2026-02-24T00:03:00Z
  checked: tmux capture-pane -t agent_warden-kingdom_session_name -p (actual TUI output)
  found: The TUI layout after /clear:
    Line 1: header (Claude Code v2.1.52)
    Line 5: ❯ /clear (old command)
    Line 6: ⎿  (no content)
    Line 8: ─── separator ───
    Line 9: ❯\xa0  (the FRESH PROMPT — uses non-breaking space \u00a0)
    Line 10: ─── separator ───
    Line 11: Opus 4.6 | warden.kingdom.lv
    Line 12: ⏵⏵ bypass permissions on (shift+tab to cycle) ← LAST NON-BLANK LINE
  implication: The last non-blank line is the status bar, NOT the prompt. The old isFreshEmptyPromptVisible checked lastNonBlankLine === '❯' or '❯ ' — this would NEVER match.

- timestamp: 2026-02-24T00:04:00Z
  checked: Logic test with node -e against captured pane content
  found: New logic (checking any line starting with ❯ that has only whitespace after) correctly returns true for the post-/clear pane and false for "❯ /clear" (old command) and "❯ /gsd:quick ..." (mid-typing).
  implication: Fix is correct.

## Resolution

root_cause: isFreshEmptyPromptVisible in bin/type-command-deferred.mjs checked whether the LAST non-blank line of the pane equals the prompt indicator. But the Claude Code TUI renders a separator line and status bar (model name + permissions) BELOW the prompt. The last non-blank line is always the status bar ("⏵⏵ bypass permissions on..."), never the prompt. Additionally, the prompt uses a non-breaking space (\u00a0) after ❯, not a regular space. The function therefore returned false on every poll and timed out after 15 seconds.

fix: Changed isFreshEmptyPromptVisible to use lines.some() — checking whether ANY line starts with the prompt indicator (❯) and has only whitespace (via .trim().length === 0) after it. This correctly identifies the fresh empty prompt line regardless of what appears below it in the TUI layout.

verification: Tested with node -e against the actual captured pane content. All 5 scenarios pass:
  - After /clear (fresh prompt with \xa0): true
  - During /clear processing (❯ /clear in last line): false
  - With command being typed (❯ /gsd:quick ...): false
  - Just empty prompt (regular space): true
  - Just empty prompt (no space): true

files_changed:
  - bin/type-command-deferred.mjs: Fixed isFreshEmptyPromptVisible to scan all lines instead of checking only the last non-blank line; also updated stale header comment.
