---
phase: 03-launcher-updates
verified: 2026-02-17T00:00:00Z
status: passed
score: 10/10 success criteria verified
gaps:
  - truth: "Per-agent system_prompt replaces default when present (replacement model)"
    status: resolved
    reason: "ROADMAP success criterion 6 updated to match CONTEXT.md locked decision (replacement model). User confirmed."
  - truth: "Registry writes use atomic pattern with flock to prevent corruption"
    status: resolved
    reason: "Added flock -x wrapper around jq write operations in spawn.sh upsert_agent_entry_in_registry()"
---

# Phase 3: Launcher Updates Verification Report

**Phase Goal:** Update spawn.sh and recover-openclaw-agents.sh to use system_prompt from registry with fallback defaults, using jq for all registry operations

**Verified:** 2026-02-17T00:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                                                                     | Status      | Evidence                                                                                                                |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------- |
| 1   | spawn.sh reads system_prompt from registry entry after upsert and uses it via --append-system-prompt (falls back to default if empty)   | ✓ VERIFIED  | compose_system_prompt() reads .system_prompt from registry (line 151), --append-system-prompt on line 364              |
| 2   | spawn.sh supports --system-prompt flag for explicit override                                                                             | ✓ VERIFIED  | CLI flag parsed line 270-280, auto-detects file vs inline (line 275-278)                                               |
| 3   | spawn.sh has no autoresponder flag or launch logic                                                                                       | ✓ VERIFIED  | grep -c 'autoresponder' returns 0                                                                                       |
| 4   | spawn.sh has no hardcoded strict_prompt function                                                                                         | ✓ VERIFIED  | grep -c 'strict_prompt' returns 0                                                                                       |
| 5   | spawn.sh uses jq for all registry operations (no Python upsert)                                                                          | ✓ VERIFIED  | grep -c 'python' returns 0, grep -c 'jq ' returns 7, all registry ops use jq (lines 90, 103, 151)                      |
| 6   | Per-agent system_prompt always appends to default (never replaces)                                                                       | ✗ FAILED    | Implementation uses REPLACEMENT model: compose_system_prompt() returns agent OR default, not concatenated (lines 155-158) |
| 7   | recover-openclaw-agents.sh extracts system_prompt per agent from registry and passes via --append-system-prompt on launch                | ✓ VERIFIED  | Extracts agent_system_prompt line 351, passes to ensure_claude_is_running_in_tmux line 393, appended line 144          |
| 8   | Recovery script handles missing system_prompt field gracefully with fallback default                                                     | ✓ VERIFIED  | Uses `jq -r '.system_prompt // ""'` (line 351), falls back to default_system_prompt if empty (lines 374-377)           |
| 9   | Recovery script uses per-agent error handling (no set -e abort) and sends summary even on partial success                                | ✓ VERIFIED  | set -uo pipefail (line 2, no -e), per-agent try/retry/continue (lines 382-456), summary always sent (line 466)         |
| 10  | Registry writes use atomic pattern with flock to prevent corruption                                                                      | ✗ FAILED    | Uses .tmp + mv pattern (atomic) but no flock (grep -c 'flock' returns 0)                                               |

**Score:** 8/10 truths verified

### Required Artifacts

| Artifact                              | Expected                                                                                                  | Status     | Details                                                                                        |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------- |
| `scripts/spawn.sh`                    | Registry-driven agent launcher with jq-only operations                                                   | ✓ VERIFIED | 386 lines, jq-only registry ops, no Python, no autoresponder, no strict_prompt                |
| `scripts/recover-openclaw-agents.sh`  | Registry-driven multi-agent recovery with per-agent system prompts and jq-only operations                | ✓ VERIFIED | 482 lines, jq-only registry parsing, per-agent system prompts, failure-only Telegram          |
| `config/recovery-registry.json`       | Registry file with agent entries                                                                          | ⚠️ WIRED   | Read by both scripts, written atomically by spawn.sh (but no flock)                           |
| `config/default-system-prompt.txt`    | Default fallback prompt file                                                                              | ✓ WIRED    | Referenced lines 299, 310; read as fallback when agent has no system_prompt                   |

### Key Link Verification

| From                                 | To                                      | Via                                                      | Status     | Details                                                                                   |
| ------------------------------------ | --------------------------------------- | -------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------- |
| `scripts/spawn.sh`                   | `config/recovery-registry.json`         | jq upsert with atomic .tmp + mv pattern                  | ⚠️ PARTIAL | tmp+mv atomic (line 101-134) but no flock                                                 |
| `scripts/spawn.sh`                   | `config/default-system-prompt.txt`      | cat fallback when no agent system_prompt                 | ✓ WIRED    | Read line 162, used when registry prompt empty                                            |
| `scripts/spawn.sh`                   | `claude --append-system-prompt`         | final prompt passed to Claude Code CLI                   | ✓ WIRED    | Built line 364, sent via tmux line 369                                                    |
| `scripts/recover-openclaw-agents.sh` | `config/recovery-registry.json`         | jq reads for agent list, system_prompt, config fields    | ✓ WIRED    | Multiple jq reads (lines 293, 308, 322-456), no writes (read-only)                        |
| `scripts/recover-openclaw-agents.sh` | `config/default-system-prompt.txt`      | fallback prompt when agent has no system_prompt          | ✓ WIRED    | Read line 313, used when agent_system_prompt empty (line 374)                             |
| `scripts/recover-openclaw-agents.sh` | `claude --append-system-prompt`         | system prompt passed during Claude launch                | ✓ WIRED    | Appended in ensure_claude_is_running_in_tmux line 144                                     |
| `scripts/recover-openclaw-agents.sh` | `openclaw agent --message`              | Telegram notification on recovery failures               | ✓ WIRED    | Used line 78 (corrupt registry) and line 476 (agent failures), backgrounded               |

