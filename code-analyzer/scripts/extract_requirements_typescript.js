#!/usr/bin/env node
/**
 * extract_requirements_typescript.js
 * Detects the TypeScript/Node project and generates requirements_typescript.txt
 *
 * Usage: node extract_requirements_typescript.js <project_dir> [report_dir]
 *        If project_dir is not provided, uses the current directory.
 *        report_dir: path of the report dir (from init_report_dir.js);
 *                    if omitted, saves to <project_dir>/code-analyzer/
 *        npm/yarn/pnpm warnings are redirected to a log file in the output directory.
 *
 * Exit codes:
 *   0 = success
 *   1 = fatal error (directory not found, package.json missing)
 *
 * Compatible with Windows, macOS, Linux.
 */

'use strict';

const fs            = require('fs');
const path          = require('path');
const { spawnSync } = require('child_process');

const info = msg => process.stderr.write(msg + '\n');
const err  = msg => process.stderr.write(msg + '\n');

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

info(`🔍 Searching for TypeScript/Node project in: ${projectDir}`);

// ── check package.json (before creating output directory) ────────────────────
const pkgJsonPath = path.join(projectDir, 'package.json');
if (!fs.existsSync(pkgJsonPath)) {
  err(`❌ package.json not found in ${projectDir}`);
  err(`   Make sure you are pointing to the root of the Node/TypeScript project.`);
  process.exit(1);
}

// ── output dir ────────────────────────────────────────────────────────────────
// Security: resolve reportDir with realpath if it exists, otherwise resolve normally (CWE-22)
let outputDir;
if (reportDirArg) {
  outputDir = path.resolve(reportDirArg);
  if (fs.existsSync(outputDir)) { outputDir = fs.realpathSync(outputDir); }
} else {
  outputDir = path.join(projectDir, 'code-analyzer');
}
const outputFile = path.join(outputDir, 'requirements_typescript.txt');
fs.mkdirSync(outputDir, { recursive: true, mode: 0o700 });

const pkgMgrLogFile = path.join(outputDir, 'npm_warnings.log');
let pkgMgrLogFd = fs.openSync(pkgMgrLogFile, 'w', 0o600);

info(`✅ package.json found`);

// ── check node_modules ───────────────────────────────────────────────────────
const nodeModulesPath = path.join(projectDir, 'node_modules');
const hasNodeModules  = fs.existsSync(nodeModulesPath) && fs.statSync(nodeModulesPath).isDirectory();
if (hasNodeModules) {
  info(`✅ node_modules found`);
} else {
  info(`⚠️  node_modules not found — dependencies may not be installed`);
}

// ── read package.json ─────────────────────────────────────────────────────────
// Security: limit file size to prevent OOM from malicious input (CWE-400)
const MAX_JSON_SIZE = 10 * 1024 * 1024; // 10 MB
let pkg = {};
try {
  const pkgStat = fs.statSync(pkgJsonPath);
  if (pkgStat.size > MAX_JSON_SIZE) {
    err(`❌ package.json is too large (${pkgStat.size} bytes, max ${MAX_JSON_SIZE})`);
    process.exit(1);
  }
  pkg = JSON.parse(fs.readFileSync(pkgJsonPath, 'utf8'));
} catch (e) {
  err(`❌ Error reading package.json: ${e.message}`);
  process.exit(1);
}

// ── header ────────────────────────────────────────────────────────────────────
const now     = new Date();
const dateStr = now.toISOString().replace('T', ' ').substring(0, 19);
let output    = [
  '# TypeScript/Node Requirements',
  `# Extracted from: ${path.basename(projectDir)}`,
  `# Date: ${dateStr}`,
  '',
  '# Declared dependencies (package.json)',
  '',
].join('\n');

// ── section 1: dependencies from package.json ────────────────────────────────
const sections = [
  ['dependencies',         pkg.dependencies         || {}],
  ['devDependencies',      pkg.devDependencies      || {}],
  ['peerDependencies',     pkg.peerDependencies     || {}],
  ['optionalDependencies', pkg.optionalDependencies || {}],
];

for (const [section, deps] of sections) {
  const entries = Object.entries(deps);
  if (entries.length === 0) continue;
  output += `# ${section}\n`;
  for (const [name, version] of entries) {
    output += `${name}@${version}\n`;
  }
  output += '\n';
}

