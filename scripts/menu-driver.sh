#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  menu-driver.sh <session> <action> [args]

Actions:
  snapshot                         Print last ~180 lines from pane
  enter                            Press Enter once
  esc                              Press Esc once
  clear_then <slash-command>       Run /clear then (after short delay) run slash command
  choose <n>                       Type option number n + Enter
  type <text>                      Type literal freeform text + submit (Tab Enter)
  submit                           Move to Submit row and press Enter (tab then enter)

Notes:
- Deterministic tmux helper for GSD/Claude Code TUI menus.
- Intended to be called by the orchestrating agent after deciding what to answer.
USAGE
}

SESSION="${1:-}"
ACTION="${2:-}"
shift 2 || true

[ -n "$SESSION" ] || { usage; exit 1; }
[ -n "$ACTION" ] || { usage; exit 1; }

tmux has-session -t "$SESSION" 2>/dev/null || { echo "session not found: $SESSION" >&2; exit 1; }

case "$ACTION" in
  snapshot)
    tmux capture-pane -pt "$SESSION:0.0" -S -180
    ;;
  enter)
    tmux send-keys -t "$SESSION:0.0" Enter
    ;;
  esc)
    tmux send-keys -t "$SESSION:0.0" Escape
    ;;
  clear_then)
    cmd="${1:-}"
    [ -n "$cmd" ] || { echo "clear_then requires <slash-command>" >&2; exit 1; }
    tmux send-keys -t "$SESSION:0.0" C-u
    tmux send-keys -t "$SESSION:0.0" "/clear" Enter
    sleep 0.8
    tmux send-keys -t "$SESSION:0.0" C-u
    tmux send-keys -t "$SESSION:0.0" "$cmd" Enter
    ;;
  choose)
    n="${1:-}"
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "choose requires numeric option" >&2; exit 1; }
    tmux send-keys -t "$SESSION:0.0" C-u
    tmux send-keys -t "$SESSION:0.0" "$n" Enter
    ;;
  type)
    text="$*"
    [ -n "$text" ] || { echo "type requires text argument" >&2; usage; exit 1; }
    tmux send-keys -t "$SESSION:0.0" C-u
    tmux send-keys -t "$SESSION:0.0" -l -- "$text"
    sleep 0.1
    tmux send-keys -t "$SESSION:0.0" Tab Enter
    ;;
  submit)
    tmux send-keys -t "$SESSION:0.0" Tab Enter
    ;;
  *)
    usage
    exit 1
    ;;
esac
