# Specs for the SSH key primitives. TEST_FLAG keeps the functions non-readonly so the
# spec can source the fragment without making them readonly; helper::isolate redirects
# HOME, so every key write stays in the per-example temp tree. The real ssh-keygen and
# ssh-add are stubbed, so no key is ever generated and the agent is never touched on the
# host. The module records no state, so its settings arrive as arguments (collected by
# manage_ssh_keys::create, which also owns the spinner and the agent/config/register
# wiring around generation).
Describe 'lib/ssh_key'
    TEST_FLAG=true
    Include lib/ssh_key.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # ssh_key::path
    # ==========================================================================
    Describe 'ssh_key::path'

        It 'is the per-keyname key under .ssh in HOME with no algorithm infix'
            When call ssh_key::path github.com-personal
            The status should be success
            The stdout should equal "$HOME/.ssh/id_github.com-personal"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_key::generate
    # ==========================================================================
    # The real ssh-keygen is stubbed and the real ssh_key::path used, so generation
    # resolves to the temp HOME and writes only the stub's argument dump.
    Describe 'ssh_key::generate'

        ssh-keygen() { printf '%s\n' "$*" >"$HOME/keygen.args"; }

        It 'generates an ed25519 key at the keyname path when none exists'
            When call ssh_key::generate personal ed25519 '' me@example.com secret
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/keygen.args" should include 'ed25519'
            The contents of file "$HOME/keygen.args" should include "-f $HOME/.ssh/id_personal"
            The contents of file "$HOME/keygen.args" should include '-C me@example.com'
        End

        It 'generates an rsa key with the given bit length when the type is rsa'
            When call ssh_key::generate personal rsa 2048 me@example.com secret
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/keygen.args" should include '-t rsa'
            The contents of file "$HOME/keygen.args" should include '-b 2048'
        End

        It 'reuses an existing key without regenerating'
            mkdir -p "$HOME/.ssh"
            : >"$HOME/.ssh/id_personal"

            When call ssh_key::generate personal ed25519 '' me@example.com secret
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/keygen.args" should not be exist
        End

    End

    # ==========================================================================
    # ssh_key::register
    # ==========================================================================
    Describe 'ssh_key::register'

        ssh-add() { printf '%s|%s|%s\n' "$SSH_ASKPASS_REQUIRE" "$SSH_PASSPHRASE" "$1" >"$HOME/sshadd"; }

        It 'loads the key into the agent through the askpass helper'
            When call ssh_key::register "$HOME/.ssh/id" secret
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/sshadd" should equal "force|secret|$HOME/.ssh/id"
        End

    End

    # ==========================================================================
    # ssh_key::public_file_content
    # ==========================================================================
    Describe 'ssh_key::public_file_content'

        It 'prints the public half of the key'
            mkdir -p "$HOME/.ssh"
            printf 'ssh-ed25519 AAAA me@example.com\n' >"$HOME/.ssh/id.pub"

            When call ssh_key::public_file_content "$HOME/.ssh/id"
            The status should be success
            The stdout should equal 'ssh-ed25519 AAAA me@example.com'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_key::fingerprint
    # ==========================================================================
    Describe 'ssh_key::fingerprint'

        ssh-keygen() { printf '256 SHA256:abc me@example.com (ED25519)\n'; }

        It 'prints the key fingerprint'
            When call ssh_key::fingerprint "$HOME/.ssh/id"
            The status should be success
            The stdout should equal '256 SHA256:abc me@example.com (ED25519)'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_key::remove
    # ==========================================================================
    Describe 'ssh_key::remove'

        output::run() { shift; "$@"; }
        ssh_key::path() { printf '/keys/%s' "$1"; }

        It 'removes the private and public halves of the named key'
            rm() { printf 'rm %s\n' "$*" >>"$HOME/log"; }

            When call ssh_key::remove personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'rm -f -- /keys/personal /keys/personal.pub'
        End

    End

End