// ── section 2: actually installed versions ───────────────────────────────────
if (hasNodeModules) {
  output += '\n# Actually installed versions (node_modules)\n\n';

  const hasYarnLock = fs.existsSync(path.join(projectDir, 'yarn.lock'));
  const hasPnpmLock = fs.existsSync(path.join(projectDir, 'pnpm-lock.yaml'));

  const SPAWN_TIMEOUT = 30000; // 30s max per command (CWE-400)
  const npmCheck = spawnSync('npm', ['--version'], { encoding: 'utf8', timeout: SPAWN_TIMEOUT });
  const hasNpm   = npmCheck.status === 0;

  if (hasNpm) {
    // npm list --depth=0 — stderr redirected to log file
    const result = spawnSync(
      'npm',
      ['list', '--depth=0', '--prefix', projectDir],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', pkgMgrLogFd], timeout: SPAWN_TIMEOUT }
    );
    const npmOut = (result.stdout || '').trim();
    output += npmOut
      ? npmOut + '\n'
      : '(npm list produced no useful output — peer deps may be missing)\n';
  } else if (hasYarnLock) {
    const yarnVer   = spawnSync('yarn', ['--version'], { encoding: 'utf8', timeout: SPAWN_TIMEOUT });
    const yarnMajor = yarnVer.status === 0
      ? parseInt((yarnVer.stdout || '1').trim().split('.')[0], 10) : 1;
    const yarnArgs  = yarnMajor >= 2 ? ['workspaces', 'list'] : ['list', '--depth=0'];
    const result    = spawnSync('yarn', ['--cwd', projectDir, ...yarnArgs], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', pkgMgrLogFd], timeout: SPAWN_TIMEOUT,
    });
    output += result.stdout ? result.stdout.trim() + '\n' : '(yarn list returned errors)\n';
  } else if (hasPnpmLock) {
    const result = spawnSync('pnpm', ['--dir', projectDir, 'list', '--depth=0'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', pkgMgrLogFd], timeout: SPAWN_TIMEOUT,
    });
    if (result.stdout && result.stdout.trim()) {
      output += result.stdout.trim() + '\n';
    } else {
      const result2 = spawnSync('pnpm', ['--dir', projectDir, 'list'], {
        encoding: 'utf8', stdio: ['ignore', 'pipe', pkgMgrLogFd], timeout: SPAWN_TIMEOUT,
      });
      output += result2.stdout ? result2.stdout.trim() + '\n' : '(pnpm list returned errors)\n';
    }
  } else {
    output += '(no package manager available to list installed versions)\n';
  }
}

// ── section 3: tsconfig.json ──────────────────────────────────────────────────
const tsconfigPath = path.join(projectDir, 'tsconfig.json');
if (fs.existsSync(tsconfigPath)) {
  const tsStat = fs.statSync(tsconfigPath);
  if (tsStat.size <= MAX_JSON_SIZE) {
    output += '\n# TypeScript configuration (tsconfig.json)\n\n';
    output += fs.readFileSync(tsconfigPath, 'utf8') + '\n';
  } else {
    output += '\n# TypeScript configuration (tsconfig.json) — skipped: file too large\n';
  }
}

// ── write file ────────────────────────────────────────────────────────────────
fs.writeFileSync(outputFile, output, { encoding: 'utf8', mode: 0o600 });

// ── summary ───────────────────────────────────────────────────────────────────
const countDeps = [
  ...Object.keys(pkg.dependencies         || {}),
  ...Object.keys(pkg.devDependencies      || {}),
  ...Object.keys(pkg.peerDependencies     || {}),
  ...Object.keys(pkg.optionalDependencies || {}),
].length;

// Clean up log file: remove if empty, warn if not
fs.closeSync(pkgMgrLogFd);
try {
  const logStat = fs.statSync(pkgMgrLogFile);
  if (logStat.size === 0) {
    fs.unlinkSync(pkgMgrLogFile);
  } else {
    info(`⚠️  Package manager produced warnings — see ${pkgMgrLogFile}`);
  }
} catch { /* log file may not exist */ }

info('');
info(`✅ Analysis complete: ${countDeps} declared dependencies`);
info(`📄 File saved to: ${outputFile}`);
