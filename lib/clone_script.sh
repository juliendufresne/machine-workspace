#!/usr/bin/env bash
set -euo pipefail
# Deploys the managed clone-repo helper to a workspace root. The helper
# (libexec/clone-repo) clones a repository through the workspace's SSH identity;
# a verbatim copy of it is dropped at the root of each workspace so it is on hand
# there, and re-running the workspace tool overwrites that copy, so the source in
# the repository stays the single place its logic lives. This library is the one
# step that copies the source to the destination and records it for removal; it
# is a sourced fragment with no entry point of its own, taking the clone_script::
# prefix from the filename (see the shell style guide). The copy is recorded in
# the workspace@<slug> manifest on first creation, so the manifest-driven removal
# deletes it when the workspace is removed.

! declare -F clone_script::source_path &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   clone_script::source_path
#
# Description:
#   Prints the path of the clone-repo source script in the repository,
#   $PROJECT_ROOT/libexec/clone-repo, the file copied to each workspace root.
#   Resolved from PROJECT_ROOT at call time so the helper finds its source
#   regardless of the caller's working directory. Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   clone_script::source_path
#--------------------------------------------------
clone_script::source_path() {
    printf '%s/libexec/clone-repo' "$PROJECT_ROOT"
}
[[ -v TEST_FLAG ]] || readonly -f clone_script::source_path

#--------------------------------------------------
# Function:
#   clone_script::dest_path <workspace-path>
#
# Description:
#   Prints the path the clone-repo helper is deployed to for a workspace,
#   <workspace-path>/clone-repo (the helper at the root of the workspace tree).
#   Writes the path to stdout.
#
# Arguments:
#   <workspace-path>  The workspace's directory path (its tree root)
#
# Returns:
#   0 on success
#
# Example:
#   clone_script::dest_path ~/Workspace/Personal
#--------------------------------------------------
clone_script::dest_path() {
    printf '%s/clone-repo' "$1"
}
[[ -v TEST_FLAG ]] || readonly -f clone_script::dest_path

#--------------------------------------------------
# Function:
#   clone_script::deploy <source> <dest>
#
# Description:
#   Copies the clone-repo source to its destination and makes it executable
#   (mode 0755). The whole file is overwritten, which the workspace tool owns, so
#   re-running is idempotent. UI-free, so the caller wraps it in output::run.
#   Writes the destination file.
#
# Arguments:
#   <source>  The clone-repo source path (clone_script::source_path)
#   <dest>    The destination path (clone_script::dest_path)
#
# Returns:
#   0 on success
#   non-zero when the copy or chmod fails
#
# Example:
#   clone_script::deploy "$src" "$dest"
#--------------------------------------------------
clone_script::deploy() {
    local dest
    local source

    source="$1"
    dest="$2"

    cp -- "$source" "$dest"
    chmod 0755 -- "$dest"
}
[[ -v TEST_FLAG ]] || readonly -f clone_script::deploy

#--------------------------------------------------
# Function:
#   clone_script::install <name> <path>
#
# Description:
#   Deploys the managed clone-repo helper to a workspace root: it records the
#   destination in the workspace@<slug> manifest on first creation (so the
#   manifest-driven removal deletes it), then copies the source over and makes it
#   executable (clone_script::deploy) behind output::run. The copy is overwritten
#   every run, the managed-file contract, so re-running is idempotent. Derives the
#   slug from <name> and the destination from <path>. Writes the helper at the
#   workspace root under $HOME.
#
# Arguments:
#   <name>  The workspace display name
#   <path>  The workspace's directory path (its tree root)
#
# Returns:
#   0 on success
#   the failing step's exit status when the copy fails
#
# Example:
#   clone_script::install Personal ~/Workspace/Personal
#--------------------------------------------------
clone_script::install() {
    local dest
    local name
    local path
    local slug
    local source

    name="$1"
    path="$2"
    slug="$(workspace::slug "$name")"

    source="$(clone_script::source_path)"
    dest="$(clone_script::dest_path "$path")"

    [[ -f "$dest" ]] || state::created "workspace@$slug" "$dest"
    output::run "Installing the clone-repo helper in $path" clone_script::deploy "$source" "$dest" || return $?
}
[[ -v TEST_FLAG ]] || readonly -f clone_script::install

# ─── Constants / globals ────────────────────────────────────────────────────────

# This library's own directory, so the sibling libraries are sourced regardless
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
# shellcheck source=lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=lib/workspace.sh
source "$LIB_DIR/workspace.sh"
