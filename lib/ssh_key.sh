#!/usr/bin/env bash
set -euo pipefail
# The SSH key primitives: the low-level toolkit that generates, loads, reads back and
# removes a workspace's SSH key files. It is deliberately free of the state store and
# the workspace registry: recording what a key is and what it serves is the create
# action's concern, so this module only ever takes the settings it is given and acts on
# them. ssh_key::generate generates one key file with ssh-keygen (idempotent, reusing an
# existing one); ssh_key::register loads a key into the running ssh-agent through the
# libexec/ssh_askpass helper; ssh_key::public_file_content and ssh_key::fingerprint read
# back the public half and its fingerprint that the provider-registration step shows;
# ssh_key::path resolves a key's file from its name; ssh_key::remove tears a key's files
# down behind output::run. Every function but remove is UI-free, prompting and printing
# nothing of its own, so its caller owns the spinner: manage_ssh_keys::create wraps
# generation and the agent load in output::run and drives the per-host config blocks
# (ssh_config.sh) and the interactive provider-registration gate (ssh_connect::register
# in ssh_connect.sh, distinct from ssh_key::register's agent load), which shows the
# public key and fingerprint read back here. The per-host config-block teardown lives in
# ssh_config.sh and libexec/remove. The show action's read-only SSH report is a
# presentation concern and lives in libexec/show as show::one::ssh. Like lib/ssh_config.sh
# it is a sourced fragment with no entry point of its own; it pulls in the libs its
# functions call.

