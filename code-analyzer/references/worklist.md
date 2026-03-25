# Code Analyzer — Security Bug Worklist

> Generated: 2026-03-25
> Source: Static security audit (Snyk-style, 4 passes)
> Severity scale: 1 (lowest) to 10 (highest)

---

## Severity 10 — Critical

### [ ] BUG-001: Symlink attack on pip executable (CWE-61)

**Files:** `scripts/extract_requirements_python.sh`, `scripts/extract_requirements_python.js`

**Description:**
The script searches for `pip` inside standard venv directories (`.venv/bin/pip`, `venv/bin/pip`, etc.) and executes it directly. If an attacker replaces the `pip` binary with a symlink pointing to a malicious executable outside the venv, the script runs that executable with the user's privileges. This is a classic symlink attack (CWE-61: UNIX Symbolic Link Following).

**How to fix:**
After locating the `pip` binary, resolve its real path using `fs.realpathSync()` (JS) or `readlink`/`realpath` (bash). Then verify the resolved path is still inside the venv directory. If it resolves outside the venv, abort with an error.

**Steps:**
1. After finding `pipCmd`, call `fs.realpathSync(pipCmd)` to get the canonical path
2. Also resolve `foundVenv` with `fs.realpathSync(foundVenv)`
3. Check that `realPip.startsWith(realVenv + path.sep)` is true
4. If false, print a security error and `process.exit(1)`
5. In bash: use `portable_realpath` (see BUG-002) to resolve both paths, then use a `case` statement to verify containment

**References:**
- CWE-61: https://cwe.mitre.org/data/definitions/61.html
- Node.js `fs.realpathSync`: https://nodejs.org/api/fs.html#fsrealpathsyncpath-options

---

### [ ] BUG-002: Symlink checks silently bypassed on macOS (CWE-22)

**Files:** All 4 bash scripts (`init_report_dir.sh`, `extract_requirements_python.sh`, `extract_requirements_typescript.sh`)

**Description:**
The original symlink resolution used `readlink -f` as the primary method. On macOS, BSD `readlink` does not support the `-f` flag. The `realpath` command is only available on macOS 13+ (Ventura). On older macOS versions, both fail and the fallback was `echo "$path"`, which returns the path unchanged — silently disabling all symlink protection (CWE-22 path traversal and CWE-61 symlink attacks).

Additionally, the fallback `cd dir && pwd` (without `-P`) returns the logical path on macOS, which may still contain symlinks.

**How to fix:**
Replace the `readlink -f || realpath || echo` chain with a `portable_realpath()` function that works on all platforms. The function must:
1. Try `realpath` first (available on modern systems)
2. Try `readlink -f` second (available on GNU/Linux)
3. Fall back to manual resolution using `pwd -P` (POSIX, works everywhere) for directories
4. For files: follow the symlink chain using `readlink` (without `-f`, available on all platforms) in a `while [ -L ]` loop, re-resolving the directory component with `pwd -P` after each hop

**Steps:**
1. Define `portable_realpath()` at the top of each bash script, before any path operations
2. The function must handle three cases:
   - **Directory target**: `(cd "$target" && pwd -P)`
   - **File target**: resolve directory with `cd + pwd -P`, then follow file-level symlinks with `while [ -L "$current" ]; do readlink "$current"; done`, re-resolving the directory after each hop
   - **Non-existent target**: return the path unchanged (caller checks existence separately)
3. Handle both absolute and relative symlink targets in the loop (`case "$link_target" in /*) absolute ;; *) relative ;;`)
4. Replace every occurrence of `readlink -f ... || realpath ... || echo ...` with `portable_realpath`
5. Test on macOS with a real symlink chain to verify resolution

**References:**
- CWE-22: https://cwe.mitre.org/data/definitions/22.html
- POSIX `pwd -P`: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/pwd.html
- macOS `readlink` (BSD): https://www.freebsd.org/cgi/man.cgi?query=readlink

---

## Severity 8 — High

### [ ] BUG-003: Installation overwrites without backup (destructive operation)

**File:** `install.sh` (function `install_to`, line with `rm -rf "$dest"`)

