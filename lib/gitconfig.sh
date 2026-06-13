#!/usr/bin/env bash
set -euo pipefail
# Shared ~/.gitconfig IncludeIf helpers for the workspace and dotfiles units: add
# and remove a reversible block that pulls an identity's .gitconfig in for repos
# under a directory tree. The block is appended, not prepended, so it is evaluated
# after the global [user] section and its user.* therefore wins for repos in the
# gitdir (git reads top to bottom, last value wins). Each block is delimited by a
# labelled marker pair so two identities never clash and uninstall restores the
# file exactly, the same way the fish unit manages its rc block. The functions are
# plain (no spinner, no output); a unit wraps them in output::run. Like lib/ssh_key.sh
# it is a sourced fragment with no entry point of its own; its functions take the
# gitconfig:: prefix from the filename (see the shell style guide).

! declare -F gitconfig::path &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   gitconfig::path
#
# Description:
#   Prints the path of the global git config the IncludeIf blocks live in,
#   ~/.gitconfig under the caller's HOME. Resolved from HOME at call time, so tests
#   can redirect HOME. Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   gitconfig::path
#--------------------------------------------------
gitconfig::path() {
    printf '%s/.gitconfig' "$HOME"
}
[[ -v TEST_FLAG ]] || readonly -f gitconfig::path

#--------------------------------------------------
# Function:
#   gitconfig::marker::begin <label>
#
# Description:
#   Prints the begin marker that opens a labelled IncludeIf block in ~/.gitconfig.
#   The label is embedded so each block is delimited uniquely and can be found and
#   removed on its own. Writes the marker line to stdout.
#
# Arguments:
#   <label>  The identity the block belongs to (a workspace name)
#
# Returns:
#   0 on success
#
# Example:
#   gitconfig::marker::begin personal
#--------------------------------------------------
gitconfig::marker::begin() {
    printf '# >>> workspace gitconfig %s >>>' "$1"
}
[[ -v TEST_FLAG ]] || readonly -f gitconfig::marker::begin

#--------------------------------------------------
# Function:
#   gitconfig::marker::end <label>
#
# Description:
#   Prints the end marker that closes a labelled IncludeIf block in ~/.gitconfig,
#   the counterpart to gitconfig::marker::begin. Writes the marker line to stdout.
#
# Arguments:
#   <label>  The identity the block belongs to (a workspace name)
#
# Returns:
#   0 on success
#
# Example:
#   gitconfig::marker::end personal
#--------------------------------------------------
gitconfig::marker::end() {
    printf '# <<< workspace gitconfig %s <<<' "$1"
}
[[ -v TEST_FLAG ]] || readonly -f gitconfig::marker::end

#--------------------------------------------------
# Function:
#   gitconfig::block::display <label> <gitdir> <target>
#
# Description:
#   Prints the full IncludeIf block for an identity - the begin marker, the
#   includeIf stanza, and the end marker - that gitconfig::block::add appends to
#   ~/.gitconfig. The stanza pulls <target> in for any repo under <gitdir> (a
#   trailing slash is added so the match is the whole subtree), so that identity's
#   user.name, user.email and user.signingKey apply only there. Writes the block to
#   stdout.
#
# Arguments:
#   <label>   The identity the block belongs to (a workspace name)
#   <gitdir>  The directory tree the identity applies to (no trailing slash needed)
#   <target>  Path to the identity's own .gitconfig to include
#
# Returns:
#   0 on success
#
# Example:
#   gitconfig::block::display personal ~/Workspace/Personal ~/Workspace/Personal/.gitconfig
#--------------------------------------------------
gitconfig::block::display() {
    local gitdir
    local label
    local target

    label="$1"
    gitdir="$2"
    target="$3"

    gitconfig::marker::begin "$label"
    printf '\n'
    printf '[includeIf "gitdir:%s/"]\n' "$gitdir"
    printf '\tpath = %s\n' "$target"
    gitconfig::marker::end "$label"
    printf '\n'
}
[[ -v TEST_FLAG ]] || readonly -f gitconfig::block::display

#--------------------------------------------------
# Function:
#   gitconfig::block::exist <label>
#
# Description:
#   Reports whether ~/.gitconfig already carries the identity's IncludeIf block, by
#   looking for its begin marker as a fixed string. A missing config counts as
#   absent. grep's own output is discarded, so nothing is written to stdout or
#   stderr.
#
# Arguments:
#   <label>  The identity whose block to look for (a workspace name)
#
# Returns:
#   0 when the block is present
#   1 when the block or the config is absent
#
# Example:
#   gitconfig::block::exist personal
#--------------------------------------------------
gitconfig::block::exist() {
    local file
    local label

    label="$1"
    file="$(gitconfig::path)"
    [[ -f "$file" ]] || return 1

    grep -qF -- "$(gitconfig::marker::begin "$label")" "$file"
}
[[ -v TEST_FLAG ]] || readonly -f gitconfig::block::exist

#--------------------------------------------------
# Function:
#   gitconfig::block::add <label> <gitdir> <target>
#
# Description:
#   Appends the identity's IncludeIf block (gitconfig::block::display) to
#   ~/.gitconfig, creating the file when missing and inserting a separating newline
#   first when the existing file does not end in one. The block goes at the end so
#   it overrides the global [user] for repos under <gitdir>. The caller checks
#   gitconfig::block::exist first, so this is not itself idempotent. Writes nothing
#   to stdout or stderr; its only effect is the file change.
#
# Arguments:
#   <label>   The identity the block belongs to (a workspace name)
#   <gitdir>  The directory tree the identity applies to
#   <target>  Path to the identity's own .gitconfig to include
#
# Returns:
#   0 on success
#
# Example:
#   gitconfig::block::add personal ~/Workspace/Personal ~/Workspace/Personal/.gitconfig
#--------------------------------------------------
gitconfig::block::add() {
    local file
    local gitdir
    local label
    local target

    label="$1"
    gitdir="$2"
    target="$3"
    file="$(gitconfig::path)"

    [[ -f "$file" && -n "$(tail -c1 -- "$file")" ]] && printf '\n' >>"$file"
    gitconfig::block::display "$label" "$gitdir" "$target" >>"$file"
}
[[ -v TEST_FLAG ]] || readonly -f gitconfig::block::add

#--------------------------------------------------
# Function:
#   gitconfig::block::remove <label>
#
# Description:
#   Removes the identity's IncludeIf block (every line from its begin marker through
#   its end marker) from ~/.gitconfig, leaving the rest of the file untouched. A
#   missing config or a config without the block is left as is, so this is
#   idempotent. Writes nothing to stdout or stderr; its only effect is the file
#   change.
#
# Arguments:
#   <label>  The identity whose block to remove (a workspace name)
#
# Returns:
#   0 on success
#
# Example:
#   gitconfig::block::remove personal
#--------------------------------------------------
gitconfig::block::remove() {
    local file
    local label
    local tmp

    label="$1"
    file="$(gitconfig::path)"
    [[ -f "$file" ]] || return 0

    tmp="$(mktemp)"
    sed "/$(gitconfig::marker::begin "$label")/,/$(gitconfig::marker::end "$label")/d" "$file" >"$tmp"
    cat -- "$tmp" >"$file"
    rm -f -- "$tmp"
}
[[ -v TEST_FLAG ]] || readonly -f gitconfig::block::remove
