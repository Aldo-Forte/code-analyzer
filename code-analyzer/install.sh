#!/usr/bin/env bash
# install.sh — Install code-analyzer on all detected AI agents
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

SKILL_NAME="code-analyzer"
REPO_URL="https://github.com/Aldo-Forte/code-analyzer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[--]${RESET} $*"; }
err()  { echo -e "${RED}[ERR]${RESET} $*" >&2; }
hdr()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Agent → installation path map ────────────────────────────────────────────
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

# ── Core functions ───────────────────────────────────────────────────────────

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

  mkdir -p -m 0700 "$skills_dir"

  if [ -d "$dest" ]; then
    # Already installed — update with git pull if it is a clone, otherwise overwrite
    if [ -d "$dest/.git" ]; then
      echo "  Updating via git pull..."
      git -C "$dest" pull --quiet
      # Integrity: log commit hash after update (parity with install_from_github)
      local updated_hash
      updated_hash="$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo "unknown")"
      echo "  Updated to commit: $updated_hash"
    else
      # Backup existing installation before overwriting
      local backup="${dest}.backup.$(date '+%Y%m%d%H%M%S')"
      if [ "$FORCE" = true ]; then
        echo "  --force: overwriting existing installation..."
      else
        echo "  Backing up existing installation to: $backup"
        cp -r "$dest" "$backup"
        ok "Backup saved: $backup"
      fi
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

  # Integrity verification: log commit hash for auditability
  local commit_hash
  commit_hash="$(git -C "$tmp/$SKILL_NAME" rev-parse HEAD)"
  ok "Cloned commit: $commit_hash"

  # Verify SKILL.md exists (basic tamper check — ensures the repo is genuine)
  if [ ! -f "$tmp/$SKILL_NAME/SKILL.md" ]; then
    err "Integrity check failed: SKILL.md not found in downloaded repository."
    err "The repository may be corrupted or tampered with."
    exit 1
  fi

  # SHA256 checksum of SKILL.md for reproducibility
  local checksum
  if command -v sha256sum &>/dev/null; then
    checksum="$(sha256sum "$tmp/$SKILL_NAME/SKILL.md" | awk '{print $1}')"
  elif command -v shasum &>/dev/null; then
    checksum="$(shasum -a 256 "$tmp/$SKILL_NAME/SKILL.md" | awk '{print $1}')"
  else
    checksum="(sha256sum not available)"
  fi
  ok "SKILL.md SHA256: $checksum"

  # If EXPECTED_CHECKSUM env var is set, verify automatically (CWE-345)
  if [ -n "${EXPECTED_CHECKSUM:-}" ]; then
    if [ "$checksum" = "$EXPECTED_CHECKSUM" ]; then
      ok "Checksum verified: matches expected value"
    else
      err "Checksum mismatch!"
      err "  Expected: $EXPECTED_CHECKSUM"
      err "  Got:      $checksum"
      err "The downloaded repository may have been tampered with. Aborting."
      exit 1
    fi
  else
    echo "  Tip: set EXPECTED_CHECKSUM=<hash> to enable automatic verification." >&2
  fi

  bash "$tmp/$SKILL_NAME/install.sh" "$@"
}

list_agents() {
  hdr "Installation paths:"
  for agent in $(printf '%s\n' "${!AGENT_PATHS[@]}" | sort); do
    local dest="${AGENT_PATHS[$agent]}/$SKILL_NAME"
    if [ -d "$dest" ]; then
      ok "  $agent → $dest (installed)"
    else
      warn "  $agent → ${AGENT_PATHS[$agent]} (not installed)"
    fi
  done
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
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent|-a)   TARGET_AGENT="$2"; shift 2 ;;
    --list|-l)    MODE="list"; shift ;;
    --uninstall)  MODE="uninstall"; shift ;;
    --force|-f)   FORCE=true; shift ;;
    --help|-h)
      echo "Usage: bash install.sh [--agent NAME] [--list] [--uninstall] [--force]"
      echo ""
      echo "  --force, -f   Overwrite existing installation without backup prompt"
      echo ""
      echo "Available agents: $(printf '%s\n' "${!AGENT_PATHS[@]}" | sort | tr '\n' ' ')"
      exit 0 ;;
    *) err "Unknown argument: $1"; exit 1 ;;
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

# ── Installation ─────────────────────────────────────────────────────────────
hdr "Installing $SKILL_NAME v$(grep '^version:' "$SCRIPT_DIR/SKILL.md" | awk '{print $2}')"

if [ -n "$TARGET_AGENT" ]; then
  # Specific agent
  if [[ -z "${AGENT_PATHS[$TARGET_AGENT]+x}" ]]; then
    err "Unrecognized agent: $TARGET_AGENT"
    echo "Available agents: $(printf '%s\n' "${!AGENT_PATHS[@]}" | sort | tr '\n' ' ')"
    exit 1
  fi
  install_to "$TARGET_AGENT"
else
  # All detected agents
  mapfile -t detected < <(detect_agents)

  if [ ${#detected[@]} -eq 0 ]; then
    warn "No agents detected automatically."
    warn "Use --agent NAME to specify one manually."
    warn "Available agents: $(printf '%s\n' "${!AGENT_PATHS[@]}" | sort | tr '\n' ' ')"
    exit 0
  fi

  echo "Detected agents: ${detected[*]}"
  for agent in "${detected[@]}"; do
    install_to "$agent"
  done
fi

hdr "Done."
echo "Restart the agent and type /skills to verify."