**Description:**
When the skill is already installed (non-git copy), the installer runs `rm -rf "$dest"` to remove the old version before copying the new one. If the copy fails (disk full, permission error), the old installation is lost with no way to recover. There is no backup and no user confirmation.

**How to fix:**
Before `rm -rf`, create a timestamped backup of the existing installation. Add a `--force` flag that skips the backup for automated/CI use.

**Steps:**
1. Add a `FORCE=false` variable and `--force|-f` flag to argument parsing
2. In `install_to()`, before the `rm -rf` block, compute `backup="${dest}.backup.$(date '+%Y%m%d%H%M%S')"`
3. If `FORCE` is false: `cp -r "$dest" "$backup"` and print the backup path
4. If `FORCE` is true: print a message and skip the backup
5. Then proceed with `rm -rf "$dest"` and `cp -r "$SCRIPT_DIR" "$dest"`
6. Update `--help` output to document the `--force` flag

**References:**
- Defensive scripting best practices: https://mywiki.wooledge.org/BashPitfalls

---

## Severity 7 — High-Medium

### [ ] BUG-004: Insecure file permissions on created directories and files (CWE-276)

**Files:** All 6 scripts (`.sh` and `.js` versions of `init_report_dir`, `extract_requirements_python`, `extract_requirements_typescript`)

**Description:**
Directories created with `mkdir -p` (bash) and `fs.mkdirSync({ recursive: true })` (JS) inherit permissions from the system umask. Files created with `>` redirect (bash) and `fs.writeFileSync` (JS) also depend on umask. If the user has a permissive umask (e.g., `0022`), report directories are world-readable (`drwxr-xr-x`) and report files are world-readable (`-rw-r--r--`). Reports may contain sensitive information from the analyzed code.

**How to fix:**
Set explicit restrictive permissions on all created directories and files:
- Directories: `0700` (owner read/write/execute only)
- Files: `0600` (owner read/write only)

**Steps:**
1. **Bash directories**: add `-m 0700` to every `mkdir -p` call
2. **Bash files**: add `chmod 0600 "$file"` immediately after creating each output file
3. **Bash log files**: use `install -m 0600 /dev/null "$logfile"` to pre-create with correct permissions before redirecting stderr to them
4. **JS directories**: add `mode: 0o700` to every `fs.mkdirSync()` options object
5. **JS files**: change `fs.writeFileSync(path, data, 'utf8')` to `fs.writeFileSync(path, data, { encoding: 'utf8', mode: 0o600 })`
6. **JS log files**: add `0o600` as third argument to `fs.openSync(path, 'w', 0o600)`

**References:**
- CWE-276: https://cwe.mitre.org/data/definitions/276.html
- Node.js `fs.mkdirSync` options: https://nodejs.org/api/fs.html#fsmkdirsyncpath-options
- Node.js `fs.writeFileSync` options: https://nodejs.org/api/fs.html#fswritefilesyncfile-data-options

---

### [ ] BUG-005: TOCTOU race condition on report directory creation (CWE-367)

**Files:** `scripts/init_report_dir.sh`, `scripts/init_report_dir.js`

**Description:**
The script checks if a directory exists (`fs.existsSync` / `[ -d ]`) and then creates it (`fs.mkdirSync` / `mkdir`). Between the check and the create, another process could create the same directory, causing either an error or two processes sharing the same report directory (data corruption). This is a classic TOCTOU (Time-of-Check to Time-of-Use) race condition.

**How to fix:**
Replace the check-then-create pattern with atomic creation: try to create the directory directly, and handle the `EEXIST` error to try the next counter value.

**Steps:**
1. **JS**: Remove the `while (fs.existsSync(...))` loop. Replace with a `while (!created)` loop that calls `fs.mkdirSync(reportDir, { mode: 0o700 })` (without `recursive`) inside a try/catch. On `EEXIST` error, increment counter and try next name. On other errors, re-throw.
2. **Bash**: Remove the `while [ -d "$REPORT_DIR" ]` loop. Replace with `while true; do if mkdir -m 0700 "$REPORT_DIR" 2>/dev/null; then break; fi; ...`. The `mkdir` (without `-p`) fails atomically if the directory exists.
3. Add `MAX_ATTEMPTS=100` limit to prevent infinite loops (also fixes BUG-010)

