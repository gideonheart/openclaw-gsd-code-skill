#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_directory="$(cd "${script_directory}/.." && pwd)"
default_registry_path="${skill_directory}/config/recovery-registry.json"

function print_usage() {
  cat <<'USAGE'
Usage:
  sync-recovery-registry-session-ids.sh [--registry <path>] [--dry-run]

Purpose:
  Refresh openclaw_session_id values in recovery registry from each agent's
  sessions/sessions.json file by selecting the most recently updated OpenAI-backed
  session key: agent:<agent_id>:openai:*
USAGE
}

function fail_with_error() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

registry_path="${default_registry_path}"
dry_run_enabled="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry)
      registry_path="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run_enabled="1"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      fail_with_error "Unknown argument: $1"
      ;;
  esac
done

if [[ ! -f "${registry_path}" ]]; then
  mkdir -p "$(dirname "${registry_path}")"
  cat > "${registry_path}" <<'JSON'
{
  "global_status_openclaw_session_id": "",
  "global_status_openclaw_session_key": "",
  "agents": []
}
JSON
  printf 'INFO: created missing empty registry: %s\n' "${registry_path}" >&2
fi

python3 - "${registry_path}" "${dry_run_enabled}" <<'PYTHON'
import json
import pathlib
import re
import sys

registry_path = pathlib.Path(sys.argv[1])
dry_run_enabled = sys.argv[2] == "1"

registry = json.loads(registry_path.read_text())
if not isinstance(registry, dict) or not isinstance(registry.get("agents"), list):
    raise SystemExit("Invalid registry format: expected object with agents array")

updated_entries = []
skipped_entries = []
bootstrapped_entries = []

agents_root_path = pathlib.Path("/home/forge/.openclaw/agents")


def select_latest_openai_session_id(agent_id: str):
    sessions_index_path = pathlib.Path(f"/home/forge/.openclaw/agents/{agent_id}/sessions/sessions.json")
    if not sessions_index_path.exists():
        return None, None, None
    try:
        sessions_index = json.loads(sessions_index_path.read_text())
    except Exception:
        return None, None, None
    if not isinstance(sessions_index, dict):
        return None, None, None

    selected_key = None
    selected_updated_at = -1
    selected_session_id = None
    pattern = re.compile(rf"^agent:{re.escape(agent_id)}:openai:")

    for session_key, session_record in sessions_index.items():
        if not pattern.match(session_key):
            continue
        if not isinstance(session_record, dict):
            continue
        session_id = session_record.get("sessionId")
        updated_at = session_record.get("updatedAt")
        if not session_id or not isinstance(updated_at, (int, float)):
            continue
        if updated_at > selected_updated_at:
            selected_updated_at = int(updated_at)
            selected_session_id = str(session_id)
            selected_key = session_key

    return selected_session_id, selected_key, selected_updated_at


# Bootstrap missing global status key/id from gideon topic:1 session if absent.
if not registry.get("global_status_openclaw_session_key"):
    gideon_index_path = pathlib.Path("/home/forge/.openclaw/agents/gideon/sessions/sessions.json")
    if gideon_index_path.exists():
        try:
            gideon_index = json.loads(gideon_index_path.read_text())
            if isinstance(gideon_index, dict):
                selected_global_key = None
                selected_global_id = None
                selected_global_updated_at = -1
                for session_key, session_record in gideon_index.items():
                    if not isinstance(session_key, str) or not session_key.startswith("agent:gideon:telegram:group:"):
                        continue
                    if not session_key.endswith(":topic:1"):
                        continue
                    if not isinstance(session_record, dict):
                        continue
                    session_id = session_record.get("sessionId")
                    updated_at = session_record.get("updatedAt")
                    if not session_id or not isinstance(updated_at, (int, float)):
                        continue
                    if updated_at > selected_global_updated_at:
                        selected_global_updated_at = int(updated_at)
                        selected_global_key = session_key
                        selected_global_id = str(session_id)
                if selected_global_key and selected_global_id:
                    registry["global_status_openclaw_session_key"] = selected_global_key
                    registry["global_status_openclaw_session_id"] = selected_global_id
                    bootstrapped_entries.append(("global", selected_global_id, selected_global_key))
        except Exception:
            pass

# Bootstrap missing agent entries from discovered /home/forge/.openclaw/agents/* directories.
existing_agent_ids = {
    entry.get("agent_id")
    for entry in registry.get("agents", [])
    if isinstance(entry, dict) and entry.get("agent_id")
}

