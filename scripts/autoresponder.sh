#!/usr/bin/env bash
set -euo pipefail

# Local deterministic responder for interactive GSD menus inside Claude Code TUI.
# Runs outside the model loop (no token burn).

SESSION="${1:-}"
[ -n "$SESSION" ] || { echo "usage: $0 <tmux-session>" >&2; exit 1; }

STATE_DIR="/tmp/gsd-autoresponder"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/${SESSION}.state"

log() {
  printf '[gsd-autoresponder][%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

capture() {
  tmux capture-pane -pt "$SESSION:0.0" -S -220 2>/dev/null || true
}

pane_signature() {
  sha1sum | awk '{print $1}'
}

choose_action() {
  local pane="$1"

  # Must be a selectable prompt page.
  if ! grep -q "Enter to select" <<<"$pane"; then
    return 1
  fi

  # Never auto-approve updates.
  if grep -Eqi "update from|confirm update|workflow: update|/gsd:update" <<<"$pane"; then
    echo "choice:2"
    return 0
  fi

  # If explicit recommended option appears, choose 1.
  if grep -q "(Recommended)" <<<"$pane"; then
    echo "choice:1"
    return 0
  fi

  # Prefer "You decide" to avoid checkbox/menu navigation complexity.
  if grep -Eq "^[[:space:]]*[0-9]+\.[[:space:]]+You decide" <<<"$pane"; then
    local n
    n="$(grep -En "^[[:space:]]*[0-9]+\.[[:space:]]+You decide" <<<"$pane" | tail -n1 | sed -E 's/^([0-9]+):.*$/\1/')"
    # n is line number; derive option number from line itself instead:
    local opt
    opt="$(grep -E "^[[:space:]]*[0-9]+\.[[:space:]]+You decide" <<<"$pane" | tail -n1 | sed -E 's/^[[:space:]]*([0-9]+)\..*$/\1/')"
    echo "choice:${opt}"
    return 0
  fi

  # Fallback default: first option.
  echo "choice:1"
  return 0
}

apply_action() {
  local action="$1"
  case "$action" in
    choice:*)
      local choice="${action#choice:}"
      tmux send-keys -t "$SESSION:0.0" C-u
      tmux send-keys -t "$SESSION:0.0" "$choice" Enter
      log "answered menu with option $choice"
      ;;
    *)
      return 1
      ;;
  esac
}

log "started for session=$SESSION"

last_sig=""
last_action=""

while tmux has-session -t "$SESSION" 2>/dev/null; do
  pane="$(capture)"
  [ -n "$pane" ] || { sleep 1; continue; }

  sig="$(printf '%s' "$pane" | pane_signature)"
  if [ "$sig" = "$last_sig" ]; then
    sleep 1
    continue
  fi
  last_sig="$sig"

  action="$(choose_action "$pane" || true)"
  if [ -z "$action" ]; then
    sleep 1
    continue
  fi

  # Avoid firing same action repeatedly on unchanged question text.
  question_sig="$(printf '%s\n%s' "$action" "$(printf '%s' "$pane" | tail -n 80)" | pane_signature)"
  if [ -f "$STATE_FILE" ] && grep -qx "$question_sig" "$STATE_FILE"; then
    sleep 1
    continue
  fi

  apply_action "$action" || true
  printf '%s\n' "$question_sig" > "$STATE_FILE"
  sleep 1

done

log "stopped (session ended)"