**References:**
- CWE-367: https://cwe.mitre.org/data/definitions/367.html
- TOCTOU explanation: https://en.wikipedia.org/wiki/Time-of-check_to_time-of-use

---

## Severity 6 — Medium

### [ ] BUG-006: Path traversal on reportDir argument (CWE-22)

**Files:** `extract_requirements_python.sh`, `extract_requirements_python.js`, `extract_requirements_typescript.sh`, `extract_requirements_typescript.js`

**Description:**
The second argument (`reportDir` / `$REPORT_DIR`) passed to the extraction scripts is used as the output directory for report files. This argument is resolved with `path.resolve()` (JS) or used directly (bash) but is not validated against symlinks. An attacker who controls this argument could point it to a symlink targeting a sensitive directory, causing the script to write files there.

**How to fix:**
Apply the same symlink resolution used for `projectDir` to the `reportDir` argument.

**Steps:**
1. **JS**: After `path.resolve(reportDirArg)`, check `fs.existsSync(outputDir)` and if true, apply `fs.realpathSync(outputDir)` to resolve symlinks
2. **Bash**: After checking `[ -d "$REPORT_DIR" ]`, apply `portable_realpath "$REPORT_DIR"` to resolve symlinks
3. If the directory does not exist yet, accept the path as-is (it will be created fresh, no symlink to follow)

**References:**
- CWE-22: https://cwe.mitre.org/data/definitions/22.html

---

### [ ] BUG-007: stderr silenced with /dev/null hides real errors

**Files:** `extract_requirements_python.sh`, `extract_requirements_python.js`, `extract_requirements_typescript.sh`, `extract_requirements_typescript.js`

**Description:**
All extraction scripts redirect stderr from `pip freeze`, `npm list`, `yarn list`, and `pnpm list` to `/dev/null` (bash: `2>/dev/null`, JS: `stdio: ['ignore', 'pipe', 'ignore']`). This hides not just expected warnings (peer dep issues) but also real errors (corrupted packages, permission problems, network failures). Debugging becomes impossible when these commands fail silently.

**How to fix:**
Redirect stderr to a log file in the report directory instead of discarding it. Remove the log file if empty (no warnings). Warn the user if warnings were produced.

**Steps:**
1. Define a log file path: `pip_warnings.log` or `npm_warnings.log` in the output directory
2. **Bash**: Pre-create the log file with `install -m 0600 /dev/null "$LOG_FILE"`, then redirect with `2>"$LOG_FILE"` instead of `2>/dev/null`
3. **JS**: Open the log file with `fs.openSync(logFile, 'w', 0o600)`, pass the fd as stdio[2] in `execFileSync`/`spawnSync`, close after execution
4. After the command completes: check if log file is empty (`[ -s "$LOG" ]` / `fs.statSync().size`), remove if empty, otherwise print a warning to stderr
5. Apply to all commands: `pip freeze`, `npm list`, `yarn list`, `pnpm list`, `yarn --version`

**References:**
- Node.js `child_process` stdio: https://nodejs.org/api/child_process.html#optionsstdio

---

### [ ] BUG-008: Unbounded file reads can cause OOM (CWE-400)

**Files:** `extract_requirements_typescript.js` (lines reading `package.json` and `tsconfig.json`), `extract_requirements_typescript.sh` (inline `node -e` and `cat`)

**Description:**
The scripts read `package.json` and `tsconfig.json` into memory without checking file size first. A malicious or corrupted file of several GB would exhaust available memory, crashing the process (Denial of Service). The JS standalone version uses `fs.readFileSync` which loads the entire file into a string; the bash version pipes through `node -e` or `cat` which also buffers in memory.

**How to fix:**
Check file size before reading. Reject files exceeding a reasonable limit (10 MB).

**Steps:**
1. Define `MAX_JSON_SIZE = 10 * 1024 * 1024` (10 MB) as a constant
2. **JS**: Before `fs.readFileSync`, call `fs.statSync(path).size` and compare against the limit. If exceeded, print error and `process.exit(1)` (for package.json) or skip with a note (for tsconfig.json)
3. **Bash**: Before reading, use `wc -c < "$FILE"` to get byte count and compare with `$MAX_FILE_SIZE`. If exceeded, print error and exit (package.json) or skip (tsconfig.json)
4. Apply to both `package.json` (hard fail) and `tsconfig.json` (soft skip with message)

