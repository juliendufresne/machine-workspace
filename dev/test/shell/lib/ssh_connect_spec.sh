# Specs for the per-provider SSH authentication probe. TEST_FLAG keeps the
# functions non-readonly so the spec can source the fragment. ssh is stubbed
# throughout, so the probe never opens a real connection: the stub stands in for
# each provider's greeting.
Describe 'lib/ssh_connect.sh'
    TEST_FLAG=true
    Include lib/ssh_connect.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # ssh_connect::has_authentication_succeeded
    # ==========================================================================
    Describe 'ssh_connect::has_authentication_succeeded'

        It 'recognises the GitHub success greeting'
            When call ssh_connect::has_authentication_succeeded github.com "Hi ada! You've successfully authenticated, but GitHub does not provide shell access."
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'recognises the GitLab success greeting'
            When call ssh_connect::has_authentication_succeeded gitlab.com 'Welcome to GitLab, @ada!'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'recognises the Bitbucket success greeting'
            When call ssh_connect::has_authentication_succeeded bitbucket.org 'logged in as ada.'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'fails on a permission-denied message'
            When call ssh_connect::has_authentication_succeeded github.com 'git@github.com: Permission denied (publickey).'
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'falls back to the absence of permission-denied for an unknown provider'
            When call ssh_connect::has_authentication_succeeded git.example.com 'Hi ada, welcome.'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_connect::authenticate
    # ==========================================================================
    Describe 'ssh_connect::authenticate'

        It 'succeeds when the provider greets the key'
            ssh() { printf "Hi ada! You've successfully authenticated.\n" >&2; return 1; }

            When call ssh_connect::authenticate github.com-personal github.com
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'fails when the provider denies the key'
            ssh() { printf 'git@github.com: Permission denied (publickey).\n' >&2; return 255; }

            When call ssh_connect::authenticate github.com-personal github.com
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_connect::register
    # ==========================================================================
    # The helpers it depends on (ssh_key::public_file_content, ssh_key::fingerprint,
    # ssh_connect::authenticate) are stubbed, so no key is shown from disk and no
    # connection is made; the user's terminal input comes from the Data block.
    Describe 'ssh_connect::register'

        ssh_key::public_file_content() { printf 'ssh-ed25519 AAAA me@example.com\n'; }
        ssh_key::fingerprint() { printf '256 SHA256:abc me@example.com\n'; }

        It 'shows the key and returns once the provider authenticates'
            ssh_connect::authenticate() { return 0; }

            When call ssh_connect::register github.com-personal github.com /keys/id
            The status should be success
            The stdout should include 'ssh-ed25519 AAAA me@example.com'
            The stdout should include 'Authenticated to github.com'
            The stderr should be blank
        End

        It 'prints the provider SSH key settings URL'
            ssh_connect::authenticate() { return 0; }

            When call ssh_connect::register github.com-personal github.com /keys/id
            The status should be success
            The stdout should include 'https://github.com/settings/ssh/new'
            The stdout should include 'Public key'
            The stderr should be blank
        End

        It 'returns failure when the user skips'
            ssh_connect::authenticate() { return 1; }
            Data 's'

            When call ssh_connect::register github.com-personal github.com /keys/id
            The status should be failure
            The stdout should include 'Press Enter to retry'
            The stderr should be blank
        End

        It 'retries until the provider authenticates'
            ssh_connect::authenticate() {
                [[ -f "$HOME/probed" ]] && return 0
                : >"$HOME/probed"

                return 1
            }
            Data ''

            When call ssh_connect::register github.com-personal github.com /keys/id
            The status should be success
            The stdout should include 'Authenticated to github.com'
            The stderr should be blank
        End

    End

End
