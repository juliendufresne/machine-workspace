# Specs for the remove action. TEST_FLAG keeps the functions non-readonly so the
# spec can source libexec/remove (which pulls in the UI libraries, the registry and
# the identity toolkit) without running its entrypoint; helper::isolate redirects
# the state store and HOME. The interactive primitives (prompt::*),
# output::*, and the identity helpers are stubbed where a test drives a flow, so
# nothing is prompted and nothing outside the temp tree is touched. The registry is
# seeded through helper::seed_input and asserted through state::input.
Describe 'libexec/remove'
    TEST_FLAG=true
    Include libexec/remove

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # remove::ask_should_remove_keys
    # ==========================================================================
    Describe 'remove::ask_should_remove_keys'

        It 'prints the key-removal choice'
            prompt::select_one() { printf 'yes'; }

            When call remove::ask_should_remove_keys
            The status should be success
            The stdout should equal 'yes'
            The stderr should be blank
        End

        It 'keeps the keys when the prompt is cancelled'
            prompt::select_one() { return 2; }

            When call remove::ask_should_remove_keys
            The status should be success
            The stdout should equal 'no'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # remove::ssh_config_host_files
    # ==========================================================================
    Describe 'remove::ssh_config_host_files'

        ssh_config::host::remove() { printf 'ssh_config_remove %s %s\n' "$1" "$2" >>"$HOME/log"; }

        It 'removes each host config block by host and slug'
            helper::seed_input workspace.personal.providers "$(printf 'github.com\ngitlab.com')"

            When call remove::ssh_config_host_files Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'ssh_config_remove github.com personal'
            The contents of file "$HOME/log" should include 'ssh_config_remove gitlab.com personal'
        End

        It 'does nothing when the workspace grants no hosts'
            When call remove::ssh_config_host_files Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # remove::ssh_keys
    # ==========================================================================
    Describe 'remove::ssh_keys'

        ssh_key::remove() { printf 'ssh_key_remove %s\n' "$1" >>"$HOME/log"; }

        It 'removes each unique ssh key the workspace hosts map to'
            helper::seed_input workspace.personal.providers "$(printf 'github.com\ngitlab.com')"
            helper::seed_input workspace.personal.ssh.host.github.com.key personal
            helper::seed_input workspace.personal.ssh.host.gitlab.com.key personal

            When call remove::ssh_keys Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'ssh_key_remove personal'
        End

        It 'removes a host-less extra key'
            helper::seed_input workspace.personal.ssh.extra_keys backup

            When call remove::ssh_keys Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'ssh_key_remove backup'
        End

    End

    # ==========================================================================
    # remove::keys
    # ==========================================================================
    Describe 'remove::keys'

        output::run() { shift; "$@"; }
        workspace::git::user_email() { printf 'ada@example.com'; }
        gpg::key_id_from_email() { printf 'KEYID'; }
        gpg::remove_by_id() { printf 'gpg_remove %s\n' "$1" >>"$HOME/log"; }
        remove::ssh_keys() { printf 'ssh_remove_keys %s\n' "$1" >>"$HOME/log"; }

        It 'removes the gpg key and delegates the ssh key removal'
            When call remove::keys Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'gpg_remove KEYID'
            The contents of file "$HOME/log" should include 'ssh_remove_keys Personal'
        End

    End

    # ==========================================================================
    # remove::deregister
    # ==========================================================================
    Describe 'remove::deregister'

        It 'drops the name from the list and keeps the others in order'
            helper::seed_input workspace.list "$(printf 'Personal\nAcme\nWork')"

            When call remove::deregister Acme
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.list" should equal "$(printf 'Personal\nWork')"
        End

        It 'clears the list when the last workspace is deregistered'
            helper::seed_input workspace.list Personal

            When call remove::deregister Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.list" should not be exist
        End

        It 'removes the slug-namespaced inputs and the manifest, leaving other workspaces alone'
            helper::seed_input workspace.list "$(printf 'Personal\nAcme')"
            helper::seed_input workspace.personal.path /srv/personal
            helper::seed_input workspace.acme.path /srv/acme
            state::created 'workspace@personal' /srv/personal/.gitconfig

            When call remove::deregister Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.path" should not be exist
            The path "$XDG_STATE_HOME/workspace/manifests/workspace@personal" should not be exist
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.acme.path" should be exist
        End

    End

    # ==========================================================================
    # remove::remove_one
    # ==========================================================================
    Describe 'remove::remove_one'

        output::run() { shift; "$@"; }
        output::stage() { :; }
        output::warn() { printf '%s\n' "$1" >&2; }
        gitconfig::block::exist() { return 0; }
        gitconfig::block::remove() { printf 'gitconfig_block_remove %s\n' "$1" >>"$HOME/log"; }
        remove::ssh_config_host_files() { printf 'ssh_config_host_files %s\n' "$1" >>"$HOME/log"; }
        remove::keys() { printf 'remove_keys %s\n' "$1" >>"$HOME/log"; }

        It 'reverses the blocks, removes a directory we created, and deregisters'
            helper::seed_input workspace.list Personal
            helper::seed_input workspace.personal.path "$HOME/personal"
            mkdir -p "$HOME/personal"
            state::contains_only_created() { return 0; }

            When call remove::remove_one Personal no
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/personal" should not be exist
            The contents of file "$HOME/log" should include 'gitconfig_block_remove personal'
            The contents of file "$HOME/log" should include 'ssh_config_host_files Personal'
            The contents of file "$HOME/log" should not include 'remove_keys'
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.list" should not be exist
        End

        It 'removes the keys when asked'
            helper::seed_input workspace.list Personal

            When call remove::remove_one Personal yes
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'remove_keys Personal'
        End

        It 'leaves a directory that holds files we did not create'
            helper::seed_input workspace.list Personal
            helper::seed_input workspace.personal.path "$HOME/personal"
            mkdir -p "$HOME/personal"
            state::contains_only_created() { return 1; }

            When call remove::remove_one Personal no
            The status should be success
            The stdout should be blank
            The stderr should include 'leaving it in place'
            The path "$HOME/personal" should be directory
        End

    End

    # ==========================================================================
    # remove::interactive
    # ==========================================================================
    Describe 'remove::interactive'

        PROMPT_INPUT='/dev/null'                  # a readable input: the terminal probe passes
        remove::ask_should_remove_keys() { :; }
        remove::remove_one() { printf 'remove_one %s\n' "$1" >>"$HOME/log"; }

        It 'warns and removes nothing when there is no terminal'
            PROMPT_INPUT='/nonexistent'

            When call remove::interactive
            The status should be success
            The stdout should be blank
            The stderr should include 'interactive terminal'
            The path "$HOME/log" should not be exist
        End

        It 'removes only the workspaces the menu selected'
            helper::seed_input workspace.list "$(printf 'Personal\nAcme')"
            helper::seed_input workspace.personal.path "$HOME/personal"
            helper::seed_input workspace.acme.path "$HOME/acme"
            prompt::select_multi() { printf 'Personal\n'; }  # the user picked only Personal

            When call remove::interactive
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'remove_one Personal'
        End

        It 'returns without asking for keys when no workspace is registered'
            remove::ask_should_remove_keys() { printf 'ask_keys\n' >>"$HOME/log"; }

            When call remove::interactive
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # remove::main
    # ==========================================================================
    Describe 'remove::main'

        It 'runs the interactive removal with no argument'
            helper::seed_input workspace.list Personal
            remove::interactive() { printf 'interactive\n' >>"$HOME/log"; }

            When call remove::main
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'interactive'
        End

        It 'warns without running the removal when no workspace is registered'
            remove::interactive() { printf 'interactive\n' >>"$HOME/log"; }

            When call remove::main
            The status should be success
            The stdout should be blank
            The stderr should include 'no workspaces registered'
            The path "$HOME/log" should not be exist
        End

        It 'asks about keys then removes just the named workspace'
            helper::seed_input workspace.list Personal
            remove::ask_should_remove_keys() { printf 'ask_keys\n' >>"$HOME/log"; }
            remove::remove_one() { printf 'remove_one %s\n' "$1" >>"$HOME/log"; }

            When call remove::main Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "$(printf 'ask_keys\nremove_one Personal')"
        End

        It 'fails with exit 2 when the named workspace does not exist'
            remove::remove_one() { printf 'remove_one\n' >>"$HOME/log"; }

            When call remove::main Acme
            The status should equal 2
            The stdout should be blank
            The stderr should include 'no such workspace'
            The path "$HOME/log" should not be exist
        End

    End

End
