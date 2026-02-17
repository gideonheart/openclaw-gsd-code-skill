# Phase 2: Hook Wiring - Research

**Researched:** 2026-02-17
**Domain:** Claude Code settings.json hook configuration, hook event lifecycle, matcher patterns
**Confidence:** HIGH

## Summary

Phase 2 wires the 5 hook scripts created in Phase 1 into Claude Code's native hook system by registering them in `~/.claude/settings.json`. The goal is pure configuration — no new scripts, no launcher changes, just connecting existing hook scripts to their corresponding lifecycle events. This enables event-driven agent control and replaces the obsolete SessionStart-based hook-watcher polling system.

The core technical challenge is understanding Claude Code's hook configuration schema and ensuring proper registration of all 5 events: Stop, Notification (with two matchers: idle_prompt and permission_prompt), SessionEnd, and PreCompact. Each hook type has different matcher support, timeout requirements, and async behavior. The research confirms that hooks snapshot at session startup, meaning settings.json changes require new sessions to take effect — allowing for a brief overlap period where old sessions continue using hook-watcher while new sessions use native hooks.

**Primary recommendation:** Create an idempotent registration script (register-hooks.sh) that builds the complete hooks configuration object and uses jq to merge it into settings.json, preserving existing hooks like gsd-check-update.js while removing the obsolete gsd-session-hook.sh. All hooks should use absolute paths, appropriate timeout values (600s for Stop/Notification/PreCompact, default for SessionEnd), and async:false for synchronous execution except where bidirectional mode requires blocking.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**SessionEnd scope:**
- Fire on ALL exit reasons (logout, /clear, prompt_input_exit, other) — no matcher filtering
- OpenClaw agent decides relevance based on the `reason` field in stdin JSON
- Use the same `/hooks/wake` webhook with a `session_end` trigger type

**SessionStart cleanup:**
- Keep `gsd-check-update.js` in SessionStart hooks array — only remove `gsd-session-hook.sh`
- No new SessionStart hook registration in this phase — scope is wiring the 5 Phase 1 hooks only

### Claude's Discretion

- **PreCompact trigger scope** — Claude decides whether to match auto-only, manual-only, or both (recommendation: both, synchronous)
- **Stop hook blocking behavior** — Claude decides whether bidirectional agents use the blocking mechanism (decision:block) or fire-and-forget (recommendation: blocking for bidirectional, async for default)
- **Hook registration approach** — Claude decides whether to create a registration script or directly edit settings.json in plan tasks (recommendation: registration script for idempotency/portability)
- **Hook async/timeout configuration** — Claude decides appropriate timeout values and async flags per hook type
- **Notification hook matchers** — Claude decides exact matcher values (idle_prompt, permission_prompt)

### Deferred Ideas (OUT OF SCOPE)

- SessionStart context injection (inject agent identity/state on startup) — could be a future enhancement
- Hook health monitoring / observability — v2 requirements (OBS-01, OBS-02)

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONFIG-03 | settings.json has all hooks registered (Stop, Notification, SessionEnd, PreCompact), gsd-session-hook.sh removed from SessionStart | Official Claude Code hooks reference confirms JSON schema structure, matcher patterns, and event lifecycle |

</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| jq | 1.7+ | JSON manipulation for settings.json | Already used in Phase 1 for registry operations, atomic update capability |
| bash | 4.0+ | Hook registration script | Universal on Linux/macOS, existing skill standard |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Claude Code | current (2026) | Hook system runtime | Required — hosts the hooks being configured |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Registration script | Manual editing | Script provides idempotency, validation, and atomic updates; manual editing risks syntax errors and loses backup capability |
| jq merge | Python/Node.js JSON library | jq is already required by Phase 1, zero additional dependencies |

**Installation:**

No new dependencies — jq and bash are already required by Phase 1.

## Architecture Patterns

### Recommended Hook Configuration Structure

The settings.json hooks object uses a three-level nested structure:

```json
{
  "hooks": {
    "EventName": [
      {
        "matcher": "pattern",  // Optional, event-specific
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/script.sh",
            "async": false,      // Optional, default false
            "timeout": 600       // Optional, default 600s
          }
        ]
      }
    ]
  }
}
```

