#!/usr/bin/env bash
set -euo pipefail
# The shared workspace primitives: the registry and query helpers the three
# actions (create, remove, show) all build on. The registry of definitions lives
# in the state store (inputs/workspace.list plus slug-namespaced
# inputs/workspace.<slug>.*); these functions slug a name, list the registered
# workspaces, test whether one exists, and read a workspace's path, git email and
# SSH hosts back out. The action-specific logic - defining and provisioning
# (libexec/create), removal (libexec/remove) and the read-only report
# (libexec/show) - lives in the libexec scripts, each of which sources this file
# for these primitives. This is a sourced fragment: it pulls in only lib/state.sh,
# the store it reads, and defines no entry point of its own.

! declare -F workspace::slug &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   workspace::slug <name>
#
# Description:
#   Prints the slug for a workspace display name: the name lower-cased, spaces
#   turned into hyphens, and every other character outside [a-z0-9._-] stripped.
#   The slug namespaces the workspace's state keys and its SSH host aliases, so it
#   keeps filenames and aliases clean, and because it lower-cases, two names that
#   differ only in case collapse to the same slug (case-insensitive duplicate
#   detection). Writes the slug to stdout.
#
# Arguments:
#   <name>  The workspace display name
#
# Returns:
#   0 on success
#
# Example:
#   workspace::slug 'Acme Corp'
#--------------------------------------------------
workspace::slug() {
    local name
    local slug

    name="$1"
    slug="${name,,}"                              # lower-case
    slug="${slug// /-}"                           # spaces to hyphens
    slug="${slug//[^a-z0-9._-]/}"                 # strip everything else

    printf '%s' "$slug"
}
[[ -v TEST_FLAG ]] || readonly -f workspace::slug

#--------------------------------------------------
# Function:
#   workspace::list
#
# Description:
#   Prints the registered workspace display names, one per line and in definition
#   order, read from the workspace.list input. The names are emitted with a trailing
#   newline (the stored value has none), so a `while read` loop over the output
#   processes the last workspace too. A soft read - a missing list is not an error -
#   so it prints nothing on a host with no workspaces yet. Writes the names to
#   stdout, or nothing.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   workspace::list
#--------------------------------------------------
workspace::list() {
    local raw

    raw="$(state::input workspace.list 2>/dev/null || true)"
    [[ -n "$raw" ]] || return 0

    printf '%s\n' "$raw"
}
[[ -v TEST_FLAG ]] || readonly -f workspace::list

#--------------------------------------------------
# Function:
#   workspace::exists <name>
#
# Description:
#   Reports whether a workspace whose slug matches <name>'s slug is already
#   registered, that is whether <name> is a case-insensitive duplicate of a defined
#   workspace (the slug lower-cases, so the comparison ignores case). Writes
#   nothing.
#
# Arguments:
#   <name>  The candidate workspace display name
#
# Returns:
#   0 when a workspace with the same slug is registered
#   1 otherwise
#
# Example:
#   workspace::exists Personal
#--------------------------------------------------
workspace::exists() {
    local candidate
    local name
    local slug

    name="$1"
    slug="$(workspace::slug "$name")"

    while IFS= read -r candidate
    do
        [[ -n "$candidate" ]] || continue
        [[ "$(workspace::slug "$candidate")" != "$slug" ]] || return 0
    done < <(workspace::list)

    return 1
}
[[ -v TEST_FLAG ]] || readonly -f workspace::exists

#--------------------------------------------------
# Function:
#   workspace::path <name>
#
# Description:
#   Prints the absolute path of a workspace's directory tree, read from
#   workspace.<slug>.path. A soft read - the input is always set for a registered
#   workspace, but a missing one prints nothing rather than failing - so a status
#   check is safe. Writes the path to stdout, or nothing.
#
# Arguments:
#   <name>  The workspace display name
#
# Returns:
#   0 on success
#
# Example:
#   workspace::path Personal
#--------------------------------------------------
workspace::path() {
    state::input "workspace.$(workspace::slug "$1").path" 2>/dev/null || true
}
[[ -v TEST_FLAG ]] || readonly -f workspace::path

