#!/usr/bin/env bash
set -euo pipefail
# Per-provider SSH authentication probe and the registration gate it backs: connect
# through an identity's host alias and report whether the provider recognised the
# key, then drive the interactive step (ssh_connect::register) that shows the key and
# loops on the probe until the provider accepts it. Detection is provider-specific
# because the providers disagree on how success looks - GitHub exits non-zero even on
# success and only the greeting tells you it worked - so a bare exit code is not
# enough. The probe connects to the alias (so ssh offers that identity's key, via the
# Host block lib/ssh_config.sh wrote) and matches the greeting against the real
# provider. Like lib/ssh_key.sh it is a sourced fragment with no entry point of its own;
# it pulls in lib/ssh_key.sh, whose public-key and fingerprint readers the registration
# gate shows, and its functions take the ssh_connect:: prefix from the filename (see
# the shell style guide).

! declare -F ssh_connect::has_authentication_succeeded &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   ssh_connect::has_authentication_succeeded <provider> <output>
#
# Description:
#   Reports whether <output> (the combined output of an `ssh -T` attempt) shows a
#   successful authentication to <provider>. Each known provider has its own
#   success greeting (GitHub's "successfully authenticated", GitLab's "Welcome to
#   GitLab", Bitbucket's "logged in"/"authenticated via"); an unknown provider
#   falls back to the absence of a permission-denied message. Pure string matching,
#   so it is the testable core of ssh_connect::authenticate. Writes nothing.
#
# Arguments:
#   <provider>  The real provider host (github.com, gitlab.com, bitbucket.org, ...)
#   <output>    The combined stdout and stderr of the ssh attempt
#
# Returns:
#   0 when the output shows a successful authentication
#   1 otherwise
#
# Example:
#   ssh_connect::has_authentication_succeeded github.com "$ssh_output"
#--------------------------------------------------
ssh_connect::has_authentication_succeeded() {
    local output
    local provider

    provider="$1"
    output="$2"

    case "$provider" in
        github.com)
            [[ "$output" == *'successfully authenticated'* ]]
            ;;
        gitlab.com)
            [[ "$output" == *'Welcome to GitLab'* ]]
            ;;
        bitbucket.org)
            [[ "$output" == *'logged in as'* || "$output" == *'authenticated via'* ]]
            ;;
        *)
            [[ "$output" != *'Permission denied'* ]]
            ;;
    esac
}
[[ -v TEST_FLAG ]] || readonly -f ssh_connect::has_authentication_succeeded

#--------------------------------------------------
# Function:
#   ssh_connect::authenticate <alias> <provider>
#
# Description:
#   Attempts an SSH authentication to <provider> through the identity's host
#   <alias> and reports whether it succeeded
#   (ssh_connect::has_authentication_succeeded). Connecting to the alias makes ssh
#   use that identity's key from the Host block, not the default key; the real
#   provider drives the success match. Runs non-interactively (BatchMode, so a
#   missing agent key fails instead of prompting) and accepts an unknown host key on
#   first contact. Relies on the key already being loaded into ssh-agent for the
#   run. Writes nothing to stdout; ssh's own output is captured and inspected, not
#   shown.
#
# Arguments:
#   <alias>     The identity's host alias to connect through (ssh_config::host::alias)
#   <provider>  The real provider host the alias resolves to, for the success match
#
# Returns:
#   0 when the provider authenticated the key
#   1 otherwise
#
# Example:
#   ssh_connect::authenticate github.com-personal github.com
#--------------------------------------------------
ssh_connect::authenticate() {
    local alias_name
    local output
    local provider

    alias_name="$1"
    provider="$2"

    output="$(ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new "git@$alias_name" 2>&1)" || true

    ssh_connect::has_authentication_succeeded "$provider" "$output"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_connect::authenticate

#--------------------------------------------------
# Function:
#   ssh_connect::register <alias> <provider> <keyfile>
#
# Description:
#   Registers one SSH key with a provider, interactively: the registration gate for
#   a freshly generated key. Generation runs unattended, but a key is useless until
#   its public half is on the provider, so this is the interactive step that blocks
#   until the key is usable. Prints the direct SSH-key settings URL for the provider
#   (GitHub, GitLab, Bitbucket; omitted for an unknown provider) so the user can jump
#   straight to the page, then shows the labelled public key
#   (ssh_key::public_file_content, the line to paste) and its fingerprint
#   (ssh_key::fingerprint, for verification), then loops on ssh_connect::authenticate
#   until the provider authenticates the key through its alias, prompting the user
#   between attempts to retry or skip. Returns as soon as the key already
#   authenticates, so a key registered on an earlier run needs no action. Reads the
#   user's retry/skip choice from the terminal; writes the URL, the key, the prompts,
#   and the result to stdout.
#
# Arguments:
#   <alias>     The identity's host alias to probe through (ssh_config::host::alias)
#   <provider>  The real provider host, for the success match
#   <keyfile>   Path of the private key whose public half to show
#
# Returns:
#   0 when the provider authenticated the key
#   1 when the user skipped, or input ended before authentication
#
# Example:
#   ssh_connect::register github.com-personal github.com ~/.ssh/id_ed25519_github.com-personal
#--------------------------------------------------
ssh_connect::register() {
    local alias_name
    local keyfile
    local provider
    local reply
    local url

    alias_name="$1"
    provider="$2"
    keyfile="$3"

    # The direct "add an SSH key" settings page for each known provider, so the user
    # can jump straight to it; an unknown provider gets no link.
    case "$provider" in
        github.com)    url='https://github.com/settings/ssh/new' ;;
        gitlab.com)    url='https://gitlab.com/-/user_settings/ssh_keys' ;;
        bitbucket.org) url='https://bitbucket.org/account/settings/ssh-keys/' ;;
        *)             url='' ;;
    esac

    printf 'Add this SSH key to %s, then confirm it authenticates.\n\n' "$provider"
    [[ -z "$url" ]] || printf 'SSH key settings: %s\n\n' "$url"
    printf 'Public key (paste this line):\n'
    ssh_key::public_file_content "$keyfile"
    printf '\n'
    printf 'Fingerprint (for verification):\n'
    ssh_key::fingerprint "$keyfile"
    printf '\n'

    while ! ssh_connect::authenticate "$alias_name" "$provider"
    do
        printf 'Not authenticated to %s yet. Press Enter to retry, or type s to skip: ' "$provider"
        read -r reply || return 1
        [[ "$reply" != s ]] || return 1
    done

    printf 'Authenticated to %s as %s.\n' "$provider" "$alias_name"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_connect::register

# ─── Constants / globals ────────────────────────────────────────────────────────

# This library's own directory, so the sibling libraries are sourced regardless of
# the caller's working directory. Defined only when not already set, and made
# readonly outside tests so specs can reassign it.
if [[ -z "${LIB_DIR:-}" ]]
then
    LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    [[ -v TEST_FLAG ]] || readonly LIB_DIR
fi

# ─── Imports ──────────────────────────────────────────────────────────────────
# shellcheck source=lib/ssh_key.sh
source "$LIB_DIR/ssh_key.sh"
