#!/usr/bin/env node
/**
 * extract_requirements_python.js
 * Detects the Python virtual environment and generates requirements_python.txt
 *
 * Usage: node extract_requirements_python.js <project_dir> [report_dir]
 *        All informational messages go to stderr.
 *        If report_dir is not provided, saves to <project_dir>/code-analyzer/
 *
 * Exit codes:
 *   0 = success
 *   1 = fatal error (directory not found, pip failed)
 *   2 = venv not found (non-fatal — caller decides how to proceed)
 *
 * Notes:
 *   - pip warnings are redirected to a log file in the output directory.
 *     Check pip_warnings.log if requirements seem incomplete.
 *   - On Windows supports Scripts/pip.exe; on Linux/macOS bin/pip.
 *
 * Compatible with Windows, macOS, Linux.
 */

'use strict';

const fs               = require('fs');
const path             = require('path');
const { execFileSync } = require('child_process');

const err  = msg => process.stderr.write(msg + '\n');
const info = msg => process.stderr.write(msg + '\n');

// ── arguments ─────────────────────────────────────────────────────────────────
const projectDirArg = process.argv[2] || '.';
const reportDirArg  = process.argv[3] || '';

// ── validate PROJECT_DIR ──────────────────────────────────────────────────────
let projectDir = path.resolve(projectDirArg);
if (!fs.existsSync(projectDir) || !fs.statSync(projectDir).isDirectory()) {
  err(`❌ Directory not found: ${projectDirArg}`);
  process.exit(1);
}
// Security: resolve symlinks to canonical path (CWE-22)
projectDir = fs.realpathSync(projectDir);

// ── output directory ──────────────────────────────────────────────────────────
// Security: resolve reportDir with realpath if it exists, otherwise resolve normally (CWE-22)
let outputDir;
if (reportDirArg) {
  outputDir = path.resolve(reportDirArg);
  if (fs.existsSync(outputDir)) { outputDir = fs.realpathSync(outputDir); }
} else {
  outputDir = path.join(projectDir, 'code-analyzer');
}
const outputFile = path.join(outputDir, 'requirements_python.txt');
fs.mkdirSync(outputDir, { recursive: true, mode: 0o700 });

// ── search for venv ───────────────────────────────────────────────────────────
info(`🔍 Searching for virtual environment in: ${projectDir}`);

const venvDirs = ['.venv', 'venv', 'env', '.env', 'virtualenv'];
let foundVenv  = null;
let pipCmd     = null;

for (const d of venvDirs) {
  const candidate = path.join(projectDir, d);
  const pipPosix  = path.join(candidate, 'bin', 'pip');
  const pipWinExe = path.join(candidate, 'Scripts', 'pip.exe');
  const pipWin    = path.join(candidate, 'Scripts', 'pip');

  if (fs.existsSync(pipPosix)) {
    foundVenv = candidate; pipCmd = pipPosix; break;
  } else if (fs.existsSync(pipWinExe)) {
    foundVenv = candidate; pipCmd = pipWinExe; break;
  } else if (fs.existsSync(pipWin)) {
    foundVenv = candidate; pipCmd = pipWin; break;
  }
}

if (!foundVenv) {
  err(`⚠️  No virtual environment found in standard locations.`);
  err(`   Locations searched: ${venvDirs.join(', ')}`);
  err(`   Suggestion: use requirements.txt or pyproject.toml as fallback.`);
  process.exit(2);
}

info(`✅ Virtual environment found: ${foundVenv}`);

// ── verify pip is executable ──────────────────────────────────────────────────
try {
  fs.accessSync(pipCmd, fs.constants.X_OK);
} catch {
  // On Windows .exe files may not always have X bit — try anyway
  if (!pipCmd.endsWith('.exe')) {
    err(`❌ pip found but not executable: ${pipCmd}`);
    process.exit(1);
  }
}

// Security: resolve symlinks and verify pip is inside the venv (CWE-61)
try {
  const realPip  = fs.realpathSync(pipCmd);
  const realVenv = fs.realpathSync(foundVenv);
  if (!realPip.startsWith(realVenv + path.sep)) {
    err(`❌ Security: pip resolves outside the virtual environment`);
    err(`   pip path: ${pipCmd} → ${realPip}`);
    err(`   venv path: ${foundVenv} → ${realVenv}`);
    err(`   This may indicate a symlink attack. Aborting.`);
    process.exit(1);
  }
} catch (e) {
  err(`❌ Security: cannot resolve pip path: ${e.message}`);
  process.exit(1);
}

info(`📦 Extracting installed packages with: ${pipCmd}`);

// ── run pip freeze ────────────────────────────────────────────────────────────
const pipLogFile = path.join(outputDir, 'pip_warnings.log');
let freezeOut = '';
try {
  const pipLogFd = fs.openSync(pipLogFile, 'w', 0o600);
  freezeOut = execFileSync(pipCmd, ['freeze'], {
    stdio: ['ignore', 'pipe', pipLogFd],  // stderr redirected to log file
    encoding: 'utf8',
    timeout: 60000,  // 60s max — prevents indefinite hang (CWE-400)
  });
  fs.closeSync(pipLogFd);
  // Remove empty log file if no warnings were produced
  const logStat = fs.statSync(pipLogFile);
  if (logStat.size === 0) {
    fs.unlinkSync(pipLogFile);
  } else {
    info(`⚠️  pip produced warnings — see ${pipLogFile}`);
  }
} catch (e) {
  err(`❌ pip freeze failed: ${e.message} (see ${pipLogFile} for details)`);
  process.exit(1);
}

// ── write output file ─────────────────────────────────────────────────────────
const now = new Date();
const dateStr = now.toISOString().replace('T', ' ').substring(0, 19);
const header = [
  '# Requirements extracted from virtual environment',
  `# Project: ${path.basename(projectDir)}`,
  `# Venv: ${path.basename(foundVenv)}`,
  `# Date: ${dateStr}`,
  '',
].join('\n');

fs.writeFileSync(outputFile, header + freezeOut, { encoding: 'utf8', mode: 0o600 });

// ── count packages (non-comment, non-empty lines) ─────────────────────────────
const count = freezeOut
  .split('\n')
  .filter(line => line.trim() && !line.trim().startsWith('#'))
  .length;

info(`✅ Requirements extracted: ${count} packages`);
info(`📄 File saved to: ${outputFile}`);
info(`--- Contents (first 20 lines) ---`);
const preview = (header + freezeOut).split('\n').slice(0, 20).join('\n');
info(preview);
