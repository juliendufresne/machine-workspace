# Shellspec style guide

The conventions every shellspec test file (`*_spec.sh`) in this repository
follows: file header, Include guard, section separators, description sentences,
stream subject names, test structure order, blank stream assertions, eq vs
include, wrapper naming, dependency mocking, filesystem isolation, and spacing.
The specs under `dev/test/shell/` are the worked examples; this page is the
reference they all conform to.

These rules are also the source of truth for the `fix-shellspec-style` skill,
which applies them mechanically. Edit a rule here and the skill follows.

The rules describe formatting only. They never call for refactoring test logic,
renaming variables, or changing what is being tested.

> **Related (lives in the [shell style guide](shell-style.md)).** These rules
> edit only `*_spec.sh` files. The script under test keeps its
> `# ─── Execute ───` line on a single line -
> `[[ "${BASH_SOURCE[0]}" != "$0" ]] || <prefix>::main "$@"` - so kcov does not
> count the never-sourced `::main` call as an uncovered line. That rule changes
> the executed script, not the spec, so it lives in the shell style guide
> (File structure, Execute section).

## Rules

### 1 - Include line

The outermost `Describe` block must be followed immediately by:

```shellspec
Describe 'lib/foo.sh'
    TEST_FLAG=true
    Include lib/foo.sh

    ...
```

One blank line must follow the `Include` line before anything else (nested
`Describe` blocks, helpers, `BeforeAll`, etc.).

### 2 - Section separators

Each nested `Describe` block (one that describes a function under test) must be
preceded by a separator comment at the same indentation level:

```
    # ==========================================================================
    # function::name
    # ==========================================================================
```

The label must match the string passed to `Describe`.

Exception: the outermost `Describe` (names the file under test) and
`Describe 'constants'`-style structural groupings do not get separators.

### 3 - Stream subject names

Always use the canonical names:

- `The stdout` - never `The output`
- `The stderr` - never `The error`

```shellspec
# ✗
The output should include 'foo'
The error should include 'bar'

# ✓
The stdout should include 'foo'
The stderr should include 'bar'
```

### 4 - Test structure order

**Function tests** - every `It` block that calls a function via `When call` must
follow this assertion order:

1. `When call ...`
2. `The status should ...`
3. All `The stdout ...` assertions (at least one; use `be blank` if no output)
4. All `The stderr ...` assertions (at least one; use `be blank` if no stderr)

No blank lines between any of these lines (see rule 10).

```shellspec
# ✓
            When call foo 'arg'
            The status should be success
            The stdout should equal 'result'
            The stderr should be blank
```

**Variable tests** - every `It` block that only asserts `The variable` must
contain only `The variable` assertions. Do **not** add
`The stdout should be blank` or `The stderr should be blank` to variable tests.

```shellspec
# ✓
        It 'defines E_SUCCESS as 0'
            The variable E_SUCCESS should equal 0
        End
```

### 5 - `equal` vs `include`

Use `equal` (exact equality) when the full content of the stream is known. Use
`include` only when checking a substring of a larger, partially-known output.

```shellspec
# ✗ - if the full stdout is exactly 'build-dev'
The stdout should include 'build-dev'

# ✓
The stdout should equal 'build-dev'
```

A good signal for `equal`: the function is a getter or resolver that returns a
single value or token, or the `It` description says "returns X" / "outputs X".

When multiple `include` assertions together cover the entire known output, they
should be collapsed into a single `equal` assertion.

### 6 - Spacing: between top-level elements

Inside the outermost `Describe`, one blank line must separate each element:
`Include`, section-separator+`Describe` blocks, `BeforeAll`, helper definitions.

```shellspec
Describe 'lib/foo.sh'
    TEST_FLAG=true
    Include lib/foo.sh

    BeforeAll 'setup'

    # ====...====
    # foo::bar
    # ====...====
    Describe 'foo::bar'
        ...
    End

    # ====...====
    # foo::baz
    # ====...====
    Describe 'foo::baz'
        ...
    End

End
```

### 7 - Spacing: inside a nested `Describe`

Inside a nested `Describe`, maintain these blank-line rules:

**After opening** - one blank line after the `Describe '...'` line when it
contains `It` blocks or helper definitions directly.

**After Describe-level helpers** - one blank line after the last mock/fixture
definition (function or variable assignment) before the first `It` block.

**Between `It` blocks** - one blank line between consecutive `It` blocks.

**Between multi-line functions** - one blank line between consecutive multi-line
function definitions (a multi-line function is any function whose body spans
more than one line).

```shellspec
    Describe 'foo::bar'

        docker() { :; }
        git() { :; }

        It 'succeeds'
            When call foo::bar
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'fails when docker is down'
            docker() { return 1; }

            When call foo::bar
            The status should equal 1
            The stdout should be blank
            The stderr should include 'docker'
        End

    End
```

### 8 - Spacing: inside an `It` block

**Mock definitions** - one-liner mock functions (`func() { ...; }`) need no
trailing blank line unless a multi-line function follows.

**Before the When group** - one blank line before the When group. The "When
group" is: any variable assignments immediately followed by `When call ...` and
its assertions. The blank line goes before the first assignment (or before
`When call` if there are no assignments).

**Multi-line functions** - inside an `It` block, multi-line function bodies must
follow the function-body style from the [shell style guide](shell-style.md)
(applied to the body only). One blank line between multi-line functions.

