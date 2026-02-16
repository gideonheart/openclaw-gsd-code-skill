#!/usr/bin/env bash
set -euo pipefail

# Watches Claude Code tmux pane for interactive menu prompts and sends a wake event.
# Agent remains decision-maker; this only wakes OpenClaw quickly.

SESSION="${1:-}"
[ -n "$SESSION" ] || exit 0

command -v tmux >/dev/null 2>&1 || exit 0
command -v openclaw >/dev/null 2>&1 || exit 0

tmux has-session -t "$SESSION" 2>/dev/null || exit 0

STATE_DIR="/tmp/gsd-hook-watcher"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/${SESSION}.lastsig"
CTX_FILE="$STATE_DIR/${SESSION}.ctxsig"

sig() { sha1sum | awk '{print $1}'; }

while tmux has-session -t "$SESSION" 2>/dev/null; do
  pane="$(tmux capture-pane -pt "$SESSION:0.0" -S -200 2>/dev/null || true)"
  [ -n "$pane" ] || { sleep 1; continue; }

  if grep -q "Enter to select" <<<"$pane"; then
    # signature from the most recent menu block to avoid duplicate wakes
    block="$(printf '%s' "$pane" | tail -n 80)"
    cur="$(printf '%s' "$block" | sig)"
    prev="$(cat "$STATE_FILE" 2>/dev/null || true)"
    if [ "$cur" != "$prev" ]; then
      printf '%s' "$cur" > "$STATE_FILE"
      # best-effort wake; never fail loop
      openclaw system event --text "GSD hook: menu prompt detected in session $SESSION; agent decision needed." --mode now >/dev/null 2>&1 || true
    fi
  fi

  # Context pressure monitor from statusline percentage (best-effort heuristic)
  pct="$(printf '%s' "$pane" | grep -Eo '[[:space:]][0-9]{1,3}%[[:space:]]' | tail -n1 | tr -dc '0-9' || true)"
  if [[ -n "$pct" ]] && [[ "$pct" =~ ^[0-9]+$ ]] && [ "$pct" -ge 50 ]; then
    csig="ctx-${pct}"
    prevc="$(cat "$CTX_FILE" 2>/dev/null || true)"
    if [ "$csig" != "$prevc" ]; then
      printf '%s' "$csig" > "$CTX_FILE"
      openclaw system event --text "GSD hook: context pressure ${pct}% in session $SESSION; agent should compact context (prefer Next area / You decide, then /clear + resume/continue when safe)." --mode now >/dev/null 2>&1 || true
    fi
  fi

  sleep 1
done
