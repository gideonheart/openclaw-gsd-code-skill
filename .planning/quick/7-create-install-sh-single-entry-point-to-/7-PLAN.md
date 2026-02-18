---
phase: quick-7
plan: 1
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/install.sh
autonomous: true
requirements: [INSTALL-01]

must_haves:
  truths:
    - "Running scripts/install.sh registers all 7 hooks in ~/.claude/settings.json"
    - "Running scripts/install.sh installs logrotate config at /etc/logrotate.d/gsd-code-skill"
    - "Running scripts/install.sh creates logs/ directory if missing"
    - "Running scripts/install.sh prints clear next-steps instructions"
    - "Running scripts/install.sh a second time produces the same end state (idempotent)"
  artifacts:
    - path: "scripts/install.sh"
      provides: "Single entry point installer for gsd-code-skill"
      min_lines: 60
  key_links:
    - from: "scripts/install.sh"
      to: "scripts/register-hooks.sh"
      via: "bash invocation"
      pattern: "register-hooks\\.sh"
    - from: "scripts/install.sh"
      to: "scripts/install-logrotate.sh"
      via: "bash invocation"
      pattern: "install-logrotate\\.sh"
    - from: "scripts/install.sh"
      to: "scripts/diagnose-hooks.sh"
      via: "optional bash invocation with --skip-diagnose or agent name"
      pattern: "diagnose-hooks\\.sh"
---

<objective>
Create scripts/install.sh -- a single entry point that orchestrates the full gsd-code-skill installation: hook registration, logrotate setup, log directory creation, diagnostic verification, and user-facing next-steps instructions.

Purpose: New users (or re-installs) should run ONE script instead of remembering 3-4 separate commands in the right order.
Output: scripts/install.sh (executable, idempotent)
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@scripts/register-hooks.sh
@scripts/install-logrotate.sh
@scripts/diagnose-hooks.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create scripts/install.sh orchestrator</name>
  <files>scripts/install.sh</files>
  <action>
Create scripts/install.sh that orchestrates the full installation. Follow project conventions:
- Shebang: #!/usr/bin/env bash
- set -euo pipefail
- log_message() function using printf with UTC timestamp (same pattern as other scripts)
- Derive SCRIPT_DIR and SKILL_ROOT from BASH_SOURCE (same pattern as install-logrotate.sh)

The script must execute these steps in order:

**Step 1: Pre-flight checks**
- Verify jq is installed (required by register-hooks.sh)
- Verify sudo is available (required by install-logrotate.sh)
- Print SKILL_ROOT for user orientation

**Step 2: Create logs/ directory**
- mkdir -p "${SKILL_ROOT}/logs"
- Log whether it was created or already existed

**Step 3: Register hooks**
- Run: bash "${SCRIPT_DIR}/register-hooks.sh"
- Check exit code, abort with clear error if it fails

**Step 4: Install logrotate config**
- Run: bash "${SCRIPT_DIR}/install-logrotate.sh"
- This requires sudo -- warn the user before invoking ("This step requires sudo for /etc/logrotate.d/")
- Check exit code, but do NOT abort -- log a warning and continue. Logrotate is non-critical for basic functionality.

**Step 5: Run diagnostics (optional)**
- Accept an optional first argument: agent name for diagnose-hooks.sh
- Usage line: install.sh [agent-name]
- If agent name provided: run "bash ${SCRIPT_DIR}/diagnose-hooks.sh ${AGENT_NAME}"
- If no agent name provided: skip diagnostics with an INFO log explaining why ("No agent name provided -- skipping diagnostics. Run manually: scripts/diagnose-hooks.sh <agent-name>")

**Step 6: Print next-steps banner**
After all steps complete, print a clear banner:
```
==========================================
  gsd-code-skill installation complete
==========================================

Next steps:
  1. Restart any running Claude Code sessions (hooks snapshot at startup)
  2. Register an agent in config/recovery-registry.json (see config/recovery-registry.example.json)
  3. Spawn a session:  scripts/spawn.sh <agent-name> <workdir>
  4. Verify hooks:     scripts/diagnose-hooks.sh <agent-name>
```

If logrotate step failed, append a note: "NOTE: Logrotate installation failed. Run manually: sudo scripts/install-logrotate.sh"

**Idempotency requirements:**
- mkdir -p handles existing logs/ directory
- register-hooks.sh is already idempotent (merges into settings.json)
- install-logrotate.sh is already idempotent (sudo tee overwrites)
- No state files created by install.sh itself

Make the script executable: chmod +x scripts/install.sh
  </action>
  <verify>
    Run: bash -n scripts/install.sh (syntax check passes)
    Run: file scripts/install.sh (should show "Bash script")
    Run: stat -c '%a' scripts/install.sh (should show 755 or similar executable permission)
    Verify BASH_SOURCE path derivation: grep -c 'BASH_SOURCE' scripts/install.sh (at least 1)
    Verify all 3 sub-scripts are referenced: grep -c 'register-hooks\|install-logrotate\|diagnose-hooks' scripts/install.sh (at least 3)
    Verify log_message function exists: grep -c 'log_message()' scripts/install.sh (exactly 1)
    Verify set -euo pipefail: head -3 scripts/install.sh
  </verify>
  <done>
    scripts/install.sh exists, is executable, passes bash -n syntax check, orchestrates register-hooks.sh + install-logrotate.sh + optional diagnose-hooks.sh, creates logs/ directory, prints next-steps banner, and is safe to run multiple times.
  </done>
</task>

</tasks>

<verification>
- bash -n scripts/install.sh passes (valid syntax)
- scripts/install.sh is executable
- Script references all three sub-scripts by name
- Script uses BASH_SOURCE for path derivation
- Script follows project conventions (shebang, set -euo pipefail, log_message)
- Optional agent-name argument is handled (skip diagnose when absent)
- Logrotate failure does not abort the entire install
</verification>

<success_criteria>
scripts/install.sh is a single-command installer that: registers all 7 hooks, installs logrotate, creates logs/, optionally runs diagnostics, and prints clear next-steps. Safe to run repeatedly.
</success_criteria>

<output>
After completion, create `.planning/quick/7-create-install-sh-single-entry-point-to-/7-SUMMARY.md`
</output>
