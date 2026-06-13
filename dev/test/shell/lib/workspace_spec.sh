# Specs for the shared workspace primitives. TEST_FLAG keeps the functions
# non-readonly so the spec can source lib/workspace.sh (which pulls in only the
# state store it reads) without running an entrypoint; helper::isolate redirects the
# state store and HOME. The registry is seeded through helper::seed_input and
# asserted through state::input. The action-specific logic lives in the libexec
# scripts and is tested under dev/test/shell/libexec/.
Describe 'lib/workspace.sh'
    TEST_FLAG=true
    Include lib/workspace.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # workspace::slug
    # ==========================================================================
    Describe 'workspace::slug'

        It 'lower-cases the name and turns spaces into hyphens'
            When call workspace::slug 'Acme Corp'
            The status should be success
            The stdout should equal 'acme-corp'
            The stderr should be blank
        End

        It 'strips characters outside the safe set'
            When call workspace::slug 'Work/Stuff!'
            The status should be success
            The stdout should equal 'workstuff'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # workspace::list
    # ==========================================================================
    Describe 'workspace::list'

        It 'prints the registered workspace names in order'
            helper::seed_input workspace.list "$(printf 'Personal\nAcme')"

            When call workspace::list
            The status should be success
            The stdout should equal "$(printf 'Personal\nAcme')"
            The stderr should be blank
        End

        It 'prints nothing when no workspace is registered'
            When call workspace::list
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # workspace::exists
    # ==========================================================================
    Describe 'workspace::exists'

        It 'is true for a registered name regardless of case'
            helper::seed_input workspace.list Personal

            When call workspace::exists personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false for an unregistered name'
            helper::seed_input workspace.list Personal

            When call workspace::exists Acme
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # workspace::path
    # ==========================================================================
    Describe 'workspace::path'

        It 'prints the saved path for the workspace'
            helper::seed_input workspace.personal.path /srv/personal

            When call workspace::path Personal
            The status should be success
            The stdout should equal '/srv/personal'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # workspace::git::user_name
    # ==========================================================================
    Describe 'workspace::git::user_name'

        It 'prints the git user name read back from the per-tree .gitconfig'
            helper::seed_input workspace.personal.path "$HOME/personal"
            mkdir -p "$HOME/personal"
            printf '[user]\n\tname = Ada Lovelace\n\temail = ada@example.com\n' >"$HOME/personal/.gitconfig"

            When call workspace::git::user_name Personal
            The status should be success
            The stdout should equal 'Ada Lovelace'
            The stderr should be blank
        End

        It 'prints nothing when the .gitconfig is missing'
            helper::seed_input workspace.personal.path "$HOME/personal"

            When call workspace::git::user_name Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # workspace::git::user_email
    # ==========================================================================
    Describe 'workspace::git::user_email'

        It 'prints the git user email read back from the per-tree .gitconfig'
            helper::seed_input workspace.personal.path "$HOME/personal"
            mkdir -p "$HOME/personal"
            printf '[user]\n\tname = Ada Lovelace\n\temail = ada@example.com\n' >"$HOME/personal/.gitconfig"

            When call workspace::git::user_email Personal
            The status should be success
            The stdout should equal 'ada@example.com'
            The stderr should be blank
        End

        It 'prints nothing when the .gitconfig is missing'
            helper::seed_input workspace.personal.path "$HOME/personal"

            When call workspace::git::user_email Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # workspace::ssh::hosts
    # ==========================================================================
    Describe 'workspace::ssh::hosts'

        It 'lists providers then extra hosts, dropping duplicates'
            helper::seed_input workspace.personal.providers "$(printf 'github.com\nbitbucket.org')"
            helper::seed_input workspace.personal.extra_hosts 'github.com codeberg.org'

            When call workspace::ssh::hosts Personal
            The status should be success
            The line 1 of stdout should equal 'github.com'
            The line 2 of stdout should equal 'bitbucket.org'
            The line 3 of stdout should equal 'codeberg.org'
            The stderr should be blank
        End

        It 'prints nothing when no host is configured'
            When call workspace::ssh::hosts Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

End