**References:**
- CWE-400: https://cwe.mitre.org/data/definitions/400.html
- Node.js `fs.statSync`: https://nodejs.org/api/fs.html#fsstatsyncpath-options

---

### [ ] BUG-009: Child process calls without timeout (CWE-400)

**Files:** `extract_requirements_python.js` (`execFileSync`), `extract_requirements_typescript.js` (all `spawnSync` calls)

**Description:**
All calls to `execFileSync` and `spawnSync` have no `timeout` option. If `pip freeze` hangs (broken package, network issue), or `npm list` / `yarn list` / `pnpm list` hang (registry timeout, corrupted lockfile), the script blocks indefinitely. This is a Denial of Service condition — the analysis never completes and the user must manually kill the process.

**How to fix:**
Add a `timeout` option to every `execFileSync` and `spawnSync` call.

**Steps:**
1. **extract_requirements_python.js**: Add `timeout: 60000` (60 seconds) to the `execFileSync(pipCmd, ['freeze'], { ... })` options
2. **extract_requirements_typescript.js**: Define `const SPAWN_TIMEOUT = 30000` (30 seconds) at the start of the section
3. Add `timeout: SPAWN_TIMEOUT` to every `spawnSync` call: `npm --version`, `npm list`, `yarn --version`, `yarn list`/`workspaces list`, `pnpm list` (both calls)
4. When a timeout occurs, `spawnSync` returns `{ status: null, signal: 'SIGTERM' }` — existing error handling (`|| true`, stdout check) already covers this gracefully

**References:**
- CWE-400: https://cwe.mitre.org/data/definitions/400.html
- Node.js `execFileSync` timeout: https://nodejs.org/api/child_process.html#child_processexecfilesyncfile-args-options
- Node.js `spawnSync` timeout: https://nodejs.org/api/child_process.html#child_processspawnsynccommand-args-options

---

### [ ] BUG-010: SHA256 checksum is informational only, no automatic verification (CWE-345)

**File:** `install.sh` (function `install_from_github`)

**Description:**
When installing from GitHub via `curl | bash`, the script computes a SHA256 checksum of `SKILL.md` and prints it to stdout. However, it does not compare it against any known-good value. The user is expected to verify manually, which in practice never happens. This makes the checksum purely cosmetic — it does not prevent installing a tampered repository.

**How to fix:**
Support an optional `EXPECTED_CHECKSUM` environment variable. When set, compare the computed checksum against it and abort on mismatch. When not set, print the checksum with a tip to enable verification.

**Steps:**
1. After computing `$checksum`, check if `${EXPECTED_CHECKSUM:-}` is non-empty
2. If set: compare `$checksum` with `$EXPECTED_CHECKSUM`. If equal, print success. If different, print both values and `exit 1`
3. If not set: print the checksum and a tip message: `"Tip: set EXPECTED_CHECKSUM=<hash> to enable automatic verification."`
4. Document usage in the script header: `EXPECTED_CHECKSUM=abc123 curl -fsSL ... | bash`

**References:**
- CWE-345: https://cwe.mitre.org/data/definitions/345.html
- Supply chain security: https://slsa.dev/spec/v1.0/threats

---

## Severity 5 — Medium-Low

### [ ] BUG-011: Information disclosure — full filesystem paths in output files (CWE-200)

**Files:** `extract_requirements_python.sh`, `extract_requirements_python.js`, `extract_requirements_typescript.sh`, `extract_requirements_typescript.js`

**Description:**
The report header comments in output files include full absolute paths (e.g., `# Project: /Users/aldo/Projects/myapp`, `# Venv: /Users/aldo/Projects/myapp/.venv`). If the report is shared (code review, issue tracker, documentation), this leaks the filesystem structure and potentially the username.

**How to fix:**
Use `basename` instead of the full path in file output headers.

