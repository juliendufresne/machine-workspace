# Shell style guide

The conventions every shell script in this repository follows: double-bracket
tests, structured docblocks, typed locals, blank-line rules, readonly functions,
main-function wrapping, and dependency-first ordering. Existing scripts under
`lib/`, `libexec/` and `bin/` are the worked examples; this page is the
reference they all conform to.

These rules are also the source of truth for the `fix-shell-style` skill, which
applies them mechanically. Edit a rule here and the skill follows.

The rules describe formatting only. They never call for refactoring logic,
renaming identifiers, or adding features.

## Rules

### 1 - True Bash: no single-bracket tests

Use `[[ ... ]]`, never `[ ... ]`. Use `source`, never `.` (the POSIX source
operator).

### 2 - File structure (in order)

1. Shebang + `set -euo pipefail`
2. Guard (sourced lib files only): `! declare -F <name of main or first function> &>/dev/null || return 0`
3. `# ─── Functions ───...`
4. `# ─── Runner contracts ───...` (software unit scripts only): the `unit::*`
   interface the runner calls, kept together between Functions and Main. See
   rule 14.
5. `# ─── Main ───...` (directly-executed scripts only; **omit for sourced lib files**)
6. `# ─── Constants / globals ───...`
7. `# ─── Imports ───...` (lib files that re-source dependencies)
8. `# ─── Execute ───...` (directly-executed scripts only): a single line that
   runs the entry point only when the file is executed directly, never when it
   is sourced (e.g. `Include`d by a shellspec spec):

   ```bash
   [[ "${BASH_SOURCE[0]}" != "$0" ]] || <prefix>::main "$@"
   ```

   Keep the guard test and the `::main` call on **one line**. Do **not** split it
   into a `[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0` guard followed by a
   separate `<prefix>::main "$@"` line. The reason is coverage: when the file is
   sourced under kcov (which is how shellspec instruments it), a standalone
   trailing `<prefix>::main "$@"` line is instrumented but never executed, so
   kcov reports it as an uncovered line and permanently deflates the entry
   point's coverage. Folding the guard and the call onto one line means the line
   is evaluated (the `[[ ... ]]` test runs) every time the file is loaded, so kcov
   counts it as covered, while `<prefix>::main "$@"` still only fires on direct
   execution. Note the condition is inverted (`!=`, not `==`): `[[ A != B ]] || C`
   runs `C` exactly when `A == B`, i.e. when the script is run directly.

### 3 - Function docblock format

Every function must have this block immediately above it:

```
#--------------------------------------------------
# Function:
#   <name> [<signature>]
#
# Description:
#   ...
#
# Arguments:
#   --option <val>  What it does
#   <positional>    What it does
#   N/A             (when no arguments)
#
# Returns:
#   0 on success
#   N on specific error
#
# Example:
#   <name> args
#--------------------------------------------------
```

Signature line rules:

- Include options and positional args; wrap optional ones in `[...]`.
- If there are more than 3 `--*` options, collapse them to `[OPTIONS]`.
- The `--` end-of-options separator is **not** listed in the Arguments section.
- Every section ends with a blank comment line (`#`) **except** the last section
  (Example).

Docblock accuracy - every section must reflect the function's actual behavior:

- **Description**: summarize what the function does, and also state anything it
  writes to stdout/stderr and any observable side effects (file writes, network
  calls, or other effects caused directly or through called functions). There
  are no dedicated Outputs or Side Effects sections - fold both into here.
- **Arguments**: the signature line and the Arguments table must match the
  function's actual parameters exactly (count, names, types, optionality).
- **Returns**: list every distinct exit code the function can emit, including
  those propagated from called functions via `|| return $?` or
  `return "${CONSTANT}"`.

### 4 - Local variable style

Inside every function:

1. Declare **all** locals at the very top with type annotations where
   applicable:
   - `local -i` for integers
   - `local -a` for arrays
   - `local -n` for namerefs
   - plain `local` for strings
   - **No inline initialization in declarations** (exception:
     `local exit_status=$?` to capture `$?` immediately).
2. Variable declaration list must be ordered alphabetically.
3. One blank line after the last `local` declaration.
4. Then, optionally (main functions only), a call to the project's stage/banner
   helper, if it has one.
5. Then assignments - set each variable as close as possible to its first use
   ("only set when needed"). Exceptions: variables that hold arguments must be
   declared after that stage/banner call.
6. One blank line before the first executable statement when assignments follow
   the declarations.
7. The variable that holds an exit/return status must be named `exit_status`.

### 5 - Blank lines before jump statements

Add one blank line before `return`, `exit`, `continue`, and `break` **unless**
the statement is the only line in its block.

### 6 - No semicolons for code blocks

`then` and `do` must be on their own line:

```bash
# ✗
if condition; then

# ✓
if condition
then
```

Avoid `;` for code-block delimiters everywhere. One-liner `&&`/`||` chains are
fine.

### 7 - Single quotes where possible

Use `'...'` instead of `"..."` for strings that contain no variable references or
escape sequences.

### 8 - readonly functions

After every function body, add:

