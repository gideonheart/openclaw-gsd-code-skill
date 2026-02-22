# AskUserQuestion Verification — MISMATCH

Your answer was not submitted correctly. The details above show what you intended versus what Claude Code actually recorded.

## What happened
The TUI driver typed keys into the tmux session, but Claude Code recorded a different answer than what you intended. This can happen when:
1. **TUI cursor position was wrong** — the navigation key count was off (most common for new question layouts)
2. **Option labels shifted** — Claude Code rendered options differently than expected
3. **Timing issue** — keystroke reached tmux before the TUI was ready

## What to do
On the **next** AskUserQuestion that fires (which may be coming soon — Claude Code continues after receiving an answer):
1. If the mismatch was minor (close to correct), proceed normally with the new question
2. If the mismatch was significant (wrong answer entirely), use **"Chat about this"** on the next question to tell Claude Code: "My previous answer was wrong. I meant to select [X]. Please adjust your approach accordingly."
3. If you need to type a correction, use **"Type something"** to provide the correct direction

## Do NOT
- Do not try to re-answer the already-answered question — it is done
- Do not panic — Claude Code will ask more questions if it needs clarification
- The mismatch is logged for debugging. If it keeps happening, the TUI driver navigation counts need adjustment.