**Steps:**
1. **Bash**: Replace `$PROJECT_DIR` with `$(basename "$PROJECT_DIR")` and `$FOUND_VENV` with `$(basename "$FOUND_VENV")` in the output header `echo` statements
2. **JS**: Replace `projectDir` with `path.basename(projectDir)` and `foundVenv` with `path.basename(foundVenv)` in the header string array
3. Stderr messages (shown only in terminal, not saved) can keep full paths for debugging — only the file output needs redaction

**References:**
- CWE-200: https://cwe.mitre.org/data/definitions/200.html

---

### [ ] BUG-012: git pull on existing installation has no integrity check

**File:** `install.sh` (function `install_to`, git pull branch)

**Description:**
When updating an existing git-cloned installation, `git pull --quiet` runs with no integrity verification afterward. Unlike `install_from_github()` which logs the commit hash and computes a SHA256 checksum, the update path gives no audit trail. If the remote repository is compromised, the update is applied silently.

**How to fix:**
Log the commit hash after `git pull` to maintain parity with the fresh install path.

**Steps:**
1. After `git -C "$dest" pull --quiet`, add:
   ```bash
   local updated_hash
   updated_hash="$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo "unknown")"
   echo "  Updated to commit: $updated_hash"
   ```
2. This provides an audit trail in terminal output without blocking the update

**References:**
- Git security: https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work

---

## Severity 4 — Low

### [ ] BUG-013: Unbounded collision counter causes potential infinite loop (CWE-400)

**Files:** `scripts/init_report_dir.sh`, `scripts/init_report_dir.js`

**Description:**
The collision counter that appends `-1`, `-2`, etc. to the report directory name has no upper bound. If the filesystem is in an unusual state (e.g., hundreds of pre-existing directories matching the pattern), the loop runs indefinitely.

**How to fix:**
Add a `MAX_ATTEMPTS` constant and abort if reached.

**Steps:**
1. Define `MAX_ATTEMPTS=100`
2. In the loop, increment a counter and compare against `MAX_ATTEMPTS` on each iteration
3. If reached, print an error and exit with code 1
4. This is resolved together with BUG-005 (TOCTOU fix) since the atomic creation loop already needs a counter

**References:**
- CWE-400: https://cwe.mitre.org/data/definitions/400.html

---

### [ ] BUG-014: Web search rate limiting not enforced (SKILL.md)

**File:** `SKILL.md` (Steps 3, 5, 7, 8 — all steps that search online)

**Description:**
The skill instructions tell the agent to search online for library versions, documentation, and patterns across multiple steps. There is no guidance on deduplication, batching, or limiting the number of searches. This can result in excessive requests to search engines (potential rate-limiting or blocking) and unnecessarily slow analysis.

**How to fix:**
Add a security rule (W015) in SKILL.md with explicit constraints on web search behavior.

**Steps:**
1. Add a new rule `W015 — Web search rate limiting` in the "Security rules" section
2. Include these constraints:
   - **Deduplicate**: check if the same library/topic was already searched earlier; reuse results
   - **Batch**: prefer a single search covering multiple packages over individual searches
   - **Limit**: max 20 distinct searches per single-file analysis, 40 for multi-file/directory
   - **Cache**: if the same URL was already fetched, reference the earlier result instead of fetching again
3. Specify that security-related searches take priority over informational ones when approaching the limit

**References:**
- Rate limiting best practices: https://cloud.google.com/architecture/rate-limiting-strategies-techniques

---

### [ ] BUG-015: Emoji characters in script output cause encoding issues

**Files:** All scripts (`.sh` and `.js`)

**Description:**
All scripts use emoji characters (`[ERR]`, `[OK]`, `[WARN]`, `[INFO]`, etc.) in stderr output messages. Terminals or log systems that do not support UTF-8 encoding display garbled output or crash. CI/CD pipelines with `LANG=C` or `LC_ALL=C` are particularly affected.

**How to fix:**
Replace all emoji with ASCII-only text prefixes.

**Steps:**
1. Define a consistent mapping:
   - Error messages: `[ERR]`
   - Success messages: `[OK]`
   - Warning messages: `[WARN]`
   - Informational messages: `[INFO]`
2. Apply `replace_all` across every script file for each emoji
3. Verify no non-ASCII characters remain with `grep -P '[\x80-\xFF]'` on all script files

**References:**
- POSIX locale: https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap07.html

---

*End of worklist.*