if agents_root_path.exists():
    for agent_directory in sorted(agents_root_path.iterdir()):
        if not agent_directory.is_dir():
            continue
        agent_id = agent_directory.name
        if agent_id in {"gideon", "main"}:
            continue
        if agent_id in existing_agent_ids:
            continue

        latest_session_id, latest_session_key, latest_updated_at = select_latest_openai_session_id(agent_id)
        registry["agents"].append(
            {
                "agent_id": agent_id,
                "enabled": True,
                "auto_wake": False,
                "topic_id": 1,
                "openclaw_session_id": latest_session_id or "",
                "working_directory": "/home/forge",
                "tmux_session_name": f"{agent_id}-main",
                "claude_resume_target": "",
                "claude_launch_command": "claude --dangerously-skip-permissions",
                "claude_post_launch_mode": "resume_then_agent_pick",
            }
        )
        existing_agent_ids.add(agent_id)
        bootstrapped_entries.append((agent_id, latest_session_id or "", latest_session_key or ""))

# Optional global status session sync via explicit session key lookup.
global_status_session_key = registry.get("global_status_openclaw_session_key", "")
if isinstance(global_status_session_key, str) and global_status_session_key:
    key_parts = global_status_session_key.split(":")
    if len(key_parts) >= 2 and key_parts[0] == "agent":
        global_agent_id = key_parts[1]
        global_sessions_index_path = pathlib.Path(f"/home/forge/.openclaw/agents/{global_agent_id}/sessions/sessions.json")
        if global_sessions_index_path.exists():
            try:
                global_sessions_index = json.loads(global_sessions_index_path.read_text())
                global_record = global_sessions_index.get(global_status_session_key)
                if isinstance(global_record, dict) and global_record.get("sessionId"):
                    current_global_id = registry.get("global_status_openclaw_session_id", "")
                    new_global_id = str(global_record["sessionId"])
                    if current_global_id != new_global_id:
                        registry["global_status_openclaw_session_id"] = new_global_id
                        updated_entries.append(("global", current_global_id, new_global_id, global_status_session_key, int(global_record.get("updatedAt", 0))))
                else:
                    skipped_entries.append(("global", f"session key not found in index: {global_status_session_key}"))
            except Exception as error:
                skipped_entries.append(("global", f"failed to parse global sessions index: {error}"))
        else:
            skipped_entries.append(("global", f"global sessions index missing: {global_sessions_index_path}"))
    else:
        skipped_entries.append(("global", f"invalid global_status_openclaw_session_key: {global_status_session_key}"))

for agent_entry in registry["agents"]:
    if not isinstance(agent_entry, dict):
        continue

    agent_id = agent_entry.get("agent_id", "")
    if not agent_id:
        skipped_entries.append(("<missing-agent-id>", "missing agent_id"))
        continue

    sessions_index_path = pathlib.Path(f"/home/forge/.openclaw/agents/{agent_id}/sessions/sessions.json")
    if not sessions_index_path.exists():
        skipped_entries.append((agent_id, f"sessions index missing: {sessions_index_path}"))
        continue

    try:
        sessions_index = json.loads(sessions_index_path.read_text())
    except Exception as error:
        skipped_entries.append((agent_id, f"failed to parse sessions index: {error}"))
        continue

    if not isinstance(sessions_index, dict):
        skipped_entries.append((agent_id, "sessions index is not an object"))
        continue

    selected_key = None
    selected_updated_at = -1
    selected_session_id = None

    pattern = re.compile(rf"^agent:{re.escape(agent_id)}:openai:")

    for session_key, session_record in sessions_index.items():
        if not pattern.match(session_key):
            continue
        if not isinstance(session_record, dict):
            continue

        session_id = session_record.get("sessionId")
        updated_at = session_record.get("updatedAt")
        if not session_id or not isinstance(updated_at, (int, float)):
            continue

        if updated_at > selected_updated_at:
            selected_updated_at = int(updated_at)
            selected_session_id = str(session_id)
            selected_key = session_key

    if not selected_session_id:
        skipped_entries.append((agent_id, "no openai session entries found"))
        continue

    current_session_id = agent_entry.get("openclaw_session_id", "")
    if current_session_id != selected_session_id:
        agent_entry["openclaw_session_id"] = selected_session_id
        updated_entries.append((agent_id, current_session_id, selected_session_id, selected_key, selected_updated_at))

if bootstrapped_entries or (updated_entries and not dry_run_enabled):
    registry_path.write_text(json.dumps(registry, indent=2) + "\n")

for agent_id, openclaw_session_id, source_session_key in bootstrapped_entries:
    print(
        f"BOOTSTRAPPED agent={agent_id} openclaw_session_id={openclaw_session_id or '<empty>'} "
        f"source={source_session_key or '<none>'}"
    )

for agent_id, old_value, new_value, selected_key, selected_updated_at in updated_entries:
    print(
        f"UPDATED agent={agent_id} old={old_value or '<empty>'} new={new_value} "
        f"source={selected_key} updatedAt={selected_updated_at}"
    )

for agent_id, reason in skipped_entries:
    print(f"SKIPPED agent={agent_id} reason={reason}")

print(f"SUMMARY bootstrapped={len(bootstrapped_entries)} updated={len(updated_entries)} skipped={len(skipped_entries)} dry_run={dry_run_enabled}")
PYTHON
