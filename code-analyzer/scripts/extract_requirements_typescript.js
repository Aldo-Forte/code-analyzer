#!/usr/bin/env node
/**
 * extract_requirements_typescript.js
 * Detects the TypeScript/Node project and generates requirements_typescript.txt
 *
 * Usage: node extract_requirements_typescript.js <project_dir> [report_dir]
 *        If project_dir is not provided, uses the current directory.
 *        report_dir: path of the report dir (from init_report_dir.js);
 *                    if omitted, saves to <project_dir>/code-analyzer/
 *        npm warnings (missing peer deps) are intentionally silenced.
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
const projectDir = path.resolve(projectDirArg);
if (!fs.existsSync(projectDir) || !fs.statSync(projectDir).isDirectory()) {
  err(`❌ Directory not found: ${projectDirArg}`);
  process.exit(1);
}

info(`🔍 Searching for TypeScript/Node project in: ${projectDir}`);

// ── check package.json (before creating output directory) ────────────────────
const pkgJsonPath = path.join(projectDir, 'package.json');
if (!fs.existsSync(pkgJsonPath)) {
  err(`❌ package.json not found in ${projectDir}`);
  err(`   Make sure you are pointing to the root of the Node/TypeScript project.`);
  process.exit(1);
}

// ── output dir ────────────────────────────────────────────────────────────────
const outputDir  = reportDirArg ? path.resolve(reportDirArg) : path.join(projectDir, 'code-analyzer');
const outputFile = path.join(outputDir, 'requirements_typescript.txt');
fs.mkdirSync(outputDir, { recursive: true });

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
let pkg = {};
try {
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
  `# Extracted from: ${projectDir}`,
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

  const npmCheck = spawnSync('npm', ['--version'], { encoding: 'utf8', shell: true });
  const hasNpm   = npmCheck.status === 0;

  if (hasNpm) {
    // npm list --depth=0 — stderr silenced (peer dep warnings are common)
    const result = spawnSync(
      'npm',
      ['list', '--depth=0', '--prefix', projectDir],
      { encoding: 'utf8', shell: true, stdio: ['ignore', 'pipe', 'ignore'] }
    );
    const npmOut = (result.stdout || '').trim();
    output += npmOut
      ? npmOut + '\n'
      : '(npm list produced no useful output — peer deps may be missing)\n';
  } else if (hasYarnLock) {
    const yarnVer   = spawnSync('yarn', ['--version'], { encoding: 'utf8', shell: true });
    const yarnMajor = yarnVer.status === 0
      ? parseInt((yarnVer.stdout || '1').trim().split('.')[0], 10) : 1;
    const yarnArgs  = yarnMajor >= 2 ? ['workspaces', 'list'] : ['list', '--depth=0'];
    const result    = spawnSync('yarn', ['--cwd', projectDir, ...yarnArgs], {
      encoding: 'utf8', shell: true, stdio: ['ignore', 'pipe', 'ignore'],
    });
    output += result.stdout ? result.stdout.trim() + '\n' : '(yarn list returned errors)\n';
  } else if (hasPnpmLock) {
    const result = spawnSync('pnpm', ['--dir', projectDir, 'list', '--depth=0'], {
      encoding: 'utf8', shell: true, stdio: ['ignore', 'pipe', 'ignore'],
    });
    if (result.stdout && result.stdout.trim()) {
      output += result.stdout.trim() + '\n';
    } else {
      const result2 = spawnSync('pnpm', ['--dir', projectDir, 'list'], {
        encoding: 'utf8', shell: true, stdio: ['ignore', 'pipe', 'ignore'],
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
  output += '\n# TypeScript configuration (tsconfig.json)\n\n';
  output += fs.readFileSync(tsconfigPath, 'utf8') + '\n';
}

// ── write file ────────────────────────────────────────────────────────────────
fs.writeFileSync(outputFile, output, 'utf8');

// ── summary ───────────────────────────────────────────────────────────────────
const countDeps = [
  ...Object.keys(pkg.dependencies         || {}),
  ...Object.keys(pkg.devDependencies      || {}),
  ...Object.keys(pkg.peerDependencies     || {}),
  ...Object.keys(pkg.optionalDependencies || {}),
].length;

info('');
info(`✅ Analysis complete: ${countDeps} declared dependencies`);
info(`📄 File saved to: ${outputFile}`);
