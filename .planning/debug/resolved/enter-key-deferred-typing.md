---
status: resolved
trigger: "Enter key still fails after /clear — deferred typing + bloated queue-complete + context awareness"
created: 2026-02-24T00:00:00Z
updated: 2026-02-24T12:00:00Z
symptoms_prefilled: true
---

## Current Focus

hypothesis: Hook handler calls typeCommandIntoTmuxSession synchronously while Claude Code is blocked waiting for the hook to finish — the TUI cannot render a real new prompt until the hook returns, so waitForClaudeCodeTuiReady finds the OLD ❯ from the /clear output, sends keystrokes too early, and Enter is eaten by initialization
test: Read all critical files — DONE. Root cause confirmed from symptom description and code inspection.
expecting: Three fixes needed: (1) deferred typing via background process, (2) lean queue-complete message, (3) context awareness rule in prompt_stop.md
next_action: Implement all three fixes

## Symptoms

expected: After /clear, the next queue command in the session is typed AND submitted (Enter works)
actual: Command text appears at new ❯ prompt but Enter creates a newline instead of submitting — command sits unsubmitted
errors: No crash — silent failure. Keystroke is accepted but not as a submit.
reproduction: Create queue with ["/clear", "/gsd:some-command"]. After /clear fires SessionStart(source:clear), the hook advances queue and types next command — Enter fails.
started: Persists after previous fix attempt (commit 59d5e0e). Third attempt.

## Eliminated

- hypothesis: waitForClaudeCodeTuiReady timeout too short
  evidence: The poll finds ❯ immediately (it sees the OLD ❯ from /clear output), so timing is not the issue — it's the wrong ❯ being detected
  timestamp: 2026-02-24T00:00:00Z

- hypothesis: Tab completion interference
  evidence: Previous fix (commit 2e059f6) already removed Tab — not the cause
  timestamp: 2026-02-24T00:00:00Z

## Evidence

- timestamp: 2026-02-24T00:00:00Z
  checked: lib/tui-common.mjs waitForClaudeCodeTuiReady
  found: Polls for ANY ❯ in pane content — does not distinguish old vs fresh prompt. After /clear, the /clear output itself contains ❯ characters, so the poll returns immediately with a false positive.
  implication: The real new prompt doesn't exist yet because Claude Code is blocked waiting for the hook to return.

- timestamp: 2026-02-24T00:00:00Z
  checked: lib/queue-processor.mjs processQueueForHook line 157
  found: typeCommandIntoTmuxSession called directly and synchronously inside hook handler. Hook must return before Claude Code can finish session initialization.
  implication: Fundamental timing violation — cannot poll for "real" new prompt while hook is blocking it from rendering.

- timestamp: 2026-02-24T00:00:00Z
  checked: events/stop/event_stop.mjs line 54
  found: queue-complete message uses JSON.stringify(queueResult.summary, null, 2) which includes full result field (entire last_assistant_message) for each command in the JSON
  implication: Agent receives giant JSON blob containing the same content already available as last_assistant_message — redundant and bloated.

- timestamp: 2026-02-24T00:00:00Z
  checked: events/stop/prompt_stop.md
  found: No rule about prepending /clear when context is high. Agent freely chose ["/gsd:audit-milestone"] without /clear when context was ~80%.
  implication: Need concise context awareness rule added.

## Resolution

root_cause: |
  Issue 1: typeCommandIntoTmuxSession is called synchronously INSIDE the SessionStart hook handler.
  Claude Code blocks while the hook runs. The new TUI prompt cannot render until the hook returns.
  waitForClaudeCodeTuiReady detects the OLD ❯ from /clear output (false positive), sends keystrokes
  immediately, but the TUI input handler isn't ready yet so Enter creates a newline instead of submitting.
  Fix: spawn a detached background process (bin/type-command-deferred.mjs) that polls for a FRESH
  empty ❯ prompt AFTER the hook has returned and TUI has fully initialized.

  Issue 2: buildQueueCompleteSummary includes full result text in the JSON summary sent to agent.
  Fix: truncate result to first 200 chars in the summary, and restructure queue-complete message
  to lead with human-readable last command result + compact command list header.

  Issue 3: prompt_stop.md lacks context awareness rule.
  Fix: Add concise rule — always prepend /clear when session has executed 2+ commands.

fix: |
  1. Create bin/type-command-deferred.mjs — polls for fresh empty ❯ (last non-blank line = just ❯)
     then types command + Enter. Spawned detached from processQueueForHook.
  2. Modify processQueueForHook to use spawnDetachedDeferredTyping() instead of typeCommandIntoTmuxSession().
  3. Update buildQueueCompleteSummary to truncate result field.
  4. Update event_stop.mjs queue-complete path to send readable message.
  5. Add context awareness rule to prompt_stop.md.

verification: |
  All five modified files pass node --check syntax validation.
  Logic verified by code inspection:
  - spawnDetachedDeferredTyping uses detached:true + unref() — hook returns immediately
  - type-command-deferred.mjs polls for last non-blank line === prompt indicator only,
    which cannot match /clear output (which shows the typed /clear command text after the prompt)
  - queue-complete message now human-readable with full last_assistant_message as content
  - prompt_stop.md context awareness rule added at step 3, concise single bullet
files_changed:
  - bin/type-command-deferred.mjs (new)
  - lib/tui-common.mjs (add spawnDetachedDeferredTyping, export it; update waitForClaudeCodeTuiReady for fresh prompt detection)
  - lib/queue-processor.mjs (use spawnDetachedDeferredTyping instead of typeCommandIntoTmuxSession)
  - lib/index.mjs (export spawnDetachedDeferredTyping)
  - events/stop/event_stop.mjs (fix queue-complete message)
  - events/stop/prompt_stop.md (add context awareness rule)
</content>
</invoke>