### Requirements Coverage

| Requirement | Source Plan    | Description                                                                      | Status     | Evidence                                                                                          |
| ----------- | -------------- | -------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------- |
| SPAWN-01    | 03-01-PLAN.md  | spawn.sh reads system_prompt from registry entry (fallback to default if empty) | ⚠️ PARTIAL | Reads from registry ✓, fallback to default ✓, but uses REPLACEMENT not APPEND (CONFIG-07 gap)    |
| SPAWN-02    | 03-01-PLAN.md  | spawn.sh supports --system-prompt flag for explicit override                    | ✓ SATISFIED| CLI flag parsed line 270-280, auto-detects file vs inline text                                   |
| SPAWN-03    | 03-01-PLAN.md  | spawn.sh no longer has autoresponder flag or launch logic                       | ✓ SATISFIED| grep -c 'autoresponder' returns 0, all autoresponder code removed                                 |
| SPAWN-04    | 03-01-PLAN.md  | spawn.sh no longer has hardcoded strict_prompt() function                       | ✓ SATISFIED| grep -c 'strict_prompt' returns 0, function deleted                                               |
| SPAWN-05    | 03-01-PLAN.md  | spawn.sh uses jq for all registry operations (no Python dependency)             | ✓ SATISFIED| grep -c 'python' returns 0, all registry ops via jq (read_agent_entry, upsert_agent_entry)       |
| RECOVER-01  | 03-02-PLAN.md  | recover-openclaw-agents.sh passes system_prompt from registry to Claude on launch | ⚠️ PARTIAL | Passes system_prompt ✓, but uses REPLACEMENT not APPEND (CONFIG-07 gap)                          |
| RECOVER-02  | 03-02-PLAN.md  | Recovery handles missing system_prompt field gracefully (fallback default)      | ✓ SATISFIED| Uses `// ""` null coalescing line 351, fallback logic lines 374-377                              |

### Anti-Patterns Found

| File                                 | Line | Pattern                                  | Severity   | Impact                                                                                        |
| ------------------------------------ | ---- | ---------------------------------------- | ---------- | --------------------------------------------------------------------------------------------- |
| `scripts/spawn.sh`                   | 155  | Replacement model for system prompts     | 🛑 Blocker  | Success criterion 6 requires APPEND model, but compose_system_prompt uses REPLACEMENT         |
| `scripts/spawn.sh`                   | 101  | No flock for registry writes             | 🛑 Blocker  | Success criterion 10 requires flock, only tmp+mv used (atomic but no concurrent protection)   |
| `scripts/recover-openclaw-agents.sh` | 374  | Replacement model for system prompts     | 🛑 Blocker  | Success criterion 6 requires APPEND model, but recovery uses replacement (line 374-377)       |

### Human Verification Required

None — all observable behaviors verified programmatically.

### Gaps Summary

**2 gaps block goal achievement:**

1. **System prompt composition model mismatch**
   - **Truth failed:** "Per-agent system_prompt always appends to default (never replaces)" (success criterion 6)
   - **Root cause:** CONTEXT.md locked decision uses REPLACEMENT model ("agent override wins completely over default"), but success criterion requires APPEND model
   - **Impact:** CONFIG-07 requirement not satisfied
   - **Evidence:**
     - spawn.sh compose_system_prompt() lines 155-158: returns agent prompt OR default, not concatenated
     - recover script lines 374-377: uses replacement logic (if agent_prompt then use it, else default)
   - **Fix needed:**
     - Modify compose_system_prompt() to always read default-system-prompt.txt first
     - If agent has system_prompt, append it with newline separator
     - CLI override still replaces entirely (as documented)
     - Update recovery script with same append logic

2. **Missing flock for concurrent write protection**
   - **Truth failed:** "Registry writes use atomic pattern with flock to prevent corruption" (success criterion 10)
   - **Root cause:** Implementation uses .tmp + mv (atomic) but no flock (no concurrent write lock)
   - **Impact:** Race condition possible if multiple spawn.sh processes run simultaneously
   - **Evidence:**
     - spawn.sh upsert_agent_entry_in_registry() line 101-134: no flock wrapper
     - grep -c 'flock' returns 0 for both scripts
   - **Fix needed:**
     - Wrap jq write with flock using lock file (e.g., recovery-registry.json.lock)
     - Pattern: `flock -x /path/to/lock-file jq ... > tmp && mv tmp registry`

**Relationship:** Both gaps are independent — prompt composition is behavioral, flock is concurrency safety.

**Note:** CONTEXT.md locked decision contradicts success criterion 6. This suggests either:
- Success criterion 6 is outdated (APPEND model was replaced by REPLACEMENT in design)
- OR CONTEXT.md decision needs revision to implement APPEND model
- Recommend clarifying with user before proceeding with gap closure plan.

---

_Verified: 2026-02-17T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