! declare -F ssh_key::generate &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   ssh_key::path <keyname>
#
# Description:
#   Prints the private-key path for a key, ~/.ssh/<keyname> under the caller's
#   HOME. The keyname is the file's name as-is: the caller owns the naming, so a
#   default key carries the conventional id_ prefix (id_<slug>, id_<host>-<slug>)
#   while a name the user typed is used verbatim, without a prefix forced onto it.
#   Each keyname is unique, so the keys never overwrite one another. There is no
#   ed25519 infix: a key may be ed25519 or rsa, and a shared key serves several
#   hosts, so the algorithm is not part of the name. Resolved from HOME at call
#   time, so tests can redirect HOME. Writes the path to stdout.
#
# Arguments:
#   <keyname>  The key's file name under ~/.ssh (e.g. id_github.com-personal)
#
# Returns:
#   0 on success
#
# Example:
#   ssh_key::path id_github.com-personal
#--------------------------------------------------
ssh_key::path() {
    printf '%s/.ssh/%s' "$HOME" "$1"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_key::path

#--------------------------------------------------
# Function:
#   ssh_key::generate <keyname> <type> <bits> <comment> <passphrase>
#
# Description:
#   Generates one SSH key file from its settings and nothing more. The settings have
#   already been collected from the user and recorded by manage_ssh_keys::create;
#   this function persists nothing and prompts for nothing, it only acts on its
#   arguments. It resolves the key's path from <keyname> (ssh_key::path), creates ~/.ssh
#   at mode 700 when missing, then generates the pair there with ssh-keygen: an ed25519
#   key, or an rsa key of <bits> bits (default 4096) when <type> is rsa. It is
#   idempotent: an existing key file is left untouched and reused, since its public half
#   may already be registered with a provider. It is UI-free: it shows no progress and
#   prints nothing of its own, so its caller owns the spinner (output::run) and the
#   wiring that surrounds generation - loading the key into the ssh-agent, writing each
#   provider's ~/.ssh/config.d block and registering the key. The passphrase is a
#   caller-supplied argument, passed straight into keygen and never persisted. Writes the
#   key files under $HOME.
#
# Arguments:
#   <keyname>     The key's name (its filename under ~/.ssh)
#   <type>        The key algorithm, ed25519 or rsa
#   <bits>        The RSA key length when <type> is rsa, empty otherwise
#   <comment>     The key comment
#   <passphrase>  The passphrase protecting the key, empty for an existing key
#
# Returns:
#   0 when the key exists or was generated
#   ssh-keygen's exit status when generation fails
#
# Example:
#   ssh_key::generate personal ed25519 '' me@example.com ''
#--------------------------------------------------
ssh_key::generate() {
    local bits
    local comment
    local keyfile
    local keyname
    local passphrase
    local type

    keyname="$1"
    type="$2"
    bits="$3"
    comment="$4"
    passphrase="$5"

    keyfile="$(ssh_key::path "$keyname")"
    [[ -f "$keyfile" ]] && return 0           # reuse an existing key; never regenerate

    mkdir -p -- "$(dirname -- "$keyfile")"
    chmod 700 -- "$(dirname -- "$keyfile")"

    if [[ "$type" == rsa ]]
    then
        ssh-keygen -t rsa -b "${bits:-4096}" -N "$passphrase" -C "$comment" -f "$keyfile"
    else
        ssh-keygen -t ed25519 -N "$passphrase" -C "$comment" -f "$keyfile"
    fi
}
[[ -v TEST_FLAG ]] || readonly -f ssh_key::generate

#--------------------------------------------------
# Function:
#   ssh_key::register <keyfile> <passphrase>
#
# Description:
#   Loads a private key into the running ssh-agent unattended, so the provider
#   authentication probe (ssh_connect::register) and any later clone can use it without
#   prompting. ssh-add is driven through the libexec/ssh_askpass helper, which receives
#   the passphrase in the environment (SSH_PASSPHRASE), never on disk; DISPLAY is cleared
#   and SSH_ASKPASS_REQUIRE forces the helper even without a terminal. Requires an agent
#   (SSH_AUTH_SOCK) to be running - the orchestrator starts one for the run - and a
#   readable key file, so the caller resolves the path (ssh_key::path) and gates on the
#   agent. It is UI-free, so the spinner (output::run) is the caller's concern. The
#   passphrase is never stored. Adds the key to the agent.
#
# Arguments:
#   <keyfile>     Path of the private key to load (ssh_key::path)
#   <passphrase>  The passphrase that unlocks the key, empty for an unencrypted key
#
# Returns:
#   0 when the key was added
#   ssh-add's exit status when it fails
#
# Example:
#   ssh_key::register ~/.ssh/id_github.com-personal "$passphrase"
#--------------------------------------------------
ssh_key::register() {
    local askpass
    local keyfile
    local passphrase

    keyfile="$1"
    passphrase="$2"
    # The askpass helper is an executable under libexec/, a sibling of this lib/
    # directory. Resolve to an absolute path so SSH_ASKPASS works whatever the caller's
    # working directory.
    askpass="$(cd -- "$LIB_DIR/.." && pwd)/libexec/ssh_askpass"

    SSH_PASSPHRASE="$passphrase" SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force DISPLAY='' \
        ssh-add "$keyfile" </dev/null
}
[[ -v TEST_FLAG ]] || readonly -f ssh_key::register

#--------------------------------------------------
# Function:
#   ssh_key::public_file_content <keyfile>
#
# Description:
#   Prints the public half of an SSH key (<keyfile>.pub), the line the user copies to a
#   provider during registration (ssh_connect::register shows it). Writes the public key
#   to stdout.
#
# Arguments:
#   <keyfile>  Path of the private key whose .pub to read (ssh_key::path)
#
# Returns:
#   0 on success
#   cat's exit status when the public key is missing
#
# Example:
#   ssh_key::public_file_content ~/.ssh/id_github.com-personal
#--------------------------------------------------
ssh_key::public_file_content() {
    local keyfile

    keyfile="$1"

    cat -- "${keyfile}.pub"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_key::public_file_content

#--------------------------------------------------
# Function:
#   ssh_key::fingerprint <keyfile>
#
# Description:
#   Prints the fingerprint line of an SSH key (ssh-keygen -lf on <keyfile>.pub), so the
#   user can confirm the key shown for registration (ssh_connect::register) is the one
#   they expect. Writes the fingerprint to stdout.
#
# Arguments:
#   <keyfile>  Path of the private key whose .pub to fingerprint (ssh_key::path)
#
# Returns:
#   0 on success
#   ssh-keygen's exit status when the public key is missing
#
# Example:
#   ssh_key::fingerprint ~/.ssh/id_github.com-personal
#--------------------------------------------------
ssh_key::fingerprint() {
    local keyfile

    keyfile="$1"

    ssh-keygen -lf "${keyfile}.pub"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_key::fingerprint

#--------------------------------------------------
# Function:
#   ssh_key::remove <keyname>
#
# Description:
#   Removes one generated SSH key by name: resolves the key file from <keyname>
#   (ssh_key::path) and removes its private and public halves, behind
#   output::run. This is the low-level file teardown only; the caller
#   (remove::ssh_keys in libexec/remove) is responsible for enumerating a workspace's
#   keys and deduplicating a key shared across hosts. Removes the key files under
#   $HOME.
#
# Arguments:
#   <keyname>  The SSH key name (its filename under ~/.ssh)
#
# Returns:
#   0 on success
#   the failing step's exit status when the removal fails
#
# Example:
#   ssh_key::remove personal
#--------------------------------------------------
ssh_key::remove() {
    local keyfile
    local keyname

    keyname="$1"

    keyfile="$(ssh_key::path "$keyname")"
    output::run "Removing the SSH key $keyname" rm -f -- "$keyfile" "$keyfile.pub"
}
[[ -v TEST_FLAG ]] || readonly -f ssh_key::remove

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
# shellcheck source=lib/output.sh
source "$LIB_DIR/output.sh"