#--------------------------------------------------
# Function:
#   workspace::git::user_name <name>
#
# Description:
#   Prints the git user.name for a workspace, read back from the workspace's own
#   <path>/.gitconfig (the single source of truth, written by
#   create::workspace::gitconfig::write). A soft read - a missing .gitconfig or an
#   unset key prints nothing rather than failing - so a status check is safe. Writes
#   the name to stdout, or nothing.
#
# Arguments:
#   <name>  The workspace display name
#
# Returns:
#   0 on success
#
# Example:
#   workspace::git::user_name Personal
#--------------------------------------------------
workspace::git::user_name() {
    local file

    file="$(workspace::path "$1")/.gitconfig"
    [[ -f "$file" ]] || return 0
    git config -f "$file" user.name 2>/dev/null || true
}
[[ -v TEST_FLAG ]] || readonly -f workspace::git::user_name

#--------------------------------------------------
# Function:
#   workspace::git::user_email <name>
#
# Description:
#   Prints the git user.email for a workspace, read back from the workspace's own
#   <path>/.gitconfig (the single source of truth, written by
#   create::workspace::gitconfig::write). A soft read - a missing .gitconfig or an
#   unset key prints nothing rather than failing - so a status check is safe. Writes
#   the email to stdout, or nothing.
#
# Arguments:
#   <name>  The workspace display name
#
# Returns:
#   0 on success
#
# Example:
#   workspace::git::user_email Personal
#--------------------------------------------------
workspace::git::user_email() {
    local file

    file="$(workspace::path "$1")/.gitconfig"
    [[ -f "$file" ]] || return 0
    git config -f "$file" user.email 2>/dev/null || true
}
[[ -v TEST_FLAG ]] || readonly -f workspace::git::user_email

#--------------------------------------------------
# Function:
#   workspace::ssh::hosts <name>
#
# Description:
#   Prints the SSH hosts a workspace grants access to, one per line: the selected
#   providers (workspace.<slug>.providers, newline-separated) then the extra hosts
#   (workspace.<slug>.extra_hosts, space-separated). A host equal to an
#   already-listed one is dropped as redundant, so each host - and therefore each
#   alias and key mapping - appears once. Writes the hosts to stdout, or nothing
#   when none are configured.
#
# Arguments:
#   <name>  The workspace display name
#
# Returns:
#   0 on success
#
# Example:
#   workspace::ssh::hosts Personal
#--------------------------------------------------
workspace::ssh::hosts() {
    local -a extra
    local host
    local name
    local providers
    local raw
    local slug
    local -A seen

    name="$1"
    slug="$(workspace::slug "$name")"
    seen=()

    providers="$(state::input "workspace.$slug.providers" 2>/dev/null || true)"
    while IFS= read -r host
    do
        [[ -n "$host" ]] || continue
        [[ -z "${seen[$host]:-}" ]] || continue

        printf '%s\n' "$host"
        seen["$host"]=1
    done <<<"$providers"

    raw="$(state::input "workspace.$slug.extra_hosts" 2>/dev/null || true)"
    read -ra extra <<<"$raw"
    for host in "${extra[@]}"
    do
        [[ -z "${seen[$host]:-}" ]] || continue

        printf '%s\n' "$host"
        seen["$host"]=1
    done
}
[[ -v TEST_FLAG ]] || readonly -f workspace::ssh::hosts

# ─── Constants / globals ────────────────────────────────────────────────────────

# This library's own directory, so the sibling state library is sourced regardless
# of the caller's working directory. Defined only when not already set, and made
# readonly outside tests so specs can reassign it.
if [[ -z "${LIB_DIR:-}" ]]
then
    LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    [[ -v TEST_FLAG ]] || readonly LIB_DIR
fi

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/state.sh
source "$LIB_DIR/state.sh"
