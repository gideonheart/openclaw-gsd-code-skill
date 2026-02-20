# Roadmap: gsd-code-skill

## Overview

v4.0 rewrites the hook system from scratch with an event-folder architecture. Five phases deliver this in dependency order: delete the old code first (clean slate), build the shared lib foundation, wire up the Stop event with all three files (handler + prompt + TUI driver) and validate end-to-end, do the same for AskUserQuestion lifecycle, then register everything and document. Each event phase delivers a testable, complete capability before moving to the next.

## Milestones

- [x] v1.0 Hook-Driven Agent Control (shipped 2026-02-17)
- [x] v2.0 Smart Hook Delivery (shipped 2026-02-18)
- [x] v3.0 Structured Hook Observability (shipped 2026-02-18)
- [x] v3.1 Hook Refactoring and Migration (shipped 2026-02-18)
- [x] v3.2 Per-Hook TUI Instruction Prompts (shipped 2026-02-19)
- [ ] **v4.0 Event-Driven Hook Architecture** (Phases 1-5, in progress)

---

## v4.0 Phases

### Phase Checklist

- [ ] **Phase 1: Cleanup** - Delete all v1-v3 hook scripts, old lib, old prompts, dead docs, rename registry
- [x] **Phase 2: Shared Library** - Build the Node.js shared lib with agent resolution, gateway delivery, and JSON extraction
- [ ] **Phase 02.1: Refactor (lib review)** - Fix retry defaults, logger error handling, shared SKILL_ROOT
- [ ] **Phase 3: Stop Event (Full Stack)** - Build event folder, handler, prompt, and TUI driver for Stop — test end-to-end
- [ ] **Phase 4: AskUserQuestion Lifecycle (Full Stack)** - PreToolUse and PostToolUse handlers, prompts, and TUI driver — test end-to-end
- [ ] **Phase 5: Registration and Documentation** - Register all handlers in settings.json, update install.sh, SKILL.md, README.md

## Phase Details

### Phase 1: Cleanup
**Goal**: The repository contains zero v1-v3 artifacts — old hook scripts, old lib files, old prompt directories, dead documentation, and monolithic menu-driver.sh are gone; agent-registry.json replaces recovery-registry.json in config and .gitignore
**Depends on**: Nothing (first phase)
**Requirements**: CLEAN-01, CLEAN-02, CLEAN-03, CLEAN-04, CLEAN-05, CLEAN-08
**Success Criteria** (what must be TRUE):
  1. None of the seven old hook bash scripts exist anywhere in the scripts/ directory
  2. The old lib/hook-preamble.sh and lib/hook-utils.sh files do not exist
  3. The scripts/prompts/ directory does not exist
  4. PRD.md, docs/v3-retrospective.md, and old test scripts do not exist
  5. .gitignore references agent-registry.json (not recovery-registry.json)
**Plans:** 2/2 plans executed
- [x] 01-01-PLAN.md — Purge all v1-v3 artifacts (scripts/, lib/, docs/, tests/, systemd/, PRD.md) and relocate logger to bin/
- [x] 01-02-PLAN.md — Rename registry to agent-registry, create package.json and session launcher

### Phase 01.1: Refactor Phase 1 code based on code review findings (INSERTED)

**Goal:** All Phase 1 code review findings are resolved — hook-event-logger.sh has no redundant date calls and correctly scoped trap, launch-session.mjs uses execFileSync/parseArgs/async-await with per-agent permission control, agent-registry example is clean, and project metadata (package.json, .gitignore, SKILL.md, README.md) is accurate and complete
**Depends on:** Phase 1
**Requirements:** REV-3.1, REV-3.2, REV-3.3, REV-3.4, REV-3.5, REV-3.6, REV-3.7, REV-3.8, REV-3.9, REV-3.10, REV-3.11
**Success Criteria** (what must be TRUE):
  1. hook-event-logger.sh captures the structured log block timestamp once and reuses it (no redundant date -u calls)
  2. hook-event-logger.sh trap is set after stdin read, not before
  3. launch-session.mjs uses execFileSync with argument arrays for all tmux commands
  4. launch-session.mjs uses node:util parseArgs instead of custom parser
  5. launch-session.mjs main() is async with Promise-based timer
  6. launch-session.mjs reads skip_permissions from agent registry
  7. agent-registry.example.json has no _comment keys
  8. package.json declares engines >=22 and bin entry
  9. .gitignore covers node_modules/ and .env
**Plans:** 2/2 plans complete

Plans:
- [x] 01.1-01-PLAN.md — Refactor hook-event-logger.sh and update project config files (package.json, .gitignore)
- [x] 01.1-02-PLAN.md — Refactor launch-session.mjs, clean agent-registry example, create SCHEMA.md, fix SKILL.md and README.md

### Phase 2: Shared Library
**Goal**: A Node.js shared lib exists at lib/ with agent resolution, gateway delivery, and JSON field extraction — importable by any event handler, with no code duplication across handlers
**Depends on**: Phase 1
**Requirements**: ARCH-01, ARCH-02, ARCH-03, ARCH-05, ARCH-06
**Success Criteria** (what must be TRUE):
  1. Running `node -e "import('./lib/index.mjs')"` succeeds without error
  2. `resolveAgentFromSession()` reads agent-registry.json and returns the correct agent for a known session value
  3. `wakeAgentViaGateway()` invokes `openclaw agent --session-id` with content and prompt arguments
  4. `extractJsonField()` safely returns a named field from valid hook JSON and returns null for missing fields
  5. A single shared entry point exists that event handlers can import to get all three functions pre-wired