**Key structural rules:**
- Top level: `hooks` object with event names as keys
- Event level: Array of matcher groups (each with optional `matcher` field)
- Matcher group level: `hooks` array containing handler objects
- Handler level: `type`, `command`, optional `async`, optional `timeout`

### Pattern 1: Stop Hook Registration

**What:** Registers the stop-hook.sh to fire when Claude finishes responding

**When to use:** Primary event for agent wake messages after responses

**Example:**
```json
// Source: Official Claude Code hooks reference
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/stop-hook.sh",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

**Critical details:**
- Stop does NOT support matchers — always fires on every occurrence
- Hook scripts receive `stop_hook_active: true` in stdin JSON when already continuing from a previous hook
- Exit code 0 with no JSON = allow stop; JSON with `decision: "block"` + `reason` = continue working
- Default async: false (synchronous execution)

### Pattern 2: Notification Hook Registration (Multiple Matchers)

**What:** Registers notification hooks with different matchers for idle_prompt and permission_prompt events

**When to use:** Need separate notification handling for different prompt types

**Example:**
```json
// Source: Official Claude Code hooks reference
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-idle-hook.sh",
            "timeout": 600
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-permission-hook.sh",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

**Critical details:**
- Notification event supports matchers: `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`
- Matchers use regex — exact match or omit for all notifications
- Multiple matcher groups in same event array = run different handlers per type
- Notification hooks cannot block or modify notifications (observation-only)

### Pattern 3: SessionEnd Hook Registration (No Matcher)

**What:** Registers session-end-hook.sh to fire on all session terminations

**When to use:** Need to notify OpenClaw agent when session ends, regardless of reason

**Example:**
```json
// Source: Official Claude Code hooks reference
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/session-end-hook.sh"
          }
        ]
      }
    ]
  }
}
```

**Critical details:**
- SessionEnd supports matchers (`clear`, `logout`, `prompt_input_exit`, `bypass_permissions_disabled`, `other`) but user constraint specifies no filtering
- Omitting matcher = fires on all exit reasons
- Hook receives `reason` field in stdin JSON (OpenClaw agent decides relevance)
- SessionEnd hooks have no decision control — cannot prevent termination
- Default timeout sufficient (no long-running operations)

### Pattern 4: PreCompact Hook Registration

**What:** Registers pre-compact-hook.sh to capture state before context compaction

**When to use:** Agent needs visibility into compaction events for context preservation decisions

**Example:**
```json
// Source: Official Claude Code hooks reference
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "auto|manual",
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/pre-compact-hook.sh",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

**Critical details:**
- PreCompact supports matchers: `manual` (user typed `/compact`) or `auto` (context window full)
- Recommendation: match both with `auto|manual` regex or omit matcher entirely
- Hook receives `trigger` and `custom_instructions` in stdin JSON
- Cannot block compaction but can inject context before it happens
- Use synchronous execution (async: false) to ensure hook completes before compaction

### Pattern 5: SessionStart Cleanup (Remove Obsolete Hook)

**What:** Remove gsd-session-hook.sh while preserving gsd-check-update.js

**When to use:** Migrating from polling to native hooks

**Example:**
```json
// Source: Existing ~/.claude/settings.json
// BEFORE:
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"/home/forge/.claude/hooks/gsd-check-update.js\""
          },
          {
            "type": "command",
            "command": "bash \"/home/forge/.claude/hooks/gsd-session-hook.sh\""
          }
        ]
      }
    ]
  }
}

// AFTER:
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"/home/forge/.claude/hooks/gsd-check-update.js\""
          }
        ]
      }
    ]
  }
}
```

**Critical details:**
- Use jq to filter hooks array: `del(.hooks.SessionStart[].hooks[] | select(.command | contains("gsd-session-hook.sh")))`
- Preserve all other SessionStart hooks unchanged
- Atomic file update: read → modify → write to temp → move to original

### Pattern 6: Idempotent Hook Registration Script

**What:** Script that safely merges hook configuration without duplicating entries

**When to use:** Automated deployment, recovery scenarios, manual re-runs

**Structure:**
```bash
#!/usr/bin/env bash
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
BACKUP_FILE="$SETTINGS_FILE.backup-$(date +%s)"

