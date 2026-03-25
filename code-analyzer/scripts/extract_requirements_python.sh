#!/usr/bin/env bash
# extract_requirements_python.sh
# Detects the Python virtual environment and generates requirements_python.txt
# in {report_dir}/requirements_python.txt
#
# Usage: bash extract_requirements_python.sh <project_dir> [report_dir]
#        All informational messages go to stderr.
#        If report_dir is not provided, saves to <project_dir>/code-analyzer/
#
# Exit codes:
#   0 = success
#   1 = fatal error (directory not found, pip freeze failed)
#   2 = venv not found (non-fatal — caller decides how to proceed)
#
# Note: pip warnings are redirected to a log file in the output directory.
#       Check pip_warnings.log if requirements seem incomplete.

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
    local dir base
    dir="$(dirname "$target")"
    base="$(basename "$target")"
    echo "$(cd "$dir" && pwd -P)/$base"
  else
    echo "$target"
  fi
}

PROJECT_DIR="${1:-.}"
REPORT_DIR="${2:-}"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "❌ Directory not found: $PROJECT_DIR" >&2
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
OUTPUT_FILE="$OUTPUT_DIR/requirements_python.txt"

mkdir -p -m 0700 "$OUTPUT_DIR"

echo "🔍 Searching for virtual environment in: $PROJECT_DIR" >&2

VENV_DIRS=(".venv" "venv" "env" ".env" "virtualenv")
FOUND_VENV=""

for d in "${VENV_DIRS[@]}"; do
  CANDIDATE="$PROJECT_DIR/$d"
  if [ -f "$CANDIDATE/bin/pip" ] || [ -f "$CANDIDATE/Scripts/pip.exe" ] || [ -f "$CANDIDATE/Scripts/pip" ]; then
    FOUND_VENV="$CANDIDATE"
    echo "✅ Virtual environment found: $FOUND_VENV" >&2
    break
  fi
done

if [ -z "$FOUND_VENV" ]; then
  echo "⚠️  No virtual environment found in standard locations." >&2
  echo "   Searched: ${VENV_DIRS[*]}" >&2
  echo "   Suggestion: use requirements.txt or pyproject.toml as fallback." >&2
  exit 2
fi

if [ -f "$FOUND_VENV/bin/pip" ]; then
  PIP_CMD="$FOUND_VENV/bin/pip"
elif [ -f "$FOUND_VENV/Scripts/pip.exe" ]; then
  PIP_CMD="$FOUND_VENV/Scripts/pip.exe"
else
  PIP_CMD="$FOUND_VENV/Scripts/pip"
fi

# Verify pip is actually executable (avoids silent failures with set -e)
if [ ! -x "$PIP_CMD" ]; then
  echo "❌ pip found but not executable: $PIP_CMD" >&2
  exit 1
fi

# Security: resolve symlinks and verify pip is inside the venv (CWE-61)
REAL_PIP=$(portable_realpath "$PIP_CMD")
REAL_VENV=$(portable_realpath "$FOUND_VENV")
case "$REAL_PIP" in
  "$REAL_VENV"/*)
    ;; # OK — pip is inside the venv
  *)
    echo "❌ Security: pip resolves outside the virtual environment" >&2
    echo "   pip path: $PIP_CMD → $REAL_PIP" >&2
    echo "   venv path: $FOUND_VENV → $REAL_VENV" >&2
    echo "   This may indicate a symlink attack. Aborting." >&2
    exit 1
    ;;
esac

echo "📦 Extracting installed packages with: $PIP_CMD" >&2

# pip freeze: stderr redirected to log file for later inspection
PIP_LOG="$OUTPUT_DIR/pip_warnings.log"
install -m 0600 /dev/null "$PIP_LOG"  # create log file with restricted permissions
FREEZE_OUT=$("$PIP_CMD" freeze 2>"$PIP_LOG") || {
  echo "❌ pip freeze failed (see $PIP_LOG for details)" >&2
  exit 1
}
# Remove empty log file if no warnings were produced
[ -s "$PIP_LOG" ] || rm -f "$PIP_LOG"
[ -f "$PIP_LOG" ] && echo "⚠️  pip produced warnings — see $PIP_LOG" >&2
{
  echo "# Requirements extracted from virtual environment"
  echo "# Project: $(basename "$PROJECT_DIR")"
  echo "# Venv: $(basename "$FOUND_VENV")"
  echo "# Date: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  printf '%s\n' "$FREEZE_OUT"
} > "$OUTPUT_FILE"
chmod 0600 "$OUTPUT_FILE"

# Count non-comment, non-empty lines
COUNT=$(grep -cE '^[^#[:space:]]' "$OUTPUT_FILE" 2>/dev/null || echo 0)

echo "✅ Requirements extracted: $COUNT packages" >&2
echo "📄 File saved to: $OUTPUT_FILE" >&2
echo "--- Contents (first 20 lines) ---" >&2
head -20 "$OUTPUT_FILE" >&2