```shellspec
        It 'strips npm noise from commitlint output'
            githooks::commit_msg::run_commitlint() {
                printf 'npm warn something\nsubject may not be empty\n'
                return 1
            }

            When call githooks::commit_msg::main
            The status should equal 1
            The stdout should be blank
            The stderr should include 'subject may not be empty'
            The stderr should not include 'npm warn'
        End
```

Variable assignments belong to the When group:

```shellspec
        It 'pops the stash when STASHED is 1'
            git() { :; }

            STASHED=1
            When call githooks::pre_commit::cleanup
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End
```

### 9 - No blank lines within the When group

`When call ...`, `The status`, `The stdout`, and `The stderr` assertions must
form a single uninterrupted block - no blank lines between them, and no blank
lines between variable assignments and `When call`.

```shellspec
# ✗
            STASHED=1

            When call foo

            The status should be success

# ✓
            STASHED=1
            When call foo
            The status should be success
            The stdout should be blank
            The stderr should be blank
```

### 10 - Description sentences

Every `Describe` and `It` string must form a grammatical sentence when read in
context, from outermost to innermost:

```
<file-name> <function-name> <It description>
```

The outermost `Describe` names the file (e.g. `'lib/output.sh'`). The nested
`Describe` names the function (e.g. `'output::print_success'`). The `It`
completes the sentence (e.g. `'outputs the message with a checkmark'`).

Reading left to right: _"lib/output.sh output::print_success outputs the
message with a checkmark"_ - this must clearly describe what is being tested.

Rules:

- The `It` string must start with a verb in the third person present tense (e.g.
  `'succeeds when ...'`, `'fails when ...'`, `'returns ...'`, `'outputs ...'`).
- Do not start with `'it '`, `'should '`, or `'test '` - those are implied.
- The sentence must be specific enough that a failing test identifies the exact
  scenario without reading the test body.

```shellspec
# ✗
It 'test docker check'
It 'should work'
It 'it returns the image name'

# ✓
It 'returns the image name from the environment variable'
It 'fails when docker is not running'
It 'succeeds and produces no output when the flag is set'
```

### 11 - Wrapper function naming

When the function under test cannot be called directly (e.g. it reads globals,
writes to the filesystem, or has side effects that must be isolated), a wrapper
function must be introduced. The wrapper must be named with the prefix
`wrapper::` followed by the exact function name under test:

```shellspec
# ✗
run_with_tmp() { ... }
isolated_docker_run() { ... }

# ✓
wrapper::docker::dev_tools::image_name() { ... }
wrapper::docker::dev_tools::run_args() { ... }
```

### 12 - Wrapper function contract

Every wrapper function must:

1. Save and restore all globals it modifies (restore in all exit paths).
2. Call the function under test exactly once.
3. Capture the exit status immediately after the call with `exit_status=$?`.
4. Return that exit status as its own return value - the wrapper must not mask
   it.

```shellspec
# ✓
wrapper::foo::bar() {
    local -i exit_status
    local real_root

    real_root="${PROJECT_ROOT:-}"
    PROJECT_ROOT="$(mktemp -d)"

    foo::bar "$@"
    exit_status=$?

    rm -rf "${PROJECT_ROOT}"
    PROJECT_ROOT="${real_root}"

    return "${exit_status}"
}
```

### 13 - Mock every dependency

Inside every `It` block (or at `Describe` level for shared mocks), every
external function called by the function under test must be mocked unless:

- It is a shell built-in (`printf`, `read`, `cd`, etc.).
- It is a pure utility that has no side effects and is safe to run in the test
  environment (e.g. `mktemp`, `mkdir`, `rm` on a temp directory created by a
  wrapper).

Mock at the lowest level of the test hierarchy where the mock applies. If a mock
is identical across all `It` blocks in a `Describe`, define it at `Describe`
level. Override it per-`It` only when the test scenario requires a different
behaviour.

```shellspec
# ✗ - docker is called by the function under test but not mocked
It 'succeeds when the image exists'
    When call docker::dev_tools::ensure 'test-image'
    The status should be success
    ...
End

# ✓
It 'succeeds when the image exists'
    docker() { case "$*" in *'image inspect'*) return 0 ;; *) return 1 ;; esac; }

    When call docker::dev_tools::ensure 'test-image'
    The status should be success
    ...
End
```

### 14 - No persistent filesystem writes

Tests must never write to the real filesystem outside of temporary directories.
Any function that writes files must be tested through a wrapper that:

1. Creates a temporary directory with `mktemp -d -t shellspec-{filename}-XXXXXXXXXX`.
2. Redirects the relevant global (e.g. `PROJECT_ROOT`) to that directory.
3. Removes the temporary directory after the call (even on failure).

If the function under test does not accept a configurable path and always writes
to a fixed location, it must be refactored - do not work around it by hardcoding
paths in tests.

```shellspec
# ✗ - writes to real PROJECT_ROOT
It 'creates the .env file'
    When call foo::create_env
    ...
End

# ✓ - wrapper isolates all writes to a temp directory
wrapper::foo::create_env() {
    local -i exit_status
    local real_root
    local tmp_dir

    real_root="${PROJECT_ROOT:-}"
    tmp_dir="$(mktemp -d)"
    PROJECT_ROOT="${tmp_dir}"

    foo::create_env "$@"
    exit_status=$?

    rm -rf "${tmp_dir}"
    PROJECT_ROOT="${real_root}"

    return "${exit_status}"
}

It 'creates the .env file'
    When call wrapper::foo::create_env
    ...
End
```

### 15 - functions test order

Every function under test must be tested in the same order as it is defined in
the file.