# 1. Backup existing settings
cp "$SETTINGS_FILE" "$BACKUP_FILE"

# 2. Build target configuration
TARGET_HOOKS=$(cat <<'EOF'
{
  "Stop": [...],
  "Notification": [...],
  "SessionEnd": [...],
  "PreCompact": [...]
}
EOF
)

# 3. Merge with jq (preserves other hooks, replaces matching events)
jq --argjson new "$TARGET_HOOKS" '
  .hooks = (.hooks // {}) |
  .hooks.Stop = $new.Stop |
  .hooks.Notification = $new.Notification |
  .hooks.SessionEnd = $new.SessionEnd |
  .hooks.PreCompact = $new.PreCompact |
  .hooks.SessionStart[].hooks |= map(select(.command | contains("gsd-session-hook.sh") | not))
' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"

# 4. Atomic replace
mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

echo "Hooks registered. Backup: $BACKUP_FILE"
echo "IMPORTANT: Restart Claude Code sessions to activate new hooks."
```

### Anti-Patterns to Avoid

- **Manual JSON editing:** Easy to introduce syntax errors; use jq for atomic updates
- **Relative paths in hook commands:** Hooks run in current working directory; always use absolute paths
- **Async hooks expecting decision control:** `async: true` means hook runs in background, cannot block or control behavior
- **Duplicate hook registration:** Use idempotent merge pattern to avoid multiple entries for same hook
- **Forgetting matcher requirements:** Stop, UserPromptSubmit, TeammateIdle, TaskCompleted do NOT support matchers; adding them has no effect
- **Assuming immediate activation:** Hooks snapshot at session startup; changes require session restart

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing and merging | sed/awk text manipulation | jq with --argjson and merge operators | JSON is not line-based; text tools break on whitespace variations, nested structures, and escape sequences |
| Settings backup | cp without timestamp | cp with $(date +%s) suffix | Prevents accidental overwrites during testing/rollback |
| Hook deduplication | Loop-based array filtering | jq select filter with negation | jq handles JSON arrays natively, bash loops risk quoting/escaping bugs |
| Configuration validation | Manual checks | jq parse test + schema validation | Catch syntax errors before writing to settings.json |

**Key insight:** Claude Code's hook system has specific schema requirements (nested arrays, matcher regex, timeout numbers). Any text manipulation that doesn't parse JSON structurally will break on edge cases. jq is mandatory for reliability.

## Common Pitfalls

### Pitfall 1: Hooks Not Firing After Registration

**What goes wrong:** Settings.json updated correctly but hooks don't execute in active Claude Code sessions

**Why it happens:** Claude Code snapshots hook configuration at session startup and doesn't reload settings.json during the session

**How to avoid:** Document clearly that settings.json changes require session restart. Include verification step: "Start new Claude Code session and check Stop hook fires"

**Warning signs:** Hook scripts have correct permissions and registry entries, but OpenClaw agent receives no wake messages

### Pitfall 2: Incorrect Matcher Syntax Breaking Hook Registration

**What goes wrong:** Hook registered with invalid matcher pattern causes hook to never fire or fires on wrong events

**Why it happens:** Matchers are regex patterns but event-specific values are documented separately. Using `idle` instead of `idle_prompt` for Notification matcher silently fails

**How to avoid:** Use exact matcher values from official documentation. For Notification: `idle_prompt`, `permission_prompt`, `auth_success`, `elicitation_dialog`. Test with `/hooks` menu to verify matcher is recognized

**Warning signs:** Hook appears in settings.json but never executes, or fires on unexpected event types

### Pitfall 3: Path Escaping in JSON Command Strings

**What goes wrong:** Paths with spaces or special characters break command execution

**Why it happens:** JSON requires backslash-escaped quotes, but bash also interprets backslashes. Double-escaping confusion leads to malformed commands

**How to avoid:**
- Use absolute paths without spaces when possible
- For paths with spaces, use JSON string escaping: `"command": "bash \"/path/with spaces/script.sh\""`
- Do NOT double-escape in jq heredocs — jq handles JSON escaping automatically

**Warning signs:** Hook command shows in Claude Code debug output with mangled path, script not found errors

### Pitfall 4: Async Flag Misunderstanding

**What goes wrong:** Hook marked `async: true` but planner expects it to block or return decision

**Why it happens:** Async hooks run in background and cannot control Claude's behavior. Decision fields like `decision: "block"` are ignored because action already proceeded

**How to avoid:** Use `async: false` (or omit field) for all hooks that need decision control. Only use `async: true` for logging, metrics, or side effects where result doesn't affect Claude

**Warning signs:** Hook executes but decision field ignored, Claude continues when hook expected to block

### Pitfall 5: Timeout Too Short for Hybrid Mode

**What goes wrong:** Hook times out before OpenClaw agent responds in bidirectional mode

**Why it happens:** Default timeout is 600s (10 min), but network latency + agent processing + LLM inference can exceed this in edge cases

**How to avoid:**
- Keep default 600s timeout for synchronous hooks (sufficient for 99% of cases)
- For async hooks performing external API calls, increase timeout to match expected max latency
- Document timeout value in hook registration script comments

**Warning signs:** Hook logs show timeout errors, bidirectional mode falls back to async behavior

### Pitfall 6: SessionStart Hook Removal Too Aggressive

**What goes wrong:** Removing all SessionStart hooks instead of just gsd-session-hook.sh breaks gsd-check-update.js

**Why it happens:** jq filter deletes entire SessionStart array instead of filtering specific hook

**How to avoid:** Use precise jq select filter: `select(.command | contains("gsd-session-hook.sh") | not)` to keep other hooks

**Warning signs:** Update checker stops working, no version notifications

## Hook Event Lifecycle

Understanding when hooks fire relative to Claude Code's execution flow:

```
Session Start
    ├─> SessionStart hooks (on startup, resume, clear, compact)
    │
    └─> Agentic Loop
        ├─> UserPromptSubmit (before processing user input)
        │
        ├─> Tool Execution
        │   ├─> PreToolUse (before tool call)
        │   ├─> PermissionRequest (if permission needed)
        │   ├─> PostToolUse (after success)
        │   └─> PostToolUseFailure (after failure)
        │
        ├─> Notification (idle_prompt, permission_prompt, etc.)
        │
        └─> Stop (when Claude finishes responding)
            └─> Loop continues or exits

PreCompact (before context compaction)
    ├─> auto (context window full)
    └─> manual (user typed /compact)

Session End
    ├─> clear (/clear command)
    ├─> logout (user logged out)
    ├─> prompt_input_exit (exit while prompt visible)
    └─> other (all other reasons)
```

**Phase 2 hooks coverage:**
- Stop: After Claude's response (agentic loop)
- Notification (idle_prompt): When Claude waits for input
- Notification (permission_prompt): When permission dialog appears
- SessionEnd: On all termination reasons
- PreCompact: Before context window compaction

## Code Examples

### Complete Hook Registration Configuration

```json
// Source: Official Claude Code hooks reference + Phase 1 implementation
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"/home/forge/.claude/hooks/gsd-check-update.js\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/stop-hook.sh",
            "timeout": 600
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-idle-hook.sh",
            "timeout": 600
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/notification-permission-hook.sh",
            "timeout": 600
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/session-end-hook.sh"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/forge/.openclaw/workspace/skills/gsd-code-skill/scripts/pre-compact-hook.sh",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

### Idempotent Hook Registration with jq

```bash
#!/usr/bin/env bash
# Source: Best practices from Phase 1 research (atomic updates, backup strategy)
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
SKILL_ROOT="/home/forge/.openclaw/workspace/skills/gsd-code-skill"

# Backup with timestamp
BACKUP_FILE="${SETTINGS_FILE}.backup-$(date +%s)"
cp "$SETTINGS_FILE" "$BACKUP_FILE"
echo "Backed up settings.json to: $BACKUP_FILE"

# Build complete hook configuration
HOOKS_CONFIG=$(cat <<EOF
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/stop-hook.sh",
          "timeout": 600
        }
      ]
    }
  ],
  "Notification": [
    {
      "matcher": "idle_prompt",
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/notification-idle-hook.sh",
          "timeout": 600
        }
      ]
    },
    {
      "matcher": "permission_prompt",
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/notification-permission-hook.sh",
          "timeout": 600
        }
      ]
    }
  ],
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/session-end-hook.sh"
        }
      ]
    }
  ],
  "PreCompact": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${SKILL_ROOT}/scripts/pre-compact-hook.sh",
          "timeout": 600
        }
      ]
    }
  ]
}
EOF
)

# Merge with jq: replace target hooks, remove gsd-session-hook.sh, preserve others
jq --argjson new "$HOOKS_CONFIG" '
  # Ensure hooks object exists
  .hooks = (.hooks // {}) |

  # Replace target hook events
  .hooks.Stop = $new.Stop |
  .hooks.Notification = $new.Notification |
  .hooks.SessionEnd = $new.SessionEnd |
  .hooks.PreCompact = $new.PreCompact |

  # Clean up SessionStart: remove gsd-session-hook.sh, keep others
  .hooks.SessionStart[].hooks |= map(
    select(.command | contains("gsd-session-hook.sh") | not)
  )
' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"

# Validate JSON syntax
if ! jq empty "${SETTINGS_FILE}.tmp" 2>/dev/null; then
  echo "ERROR: Generated invalid JSON. Settings unchanged." >&2
  rm "${SETTINGS_FILE}.tmp"
  exit 1
fi

# Atomic replace
mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"

echo "✓ Hooks registered in ~/.claude/settings.json"
echo "✓ Removed gsd-session-hook.sh from SessionStart hooks"
echo ""
echo "IMPORTANT: Restart all Claude Code sessions to activate new hooks."
echo "Existing sessions will continue using hook-watcher.sh until restarted."
```

### Verification: Check Hook Registration

```bash
#!/usr/bin/env bash
# Source: Verification pattern for settings.json updates
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

echo "=== Registered Hooks ==="
echo ""

echo "Stop hooks:"
jq -r '.hooks.Stop[]?.hooks[]?.command // "NOT REGISTERED"' "$SETTINGS_FILE"
echo ""

echo "Notification hooks (idle_prompt):"
jq -r '.hooks.Notification[] | select(.matcher == "idle_prompt") | .hooks[].command // "NOT REGISTERED"' "$SETTINGS_FILE"
echo ""

echo "Notification hooks (permission_prompt):"
jq -r '.hooks.Notification[] | select(.matcher == "permission_prompt") | .hooks[].command // "NOT REGISTERED"' "$SETTINGS_FILE"
echo ""

echo "SessionEnd hooks:"
jq -r '.hooks.SessionEnd[]?.hooks[]?.command // "NOT REGISTERED"' "$SETTINGS_FILE"
echo ""

echo "PreCompact hooks:"
jq -r '.hooks.PreCompact[]?.hooks[]?.command // "NOT REGISTERED"' "$SETTINGS_FILE"
echo ""

echo "SessionStart hooks (should NOT include gsd-session-hook.sh):"
jq -r '.hooks.SessionStart[]?.hooks[]?.command // "NONE"' "$SETTINGS_FILE"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SessionStart hook spawning hook-watcher.sh for polling | Native Stop/Notification/SessionEnd/PreCompact hooks | Phase 2 (2026-02-17) | Event-driven replaces polling, lower latency, more precise state detection |
| Python upsert for registry manipulation | jq-only operations | Phase 1 (2026-02-17) | Zero Python dependency, better portability |
| Hardcoded system prompts in spawn.sh | Registry-based system_prompt field | Phase 3 (planned) | Per-agent customization, no code changes for prompt updates |

**Deprecated/outdated:**
- **gsd-session-hook.sh:** Launched hook-watcher.sh on SessionStart — replaced by native hook events, removed in Phase 2
- **Autoresponder polling:** Replaced by Stop and Notification hooks, deleted in Phase 4
- **Manual hook registration:** `/hooks` menu introduced in Claude Code (2026), but registration script preferred for automation

## Open Questions

1. **PreCompact matcher scope: auto-only, manual-only, or both?**
   - What we know: PreCompact supports matchers `auto` (context window full) and `manual` (/compact command)
   - What's unclear: Whether capturing state on both is operationally useful or creates noise
   - Recommendation: Omit matcher (match both) — agent receives `trigger` field in stdin and can decide relevance. No downside to visibility.

2. **Timeout values: use defaults or increase for network latency?**
   - What we know: Default timeout is 600s (10 min), sufficient for local processing
   - What's unclear: Whether OpenClaw agent response in bidirectional mode could exceed 600s under load
   - Recommendation: Keep 600s timeout for now (same as Phase 1 hook scripts). If timeouts occur in production, increase to 900s per hook.

3. **Registration script location: scripts/ or config/?**
   - What we know: Hook scripts live in scripts/, config files in config/
   - What's unclear: Whether registration script is "executable utility" (scripts/) or "configuration template" (config/)
   - Recommendation: scripts/register-hooks.sh — it's an executable operation, not static config. Follows existing pattern (spawn.sh, menu-driver.sh in scripts/).

## Configuration Decision Matrix

For Claude's discretion areas:

| Decision Area | Recommendation | Rationale |
|---------------|----------------|-----------|
| **Hook registration approach** | Registration script (scripts/register-hooks.sh) | Idempotent, atomic updates, backup creation, validation — safer than direct editing |
| **PreCompact matcher** | Omit (match both auto and manual) | Agent receives `trigger` field in stdin, can filter if needed. No cost to extra visibility. |
| **Stop hook async** | `async: false` (synchronous) | Bidirectional mode requires waiting for OpenClaw response. Default agents use async via script logic (background openclaw call), not hook config. |
| **Notification matchers** | Exact: `idle_prompt`, `permission_prompt` | Official documented values, tested in Phase 1 |
| **Hook timeouts** | 600s for Stop/Notification/PreCompact, default for SessionEnd | Matches Phase 1 hook script design, allows for network latency + agent processing |
| **SessionStart cleanup method** | jq select filter with negation | Preserves gsd-check-update.js, atomic operation, testable |

## Sources

### Primary (HIGH confidence)

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - Official documentation for all 14 hook events, JSON schema, matchers, async support, stdin/stdout format
- Phase 1 hook scripts (stop-hook.sh, notification-idle-hook.sh, notification-permission-hook.sh, session-end-hook.sh, pre-compact-hook.sh) - Verified implementation in codebase
- ~/.claude/settings.json - Current production configuration with SessionStart hooks array

### Secondary (MEDIUM confidence)

- [Hooks reference - Claude Docs](https://docs.claude.com/en/docs/claude-code/hooks) - Alternative official source (same content as code.claude.com)
- [Claude Code power user customization: How to configure hooks | Claude](https://claude.com/blog/how-to-configure-hooks) - Blog post with configuration examples
- Phase 1 RESEARCH.md - Prior research on hook system, verified against official docs

### Tertiary (LOW confidence)

- [Claude Code Hooks: Production Patterns Nobody Talks About](https://www.marc0.dev/en/blog/claude-code-hooks-production-patterns-async-setup-guide-1770480024093) - Community patterns, marked for validation
- [GitHub - disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) - Community examples, not official

## Metadata

**Confidence breakdown:**
- Hook configuration schema: HIGH - Verified via official Claude Code hooks reference documentation
- Matcher patterns: HIGH - Official docs list exact values per event type, cross-referenced with Phase 1 implementation
- Registration approach: HIGH - jq merge pattern verified, atomic update strategy proven in Phase 1
- Timeout/async behavior: MEDIUM - Defaults documented but real-world network latency under load uncertain

**Research date:** 2026-02-17
**Valid until:** 30 days (hook system is stable, unlikely to change)
