# code-analyzer

**Version**: 1.5.0 · **License**: MIT · **Standard**: [Agent Skills](https://agentskills.io)

Skill for AI coding agents that deeply analyzes any source file or code snippet. Explains what the code does, documents every function, detects bugs, verifies dependencies online, generates UML diagrams and database schemas, and produces quality metrics — all automatically saved in a timestamped directory.

---

## Output files

Each analysis creates a timestamped subdirectory `code-analyzer/YYYY-MM-DDTHH-MM-SS-Report/` containing:

| File | Contents |
|---|---|
| `analysis.md` | Full report: overview, component analysis, API check, bugs, architectural patterns, metrics, sources |
| `summary.md` | Quick-reference card: what the code does, input/output of each function, realistic examples with edge cases |
| `uml-schema.md` | Mermaid `classDiagram` UML diagram with classes, interfaces, relationships and visibility *(if detected)* |
| `database-schema.md` | Mermaid `erDiagram` ER schema with tables, fields, PK, FK and relations *(if detected)* |
| `requirements_python.txt` | Dependencies extracted from the virtual environment *(if present)* |
| `requirements_typescript.txt` | Dependencies from `package.json` and installed versions *(if present)* |

---

## Compatibility

Follows the **open [Agent Skills](https://agentskills.io) standard** — works on all major AI agents:

| Agent | Instructions | Scripts |
|---|---|---|
| **OpenAI Codex CLI** | X | X |
| **Claude Code** | X | X |
| **GitHub Copilot** (VS Code) | X | X |
| **Cursor** | X | X |
| **Windsurf** | X | X |
| **Google Gemini CLI** | X | X |
| **OpenCode** | X | X |
| **Goose** (Block) | X | X |
| **Roo Code** | X | X |
| **Amp** | X | X |

Scripts require Node.js (already bundled with most agents). If Node is unavailable, the skill still runs all 12 analysis steps — library versions are retrieved via web search instead of the local environment.

---

## Requirements

- **Node.js** v16+ (for the `.js` scripts — included in most agents)
- **Git** (for installation via clone or npx)
- Internet access (the skill searches online to verify library versions and APIs)

---

## Installation

### Method 1 — Automatic script (recommended)

Detects installed agents and copies the skill to the correct directories:

```bash
git clone https://github.com/Aldo-Forte/code-analyzer
cd code-analyzer
bash install.sh
```

Options:

```bash
bash install.sh                         # install on all detected agents
bash install.sh --agent claude-code     # Claude Code only
bash install.sh --agent codex           # Codex CLI only
bash install.sh --list                  # show detected agents and paths
bash install.sh --uninstall             # remove from all agents
```

Supported agent names: `claude-code`, `codex`, `opencode`, `cursor`, `windsurf`, `gemini`, `goose`, `agents`.

### Method 2 — npx skills CLI

```bash
# Install code-analyzer on all detected agents
npx skills add Aldo-Forte/skills --skill code-analyzer --all

# Install on a specific agent only
npx skills add Aldo-Forte/skills --skill code-analyzer --agent claude-code
npx skills add Aldo-Forte/skills --skill code-analyzer --agent codex
```

### Method 3 — Manual git clone

```bash
# Claude Code
git clone https://github.com/Aldo-Forte/code-analyzer ~/.claude/skills/code-analyzer

# Codex CLI
git clone https://github.com/Aldo-Forte/code-analyzer ~/.codex/skills/code-analyzer

# Cursor
git clone https://github.com/Aldo-Forte/code-analyzer ~/.cursor/skills/code-analyzer

# OpenCode
git clone https://github.com/Aldo-Forte/code-analyzer ~/.config/opencode/skills/code-analyzer
```

With git clone, future updates are a single command run inside the installed directory:

```bash
git -C ~/.claude/skills/code-analyzer pull
```

---

## Uninstall

```bash
# Remove from all agents
npx skills remove code-analyzer --all

# Remove from a specific agent
npx skills remove code-analyzer --agent claude-code
npx skills remove code-analyzer --agent codex
```

Or manually by deleting the folder:

```bash
rm -rf ~/.claude/skills/code-analyzer    # Claude Code
rm -rf ~/.codex/skills/code-analyzer     # Codex
rm -rf ~/.cursor/skills/code-analyzer    # Cursor
rm -rf ~/.windsurf/skills/code-analyzer  # Windsurf
```

---

## Usage

**Explicit invocation** (type `$` followed by the skill name):

```
$code-analyzer analyze src/app.py
$code-analyzer analyze the project at /home/user/myapp
$code-analyzer what does this code do: <paste snippet>
```

**Implicit invocation** — the agent activates the skill automatically with phrases like:

- *"explain this code"*
- *"analyze this file"*
- *"what does this function do?"*
- *"what libraries does it use?"*
- *"is this code correct?"*
- *"are there any bugs here?"*

---

## The 12 analysis steps

| Step | What it does |
|---|---|
| **1** | Detects the language — supports mixed Python + TypeScript projects |
| **1b** | Extracts dependencies from the Python venv or `node_modules` |
| **2** | Overview: purpose, architectural pattern, size, complexity |
| **3** | Library table: installed vs current version (verified online) with update status |
| **4** | Detailed analysis of each function/class: input, output, internal logic |
| **5** | Verifies API and external library correctness online |
| **6** | Detected bugs with impact and reproduction steps + unclear parts |
| **7** | Advisory architectural suggestions: applicable patterns and anti-patterns |
| **8** | Quality metrics: cyclomatic complexity, nesting, type hints, `any`, `var`… |
| **9** | 3-sentence summary + complete table of all sources consulted online |
| **10** | `summary.md` quick-reference with examples and edge cases per function |
| **11** | `uml-schema.md` — Mermaid `classDiagram` *(if classes/interfaces detected)* |
| **12** | `database-schema.md` — Mermaid `erDiagram` with PK, FK and relations *(if tables detected)* |

---

## Supported languages

Any language for code analysis. Automatic dependency extraction for:

- **Python** — virtual environment (`.venv`, `venv`, `env`, `.env`, `virtualenv`), fallback to `requirements.txt` / `pyproject.toml`
- **TypeScript / JavaScript** — `package.json` + `node_modules`, compatible with **npm**, **Yarn v1**, **Yarn Berry (v2+)** and **pnpm**

---

## Troubleshooting

### The skill does not create any files

**Most common cause: the agent was not restarted after installation.**
Close and reopen the agent completely, then try again.

If the problem persists:
1. Verify the skill is installed in the correct path — run `bash install.sh --list` or check manually:
   ```bash
   ls ~/.claude/skills/code-analyzer/SKILL.md    # Claude Code
   ls ~/.codex/skills/code-analyzer/SKILL.md     # Codex
   ```
2. Make sure Node.js is available: `node --version`
3. Try invoking the skill explicitly: `$code-analyzer analyze <your_file>`

---

### The skill is not recognized / not activating

- **Restart the agent** — most agents load skills at startup only
- **Check the installation path** — the structure must be exactly `<skills_dir>/code-analyzer/SKILL.md`, not a nested extra level
- **Try explicit invocation**: type `$code-analyzer` or `/skills` to see what is loaded
- If you used npx, verify with: `npx skills list`

---

### No `requirements_python.txt` or `requirements_typescript.txt` created

These files are **optional** — they are only created when:
- A Python virtual environment is found (`.venv`, `venv`, `env`, etc.)
- A `package.json` with `node_modules` is found

If your project has a venv but the file is not created:
1. Make sure the venv is inside the project root
2. Check that `pip` is present and executable: `ls .venv/bin/pip`
3. Run the script manually to see the error:
   ```bash
   node ~/.claude/skills/code-analyzer/scripts/extract_requirements_python.js .
   ```

---

### On Windows: scripts don't run

The `.js` scripts require Node.js and work natively on Windows. If you get errors:

1. **Check Node.js is installed**: open Command Prompt and run `node --version`
2. **Install Node.js** if missing: [nodejs.org](https://nodejs.org) (LTS version recommended)
3. **Run manually** to see the error:
   ```cmd
   node %USERPROFILE%\.claude\skills\code-analyzer\scripts\init_report_dir.js .
   ```
4. If the agent cannot run scripts at all, the skill still works for all 12 analysis steps — library versions will be retrieved via web search instead of the local environment.

---

### On macOS/Linux: permission denied on `.sh` scripts

```bash
chmod +x ~/.claude/skills/code-analyzer/scripts/*.sh
```

---

### The skill produces incomplete results

- **No internet access**: Steps 3, 5, 6, 7, 8 require online searches — make sure the agent has internet access
- **File too large**: files over 800 lines are analyzed with public/exported components only; private components are skipped by design
- **Snippet without a project path**: dependency versions (Step 1b) are skipped for inline snippets — this is expected behavior

---

### Updating the skill

```bash
# If installed via git clone
git -C ~/.claude/skills/code-analyzer pull

# If installed via npx
npx skills update

# If installed via install.sh
bash install.sh   # re-run: it detects existing installation and updates it
```

---

## Skill structure

```
code-analyzer/
├── SKILL.md                                ← agent instructions
├── install.sh                              ← cross-platform install script
├── scripts/
│   ├── init_report_dir.js                  ← creates the timestamped report directory (cross-platform)
│   ├── extract_requirements_python.js      ← extracts Python venv dependencies (cross-platform)
│   ├── extract_requirements_typescript.js  ← extracts node_modules dependencies (cross-platform)
│   ├── init_report_dir.sh                  ← bash version (macOS/Linux)
│   ├── extract_requirements_python.sh      ← bash version (macOS/Linux)
│   └── extract_requirements_typescript.sh  ← bash version (macOS/Linux)
└── references/
    ├── general.md                          ← multi-language patterns and anti-patterns
    ├── python.md                           ← PEP guidelines, conventions, common libraries
    └── javascript.md                       ← ES versions, npm, TypeScript, async checklist
```

---

## License

MIT