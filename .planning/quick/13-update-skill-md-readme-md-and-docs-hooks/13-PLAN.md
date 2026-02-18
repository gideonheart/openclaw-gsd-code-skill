---
phase: quick-13
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - SKILL.md
  - README.md
  - docs/hooks.md
autonomous: true
requirements: [DOC-01]

must_haves:
  truths:
    - "SKILL.md function count and registry matches actual lib/hook-utils.sh"
    - "README.md function count matches actual lib/hook-utils.sh"
    - "docs/hooks.md shared library table lists all 9 functions with correct descriptions"
    - "docs/hooks.md wake hook specs reference deliver_with_mode() for delivery"
    - "docs/hooks.md mentions JSON-safe bidirectional output via jq"
  artifacts:
    - path: "SKILL.md"
      provides: "Updated function count and registry"
      contains: "9 functions"
    - path: "README.md"
      provides: "Updated function count"
      contains: "9 functions"
    - path: "docs/hooks.md"
      provides: "Updated shared library table and delivery specs"
      contains: "deliver_with_mode"
  key_links:
    - from: "SKILL.md"
      to: "lib/hook-utils.sh"
      via: "function count and names"
      pattern: "9 functions"
    - from: "docs/hooks.md"
      to: "lib/hook-utils.sh"
      via: "shared library table"
      pattern: "deliver_with_mode"
---

<objective>
Update SKILL.md, README.md, and docs/hooks.md to reflect Quick-12 code changes.

Purpose: Documentation is stale after Quick-12 added deliver_with_mode(), fixed JSON injection, and deduplicated write_hook_event_record. Three doc files reference "6 functions" when lib/hook-utils.sh now has 9.
Output: Three updated doc files with accurate function counts, function registry, and delivery specs.
</objective>

<execution_context>
@/home/forge/.claude/get-shit-done/workflows/execute-plan.md
@/home/forge/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@SKILL.md
@README.md
@docs/hooks.md
@lib/hook-utils.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update function counts and registry in SKILL.md and README.md</name>
  <files>SKILL.md, README.md</files>
  <action>
  In SKILL.md:
  - Line 114: Change "Contains 6 functions: `lookup_agent_in_registry`, `extract_last_assistant_response`, `extract_pane_diff`, `format_ask_user_questions`, `write_hook_event_record`, `deliver_async_with_logging`. No side effects on source." to "Contains 9 functions: `lookup_agent_in_registry`, `extract_last_assistant_response`, `extract_pane_diff`, `format_ask_user_questions`, `write_hook_event_record`, `deliver_async_with_logging`, `deliver_with_mode`, `extract_hook_settings`, `detect_session_state`. No side effects on source."

  In README.md:
  - Line 534: Change "Shared library (6 functions) sourced by all hook scripts. No side effects on source." to "Shared library (9 functions) sourced by all hook scripts. No side effects on source."
  </action>
  <verify>grep -c "9 functions" SKILL.md README.md shows 1 match per file. grep "6 functions" SKILL.md README.md returns no matches.</verify>
  <done>Both files reference "9 functions" and SKILL.md lists all 9 function names.</done>
</task>