**Plans:** 2 plans
Plans:
- [ ] 02-01-PLAN.md — Build core lib modules: JSONL logger, JSON field extractor, retry utility, agent resolver
- [ ] 02-02-PLAN.md — Build gateway delivery module and unified lib/index.mjs entry point

### Phase 02.1: Refactor Phase 2 shared library based on code review findings (INSERTED)

**Goal:** All Phase 2 code review findings are resolved — retry defaults are safe for hook context, logger has discriminated error handling, SKILL_ROOT is shared via lib/paths.mjs, and event handlers can import paths without depth-counting issues
**Depends on:** Phase 2
**Requirements:** REV-02-3.2, REV-02-3.3, REV-02-3.5
**Success Criteria** (what must be TRUE):
  1. retry.mjs defaults are 3 attempts / 2000ms base (not 10 / 5000ms)
  2. logger.mjs catch block discriminates expected I/O errors from unexpected ones (stderr fallback for unexpected)
  3. lib/paths.mjs exports SKILL_ROOT, imported by logger.mjs and agent-resolver.mjs (no duplicate computation)
  4. All existing lib imports still work (`node -e "import('./lib/index.mjs')"` succeeds)
**Plans:** 1 plan

Plans:
- [ ] 02.1-01-PLAN.md — Refactor lib: shared SKILL_ROOT, discriminated logger errors, safe retry defaults

### Phase 3: Stop Event (Full Stack)
**Goal**: The complete Stop event works end-to-end — handler extracts `last_assistant_message`, resolves agent, wakes it with prompt, and TUI driver types the chosen GSD slash command in the tmux pane. Testable and validated before proceeding.
**Depends on**: Phase 02.1
**Requirements**: ARCH-04, STOP-01, STOP-02, STOP-03, TUI-01, TUI-02, TUI-05
**Success Criteria** (what must be TRUE):
  1. The folder events/stop/ exists with event_stop.js, prompt_stop.md, and tui_driver_stop.js
  2. Piping a Stop hook JSON payload to node events/stop/event_stop.js triggers an OpenClaw gateway call
  3. Piping a payload where stop_hook_active is true results in no gateway call and exit with no error
  4. tui_driver_stop.js accepts a slash command argument and types it, tab-completes, and presses enter in the tmux pane
  5. prompt_stop.md instructs the agent to read the response, decide the GSD command, and call tui_driver_stop.js
**Plans**: TBD

### Phase 4: AskUserQuestion Lifecycle (Full Stack)
**Goal**: The full PreToolUse → PostToolUse verification loop works end-to-end — PreToolUse handler extracts questions/options/multiSelect, wakes agent with prompt, TUI driver navigates and submits the answer, PostToolUse handler verifies the answer matches. Testable and validated before proceeding.
**Depends on**: Phase 2
**Requirements**: ASK-01, ASK-02, ASK-03, ASK-04, TUI-03, TUI-04
**Success Criteria** (what must be TRUE):
  1. events/pre_tool_use/ask_user_question/ exists with event_ask_user_question.js, prompt_ask_user_question.md, and tui_driver_ask_user_question.js
  2. Piping a PreToolUse(AskUserQuestion) JSON payload triggers a gateway call that includes questions array and multiSelect flag
  3. tui_driver_ask_user_question.js navigates with arrow keys, selects with space (multiSelect) or enter (single-select), and submits
  4. events/post_tool_use/ask_user_question/ exists with event_post_ask_user_question.js and prompt_post_ask_user_question.md
  5. PostToolUse prompt instructs agent to compare submitted answer against its decision and report mismatch
**Plans**: TBD

### Phase 5: Registration and Documentation
**Goal**: All v4.0 event handlers are registered in ~/.claude/settings.json via an idempotent script; install.sh reflects the new event-folder structure; SKILL.md and README.md describe v4.0 architecture accurately
**Depends on**: Phase 3, Phase 4
**Requirements**: REG-01, REG-02, REG-03, CLEAN-06, CLEAN-07
**Success Criteria** (what must be TRUE):
  1. Running the registration script once writes the Stop handler and both AskUserQuestion handlers to ~/.claude/settings.json with correct matchers
  2. Running the registration script a second time does not duplicate any entries
  3. install.sh correctly sets up the event-folder structure when run on a clean system
  4. SKILL.md frontmatter and description accurately reflect v4.0 event-folder architecture
  5. README.md explains the events/ folder structure and how to add a new event handler
**Plans**: TBD

## Progress

**Execution Order:** 1 → 01.1 → 2 → 02.1 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Cleanup | 2/2 | Complete | 2026-02-19 |
| 01.1. Refactor (code review) | 2/2 | Complete | 2026-02-20 |
| 2. Shared Library | 2/2 | Complete | 2026-02-20 |
| 02.1. Refactor (lib review) | 0/1 | Planned | - |
| 3. Stop Event (Full Stack) | 0/TBD | Not started | - |
| 4. AskUserQuestion Lifecycle (Full Stack) | 0/TBD | Not started | - |
| 5. Registration and Documentation | 0/TBD | Not started | - |

---
*Roadmap created: 2026-02-19 for v4.0 Event-Driven Hook Architecture*
