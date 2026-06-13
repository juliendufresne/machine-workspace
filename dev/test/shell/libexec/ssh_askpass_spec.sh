# Specs for the non-interactive ssh-add askpass helper. TEST_FLAG keeps the
# function non-readonly so the spec can source libexec/ssh_askpass without running
# its entrypoint. The helper has no side effects: it just echoes the passphrase
# carried in SSH_PASSPHRASE, so the env var is the only input.
Describe 'libexec/ssh_askpass'
    TEST_FLAG=true
    Include libexec/ssh_askpass

    # ==========================================================================
    # ssh_askpass::main
    # ==========================================================================
    Describe 'ssh_askpass::main'

        It 'prints the passphrase carried in SSH_PASSPHRASE'
            SSH_PASSPHRASE=secret

            When call ssh_askpass::main
            The status should be success
            The stdout should equal 'secret'
            The stderr should be blank
        End

        It 'prints an empty line when SSH_PASSPHRASE is unset'
            unset SSH_PASSPHRASE

            When call ssh_askpass::main
            The status should be success
            The stdout should equal ''
            The stderr should be blank
        End

    End

End
