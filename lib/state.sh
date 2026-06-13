#!/usr/bin/env bash
set -euo pipefail
# The persistent state store under $XDG_STATE_HOME/workspace
# (default ~/.local/state/workspace). It holds:
#
#   inputs/         the saved workspace registry, keyed by input name.
#   managed/        one marker per managed entry (unused here; kept harmless).
#   config/<id>/    the prior value of each configuration variable we set.
#   manifests/<id>  the paths a workspace created, so uninstall can tell our
#                   directory from one the user filled.
#
# <id> is the workspace instance id, workspace@<slug>.
#
# The MACHINE_SETUP_INPUTS_WORKING inputs overlay is left in the code but is never
# set in this tool: with the variable unset every read and write goes straight to
# the committed inputs/ directory, so the store behaves as a plain registry. There
# is no batching and no commit dance; the tool provisions inline as it goes.
# Sourced by lib/workspace.sh.

! declare -F state::_root &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   state::_root
#
# Description:
#   Prints the store root path, $XDG_STATE_HOME/workspace (default
#   ~/.local/state/workspace). Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   state::_root
#--------------------------------------------------
state::_root() {
    printf '%s/workspace' "${XDG_STATE_HOME:-$HOME/.local/state}"
}
[[ -v TEST_FLAG ]] || readonly -f state::_root

#--------------------------------------------------
# Function:
#   state::_dir <subdir>
#
# Description:
#   Ensures a sub-directory of the store exists, creating it with mkdir -p, and
#   prints its path. Writes the path to stdout and may create directories.
#
# Arguments:
#   <subdir>  The sub-directory under the store root
#
# Returns:
#   0 on success
#   non-zero when the directory cannot be created
#
# Example:
#   state::_dir inputs
#--------------------------------------------------
state::_dir() {
    local dir

    dir="$(state::_root)/$1"
    mkdir -p "$dir"

    printf '%s' "$dir"
}
[[ -v TEST_FLAG ]] || readonly -f state::_dir

#--------------------------------------------------
# Function:
#   state::_key <id>
#
# Description:
#   Prints a filesystem-safe token for an <id>, replacing every character
#   outside [A-Za-z0-9._@-] with an underscore (a workspace id holds a path with
#   slashes). Writes the token to stdout.
#
# Arguments:
#   <id>  The id to sanitise
#
# Returns:
#   0 on success
#
# Example:
#   state::_key 'workspaces/api@/srv/api'
#--------------------------------------------------
state::_key() {
    printf '%s' "${1//[^A-Za-z0-9._@-]/_}"
}
[[ -v TEST_FLAG ]] || readonly -f state::_key

#--------------------------------------------------
# Function:
#   state::_envname <name>
#
# Description:
#   Prints the environment variable name an input is read from, upper-casing the
#   input name and replacing every non-alphanumeric character with an underscore
#   (for example git.name -> GIT_NAME), so a non-interactive run can supply
#   inputs without prompting. Writes the name to stdout.
#
# Arguments:
#   <name>  The input name
#
# Returns:
#   0 on success
#
# Example:
#   state::_envname git.name
#--------------------------------------------------
state::_envname() {
    local name

    name="${1//[^A-Za-z0-9]/_}"

    printf '%s' "${name^^}"
}
[[ -v TEST_FLAG ]] || readonly -f state::_envname

#--------------------------------------------------
# Function:
#   state::_put <file> <value>
#
# Description:
#   Writes <value> to <file>, creating the parent directory first, with no
#   trailing newline so reads round-trip. Writes a file.
#
# Arguments:
#   <file>   The destination path
#   <value>  The value to store
#
# Returns:
#   0 on success
#   non-zero when the write fails
#
# Example:
#   state::_put "$dir/git.name" 'Ada'
#--------------------------------------------------
state::_put() {
    local file
    local value

    file="$1"
    value="$2"
    mkdir -p "$(dirname "$file")"

    printf '%s' "$value" >"$file"
}
[[ -v TEST_FLAG ]] || readonly -f state::_put

