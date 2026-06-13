# Specs for the show action. TEST_FLAG keeps the functions non-readonly so the spec
# can source libexec/show (which pulls in the registry and the identity toolkit)
# without running its entrypoint; helper::isolate redirects the state store and
# HOME. output::* and the identity block probes are stubbed so the report is
# captured to a log and nothing outside the temp tree is touched. The registry is
# seeded through helper::seed_input.
Describe 'libexec/show'
    TEST_FLAG=true
    Include libexec/show

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # show::one::git
    # ==========================================================================
    Describe 'show::one::git'

        output::group() { printf 'group %s\n' "$1" >>"$HOME/log"; }
        output::success() { printf 'ok %s\n' "$1" >>"$HOME/log"; }
        output::info() { printf 'info %s\n' "$1" >>"$HOME/log"; }
        gpg::key_id_from_email() { printf 'ED25519ABC'; }

        It 'reports the gitconfig path, the link status, the identity, and the gpg key'
            helper::seed_input workspace.personal.path "$HOME/personal"
            mkdir -p "$HOME/personal"
            printf '[user]\n\tname = Ada Lovelace\n\temail = ada@example.com\n' >"$HOME/personal/.gitconfig"
            gitconfig::block::exist() { return 0; }

            When call show::one::git Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include "group git $HOME/personal/.gitconfig"
            The contents of file "$HOME/log" should include 'ok linked into ~/.gitconfig'
            The contents of file "$HOME/log" should include 'ok user Ada Lovelace / ada@example.com'
            The contents of file "$HOME/log" should include 'ok gpg key ED25519ABC'
        End

        It 'renders placeholders when the git identity and gpg key are absent'
            helper::seed_input workspace.personal.path "$HOME/personal"
            mkdir -p "$HOME/personal"
            gitconfig::block::exist() { return 1; }
            gpg::key_id_from_email() { return 1; }

            When call show::one::git Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'info not linked into ~/.gitconfig'
            The contents of file "$HOME/log" should include 'info no git identity'
            The contents of file "$HOME/log" should include 'info no gpg key'
        End

    End

    # ==========================================================================
    # show::one::ssh
    # ==========================================================================
    Describe 'show::one::ssh'

        output::group() { printf 'group %s\n' "$1" >>"$HOME/log"; }
        output::success() { printf 'ok %s\n' "$1" >>"$HOME/log"; }
        output::info() { printf 'info %s\n' "$1" >>"$HOME/log"; }
        ssh_config::host::alias() { printf '%s-%s' "$1" "$2"; }

        It 'reports a provider key as present when its file exists'
            helper::seed_input workspace.personal.providers github.com
            helper::seed_input workspace.personal.ssh.host.github.com.key personal
            ssh_key::path() { printf '%s/keys/id_%s' "$HOME" "$1"; }
            mkdir -p "$HOME/keys"
            : >"$HOME/keys/id_personal"

            When call show::one::ssh Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'group ssh'
            The contents of file "$HOME/log" should include 'ok key personal (host github.com-personal)'
        End

        It 'reports a host-less extra key as present when its file exists'
            helper::seed_input workspace.personal.ssh.extra_keys backup
            ssh_key::path() { printf '%s/keys/id_%s' "$HOME" "$1"; }
            mkdir -p "$HOME/keys"
            : >"$HOME/keys/id_backup"

            When call show::one::ssh Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'ok key backup (no host alias)'
        End

        It 'reports a host-less extra key as missing when its file is absent'
            helper::seed_input workspace.personal.ssh.extra_keys backup
            ssh_key::path() { printf '%s/keys/id_%s' "$HOME" "$1"; }

            When call show::one::ssh Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'info key backup (no host alias) missing'
        End

        It 'says so when no ssh key is configured'
            ssh_key::path() { printf '%s/keys/id_%s' "$HOME" "$1"; }

            When call show::one::ssh Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'info no ssh keys'
        End

    End

    # ==========================================================================
    # show::one
    # ==========================================================================
    Describe 'show::one'

        output::stage() { printf 'stage %s\n' "$1" >>"$HOME/log"; }
        output::success() { printf 'ok %s\n' "$1" >>"$HOME/log"; }
        output::info() { printf 'info %s\n' "$1" >>"$HOME/log"; }
        show::one::git() { printf 'git_report %s\n' "$1" >>"$HOME/log"; }
        show::one::ssh() { printf 'ssh_report %s\n' "$1" >>"$HOME/log"; }

        It 'reports the directory and delegates the git and ssh reports'
            helper::seed_input workspace.personal.path "$HOME/personal"
            mkdir -p "$HOME/personal"

            When call show::one Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'stage Workspace Personal'
            The contents of file "$HOME/log" should include "ok directory $HOME/personal"
            The contents of file "$HOME/log" should include 'git_report Personal'
            The contents of file "$HOME/log" should include 'ssh_report Personal'
        End

        It 'stops at a missing directory without emitting the git or ssh groups'
            helper::seed_input workspace.personal.path "$HOME/personal"

            When call show::one Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include "info directory $HOME/personal missing"
            The contents of file "$HOME/log" should not include 'git_report'
            The contents of file "$HOME/log" should not include 'ssh_report'
        End

    End

    # ==========================================================================
    # show::all
    # ==========================================================================
    Describe 'show::all'

        output::info() { printf 'info %s\n' "$1" >>"$HOME/log"; }

        It 'reports each registered workspace in order'
            helper::seed_input workspace.list "$(printf 'Personal\nAcme')"
            show::one() { printf 'report_one %s\n' "$1" >>"$HOME/log"; }

            When call show::all
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "$(printf 'report_one Personal\nreport_one Acme')"
        End

        It 'says so when no workspace is registered'
            When call show::all
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'info no workspaces registered'
        End

    End

    # ==========================================================================
    # show::main
    # ==========================================================================
    Describe 'show::main'

        It 'reports every registered workspace with no argument'
            show::all() { printf 'report_all\n' >>"$HOME/log"; }

            When call show::main
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'report_all'
        End

        It 'reports just the named workspace when it exists'
            helper::seed_input workspace.list Personal
            show::one() { printf 'report_one %s\n' "$1" >>"$HOME/log"; }

            When call show::main Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'report_one Personal'
        End

        It 'fails with exit 2 when the named workspace does not exist'
            show::one() { printf 'report_one\n' >>"$HOME/log"; }

            When call show::main Acme
            The status should equal 2
            The stdout should be blank
            The stderr should include 'no such workspace'
            The path "$HOME/log" should not be exist
        End

    End

End
