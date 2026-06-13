# Specs for the shared GPG key generation helpers. TEST_FLAG keeps the functions
# non-readonly so the spec can source the fragment; helper::isolate redirects HOME.
# The real gpg is stubbed throughout, so no key is ever generated on the host: the
# stub records a generated key as a marker file under the temp HOME and lists it
# back, standing in for the GnuPG keyring.
Describe 'lib/gpg.sh'
    TEST_FLAG=true
    Include lib/gpg.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # gpg::key_id_from_email
    # ==========================================================================
    Describe 'gpg::key_id_from_email'

        It 'prints the fingerprint of the secret key for the email'
            gpg() { printf 'sec:u:255:22:ABC123::::::::::\nfpr:::::::::ABC123:\n'; }

            When call gpg::key_id_from_email me@example.com
            The status should be success
            The stdout should equal 'ABC123'
            The stderr should be blank
        End

        It 'fails when no secret key exists for the email'
            gpg() { return 2; }

            When call gpg::key_id_from_email me@example.com
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # gpg::generate
    # ==========================================================================
    Describe 'gpg::generate'

        # The keyring is the marker file: --quick-generate-key creates it,
        # --delete-secret-and-public-key removes it, and --list-secret-keys reports
        # the fingerprint while it is there. Every call records its argv so the
        # algorithm, the user id, and a recreate's delete can be asserted.
        gpg() {
            printf '%s\n' "$*" >>"$HOME/gpg.args"

            case "$*" in
                *--delete-secret-and-public-key*)
                    rm -f "$HOME/.gpg-generated"
                    ;;
                *--quick-generate-key*)
                    : >"$HOME/.gpg-generated"
                    ;;
                *--list-secret-keys*)
                    [[ -f "$HOME/.gpg-generated" ]] && printf 'fpr:::::::::ABC123:\n'
                    ;;
            esac
        }

        It 'reuses an existing gpg key and prints its id'
            : >"$HOME/.gpg-generated"

            When call gpg::generate 'Ada Lovelace' me@example.com secret
            The status should be success
            The stdout should equal 'ABC123'
            The stderr should be blank
        End

        It 'generates an ed25519 gpg key by default when none exists and prints its id'
            When call gpg::generate 'Ada Lovelace' me@example.com secret
            The status should be success
            The stdout should equal 'ABC123'
            The stderr should be blank
            The contents of file "$HOME/gpg.args" should include 'ed25519'
        End

        It 'generates an rsa key of the requested length when the type is rsa'
            When call gpg::generate 'Ada Lovelace' me@example.com secret rsa 4096
            The status should be success
            The stdout should equal 'ABC123'
            The stderr should be blank
            The contents of file "$HOME/gpg.args" should include 'rsa4096'
        End

        It 'folds the comment into the user id'
            When call gpg::generate 'Ada Lovelace' me@example.com secret ed25519 '' 'workspace Personal'
            The status should be success
            The stdout should equal 'ABC123'
            The stderr should be blank
            The contents of file "$HOME/gpg.args" should include '(workspace Personal)'
        End

        It 'deletes the existing key first when recreate is requested'
            : >"$HOME/.gpg-generated"

            When call gpg::generate 'Ada Lovelace' me@example.com secret ed25519 '' '' yes
            The status should be success
            The stdout should equal 'ABC123'
            The stderr should be blank
            The contents of file "$HOME/gpg.args" should include '--delete-secret-and-public-key'
        End

    End

    # ==========================================================================
    # gpg::remove_by_id
    # ==========================================================================
    Describe 'gpg::remove_by_id'

        It 'deletes the secret and public key for the fingerprint'
            gpg() { printf '%s\n' "$*" >>"$HOME/gpg.args"; }

            When call gpg::remove_by_id ABC123
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/gpg.args" should include '--delete-secret-and-public-key ABC123'
        End

    End

    # ==========================================================================
    # gpg::register
    # ==========================================================================
    Describe 'gpg::register'

        gpg() { printf '%s\n' '-----BEGIN PGP PUBLIC KEY BLOCK-----'; }

        It 'shows the armored key and waits for confirmation'
            Data ''

            When call gpg::register ABC123
            The status should be success
            The stdout should include 'BEGIN PGP PUBLIC KEY BLOCK'
            The stdout should include 'Add this GPG public key'
            The stderr should be blank
        End

    End

End
