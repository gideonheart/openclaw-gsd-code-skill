#!/usr/bin/env node

/**
 * bin/pause-session.mjs — CLI to toggle and query per-session auto-drive pause state.
 *
 * Usage:
 *   node bin/pause-session.mjs <session-name> <on|off|status>
 *
 * Subcommands:
 *   on     — Pause the session (hooks log events but skip auto-drive processing)
 *   off    — Unpause the session (normal auto-drive behavior resumes)
 *   status — Query whether the session is currently paused
 */

import { isSessionPaused, setSessionPauseState } from '../lib/index.mjs';

const sessionName = process.argv[2];
const subcommand = process.argv[3];

if (!sessionName || !subcommand || !['on', 'off', 'status'].includes(subcommand)) {
  console.error('Usage: pause-session.mjs <session-name> <on|off|status>');
  process.exit(1);
}

if (subcommand === 'on') {
  setSessionPauseState(sessionName, true);
  console.log(`Session '${sessionName}' paused.`);
} else if (subcommand === 'off') {
  setSessionPauseState(sessionName, false);
  console.log(`Session '${sessionName}' unpaused.`);
} else if (subcommand === 'status') {
  const paused = isSessionPaused(sessionName);
  console.log(`Session '${sessionName}' is ${paused ? 'paused' : 'not paused'}.`);
}
