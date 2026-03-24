#!/usr/bin/env node
/**
 * init_report_dir.js
 * Creates the timestamped subdirectory for the analysis and prints the absolute path.
 *
 * Usage: node init_report_dir.js <project_dir>
 *        Prints the absolute path of the created report directory on stdout.
 *        All informational messages go to stderr.
 *
 * Directory format: YYYY-MM-DDTHH-MM-SS-Report
 * Collision (same second): YYYY-MM-DDTHH-MM-SS-Report-N
 *
 * Note: uses '-' instead of ':' in time portion for Windows compatibility
 * (Windows does not allow ':' in file/directory names).
 *
 * Compatible with Windows, macOS, Linux.
 * Exit codes: 0 = success, 1 = error
 */

'use strict';

const fs   = require('fs');
const path = require('path');

// ── arguments ────────────────────────────────────────────────────────────────
const projectDirArg = process.argv[2] || '.';

// ── validate PROJECT_DIR ──────────────────────────────────────────────────────
const projectDir = path.resolve(projectDirArg);
if (!fs.existsSync(projectDir) || !fs.statSync(projectDir).isDirectory()) {
  process.stderr.write(`❌ Directory not found: ${projectDirArg}\n`);
  process.exit(1);
}

// ── generate timestamp YYYY-MM-DDTHH-MM-SS ───────────────────────────────────
function timestamp() {
  const now = new Date();
  const pad = n => String(n).padStart(2, '0');
  const date = `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}`;
  const time = `${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}`;
  return `${date}T${time}`;
}

// ── create base dir ───────────────────────────────────────────────────────────
const baseDir = path.join(projectDir, 'code-analyzer');
fs.mkdirSync(baseDir, { recursive: true });

// ── find unique name with collision counter ───────────────────────────────────
const ts = timestamp();
let reportDir = path.join(baseDir, `${ts}-Report`);
let counter = 1;
while (fs.existsSync(reportDir)) {
  reportDir = path.join(baseDir, `${ts}-Report-${counter}`);
  counter++;
}

fs.mkdirSync(reportDir, { recursive: true });

process.stderr.write(`📁 Report directory created: ${reportDir}\n`);

// print only the absolute path on stdout
process.stdout.write(reportDir + '\n');