<task type="auto">
  <name>Task 2: Update shared library table and delivery specs in docs/hooks.md</name>
  <files>docs/hooks.md</files>
  <action>
  1. Update the "Shared Library" section heading area (line 361):
     - Change "lib/hook-utils.sh contains 6 functions:" to "lib/hook-utils.sh contains 9 functions:"

  2. Replace the function table (lines 363-371) with an expanded table containing all 9 functions:

     | Function | Used By | Purpose |
     |----------|---------|---------|
     | `lookup_agent_in_registry` | all hooks | Registry agent lookup by tmux session name (prefix match) |
     | `extract_last_assistant_response` | stop-hook.sh | JSONL transcript text extraction |
     | `extract_pane_diff` | stop-hook.sh | Per-session pane line delta |
     | `format_ask_user_questions` | pre-tool-use-hook.sh | AskUserQuestion data formatting |
     | `write_hook_event_record` | all hooks (via deliver_async_with_logging) | Structured JSONL record emission with 13 positional parameters; uses conditional `extra_args` array for optional `--argjson` to avoid internal duplication |
     | `deliver_async_with_logging` | all hooks | Backgrounded async delivery with JSONL logging (calls write_hook_event_record + openclaw agent) |
     | `deliver_with_mode` | stop, notification-idle, notification-permission hooks | Encapsulates bidirectional-vs-async delivery; bidirectional emits JSON-safe output via `jq -cn` (not string interpolation); async delegates to deliver_async_with_logging; exits 0 |
     | `extract_hook_settings` | stop, notification-idle, notification-permission, pre-compact hooks | Three-tier fallback settings extraction; returns compact JSON |
     | `detect_session_state` | stop, notification-idle, notification-permission, pre-compact hooks | Case-insensitive pane pattern matching; returns menu/permission_prompt/idle/error/working |

  3. In the stop-hook.sh "What It Does" section (around line 37-39), update step 12:
     - Replace the existing step 12 text with:
       "12. Deliver message via `deliver_with_mode` from `lib/hook-utils.sh`:
           - **Async mode** (default): delegates to `deliver_async_with_logging` which backgrounds `openclaw agent` call, exit immediately
           - **Bidirectional mode**: waits for OpenClaw response, writes JSONL record, parses for `decision: "block"`, emits JSON-safe output via `jq -cn --arg` (no string-interpolated JSON), returns decision to Claude Code, exits 0"

  4. In notification-idle-hook.sh "What It Does" section (around line 85-86), update step 12:
     - Replace "12. Deliver message (async or bidirectional mode)" with:
       "12. Deliver message via `deliver_with_mode` (async or bidirectional mode)"

  5. In notification-permission-hook.sh "What It Does" section (around line 109), update:
     - Replace "1-12. Identical flow to notification-idle-hook.sh, except wake message uses `type: permission_prompt`" with:
       "1-12. Identical flow to notification-idle-hook.sh, except wake message uses `type: permission_prompt`. Delivery via `deliver_with_mode`."

  6. In pre-compact-hook.sh "What It Does" section (around line 257), update step 12:
     - Replace "12. Deliver message (async or bidirectional mode)" with:
       "12. Deliver message via `deliver_with_mode` (async or bidirectional mode)"
  </action>
  <verify>grep -c "deliver_with_mode" docs/hooks.md returns at least 5 (table + 4 hook specs). grep "6 functions" docs/hooks.md returns no matches. grep "9 functions" docs/hooks.md returns 1 match.</verify>
  <done>docs/hooks.md lists all 9 functions with accurate descriptions, all 4 wake hooks reference deliver_with_mode for delivery, and bidirectional mode mentions JSON-safe jq output.</done>
</task>

</tasks>

<verification>
- grep -rn "6 functions" SKILL.md README.md docs/hooks.md returns 0 results
- grep -rn "9 functions" SKILL.md README.md docs/hooks.md returns 3 results (one per file)
- grep "deliver_with_mode" docs/hooks.md returns 5+ matches
- grep "extract_hook_settings" docs/hooks.md returns at least 1 match in function table
- grep "detect_session_state" docs/hooks.md returns at least 1 match in function table
- grep "jq -cn" docs/hooks.md returns at least 1 match (JSON-safe bidirectional output)
</verification>

<success_criteria>
All three doc files accurately reflect the current state of lib/hook-utils.sh:
- 9 functions listed by name in SKILL.md
- 9 functions referenced by count in README.md
- 9 functions in docs/hooks.md shared library table with correct "Used By" and purpose
- Wake hook delivery steps reference deliver_with_mode()
- Bidirectional mode mentions JSON-safe output via jq
</success_criteria>

<output>
After completion, create `.planning/quick/13-update-skill-md-readme-md-and-docs-hooks/13-SUMMARY.md`
</output>
