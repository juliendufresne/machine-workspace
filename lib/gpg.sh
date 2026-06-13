#!/usr/bin/env bash
set -euo pipefail
# Shared GPG key generation for the workspace and dotfiles units: find the signing
# key for an identity and generate one unattended when it is missing. One key per
# identity (name plus email); its fingerprint becomes git's user.signingKey.
# Generation is idempotent - an existing key for the email is reused, never
# duplicated - and the passphrase is supplied by the caller, so it is never
# persisted. It also carries the interactive registration gate (gpg::register): a
# GPG key has no remote probe, so it is a confirm-and-trust step that shows the
# public key and waits for the user to add it to their provider. The generation
# helpers are plain (no spinner, no output); a unit wraps them in output::run. Like
# lib/ssh_key.sh it is a sourced fragment with no entry point of its own; its functions
# take the gpg:: prefix from the filename (see the shell style guide).

! declare -F gpg::key_id_from_email &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   gpg::key_id_from_email <email>
#
# Description:
#   Prints the fingerprint of the secret GPG key whose user id carries <email>,
#   read from gpg's machine-readable listing (the fpr record). The fingerprint is
#   what git records as user.signingKey and what the registration step shows the
#   user. With no secret key for the email it prints nothing and fails, which is how
#   gpg::generate tells generate-or-reuse apart. Writes the fingerprint to
#   stdout.
#
# Arguments:
#   <email>  The email whose secret key to look up
#
# Returns:
#   0 when a key is found (the fingerprint is printed)
#   1 when no secret key exists for the email
#
# Example:
#   gpg::key_id_from_email me@example.com
#--------------------------------------------------
gpg::key_id_from_email() {
    local email
    local id

    email="$1"

    id="$(gpg --batch --with-colons --list-secret-keys -- "$email" 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')" || true
    [[ -n "$id" ]] || return 1

    printf '%s' "$id"
}
[[ -v TEST_FLAG ]] || readonly -f gpg::key_id_from_email

#--------------------------------------------------
# Function:
#   gpg::generate <name> <email> <passphrase> [<type>] [<rsa_bits>] [<comment>] [<recreate>]
#
# Description:
#   Ensures a signing GPG key exists for an identity and prints its fingerprint.
#   When <recreate> is 'yes' and a key for <email> already exists it is deleted
#   first (--delete-secret-and-public-key) so a fresh one is generated; otherwise an
#   existing key for <email> is reused. A new key is generated unattended in batch
#   mode (loopback pinentry with <passphrase>, no expiry), then its fingerprint is
#   read back. <type> selects the algorithm: ed25519 (the default) or rsa, where rsa
#   uses <rsa_bits> bits (default 4096). A non-empty <comment> is folded into the
#   user id as "<name> (<comment>) <email>", otherwise it is "<name> <email>". The
#   passphrase is supplied by the caller, so it is never persisted. Writes the
#   fingerprint to stdout and the new key into the caller's GnuPG home; a recreate
#   removes the prior key first.
#
# Arguments:
#   <name>        The identity's display name (git user.name)
#   <email>       The identity's email (git user.email)
#   <passphrase>  The passphrase that protects the secret key
#   <type>        The key algorithm, ed25519 (default) or rsa (optional)
#   <rsa_bits>    The RSA key length when <type> is rsa, default 4096 (optional)
#   <comment>     A comment folded into the user id (optional)
#   <recreate>    'yes' to delete an existing key for <email> first (optional)
#
# Returns:
#   0 when the key exists or was generated (the fingerprint is printed)
#   gpg's exit status when the delete or generation fails
#
# Example:
#   gpg::generate 'Ada Lovelace' me@example.com "$passphrase" rsa 4096 'workspace Personal' yes
#--------------------------------------------------
gpg::generate() {
    local algo
    local comment
    local email
    local existing
    local name
    local passphrase
    local recreate
    local rsa_bits
    local type
    local uid

    name="$1"
    email="$2"
    passphrase="$3"
    type="${4:-ed25519}"
    rsa_bits="${5:-}"
    comment="${6:-}"
    recreate="${7:-}"

    # Recreate: drop the existing secret and public key for this identity first, so a
    # fresh key is generated below instead of the reuse path being taken.
    if [[ "$recreate" == yes ]] && existing="$(gpg::key_id_from_email "$email")"
    then
        gpg --batch --yes --delete-secret-and-public-key "$existing" >/dev/null 2>&1 || return $?
    fi

    if gpg::key_id_from_email "$email" >/dev/null    # already have a key for this identity
    then
        gpg::key_id_from_email "$email"

        return 0
    fi

    # --quick-generate-key takes ed25519, or rsa<bits> for an RSA key of that length.
    if [[ "$type" == rsa ]]
    then
        algo="rsa${rsa_bits:-4096}"
    else
        algo='ed25519'
    fi

    # The user id carries an optional comment: "Name (comment) <email>".
    if [[ -n "$comment" ]]
    then
        uid="$name ($comment) <$email>"
    else
        uid="$name <$email>"
    fi

    gpg --batch --pinentry-mode loopback --passphrase "$passphrase" \
        --quick-generate-key "$uid" "$algo" sign never >/dev/null 2>&1 || return $?

    gpg::key_id_from_email "$email"
}
[[ -v TEST_FLAG ]] || readonly -f gpg::generate