```bash
[[ -v TEST_FLAG ]] || readonly -f <function_name>
```

### 9 - function naming

- All functions use a prefix based on their filename
  `<filename-without-extension>::*` (replace `-` with `::` in the name).
- **Software unit scripts** (`libexec/<os>_<version>/software/<name>.sh`) follow
  the filename rule like any other directly-executed script: the filename without
  `.sh` is the software name, so `git.sh` uses the `git::` prefix - `git::main`,
  and any local helper named `git::...`, in
  `libexec/ubuntu_26.04/software/git.sh`. Their contract functions instead use the
  `unit::` prefix (rule 14).
### 10 - main function wrapping

For directly executed scripts (not sourced libs):

- Wrap all top-level logic in a `<filename-without-extension>::main` function
  (replace `-` with `::` in the name).
- Internal helpers share the same prefix.
- The execute section calls `<prefix>::main "$@"`.

### 11 - Exit status codes

- `0` - success
- `1` - reserved for generic/unclassified errors (bare `return 1` is fine)
- `2` - bad arguments (maps to `E_ARGS` where the project defines one)
- `3+` - named error constants from the project's exit-codes library, if it
  has one (e.g. `lib/exit-codes.sh`)

If the project defines a central exit-codes library, do **not** introduce new
numeric literals for exit codes in lib files - use the named constants. If no
such library exists yet, the literals `0`/`1`/`2` above are acceptable.

### 12 - Output

- use `printf` for all output except multiline strings
- use `cat` for multiline strings
- use printf-style `%s` for strings
- use printf-style `%d` for integers
- use printf-style `%b` for binary data (e.g. base64, ANSI escape sequences, colors)

### 13 - Function declaration order

Every called function must be declared **above** the function that calls it.
Among functions called at the same call-site, order follows first-call sequence.

To determine the correct order, perform a post-order depth-first traversal of
the internal call graph, starting from the file's entry-point (the `::main`
function, or the first function named in the guard for sourced libs):

1. For each function called inside a function body (in the order they appear),
   recurse into it first.
2. After all callees are placed, place the current function.
3. Skip any function already placed (handles shared dependencies).

Only consider calls to functions **defined in the same file** when building the
graph; calls to external helpers (functions defined in other files or sourced
libraries) are ignored.

**Example** - `example` calls `first_call` then `second_call`; `second_call`
calls `first_inner_call` then `second_inner_call`:

```bash
first_call()        { :; }
first_inner_call()  { :; }
second_inner_call() { :; }
second_call()       { first_inner_call; second_inner_call; }
example()           { first_call; second_call; }
```

Each function (with its docblock and `readonly -f` line) moves as a unit; do
not reorder lines within a function.

### 14 - Software unit scripts: the `unit::*` contract

A software unit script (`libexec/<os>_<version>/software/<name>.sh`) is run by the
shared runner in `lib/runner.sh`. The runner defines no hooks of its own; it only
sequences and calls a fixed interface that every unit script implements:

| Function               | Purpose                                            |
| ---------------------- | -------------------------------------------------- |
| `unit::is_available`   | requirements to install are met                    |
| `unit::is_installed`   | the unit is present on the host by any means       |
| `unit::is_managed`     | the unit is present via our own mechanism          |
| `unit::is_configured`  | our configuration is in place                      |
| `unit::request_inputs` | collect inputs, warm sudo                          |
| `unit::install`        | install or update (idempotent)                     |
| `unit::configure`      | ensure the configuration is correct (idempotent)   |
| `unit::unconfigure`    | restore configuration to its prior state           |
| `unit::uninstall`      | remove what we installed (guarded by ownership)    |

Rules:

- The contract functions use the `unit::` prefix. It reads as the interface a
  unit implements and is deliberately distinct from `runner::*`, which is
  reserved for `lib/runner.sh`.
- The six non-configuration functions are required in every per-OS unit script.
  The three configuration functions (`unit::is_configured`, `unit::configure`,
  `unit::unconfigure`) are required only when the unit configures something: they
  live in a `configure` fragment under `lib/software/<name>/`, which the per-OS
  script sources before `lib/runner.sh`. The path records its scope:
  `lib/software/<name>/configure` when the code is OS independent (every target
  sources the one file), or `lib/software/<name>/<scope>/configure` when it is
  not, where `<scope>` is the family it applies to (for example
  `lib/software/neovim/debian-family/configure` for an
  `update-alternatives`-based config). A unit that configures nothing ships no
  `configure` fragment and inherits the runner's no-op defaults for those three.
  The runner calls every contract function by these exact names, so they are never
  given the software-name prefix from rule 9.
- The functions a per-OS script defines live together in a dedicated
  `# ─── Runner contracts ───` section, placed between `# ─── Functions ───` and
  `# ─── Main ───` (rule 2). The `configure` fragment mirrors this: its helpers under
  `# ─── Functions ───`, its three contract functions under
  `# ─── Runner contracts ───`.
- Every other function in the script (local helpers and the `::main` entry
  point) takes the software-name prefix from rule 9, for example `git::main` (and
  any local helper, `git::...`).
