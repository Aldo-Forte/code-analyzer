#!/usr/bin/env bash
# install.sh — Install code-analyzer for detected AI agents
#
# Usage:
#   bash install.sh              # install on all detected agents
#   bash install.sh --agent claude-code  # install on Claude Code only
#   bash install.sh --list       # show detected installation paths
#   bash install.sh --uninstall  # remove the skill from all agents
#
# Direct install from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/Aldo-Forte/code-analyzer/main/install.sh | bash

set -euo pipefail

show_help() {
  echo "Usage: bash install.sh [--agent NAME] [--list] [--uninstall]"
  echo ""
  echo "Available agents: claude-code codex opencode cursor windsurf gemini goose agents"
}

# Ensure --help works even on Bash 3.2 before using associative arrays.
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      show_help
      exit 0
      ;;
  esac
done

# Associative arrays require Bash >= 4. Try re-exec with common Homebrew bash paths.
if [ -z "${BASH_VERSINFO+x}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [ -x "$candidate" ]; then
      exec "$candidate" "$0" "$@"
    fi
  done
  echo "[ERR] This script requires Bash 4+ (detected: ${BASH_VERSION:-unknown})." >&2
  echo "      Install bash (brew install bash) and run: /opt/homebrew/bin/bash install.sh" >&2
  exit 1
fi

SKILL_NAME="code-analyzer"
REPO_URL="https://github.com/Aldo-Forte/code-analyzer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colori ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[--]${RESET} $*"; }
err()  { echo -e "${RED}[ERR]${RESET} $*" >&2; }
hdr()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Agent map → install paths ───────────────────────────────────────────────
declare -A AGENT_PATHS=(
  ["claude-code"]="$HOME/.claude/skills"
  ["codex"]="$HOME/.codex/skills"
  ["opencode"]="$HOME/.config/opencode/skills"
  ["cursor"]="$HOME/.cursor/skills"
  ["windsurf"]="$HOME/.windsurf/skills"
  ["gemini"]="$HOME/.gemini/skills"
  ["goose"]="$HOME/.config/goose/skills"
  ["agents"]="$HOME/.agents/skills"
)

# ── Main functions ───────────────────────────────────────────────────────────

detect_agents() {
  # Returns agents whose base paths already exist (agent installed)
  local detected=()
  for agent in "${!AGENT_PATHS[@]}"; do
    local base_dir
    base_dir="$(dirname "${AGENT_PATHS[$agent]}")"
    if [ -d "$base_dir" ] || [ -d "${AGENT_PATHS[$agent]}" ]; then
      detected+=("$agent")
    fi
  done
  # Stable ordering
  printf '%s\n' "${detected[@]}" | sort
}

install_to() {
  local agent="$1"
  local skills_dir="${AGENT_PATHS[$agent]}"
  local dest="$skills_dir/$SKILL_NAME"

  mkdir -p "$skills_dir"

  if [ -d "$dest" ]; then
    # Already installed — update with git pull if it is a clone, otherwise overwrite
    if [ -d "$dest/.git" ]; then
      echo "  Updating via git pull..."
      if ! git -C "$dest" pull --ff-only --quiet; then
        err "${agent}: git pull --ff-only failed in $dest"
        return 1
      fi
    else
      echo "  Overwriting existing installation..."
      rm -rf "$dest"
      cp -r "$SCRIPT_DIR" "$dest"
    fi
  else
    cp -r "$SCRIPT_DIR" "$dest"
  fi

  # Make scripts executable
  # chmod not needed for Node.js scripts

  ok "${agent}: installed in $dest"
}

install_from_github() {
  # Called from curl | bash — clones the repo and then runs install.sh
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  hdr "Downloading from GitHub..."
  if command -v git &>/dev/null; then
    git clone --depth=1 --quiet "$REPO_URL" "$tmp/$SKILL_NAME"
  else
    err "git not found. Install git and try again."
    exit 1
  fi

  "$BASH" "$tmp/$SKILL_NAME/install.sh" "$@"
}

list_agents() {
  hdr "Installation paths:"
  local agent
  while IFS= read -r agent; do
    local dest="${AGENT_PATHS[$agent]}/$SKILL_NAME"
    if [ -d "$dest" ]; then
      ok "  $agent → $dest (installed)"
    else
      warn "  $agent → ${AGENT_PATHS[$agent]} (not installed)"
    fi
  done < <(printf '%s\n' "${!AGENT_PATHS[@]}" | sort)
}

uninstall_all() {
  hdr "Removing $SKILL_NAME..."
  local removed=0
  for agent in "${!AGENT_PATHS[@]}"; do
    local dest="${AGENT_PATHS[$agent]}/$SKILL_NAME"
    if [ -d "$dest" ]; then
      rm -rf "$dest"
      ok "Removed from $agent ($dest)"
      removed=$((removed + 1))
    fi
  done
  [ "$removed" -eq 0 ] && warn "No installation found."
}

# ── Main ─────────────────────────────────────────────────────────────────────

# If run via curl | bash, SCRIPT_DIR is an empty tmpdir — download first
if [ ! -f "$SCRIPT_DIR/SKILL.md" ]; then
  install_from_github "$@"
  exit 0
fi

# Argument parsing
TARGET_AGENT=""
MODE="install"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent|-a)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        err "--agent requires a value (e.g. --agent codex)"
        exit 1
      fi
      TARGET_AGENT="$2"
      shift 2
      ;;
    --list|-l)
      MODE="list"
      shift
      ;;
    --uninstall)
      MODE="uninstall"
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      exit 1
      ;;
  esac
done

case "$MODE" in
  list)
    list_agents
    exit 0 ;;
  uninstall)
    uninstall_all
    exit 0 ;;
esac

# Robust version extraction (does not stop script if SKILL.md has no version)
SKILL_VERSION="unknown"
if version_line="$(grep -E '^version:[[:space:]]*' "$SCRIPT_DIR/SKILL.md" | head -n 1 2>/dev/null)"; then
  SKILL_VERSION="$(printf '%s' "$version_line" | awk '{print $2}')"
fi
hdr "Installing $SKILL_NAME v$SKILL_VERSION"

if [ -n "$TARGET_AGENT" ]; then
  # Specific agent
  if [[ -z "${AGENT_PATHS[$TARGET_AGENT]+x}" ]]; then
    err "Unrecognized agent: $TARGET_AGENT"
    echo "Available agents: $(printf '%s\n' "${!AGENT_PATHS[@]}" | sort | tr '\n' ' ')"
    exit 1
  fi
  install_to "$TARGET_AGENT"
else
  # All detected agents (Bash 3.2 compatible: no mapfile)
  detected=()
  while IFS= read -r agent; do
    [ -n "$agent" ] && detected+=("$agent")
  done < <(detect_agents)

  if [ ${#detected[@]} -eq 0 ]; then
    warn "No agents detected automatically."
    warn "Use --agent NAME to specify an agent manually."
    warn "Available agents: $(printf '%s\n' "${!AGENT_PATHS[@]}" | sort | tr '\n' ' ')"
    exit 0
  fi

  echo "Detected agents: ${detected[*]}"
  for agent in "${detected[@]}"; do
    install_to "$agent"
  done
fi

hdr "Completed."
echo "Restart the agent and type /skills to verify."