#--------------------------------------------------
# Function:
#   gpg::remove_by_id <keyid>
#
# Description:
#   Deletes a GPG key from the caller's GnuPG home, both its secret and its public
#   half (--delete-secret-and-public-key), so an uninstall that the user asked to
#   take the keys with it leaves nothing behind. The key is named by its fingerprint
#   (gpg::key_id_from_email). gpg's own output is discarded; a missing key is gpg's
#   concern, not this function's. Removes the key from the keyring.
#
# Arguments:
#   <keyid>  The fingerprint of the key to delete
#
# Returns:
#   0 when the key was deleted
#   gpg's exit status when the deletion fails
#
# Example:
#   gpg::remove_by_id ABC123
#--------------------------------------------------
gpg::remove_by_id() {
    local keyid

    keyid="$1"

    gpg --batch --yes --delete-secret-and-public-key "$keyid" >/dev/null 2>&1
}
[[ -v TEST_FLAG ]] || readonly -f gpg::remove_by_id

#--------------------------------------------------
# Function:
#   gpg::register <keyid>
#
# Description:
#   Registers one GPG key, interactively. There is no remote probe for a GPG key, so
#   this is a confirm-and-trust gate: it shows the armored public key
#   (gpg --armor --export), lists the direct GPG-key settings URL for each supported
#   provider (GitHub, GitLab, Bitbucket) so the user can jump straight to the page,
#   and waits for the user to confirm they have added it to their provider. Reads the
#   confirmation from the terminal; writes the key, the URLs, the prompt, and the
#   result to stdout.
#
# Arguments:
#   <keyid>  The GPG key id (fingerprint) to export and register
#
# Returns:
#   0 on success
#
# Example:
#   gpg::register ABC123
#--------------------------------------------------
gpg::register() {
    local keyid

    keyid="$1"

    printf 'Add this GPG public key to your git provider:\n\n'
    gpg --armor --export "$keyid"
    printf '\n'
    printf 'GPG key settings for the common providers:\n'
    printf '  Bitbucket: https://bitbucket.org/account/settings/gpg-keys/\n'
    printf '  GitHub:    https://github.com/settings/keys\n'
    printf '  GitLab:    https://gitlab.com/-/user_settings/gpg_keys\n'
    printf '\n'
    # No variable: the keypress is only an acknowledgement, so read it into the
    # builtin REPLY and discard it.
    read -rp 'Press Enter once the GPG key is added: ' || true
}
[[ -v TEST_FLAG ]] || readonly -f gpg::register
