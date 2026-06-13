#!/usr/bin/env bash
set -euo pipefail
# Shared ~/.ssh/config helpers for the workspace and dotfiles units: compute the
# per-identity host alias and manage the Host config it needs. An alias is <host>-<name>
# (github.com-personal), so `git clone git@github.com-personal:org/repo.git` selects
# that identity's key instead of the default one. Each alias's Host block lives in
# its own file under ~/.ssh/config.d (20-<name>-<host>), pulled in by a single
# `Include config.d/*` line this toolkit adds to ~/.ssh/config; the directory also
# carries two maintained base fragments, 00-base (global defaults) and, on macOS,
# 10-macos (keychain). A per-identity fragment is its own file, so adding or removing
# an identity is just writing or deleting one file - two identities never clash and
# uninstall removes exactly that identity's fragment, leaving the shared scaffolding
# in place for any other identity still using it. Most functions are plain (no
# spinner, no output) and a unit wraps them in output::run; the exception is
# ssh_config::host::remove, which wraps the fragment removal in output::run itself.
# Like lib/ssh_key.sh it is a sourced fragment with no entry point of its own; its
# functions take the ssh_config:: prefix from the filename (see the shell style guide).

! declare -F ssh_config::host::alias &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   ssh_config::host::alias <host> <name>
#
# Description:
#   Prints the SSH host alias for an identity: the host and the workspace name
#   joined with a hyphen (github.com + personal -> github.com-personal). Uniqueness
#   is guaranteed by a unique host within a workspace times a unique workspace
#   name, so no two identities ever produce the same alias. Writes the alias to
#   stdout.
#
# Arguments:
#   <host>  The real host the alias points at (github.com, a custom git host)
#   <name>  The workspace name that scopes the identity
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::host::alias github.com personal
#--------------------------------------------------
ssh_config::host::alias() {
    local host
    local name

    host="$1"
    name="$2"

    printf '%s-%s' "$host" "$name"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::host::alias

#--------------------------------------------------
# Function:
#   ssh_config::filepath
#
# Description:
#   Prints the path of the SSH client config the Include line lives in,
#   ~/.ssh/config under the caller's HOME. Resolved from HOME at call time, not at
#   source time, so tests can redirect HOME. Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::filepath
#--------------------------------------------------
ssh_config::filepath() {
    printf '%s/.ssh/config' "$HOME"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::filepath

#--------------------------------------------------
# Function:
#   ssh_config::subdir
#
# Description:
#   Prints the directory the per-identity Host fragments and the base fragments
#   live in, ~/.ssh/config.d under the caller's HOME, pulled in by the Include line
#   in ~/.ssh/config. Resolved from HOME at call time, so tests can redirect HOME.
#   Writes the path to stdout.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::subdir
#--------------------------------------------------
ssh_config::subdir() {
    printf '%s/.ssh/config.d' "$HOME"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::subdir

#--------------------------------------------------
# Function:
#   ssh_config::host::filepath <fragment>
#
# Description:
#   Prints the full path of a config.d fragment file, <config.d>/<fragment>. The
#   fragment name is a base fragment (00-base, 10-macos) or a per-identity one
#   (ssh_config::host::filename). Writes the path to stdout.
#
# Arguments:
#   <fragment>  The fragment file name under config.d
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::host::filepath 20-personal-github.com
#--------------------------------------------------
ssh_config::host::filepath() {
    printf '%s/%s' "$(ssh_config::subdir)" "$1"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::host::filepath

#--------------------------------------------------
# Function:
#   ssh_config::host::filename <host> <name>
#
# Description:
#   Prints the config.d fragment file name for an identity, 20-<name>-<host> (the
#   20- prefix sorts the per-identity fragments after the 00-/10- base fragments
#   that set the global defaults). Named by workspace then host, the mirror of the
#   <host>-<name> alias, so the file lists naturally by workspace. Writes the name
#   to stdout.
#
# Arguments:
#   <host>  The real host the identity points at
#   <name>  The workspace name that scopes the identity
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::host::filename github.com personal
#--------------------------------------------------
ssh_config::host::filename() {
    local host
    local name

    host="$1"
    name="$2"

    printf '20-%s-%s' "$name" "$host"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::host::filename

#--------------------------------------------------
# Function:
#   ssh_config::marker::begin <tag>
#
# Description:
#   Prints the begin marker that opens the toolkit's own block in ~/.ssh/config -
#   the Include line it manages there. The tag is embedded so the block is delimited
#   uniquely and can be found again. Writes the marker line to stdout.
#
# Arguments:
#   <tag>  The block tag (include)
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::marker::begin include
#--------------------------------------------------
ssh_config::marker::begin() {
    printf '# >>> workspace identity %s >>>' "$1"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::marker::begin

#--------------------------------------------------
# Function:
#   ssh_config::marker::end <tag>
#
# Description:
#   Prints the end marker that closes the toolkit's own block in ~/.ssh/config, the
#   counterpart to ssh_config::marker::begin. Writes the marker line to stdout.
#
# Arguments:
#   <tag>  The block tag (include)
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::marker::end include
#--------------------------------------------------
ssh_config::marker::end() {
    printf '# <<< workspace identity %s <<<' "$1"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::marker::end

#--------------------------------------------------
# Function:
#   ssh_config::is_macos
#
# Description:
#   Reports whether the host is macOS, by checking uname for Darwin. Drives whether
#   the 10-macos base fragment (UseKeychain yes) is written, since that option is
#   macOS-only and ssh errors on it elsewhere. Writes nothing.
#
# Arguments:
#   N/A
#
# Returns:
#   0 on macOS
#   1 otherwise
#
# Example:
#   ssh_config::is_macos
#--------------------------------------------------
ssh_config::is_macos() {
    [[ "$(uname -s)" == Darwin ]]
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::is_macos

#--------------------------------------------------
# Function:
#   ssh_config::host::display <alias> <host> <user> <identityfile>
#
# Description:
#   Prints the full Host block for an identity - the whole content of its config.d
#   fragment file. The stanza pins HostName to the real host, User to the login user
#   (git for the providers), AddKeysToAgent yes so a loaded key is offered to the
#   agent, IdentityFile to the identity's key, and IdentitiesOnly yes so ssh offers
#   only that key, so a clone through the alias authenticates with exactly the
#   intended identity. Writes the block to stdout.
#
# Arguments:
#   <alias>         The host alias (the Host name git URLs use)
#   <host>          The real host the alias resolves to
#   <user>          The login user ssh connects as (git for a provider)
#   <identityfile>  Path to the private key for this identity
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::host::display github.com-personal github.com git ~/.ssh/id_personal
#--------------------------------------------------
ssh_config::host::display() {
    local alias_name
    local host
    local identityfile
    local user

    alias_name="$1"
    host="$2"
    user="$3"
    identityfile="$4"

    printf 'Host %s\n' "$alias_name"
    printf '    HostName %s\n' "$host"
    printf '    User %s\n' "$user"
    printf '    AddKeysToAgent yes\n'
    printf '    IdentityFile %s\n' "$identityfile"
    printf '    IdentitiesOnly yes\n'
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::host::display

#--------------------------------------------------
# Function:
#   ssh_config::create_base_files
#
# Description:
#   Writes the maintained base fragments into ~/.ssh/config.d, creating the
#   directory (mode 700) when missing: 00-base, the global defaults (a Host *
#   stanza with IdentitiesOnly yes), and, on macOS only (ssh_config::is_macos),
#   10-macos, the keychain default (Host * with UseKeychain yes). Both are wholly
#   the toolkit's, so they are rewritten each run to keep them correct. Writes the
#   fragment files (mode 600).
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::create_base_files
#--------------------------------------------------
ssh_config::create_base_files() {
    local dir

    dir="$(ssh_config::subdir)"

    mkdir -p -- "$dir"
    chmod 700 -- "$dir"

    {
        printf 'Host *\n'
        printf '    IdentitiesOnly yes\n'
    } >"$dir/00-base"
    chmod 600 -- "$dir/00-base"

    if ssh_config::is_macos
    then
        {
            printf 'Host *\n'
            printf '    UseKeychain yes\n'
        } >"$dir/10-macos"
        chmod 600 -- "$dir/10-macos"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::create_base_files

#--------------------------------------------------
# Function:
#   ssh_config::include_dir::ensure_present
#
# Description:
#   Ensures the shared SSH scaffolding is in place, idempotently: the ~/.ssh/config.d
#   directory (mode 700), the marked `Include config.d/*` block at the top of
#   ~/.ssh/config (prepended so the fragments are read before any hand-managed
#   config below, added only when its marker is absent), and the maintained base
#   fragments (ssh_config::create_base_files). Called before each fragment write, so the
#   first identity added sets everything up and later ones find it ready. Creates
#   the directory and edits ~/.ssh/config (mode 600).
#
# Arguments:
#   N/A
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::include_dir::ensure_present
#--------------------------------------------------
ssh_config::include_dir::ensure_present() {
    local config
    local dir
    local tmp

    config="$(ssh_config::filepath)"
    dir="$(ssh_config::subdir)"

    mkdir -p -- "$dir"
    chmod 700 -- "$dir"

    # The Include line, wrapped in markers and prepended so the config.d fragments
    # are read before any hand-managed config below. Added only when absent.
    if [[ ! -f "$config" ]] || ! grep -qF -- "$(ssh_config::marker::begin include)" "$config"
    then
        tmp="$(mktemp)"
        {
            ssh_config::marker::begin include
            printf '\nInclude config.d/*\n'
            ssh_config::marker::end include
            printf '\n'
            [[ ! -f "$config" ]] || cat -- "$config"
        } >"$tmp"
        cat -- "$tmp" >"$config"
        rm -f -- "$tmp"
        chmod 600 -- "$config"
    fi

    ssh_config::create_base_files
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::include_dir::ensure_present

#--------------------------------------------------
# Function:
#   ssh_config::host::exist <fragment>
#
# Description:
#   Reports whether an identity's config.d fragment already exists. A fragment is
#   one file, so presence is just the file existing. Writes nothing.
#
# Arguments:
#   <fragment>  The fragment file name to look for (ssh_config::host::filename)
#
# Returns:
#   0 when the fragment exists
#   1 otherwise
#
# Example:
#   ssh_config::host::exist 20-personal-github.com
#--------------------------------------------------
ssh_config::host::exist() {
    [[ -f "$(ssh_config::host::filepath "$1")" ]]
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::host::exist

#--------------------------------------------------
# Function:
#   ssh_config::host::add <fragment> <alias> <host> <user> <identityfile>
#
# Description:
#   Writes an identity's Host block (ssh_config::host::display) to its own config.d
#   fragment file, after ensuring the shared scaffolding exists
#   (ssh_config::include_dir::ensure_present: the config.d directory, the Include line, the
#   base fragments). The fragment is wholly the toolkit's, so the write is a plain
#   overwrite. Writes the fragment file (mode 600); its only effect is the file
#   changes.
#
# Arguments:
#   <fragment>      The fragment file name (ssh_config::host::filename)
#   <alias>         The host alias (the Host name git URLs use)
#   <host>          The real host the alias resolves to
#   <user>          The login user ssh connects as (git for a provider)
#   <identityfile>  Path to the private key for this identity
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::host::add 20-personal-github.com github.com-personal github.com git ~/.ssh/id_personal
#--------------------------------------------------
ssh_config::host::add() {
    local alias_name
    local fragment
    local host
    local identityfile
    local path
    local user

    fragment="$1"
    alias_name="$2"
    host="$3"
    user="$4"
    identityfile="$5"

    ssh_config::include_dir::ensure_present
    path="$(ssh_config::host::filepath "$fragment")"
    ssh_config::host::display "$alias_name" "$host" "$user" "$identityfile" >"$path"
    chmod 600 -- "$path"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::host::add

#--------------------------------------------------
# Function:
#   ssh_config::host::do_remove <fragment>
#
# Description:
#   Removes an identity's config.d fragment file, leaving the shared scaffolding
#   (the Include line, the base fragments) in place for any other identity still
#   using it. A missing fragment is left as is, so this is idempotent. Writes
#   nothing to stdout or stderr; its only effect is the file removal. The
#   spinner-wrapped, alias-resolving entry point is ssh_config::host::remove.
#
# Arguments:
#   <fragment>  The fragment file name to remove (ssh_config::host::filename)
#
# Returns:
#   0 on success
#
# Example:
#   ssh_config::host::do_remove 20-personal-github.com
#--------------------------------------------------
ssh_config::host::do_remove() {
    local path

    path="$(ssh_config::host::filepath "$1")"

    rm -f -- "$path"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::host::do_remove

#--------------------------------------------------
# Function:
#   ssh_config::host::remove <host> <name>
#
# Description:
#   Removes one identity's ~/.ssh/config.d block: resolves the host alias and the
#   fragment name (ssh_config::host::alias, ssh_config::host::filename) and, when the
#   fragment's block is present (ssh_config::host::exist), removes it
#   (ssh_config::host::do_remove) behind output::run. A missing block is left as is,
#   so this is idempotent. Only the config block is touched, never the key itself.
#   Edits the shared ~/.ssh config under $HOME.
#
# Arguments:
#   <host>  The real host the identity points at (github.com, a custom git host)
#   <name>  The workspace name that scopes the identity
#
# Returns:
#   0 on success
#   the failing step's exit status when the removal fails
#
# Example:
#   ssh_config::host::remove github.com personal
#--------------------------------------------------
ssh_config::host::remove() {
    local alias_name
    local fragment
    local host
    local name

    host="$1"
    name="$2"

    alias_name="$(ssh_config::host::alias "$host" "$name")"
    fragment="$(ssh_config::host::filename "$host" "$name")"
    if ssh_config::host::exist "$fragment"
    then
        output::run "Removing the SSH config for $alias_name" ssh_config::host::do_remove "$fragment" || return $?
    fi
}
[[ -v TEST_FLAG ]] || readonly -f ssh_config::host::remove
