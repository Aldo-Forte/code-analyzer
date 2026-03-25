#!/usr/bin/env bash
# init_report_dir.sh
# Creates the timestamped subdirectory for the current analysis run
# and prints the absolute path to stdout.
#
# Usage: bash init_report_dir.sh <project_dir>
#        Prints the absolute path of the created report dir to stdout.
#        All informational messages go to stderr to keep stdout clean.
#
# Directory format: YYYY-MM-DDTHH:MM:SS-Report
# Collision (same second): YYYY-MM-DDTHH:MM:SS-Report-N

set -euo pipefail

# Portable realpath: works on macOS (BSD) without coreutils (CWE-22/CWE-61)
portable_realpath() {
  local target="$1"
  # Try GNU/BSD realpath first, then readlink -f, then manual resolution
  if command -v realpath &>/dev/null; then
    realpath "$target" 2>/dev/null && return 0
  fi
  if readlink -f "$target" 2>/dev/null; then
    return 0
  fi
  # Manual resolution using pwd -P (physical) + readlink to follow symlink chains
  # pwd -P returns the physical path on all POSIX systems
  # readlink (without -f) reads one symlink level — available on all platforms
  if [ -d "$target" ]; then
    (cd "$target" && pwd -P)
  elif [ -e "$target" ]; then
    # Resolve directory, then follow file-level symlink chain
    local current="$target"
    local dir base
    dir="$(cd "$(dirname "$current")" && pwd -P)"
    base="$(basename "$current")"
    current="$dir/$base"
    while [ -L "$current" ]; do
      local link_target
      link_target="$(readlink "$current")"
      case "$link_target" in
        /*) current="$link_target" ;;              # absolute symlink
        *)  current="$(dirname "$current")/$link_target" ;;  # relative symlink
      esac
      # Re-resolve directory after following the link
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

if [ ! -d "$PROJECT_DIR" ]; then
  echo "❌ Directory not found: $PROJECT_DIR" >&2
  exit 1
fi

# Resolve absolute path for consistent output
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)

# Security: reject paths that resolved via symlink to unexpected locations (CWE-22)
REAL_PROJECT_DIR=$(portable_realpath "$PROJECT_DIR")
if [ "$REAL_PROJECT_DIR" != "$PROJECT_DIR" ]; then
  echo "⚠️  Note: project path resolved through symlink: $PROJECT_DIR → $REAL_PROJECT_DIR" >&2
  PROJECT_DIR="$REAL_PROJECT_DIR"
fi
BASE_DIR="$PROJECT_DIR/code-analyzer"
mkdir -p -m 0700 "$BASE_DIR"

# Generate full timestamp with seconds: YYYY-MM-DDTHH:MM:SS
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')
REPORT_DIR="$BASE_DIR/${TIMESTAMP}-Report"

# Atomic creation: try mkdir (fails if exists) to avoid TOCTOU race (CWE-367)
MAX_ATTEMPTS=100
COUNTER=0
while true; do
  if mkdir -m 0700 "$REPORT_DIR" 2>/dev/null; then
    break  # Successfully created — we own it
  fi
  # Directory already exists — try next counter
  COUNTER=$((COUNTER + 1))
  if [ "$COUNTER" -ge "$MAX_ATTEMPTS" ]; then
    echo "❌ Could not create unique report dir after $MAX_ATTEMPTS attempts" >&2
    exit 1
  fi
  REPORT_DIR="$BASE_DIR/${TIMESTAMP}-Report-${COUNTER}"
done

echo "📁 Report dir created: $REPORT_DIR" >&2

# Print only the absolute path to stdout (used by the caller)
echo "$REPORT_DIR"
