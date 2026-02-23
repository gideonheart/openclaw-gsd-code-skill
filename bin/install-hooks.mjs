#!/usr/bin/env node

/**
 * bin/install-hooks.mjs — Install, update, or remove GSD hooks in ~/.claude/settings.json.
 *
 * Reads the canonical hook definitions from config/hooks.json, resolves the
 * {{SKILL_ROOT}} placeholder to the actual skill directory, then merges the
 * hooks into ~/.claude/settings.json (preserving all other settings like
 * statusLine, enabledPlugins, etc.).
 *
 * Usage:
 *   node bin/install-hooks.mjs                  # Install handlers only (default)
 *   node bin/install-hooks.mjs --logger         # Install handlers + debug logger
 *   node bin/install-hooks.mjs --remove         # Remove all hooks
 *   node bin/install-hooks.mjs --remove --handlers  # Remove only handlers, keep logger
 *   node bin/install-hooks.mjs --remove --logger    # Remove only logger, keep handlers
 *   node bin/install-hooks.mjs --dry-run        # Preview without writing
 */

import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SKILL_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const SETTINGS_PATH = join(process.env.HOME, '.claude', 'settings.json');
const HOOKS_SOURCE_PATH = join(SKILL_ROOT, 'config', 'hooks.json');

const removeMode = process.argv.includes('--remove');
const dryRunMode = process.argv.includes('--dry-run');
const includeLogger = process.argv.includes('--logger');
const handlersFlag = process.argv.includes('--handlers');

function isLoggerEntry(hookEntry) {
  return hookEntry.hooks?.some(hook => hook.command?.includes('hook-event-logger'));
}

function isHandlerEntry(hookEntry) {
  return hookEntry.hooks?.some(hook => !hook.command?.includes('hook-event-logger'));
}

function readSettingsFile() {
  try {
    return JSON.parse(readFileSync(SETTINGS_PATH, 'utf8'));
  } catch {
    return {};
  }
}

function readCanonicalHooks() {
  const rawContent = readFileSync(HOOKS_SOURCE_PATH, 'utf8');
  const resolvedContent = rawContent.replaceAll('{{SKILL_ROOT}}', SKILL_ROOT);
  return JSON.parse(resolvedContent).hooks;
}

function filterEntries(allHooks, keepFilter) {
  const filtered = {};
  for (const [eventName, eventEntries] of Object.entries(allHooks)) {
    const kept = eventEntries.filter(keepFilter);
    if (kept.length > 0) {
      filtered[eventName] = kept;
    }
  }
  return filtered;
}

function countByType(hooksObject) {
  let loggerCount = 0;
  let handlerCount = 0;
  for (const eventEntries of Object.values(hooksObject)) {
    for (const entry of eventEntries) {
      if (isLoggerEntry(entry)) loggerCount++;
      if (isHandlerEntry(entry)) handlerCount++;
    }
  }
  return { loggerCount, handlerCount };
}

function writeSettingsAtomically(settingsObject) {
  const temporaryPath = SETTINGS_PATH + '.tmp';
  writeFileSync(temporaryPath, JSON.stringify(settingsObject, null, 2) + '\n');
  renameSync(temporaryPath, SETTINGS_PATH);
}

function printHandlerList(hooksObject) {
  for (const [eventName, eventEntries] of Object.entries(hooksObject)) {
    for (const entry of eventEntries) {
      if (!isHandlerEntry(entry)) continue;
      const matcherLabel = entry.matcher ? ` [${entry.matcher}]` : '';
      console.log(`  ${eventName}${matcherLabel}: ${entry.hooks[0].command}`);
    }
  }
}

// --- Remove mode ---

if (removeMode) {
  const settings = readSettingsFile();
  if (!settings.hooks) {
    console.log('No hooks found in settings.json — nothing to remove.');
    process.exit(0);
  }

  const selectiveRemove = handlersFlag || includeLogger;

  if (!selectiveRemove) {
    // --remove (no sub-flag) = remove everything
    if (dryRunMode) {
      console.log(`[dry-run] Would remove all ${Object.keys(settings.hooks).length} hook events`);
      process.exit(0);
    }
    delete settings.hooks;
    writeSettingsAtomically(settings);
    console.log(`Removed all hooks from ${SETTINGS_PATH}`);
    process.exit(0);
  }

  // Selective remove: keep entries of the OTHER type
  const keepFilter = handlersFlag
    ? (entry) => isLoggerEntry(entry)   // --remove --handlers → keep logger
    : (entry) => isHandlerEntry(entry); // --remove --logger → keep handlers

  const removingLabel = handlersFlag ? 'handlers' : 'logger';
  const keepingLabel = handlersFlag ? 'logger' : 'handlers';
  const remaining = filterEntries(settings.hooks, keepFilter);
  const remainingEventCount = Object.keys(remaining).length;

  if (dryRunMode) {
    console.log(`[dry-run] Would remove ${removingLabel}, keeping ${keepingLabel}`);
    console.log(`[dry-run] ${remainingEventCount} hook events would remain`);
    process.exit(0);
  }

  if (remainingEventCount === 0) {
    delete settings.hooks;
  } else {
    settings.hooks = remaining;
  }
  writeSettingsAtomically(settings);
  console.log(`Removed ${removingLabel}, kept ${keepingLabel} (${remainingEventCount} events remain)`);
  process.exit(0);
}

// --- Install mode ---

if (handlersFlag) {
  console.error('--handlers flag is only used with --remove. Default install already installs handlers.');
  process.exit(1);
}

const allCanonicalHooks = readCanonicalHooks();

// Default = handlers only. --logger = handlers + logger.
const keepFilter = includeLogger
  ? () => true
  : (entry) => isHandlerEntry(entry);

const selectedHooks = filterEntries(allCanonicalHooks, keepFilter);
const eventCount = Object.keys(selectedHooks).length;
const { loggerCount, handlerCount } = countByType(selectedHooks);
const modeLabel = includeLogger ? 'handlers + logger' : 'handlers';

if (dryRunMode) {
  console.log(`[dry-run] Mode: ${modeLabel}`);
  console.log(`[dry-run] Would install ${eventCount} hook events (${handlerCount} handlers, ${loggerCount} loggers)`);
  console.log(`[dry-run] Target: ${SETTINGS_PATH}`);

  if (handlerCount > 0) {
    console.log('\nHandlers:');
    printHandlerList(selectedHooks);
  }
  if (loggerCount > 0) {
    console.log(`\nLogger: ${loggerCount} events`);
  }
  process.exit(0);
}

const settings = readSettingsFile();
settings.hooks = selectedHooks;
writeSettingsAtomically(settings);

console.log(`Installed ${eventCount} hook events (${handlerCount} handlers, ${loggerCount} loggers) — ${modeLabel}`);
console.log(`Target: ${SETTINGS_PATH}`);
