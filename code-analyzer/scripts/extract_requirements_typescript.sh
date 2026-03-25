#!/usr/bin/env bash
# extract_requirements_typescript.sh
# Detects the TypeScript/Node project and generates requirements_typescript.txt
# in {report_dir}/requirements_typescript.txt
#
# Usage: bash extract_requirements_typescript.sh <project_dir> [report_dir]
#        If project_dir is not provided, uses the current directory.
#        report_dir: path of the report dir (from init_report_dir.sh);
#                    if omitted, saves to <project_dir>/code-analyzer/
#        npm/yarn/pnpm warnings are redirected to a log file in the output directory.

set -euo pipefail

# Portable realpath: works on macOS (BSD) without coreutils (CWE-22/CWE-61)
portable_realpath() {
  local target="$1"
  if command -v realpath &>/dev/null; then
    realpath "$target" 2>/dev/null && return 0
  fi
  if readlink -f "$target" 2>/dev/null; then
    return 0
  fi
  if [ -d "$target" ]; then
    (cd "$target" && pwd -P)
  elif [ -e "$target" ]; then
    local current="$target"
    local dir base
    dir="$(cd "$(dirname "$current")" && pwd -P)"
    base="$(basename "$current")"
    current="$dir/$base"
    while [ -L "$current" ]; do
      local link_target
      link_target="$(readlink "$current")"
      case "$link_target" in
        /*) current="$link_target" ;;
        *)  current="$(dirname "$current")/$link_target" ;;
      esac
      dir="$(cd "$(dirname "$current")" && pwd -P)"
      base="$(basename "$current")"
      current="$dir/$base"
    done
    echo "$current"
  else
    echo "$target"
  fi
}

PROJECT_DIR="${1:-.}"
REPORT_DIR="${2:-}"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "[ERR] Directory not found: $PROJECT_DIR" >&2
  exit 1
fi

# Security: resolve symlinks to canonical path (CWE-22)
PROJECT_DIR=$(portable_realpath "$PROJECT_DIR")

# Security: resolve reportDir with realpath if provided (CWE-22)
if [ -n "$REPORT_DIR" ]; then
  if [ -d "$REPORT_DIR" ]; then
    OUTPUT_DIR=$(portable_realpath "$REPORT_DIR")
  else
    OUTPUT_DIR="$REPORT_DIR"
  fi
else
  OUTPUT_DIR="$PROJECT_DIR/code-analyzer"
fi
OUTPUT_FILE="$OUTPUT_DIR/requirements_typescript.txt"

echo "[INFO] Searching for TypeScript/Node project in: $PROJECT_DIR" >&2

# --- Check package.json (before creating output directory) ---
PACKAGE_JSON="$PROJECT_DIR/package.json"
if [ ! -f "$PACKAGE_JSON" ]; then
  echo "[ERR] package.json not found in $PROJECT_DIR" >&2
  echo "   Make sure you are pointing to the root of the Node/TypeScript project." >&2
  exit 1
fi

# Security: file size limit to prevent resource exhaustion (CWE-400)
MAX_FILE_SIZE=$((10 * 1024 * 1024))  # 10 MB

mkdir -p -m 0700 "$OUTPUT_DIR"
PKG_MGR_LOG="$OUTPUT_DIR/npm_warnings.log"
install -m 0600 /dev/null "$PKG_MGR_LOG"  # initialize log file with restricted permissions
echo "[OK] package.json found" >&2

# --- Check node_modules ---
NODE_MODULES="$PROJECT_DIR/node_modules"
HAS_NODE_MODULES=false
if [ -d "$NODE_MODULES" ]; then
  HAS_NODE_MODULES=true
  echo "[OK] node_modules found" >&2
else
  echo "[WARN] node_modules not found — dependencies may not be installed" >&2
fi

# --- Output header ---
{
  echo "# TypeScript/Node Requirements"
  echo "# Extracted from: $(basename "$PROJECT_DIR")"
  echo "# Date: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
} > "$OUTPUT_FILE"
chmod 0600 "$OUTPUT_FILE"

# --- Section 1: dependencies from package.json ---
{
  echo "# Declared dependencies (package.json)"
  echo ""
} >> "$OUTPUT_FILE"

PKG_SIZE=$(wc -c < "$PACKAGE_JSON" 2>/dev/null || echo 0)
if [ "$PKG_SIZE" -gt "$MAX_FILE_SIZE" ]; then
  echo "[ERR] package.json is too large (${PKG_SIZE} bytes, max ${MAX_FILE_SIZE})" >&2
  exit 1
fi

if command -v node &>/dev/null; then
  PKG_PATH="$PACKAGE_JSON" node -e "
    const fs = require('fs');
    const pkgPath = process.env.PKG_PATH;
    let pkg;
    try {
      pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    } catch(e) {
      process.stderr.write('Error reading package.json: ' + e.message + '\n');
      process.exit(1);
    }
    const sections = [
      ['dependencies', pkg.dependencies || {}],
      ['devDependencies', pkg.devDependencies || {}],
      ['peerDependencies', pkg.peerDependencies || {}],
      ['optionalDependencies', pkg.optionalDependencies || {}],
    ];
    for (const [section, deps] of sections) {
      const entries = Object.entries(deps);
      if (entries.length === 0) continue;
      process.stdout.write('# ' + section + '\n');
      for (const [name, version] of entries) {
        process.stdout.write(name + '@' + version + '\n');
      }
      process.stdout.write('\n');
    }
  " >> "$OUTPUT_FILE" || {
    echo "[WARN] node could not read package.json — including raw file" >> "$OUTPUT_FILE"
    cat "$PACKAGE_JSON" >> "$OUTPUT_FILE"
  }
else
  echo "[WARN] node not available — including raw package.json" >> "$OUTPUT_FILE"
  cat "$PACKAGE_JSON" >> "$OUTPUT_FILE"
fi

# --- Section 2: actually installed versions ---
if [ "$HAS_NODE_MODULES" = true ]; then
  {
    echo ""
    echo "# Actually installed versions (node_modules)"
    echo ""
  } >> "$OUTPUT_FILE"

  if command -v npm &>/dev/null; then
    NPM_OUT=$(npm --prefix "$PROJECT_DIR" list --depth=0 2>>"$PKG_MGR_LOG" || true)
    NPM_OUT_TRIMMED=$(echo "$NPM_OUT" | tr -d '[:space:]')
    if [ -n "$NPM_OUT_TRIMMED" ]; then
      printf '%s\n' "$NPM_OUT" >> "$OUTPUT_FILE"
    else
      echo "(npm list produced no useful output — peer deps may be missing)" >> "$OUTPUT_FILE"
    fi
  elif command -v yarn &>/dev/null && [ -f "$PROJECT_DIR/yarn.lock" ]; then
    YARN_VERSION=$(yarn --version 2>>"$PKG_MGR_LOG" | cut -d. -f1 || echo "1")
    if [ "$YARN_VERSION" = "1" ]; then
      yarn --cwd "$PROJECT_DIR" list --depth=0 2>>"$PKG_MGR_LOG" >> "$OUTPUT_FILE" || \
        echo "(yarn list returned errors)" >> "$OUTPUT_FILE"
    else
      yarn --cwd "$PROJECT_DIR" workspaces list 2>>"$PKG_MGR_LOG" >> "$OUTPUT_FILE" || \
        echo "(yarn workspaces list not available in this version)" >> "$OUTPUT_FILE"
    fi
  elif command -v pnpm &>/dev/null && [ -f "$PROJECT_DIR/pnpm-lock.yaml" ]; then
    pnpm --dir "$PROJECT_DIR" list --depth=0 2>>"$PKG_MGR_LOG" >> "$OUTPUT_FILE" || \
    pnpm --dir "$PROJECT_DIR" list 2>>"$PKG_MGR_LOG" >> "$OUTPUT_FILE" || \
      echo "(pnpm list returned errors)" >> "$OUTPUT_FILE"
  else
    echo "(no package manager available to list installed versions)" >> "$OUTPUT_FILE"
  fi
fi

# --- Section 3: TypeScript config ---
TSCONFIG="$PROJECT_DIR/tsconfig.json"
if [ -f "$TSCONFIG" ]; then
  TS_SIZE=$(wc -c < "$TSCONFIG" 2>/dev/null || echo 0)
  if [ "$TS_SIZE" -le "$MAX_FILE_SIZE" ]; then
    {
      echo ""
      echo "# TypeScript configuration (tsconfig.json)"
      echo ""
      cat "$TSCONFIG"
    } >> "$OUTPUT_FILE"
  else
    echo "" >> "$OUTPUT_FILE"
    echo "# TypeScript configuration (tsconfig.json) — skipped: file too large" >> "$OUTPUT_FILE"
  fi
fi

# --- Summary ---
COUNT_DEPS=0
if command -v node &>/dev/null; then
  COUNT_DEPS=$(PKG_PATH="$PACKAGE_JSON" node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync(process.env.PKG_PATH, 'utf8'));
    const all = [
      ...Object.keys(pkg.dependencies || {}),
      ...Object.keys(pkg.devDependencies || {}),
      ...Object.keys(pkg.peerDependencies || {}),
      ...Object.keys(pkg.optionalDependencies || {}),
    ];
    console.log(all.length);
  " 2>>"$PKG_MGR_LOG" || echo 0)
fi

# Remove empty log file if no warnings were produced
[ -s "$PKG_MGR_LOG" ] || rm -f "$PKG_MGR_LOG"
[ -f "$PKG_MGR_LOG" ] && echo "[WARN] Package manager produced warnings — see $PKG_MGR_LOG" >&2

echo "" >&2
echo "[OK] Analysis complete: $COUNT_DEPS declared dependencies" >&2
echo "[INFO] File saved to: $OUTPUT_FILE" >&2