#--------------------------------------------------
# Function:
#   state::ask <name> <prompt>
#
# Description:
#   Resolves an input once and saves it: reuse a saved value, else take it from
#   the environment, else prompt on the terminal. Reuse-first keeps repeated
#   configuration idempotent. When PROMPT_HELP is set its help line is printed
#   above the prompt (a no-op otherwise). May read from stdin and writes the input
#   file.
#
# Arguments:
#   <name>    The input name
#   <prompt>  The text shown when prompting
#
# Returns:
#   0 on success
#
# Example:
#   state::ask git.name 'Your git name'
#--------------------------------------------------
state::ask() {
    local committed
    local env_name
    local name
    local prompt
    local value
    local working

    name="$1"
    prompt="$2"
    working="${MACHINE_SETUP_INPUTS_WORKING:-}"
    committed="$(state::_root)/inputs/$name"

    # Resolve once: a value already entered this run (the working overlay) or saved
    # on an earlier run (committed) is reused as is, never re-prompted.
    [[ -n "$working" && -f "$working/$name" ]] && return 0
    [[ -f "$committed" ]] && return 0

    env_name="$(state::_envname "$name")"
    if [[ -n "${!env_name:-}" ]]
    then
        value="${!env_name}"
    else
        # Print this input's help line above the prompt when one was passed
        # (PROMPT_HELP), then prompt. A no-op when no help was set.
        [[ -z "${PROMPT_HELP:-}" ]] || printf '%s\n\n' "$PROMPT_HELP" >&2

        read -r -p "$prompt: " value
    fi

    if [[ -n "$working" ]]
    then
        state::_put "$working/$name" "$value"
    else
        state::_put "$committed" "$value"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f state::ask

#--------------------------------------------------
# Function:
#   state::set <name> <value>
#
# Description:
#   Writes an input value unconditionally, the write-side counterpart to
#   state::input (which reads) and to state::ask (which resolves an input once and
#   skips when already saved). A flow that drives its own prompts - showing
#   defaults, re-prompting on a duplicate or on Esc, things state::ask's
#   resolve-once-skip model cannot do - persists the result here. Writes the input
#   file with no trailing newline so reads round-trip.
#
# Arguments:
#   <name>   The input name
#   <value>  The value to store
#
# Returns:
#   0 on success
#   non-zero when the write fails
#
# Example:
#   state::set workspace.personal.path /home/ada/Workspace/Personal
#--------------------------------------------------
state::set() {
    local name
    local value
    local working

    name="$1"
    value="$2"
    working="${MACHINE_SETUP_INPUTS_WORKING:-}"

    if [[ -n "$working" ]]
    then
        state::_put "$working/$name" "$value"
    else
        state::_put "$(state::_root)/inputs/$name" "$value"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f state::set

#--------------------------------------------------
# Function:
#   state::input <name>
#
# Description:
#   Prints a saved input value to stdout. Writes an error to stderr when no
#   value was saved.
#
# Arguments:
#   <name>  The input name
#
# Returns:
#   0 when the value is found
#   1 when no saved input exists
#
# Example:
#   state::input git.name
#--------------------------------------------------
state::input() {
    local committed
    local working

    working="${MACHINE_SETUP_INPUTS_WORKING:-}"
    if [[ -n "$working" && -f "$working/$1" ]]
    then
        cat "$working/$1"

        return 0
    fi

    committed="$(state::_root)/inputs/$1"
    if [[ ! -f "$committed" ]]
    then
        output::fatal "no saved input: $1"

        return 1
    fi

    cat "$committed"
}
[[ -v TEST_FLAG ]] || readonly -f state::input

#--------------------------------------------------
# Function:
#   state::unset <name>
#
# Description:
#   Removes a saved input, the delete-side counterpart to state::set. Idempotent:
#   removing an input that was never saved is a no-op, not an error. Removes the
#   input file.
#
# Arguments:
#   <name>  The input name
#
# Returns:
#   0 on success
#
# Example:
#   state::unset workspace.list
#--------------------------------------------------
state::unset() {
    rm -f "$(state::_root)/inputs/$1"

    if [[ -n "${MACHINE_SETUP_INPUTS_WORKING:-}" ]]
    then
        rm -f "$MACHINE_SETUP_INPUTS_WORKING/$1"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f state::unset

#--------------------------------------------------
# Function:
#   state::unset_prefix <prefix>
#
# Description:
#   Removes every saved input whose name begins with <prefix>, so a caller can
#   clear a whole namespace of inputs in one call (for example all of a workspace's
#   slug-namespaced keys). Idempotent: a prefix matching nothing is a no-op.
#   Removes the matching input files.
#
# Arguments:
#   <prefix>  The input-name prefix to clear
#
# Returns:
#   0 on success
#
# Example:
#   state::unset_prefix workspace.personal.
#--------------------------------------------------
state::unset_prefix() {
    local file
    local prefix

    prefix="$1"

    for file in "$(state::_root)/inputs/$prefix"*
    do
        [[ -e "$file" ]] || continue          # the glob matched nothing
        rm -f "$file"
    done

    if [[ -n "${MACHINE_SETUP_INPUTS_WORKING:-}" ]]
    then
        for file in "$MACHINE_SETUP_INPUTS_WORKING/$prefix"*
        do
            [[ -e "$file" ]] || continue
            rm -f "$file"
        done
    fi
}
[[ -v TEST_FLAG ]] || readonly -f state::unset_prefix

#--------------------------------------------------
# Function:
#   state::commit <name>...
#
# Description:
#   Promotes one or more inputs from the working overlay down to the committed
#   inputs/, called once the action an input drives has been performed (an SSH key
#   generated, a directory created), so the saved value reflects real machine
#   state rather than a still-pending answer. Each named input is moved when a
#   working copy exists; a name with no working copy - never entered this run, or
#   already committed - is skipped. A no-op when no overlay is active. Moves files
#   into inputs/.
#
# Arguments:
#   <name>...  One or more input names to commit
#
# Returns:
#   0 on success
#
# Example:
#   state::commit workspace.personal.gpg.type workspace.personal.gpg.comment
#--------------------------------------------------
state::commit() {
    local committed
    local name
    local working

    working="${MACHINE_SETUP_INPUTS_WORKING:-}"
    [[ -n "$working" ]] || return 0               # no overlay: already committed

    committed="$(state::_root)/inputs"
    for name in "$@"
    do
        [[ -f "$working/$name" ]] || continue
        mkdir -p "$(dirname "$committed/$name")"
        mv -f "$working/$name" "$committed/$name"
    done
}
[[ -v TEST_FLAG ]] || readonly -f state::commit

#--------------------------------------------------
# Function:
#   state::commit_prefix <prefix>
#
# Description:
#   Promotes every working-overlay input whose name begins with <prefix> down to
#   the committed inputs/, the bulk counterpart to state::commit for committing a
#   whole namespace at once (for example all of one workspace's slug-namespaced
#   inputs once it is provisioned). A no-op when no overlay is active or the prefix
#   matches nothing. Moves files into inputs/.
#
# Arguments:
#   <prefix>  The input-name prefix to commit
#
# Returns:
#   0 on success
#
# Example:
#   state::commit_prefix workspace.personal.
#--------------------------------------------------
state::commit_prefix() {
    local committed
    local file
    local prefix
    local working

    prefix="$1"
    working="${MACHINE_SETUP_INPUTS_WORKING:-}"
    [[ -n "$working" ]] || return 0

    committed="$(state::_root)/inputs"
    mkdir -p "$committed"
    for file in "$working/$prefix"*
    do
        [[ -e "$file" ]] || continue              # the glob matched nothing
        mv -f "$file" "$committed/$(basename "$file")"
    done
}
[[ -v TEST_FLAG ]] || readonly -f state::commit_prefix

#--------------------------------------------------
# Function:
#   state::commit_line_append <name> <line>
#
# Description:
#   Adds <line> to a committed newline-separated list input, so an aggregate
#   registry (workspace.list) gains an entry the moment the thing it names is
#   performed, keeping it in step with the per-entry inputs committed alongside.
#   Writes directly to inputs/ rather than through the overlay, because the working
#   copy still holds the whole run's list. Idempotent: a line already present is
#   not added again, and the no-trailing-newline convention is preserved. Writes
#   the committed list file.
#
# Arguments:
#   <name>  The list input name
#   <line>  The entry to add
#
# Returns:
#   0 on success
#
# Example:
#   state::commit_line_append workspace.list Personal
#--------------------------------------------------
state::commit_line_append() {
    local file
    local line
    local name

    name="$1"
    line="$2"
    file="$(state::_root)/inputs/$name"

    [[ -f "$file" ]] && grep -qxF -- "$line" "$file" && return 0   # already listed

    mkdir -p "$(dirname "$file")"
    if [[ -s "$file" ]]
    then
        printf '\n%s' "$line" >>"$file"
    else
        printf '%s' "$line" >"$file"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f state::commit_line_append

#--------------------------------------------------
# Function:
#   state::commit_line_remove <name> <line>
#
# Description:
#   Removes <line> from a committed newline-separated list input, the delete-side
#   counterpart to state::commit_line_append, so deregistering a thing drops its
#   registry entry as the removal is performed. Rewrites the list without the line
#   (preserving order and the no-trailing-newline convention) and removes the file
#   entirely when it becomes empty. Idempotent: a missing file or absent line is a
#   no-op. Writes or removes the committed list file.
#
# Arguments:
#   <name>  The list input name
#   <line>  The entry to remove
#
# Returns:
#   0 on success
#
# Example:
#   state::commit_line_remove workspace.list Personal
#--------------------------------------------------
state::commit_line_remove() {
    local existing
    local file
    local line
    local name
    local rebuilt

    name="$1"
    line="$2"
    file="$(state::_root)/inputs/$name"
    [[ -f "$file" ]] || return 0

    rebuilt=''
    while IFS= read -r existing || [[ -n "$existing" ]]
    do
        [[ "$existing" == "$line" ]] && continue
        rebuilt+="${rebuilt:+$'\n'}$existing"
    done <"$file"

    if [[ -n "$rebuilt" ]]
    then
        printf '%s' "$rebuilt" >"$file"
    else
        rm -f "$file"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f state::commit_line_remove

#--------------------------------------------------
# Function:
#   state::list_append <name> <value>
#
# Description:
#   Appends <value> to a newline-separated list input, unless it is already present,
#   preserving order and the no-trailing-newline convention reads round-trip on.
#   Reads the current list through state::input and writes it back through state::set,
#   so it follows the same working-overlay / committed resolution as every other
#   input. Used to grow a workspace's provider list (workspace.<slug>.providers) and
#   its host-less extra-key list (workspace.<slug>.ssh.extra_keys) as keys are
#   created, without duplicating an entry on an edit. Writes the list input.
#
# Arguments:
#   <name>   The list input name
#   <value>  The entry to add
#
# Returns:
#   0 on success
#
# Example:
#   state::list_append workspace.personal.providers github.com
#--------------------------------------------------
state::list_append() {
    local existing
    local line
    local name
    local value

    name="$1"
    value="$2"
    existing="$(state::input "$name" 2>/dev/null || true)"

    while IFS= read -r line
    do
        [[ "$line" != "$value" ]] || return 0     # already listed
    done <<<"$existing"

    if [[ -n "$existing" ]]
    then
        state::set "$name" "$(printf '%s\n%s' "$existing" "$value")"
    else
        state::set "$name" "$value"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f state::list_append

#--------------------------------------------------
# Function:
#   state::own <id>
#
# Description:
#   Records that we manage a unit by creating an empty owned-marker file for
#   <id>. Writes a file.
#
# Arguments:
#   <id>  The unit id
#
# Returns:
#   0 on success
#   non-zero when the marker cannot be written
#
# Example:
#   state::own git
#--------------------------------------------------
state::own() {
    : >"$(state::_dir managed)/$(state::_key "$1")"
}
[[ -v TEST_FLAG ]] || readonly -f state::own

#--------------------------------------------------
# Function:
#   state::disown <id>
#
# Description:
#   Removes the owned-marker for <id>. Removes a file.
#
# Arguments:
#   <id>  The unit id
#
# Returns:
#   0 on success
#
# Example:
#   state::disown git
#--------------------------------------------------
state::disown() {
    rm -f "$(state::_root)/managed/$(state::_key "$1")"
}
[[ -v TEST_FLAG ]] || readonly -f state::disown

#--------------------------------------------------
# Function:
#   state::owned <id>
#
# Description:
#   Reports whether <id> has an owned-marker, that is whether we manage it.
#   Writes nothing.
#
# Arguments:
#   <id>  The unit id
#
# Returns:
#   0 when the unit is owned
#   1 otherwise
#
# Example:
#   state::owned git
#--------------------------------------------------
state::owned() {
    [[ -e "$(state::_root)/managed/$(state::_key "$1")" ]]
}
[[ -v TEST_FLAG ]] || readonly -f state::owned

#--------------------------------------------------
# Function:
#   state::remember <key> <value>
#
# Description:
#   Records the prior value of a configuration variable before we change it, the
#   first time only, so re-running configure (which the runner does on every
#   install) never overwrites the genuine original with a value we set
#   ourselves. An empty record means the variable was absent. The id is the
#   current unit's name. Writes a file.
#
# Arguments:
#   <key>    The configuration variable name
#   <value>  The prior value to record
#
# Returns:
#   0 on success
#
# Example:
#   state::remember user.name 'Ada'
#--------------------------------------------------
state::remember() {
    local dir
    local key
    local value

    key="$1"
    value="$2"
    dir="$(state::_dir "config/$(state::_key "$(runner::unit_name)")")"
    [[ -e "$dir/$key" ]] && return 0          # original already captured; keep it

    state::_put "$dir/$key" "$value"
}
[[ -v TEST_FLAG ]] || readonly -f state::remember

#--------------------------------------------------
# Function:
#   state::recall <key>
#
# Description:
#   Prints a remembered prior configuration value to stdout (nothing when none
#   was recorded). The id is the current unit's name.
#
# Arguments:
#   <key>  The configuration variable name
#
# Returns:
#   0 on success
#
# Example:
#   state::recall user.name
#--------------------------------------------------
state::recall() {
    local file

    file="$(state::_root)/config/$(state::_key "$(runner::unit_name)")/$1"
    [[ -f "$file" ]] || return 0

    cat "$file"
}
[[ -v TEST_FLAG ]] || readonly -f state::recall

#--------------------------------------------------
# Function:
#   state::created <id> <path>
#
# Description:
#   Appends <path> to a unit instance's manifest, the list of paths it created.
#   Writes a file.
#
# Arguments:
#   <id>    The unit instance id
#   <path>  The path that was created
#
# Returns:
#   0 on success
#   non-zero when the manifest cannot be written
#
# Example:
#   state::created 'workspaces/api@/srv/api' /srv/api/.git
#--------------------------------------------------
state::created() {
    local file
    local id
    local path

    id="$1"
    path="$2"
    file="$(state::_dir manifests)/$(state::_key "$id")"

    printf '%s\n' "$path" >>"$file"
}
[[ -v TEST_FLAG ]] || readonly -f state::created

#--------------------------------------------------
# Function:
#   state::forget <id>
#
# Description:
#   Removes a unit instance's manifest, the delete-side counterpart to
#   state::created, so the paths it recorded creating are forgotten and a later
#   re-creation under the same id starts from an empty manifest rather than
#   appending to stale entries. Idempotent: a missing manifest is a no-op. Removes
#   the manifest file.
#
# Arguments:
#   <id>  The unit instance id
#
# Returns:
#   0 on success
#
# Example:
#   state::forget 'workspace@personal'
#--------------------------------------------------
state::forget() {
    rm -f "$(state::_root)/manifests/$(state::_key "$1")"
}
[[ -v TEST_FLAG ]] || readonly -f state::forget

#--------------------------------------------------
# Function:
#   state::contains_only_created <id> <root>
#
# Description:
#   Reports whether every path under <root> is one this instance recorded
#   creating, so its uninstall can safely remove the workspace and nothing
#   foreign. Writes nothing.
#
# Arguments:
#   <id>    The unit instance id
#   <root>  The directory whose contents are checked
#
# Returns:
#   0 when every path under <root> was recorded
#   1 when the manifest is missing or a foreign path is found
#
# Example:
#   state::contains_only_created 'workspaces/api@/srv/api' /srv/api
#--------------------------------------------------
state::contains_only_created() {
    local id
    local manifest
    local path
    local root

    id="$1"
    root="$2"
    manifest="$(state::_root)/manifests/$(state::_key "$id")"
    [[ -f "$manifest" ]] || return 1

    while IFS= read -r path
    do
        grep -qxF -- "$path" "$manifest" || return 1
    done < <(find "$root" -mindepth 1)
}
[[ -v TEST_FLAG ]] || readonly -f state::contains_only_created
