# Specs for the manage-ssh-keys helper. TEST_FLAG keeps the functions non-readonly so
# the spec can source libexec/manage-ssh-keys (which pulls in the UI libraries, the
# registry and the SSH key/config primitives) without running its entrypoint;
# helper::isolate redirects the state store and HOME. The interactive primitives
# (prompt::*), the hidden passphrase prompt (prompt::ask_secret), output::*, and the
# SSH primitives are stubbed where a test drives a flow or the provisioning, so no key
# is generated, nothing is prompted, and nothing outside the temp tree is touched. The
# registry is seeded through helper::seed_input and asserted through state::input.
Describe 'libexec/manage-ssh-keys'
    TEST_FLAG=true
    Include libexec/manage-ssh-keys

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # manage_ssh_keys::key_entries
    # ==========================================================================
    Describe 'manage_ssh_keys::key_entries'

        It 'folds every provider onto the one key it serves and lists extra keys'
            helper::seed_input workspace.personal.providers "$(printf 'github.com\ngitlab.com')"
            helper::seed_input workspace.personal.ssh.host.github.com.key personal
            helper::seed_input workspace.personal.ssh.host.gitlab.com.key personal
            helper::seed_input workspace.personal.ssh.extra_keys backup

            When call manage_ssh_keys::key_entries Personal
            The status should be success
            The stdout should equal "$(printf 'personal\tfor github.com, gitlab.com\nbackup\t(no provider)')"
            The stderr should be blank
        End

        It 'prints nothing when no keys have been created'
            When call manage_ssh_keys::key_entries Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # manage_ssh_keys::list
    # ==========================================================================
    Describe 'manage_ssh_keys::list'

        output::group() { printf 'group %s\n' "$1" >>"$HOME/log"; }
        output::info() { printf 'info %s\n' "$1" >>"$HOME/log"; }

        It 'shows the title and lists each key with its providers'
            helper::seed_input workspace.personal.providers github.com
            helper::seed_input workspace.personal.ssh.host.github.com.key personal
            helper::seed_input workspace.personal.ssh.extra_keys backup

            When call manage_ssh_keys::list Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'group ssh key management'
            The contents of file "$HOME/log" should include 'ssh key personal for github.com'
            The contents of file "$HOME/log" should include 'ssh key backup (no provider)'
        End

        It 'says so when no SSH keys have been created yet'
            When call manage_ssh_keys::list Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'no SSH keys created yet'
        End

    End

    # ==========================================================================
    # manage_ssh_keys::keys
    # ==========================================================================
    Describe 'manage_ssh_keys::keys'

        It 'prints each created key once'
            helper::seed_input workspace.personal.providers "$(printf 'github.com\ngitlab.com')"
            helper::seed_input workspace.personal.ssh.host.github.com.key personal
            helper::seed_input workspace.personal.ssh.host.gitlab.com.key personal
            helper::seed_input workspace.personal.ssh.extra_keys backup

            When call manage_ssh_keys::keys Personal
            The status should be success
            The stdout should equal "$(printf 'personal\nbackup')"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # manage_ssh_keys::pick_remove
    # ==========================================================================
    Describe 'manage_ssh_keys::pick_remove'

        # Pick the first offered key (the first option's value column).
        prompt::select_one() { shift; printf '%s' "${1%%$'\t'*}"; }

        It 'offers the created keys and prints the chosen one'
            helper::seed_input workspace.personal.providers github.com
            helper::seed_input workspace.personal.ssh.host.github.com.key personal

            When call manage_ssh_keys::pick_remove Personal
            The status should be success
            The stdout should equal 'personal'
            The stderr should be blank
        End

        It 'cancels without prompting when there is no key to remove'
            prompt::select_one() { printf 'prompted\n' >>"$HOME/log"; }

            When call manage_ssh_keys::pick_remove Personal
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # manage_ssh_keys::remove_key
    # ==========================================================================
    Describe 'manage_ssh_keys::remove_key'

        ssh_config::host::remove() { printf 'config_remove %s %s\n' "$1" "$2" >>"$HOME/log"; }
        ssh_key::remove() { printf 'key_remove %s\n' "$1" >>"$HOME/log"; }

        It 'removes a provider key: its config blocks, host mappings, provider list and settings'
            helper::seed_input workspace.personal.providers "$(printf 'github.com\ngitlab.com')"
            helper::seed_input workspace.personal.ssh.host.github.com.key personal
            helper::seed_input workspace.personal.ssh.host.gitlab.com.key personal
            helper::seed_input workspace.personal.ssh.key.personal.type ed25519

            When call manage_ssh_keys::remove_key Personal personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'config_remove github.com personal'
            The contents of file "$HOME/log" should include 'config_remove gitlab.com personal'
            The contents of file "$HOME/log" should include 'key_remove personal'
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.host.github.com.key" should not be exist
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.host.gitlab.com.key" should not be exist
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.providers" should not be exist
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.key.personal.type" should not be exist
        End

        It 'leaves the other provider in the list when only one key is removed'
            helper::seed_input workspace.personal.providers "$(printf 'github.com\nbitbucket.org')"
            helper::seed_input workspace.personal.ssh.host.github.com.key personal
            helper::seed_input workspace.personal.ssh.host.bitbucket.org.key work

            When call manage_ssh_keys::remove_key Personal personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'config_remove github.com personal'
            The contents of file "$HOME/log" should not include 'config_remove bitbucket.org'
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.providers" should equal 'bitbucket.org'
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.host.bitbucket.org.key" should be exist
        End

        It 'removes a host-less extra key without touching any config block'
            helper::seed_input workspace.personal.ssh.extra_keys backup
            helper::seed_input workspace.personal.ssh.key.backup.type ed25519

            When call manage_ssh_keys::remove_key Personal backup
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should not include 'config_remove'
            The contents of file "$HOME/log" should include 'key_remove backup'
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.extra_keys" should not be exist
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.key.backup.type" should not be exist
        End

    End

    # ==========================================================================
    # manage_ssh_keys::remaining_providers
    # ==========================================================================
    Describe 'manage_ssh_keys::remaining_providers'

        It 'offers every known provider when none is managed yet'
            When call manage_ssh_keys::remaining_providers Personal
            The status should be success
            The stdout should equal "$(printf 'github.com\ngitlab.com\nbitbucket.org')"
            The stderr should be blank
        End

        It 'drops the providers the workspace already manages'
            helper::seed_input workspace.personal.providers github.com

            When call manage_ssh_keys::remaining_providers Personal
            The status should be success
            The stdout should equal "$(printf 'gitlab.com\nbitbucket.org')"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # manage_ssh_keys::pick_providers
    # ==========================================================================
    Describe 'manage_ssh_keys::pick_providers'

        # Echo each offered entry's token (its second tab field), so the test sees
        # exactly what the checklist was given.
        prompt::select_multi() {
            local item

            shift  # drop the header arg, leaving the entries

            for item in "$@"
            do
                printf '%s\n' "$(printf '%s' "$item" | cut -f2)"
            done
        }

        It 'offers only the unmanaged providers and no custom item when not allowed'
            helper::seed_input workspace.personal.providers github.com

            When call manage_ssh_keys::pick_providers Personal no
            The status should be success
            The stdout should equal "$(printf 'gitlab.com\nbitbucket.org')"
            The stderr should be blank
        End

        It 'appends a custom item when allowed'
            When call manage_ssh_keys::pick_providers Personal yes
            The status should be success
            The stdout should equal "$(printf 'github.com\ngitlab.com\nbitbucket.org\ncustom')"
            The stderr should be blank
        End

        It 'prints nothing without prompting when there is nothing to offer'
            helper::seed_input workspace.personal.providers "$(printf 'github.com\ngitlab.com\nbitbucket.org')"
            prompt::select_multi() { printf 'prompted\n' >>"$HOME/log"; }

            When call manage_ssh_keys::pick_providers Personal no
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # manage_ssh_keys::create
    # ==========================================================================
    # The settings recording (state::set/state::list_append) runs against the isolated
    # store; the prompts, the hidden passphrase prompt, output::run and the provisioning
    # primitives (ssh_key::generate, ssh_key::register, ssh_config::*, ssh_connect::register)
    # are stubbed, so no key is generated and nothing outside the temp tree is touched.
    # prompt::ask echoes its default so the key name and comment fall to their defaults.
    # The tests assert the settings are recorded and that manage_ssh_keys::create then
    # drives generation, the agent load, each provider's Host block and registration -
    # the wiring it took over from ssh_key::generate, which is now keygen-only.
    Describe 'manage_ssh_keys::create'

        workspace::git::user_email() { printf 'ada@example.com'; }
        prompt::ask() { printf '%s' "${2:-}"; }
        prompt::select_one() { printf 'ed25519'; }
        prompt::ask_secret() { printf 'PASS'; }
        output::run() { shift; "$@"; }
        ssh_key::path() { printf '/keys/%s' "$1"; }
        ssh_key::generate() { printf 'generate %s\n' "$*" >>"$HOME/log"; }
        ssh_key::register() { printf 'register %s %s\n' "$1" "$2" >>"$HOME/log"; }
        ssh_config::host::alias() { printf '%s-%s' "$1" "$2"; }
        ssh_config::host::filename() { printf '20-%s-%s' "$2" "$1"; }
        ssh_config::host::exist() { return 1; }
        ssh_config::host::add() { printf 'ssh_add_block %s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5" >>"$HOME/log"; }
        ssh_connect::register() { printf 'register_ssh %s %s %s\n' "$1" "$2" "$3" >>"$HOME/log"; }

        It 'records the settings, maps each provider, generates the key, and writes each Host block'
            SSH_AUTH_SOCK=''

            When call manage_ssh_keys::create Personal personal github.com gitlab.com
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.key.personal.type" should equal 'ed25519'
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.host.github.com.key" should equal 'personal'
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.host.gitlab.com.key" should equal 'personal'
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.providers" should equal "$(printf 'github.com\ngitlab.com')"
            The contents of file "$HOME/log" should include 'generate personal ed25519  ada@example.com PASS'
            The contents of file "$HOME/log" should include 'ssh_add_block 20-personal-github.com github.com-personal github.com git /keys/personal'
            The contents of file "$HOME/log" should include 'ssh_add_block 20-personal-gitlab.com gitlab.com-personal gitlab.com git /keys/personal'
        End

        It 'loads the key and registers each provider when an agent is present'
            SSH_AUTH_SOCK=/tmp/agent

            When call manage_ssh_keys::create Personal personal github.com
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'register /keys/personal PASS'
            The contents of file "$HOME/log" should include 'register_ssh github.com-personal github.com /keys/personal'
        End

        It 'appends a host-less extra key, collects no passphrase for an existing key, and writes no block'
            SSH_AUTH_SOCK=''
            ssh_key::path() { : >"$HOME/keys-$1"; printf '%s' "$HOME/keys-$1"; }

            When call manage_ssh_keys::create Personal extra-personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.extra_keys" should equal 'extra-personal'
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.providers" should not be exist
            The contents of file "$HOME/log" should equal 'generate extra-personal ed25519  ada@example.com '
        End

        It 'cancels when a settings prompt is cancelled'
            prompt::ask() { return 2; }

            When call manage_ssh_keys::create Personal personal github.com
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # manage_ssh_keys::install_clone_script
    # ==========================================================================
    # clone_script::install and workspace::path are stubbed so the deploy is logged
    # rather than performed and nothing outside the temp tree is touched.
    Describe 'manage_ssh_keys::install_clone_script'

        clone_script::install() { printf 'install %s %s\n' "$1" "$2" >>"$HOME/log"; }
        workspace::path() { printf '%s/ws' "$HOME"; }

        It 'installs the helper when the workspace has at least one key'
            manage_ssh_keys::keys() { printf 'personal\n'; }

            When call manage_ssh_keys::install_clone_script Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "install Personal $HOME/ws"
        End

        It 'is a no-op when the workspace has no key'
            manage_ssh_keys::keys() { :; }

            When call manage_ssh_keys::install_clone_script Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # manage_ssh_keys::menu
    # ==========================================================================
    Describe 'manage_ssh_keys::menu'

        manage_ssh_keys::list() { :; }
        manage_ssh_keys::create() { shift; printf 'made %s\n' "$*" >>"$HOME/log"; }
        manage_ssh_keys::keys() { :; }
        manage_ssh_keys::install_clone_script() { :; }

        It 'quits immediately when the user picks do-not-manage'
            prompt::select_one() { printf 'quit'; }

            When call manage_ssh_keys::menu Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

        It 'quits immediately on a lone Escape'
            prompt::select_one() { return 2; }

            When call manage_ssh_keys::menu Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

        It 'makes one shared key for the selected providers, named from the slug'
            prompt::select_one() { printf 'all'; }
            manage_ssh_keys::pick_providers() { printf 'github.com\ngitlab.com\n'; }

            When call manage_ssh_keys::menu Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'made personal github.com gitlab.com'
        End

        It 'reuses the single existing key when the workspace already has one'
            prompt::select_one() { printf 'all'; }
            manage_ssh_keys::keys() { printf 'shared\n'; }
            manage_ssh_keys::pick_providers() { printf 'gitlab.com\n'; }

            When call manage_ssh_keys::menu Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'made shared gitlab.com'
        End

        It 'makes one key per provider plus custom keys from the suffix loop'
            prompt::select_one() { printf 'per'; }
            manage_ssh_keys::pick_providers() { printf 'github.com\ncustom\n'; }
            prompt::ask() {
                local -i n

                n="$(cat "$HOME/n" 2>/dev/null || printf 0)"
                printf '%d' $((n + 1)) >"$HOME/n"
                ((n == 0)) && printf 'backup' || printf ''
            }

            When call manage_ssh_keys::menu Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "$(printf 'made personal-github github.com\nmade backup-personal')"
        End

        It 'removes a key then redraws the menu before quitting'
            prompt::select_one() {
                local -i n

                n="$(cat "$HOME/n" 2>/dev/null || printf 0)"
                printf '%d' $((n + 1)) >"$HOME/n"
                ((n == 0)) && printf 'remove' || printf 'quit'
            }
            manage_ssh_keys::keys() { printf 'personal\n'; }
            manage_ssh_keys::pick_remove() { printf 'personal'; }
            manage_ssh_keys::remove_key() { shift; printf 'removed %s\n' "$1" >>"$HOME/log"; }

            When call manage_ssh_keys::menu Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'removed personal'
        End

        It 'creates nothing and returns to the menu when no provider is selected'
            prompt::select_one() {
                local -i n

                n="$(cat "$HOME/n" 2>/dev/null || printf 0)"
                printf '%d' $((n + 1)) >"$HOME/n"
                ((n == 0)) && printf 'all' || printf 'quit'
            }
            manage_ssh_keys::pick_providers() { printf ''; }

            When call manage_ssh_keys::menu Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

        It 'installs the clone-repo helper before leaving'
            prompt::select_one() { printf 'quit'; }
            manage_ssh_keys::install_clone_script() { printf 'install %s\n' "$1" >>"$HOME/log"; }

            When call manage_ssh_keys::menu Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'install Personal'
        End

    End

    # ==========================================================================
    # manage_ssh_keys::ask_target
    # ==========================================================================
    Describe 'manage_ssh_keys::ask_target'

        # Echo each offered option's value (its first tab field), so the test sees
        # exactly what the list was given.
        prompt::select_one() {
            local option

            shift  # drop the header arg, leaving the options

            for option in "$@"
            do
                printf '%s\n' "${option%%$'\t'*}"
            done
        }

        It 'tags each registered workspace and appends an external item'
            helper::seed_input workspace.list "$(printf 'Personal\nAcme')"

            When call manage_ssh_keys::ask_target
            The status should be success
            The stdout should equal "$(printf 'workspace:Personal\nworkspace:Acme\nexternal')"
            The stderr should be blank
        End

        It 'offers only the external item when no workspace is registered'
            When call manage_ssh_keys::ask_target
            The status should be success
            The stdout should equal 'external'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # manage_ssh_keys::external
    # ==========================================================================
    # No workspace inputs are written here: the standalone key is untracked. The
    # prompts, the hidden passphrase prompt, output::run and the SSH primitives are
    # stubbed, so no key is generated and nothing outside the temp tree is touched.
    Describe 'manage_ssh_keys::external'

        prompt::ask() {
            case "$1" in
                'SSH key name')
                    printf 'mykey'
                    ;;
                *)
                    printf '%s' "${2:-}"
                    ;;
            esac
        }
        prompt::ask_secret() { printf 'PASS'; }
        output::run() { shift; "$@"; }
        output::warn() { printf 'warn %s\n' "$1" >>"$HOME/log"; }
        ssh_key::path() { printf '/keys/%s' "$1"; }
        ssh_key::generate() { printf 'generate %s\n' "$*" >>"$HOME/log"; }
        ssh_key::register() { printf 'register %s %s\n' "$1" "$2" >>"$HOME/log"; }
        ssh_config::host::alias() { printf '%s-%s' "$1" "$2"; }
        ssh_config::host::filename() { printf '20-%s-%s' "$2" "$1"; }
        ssh_config::host::exist() { return 1; }
        ssh_config::host::add() { printf 'ssh_add_block %s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5" >>"$HOME/log"; }
        ssh_connect::register() { printf 'register_ssh %s %s %s\n' "$1" "$2" "$3" >>"$HOME/log"; }

        It 'generates a standalone key and writes no Host block when none is chosen'
            SSH_AUTH_SOCK=''
            prompt::select_one() {
                case "$1" in
                    'SSH key type')
                        printf 'ed25519'
                        ;;
                    'create a Host config block?')
                        printf 'none'
                        ;;
                esac
            }

            When call manage_ssh_keys::external
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'generate mykey ed25519  '
            The contents of file "$HOME/log" should not include 'ssh_add_block'
            The contents of file "$HOME/log" should include 'not tracked in any workspace'
        End

        It 'writes a Host block keyed by the key name when a provider is chosen'
            SSH_AUTH_SOCK=''
            prompt::select_one() {
                case "$1" in
                    'SSH key type')
                        printf 'ed25519'
                        ;;
                    'create a Host config block?')
                        printf 'github.com'
                        ;;
                esac
            }

            When call manage_ssh_keys::external
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'ssh_add_block 20-mykey-github.com github.com-mykey github.com git /keys/mykey'
        End

        It 'loads the key into the agent when one is running'
            SSH_AUTH_SOCK=/tmp/agent
            prompt::select_one() {
                case "$1" in
                    'SSH key type')
                        printf 'ed25519'
                        ;;
                    'create a Host config block?')
                        printf 'none'
                        ;;
                esac
            }

            When call manage_ssh_keys::external
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'register /keys/mykey PASS'
        End

        It 're-prompts the key name until a non-empty name is given'
            SSH_AUTH_SOCK=''
            prompt::ask() {
                local -i n

                case "$1" in
                    'SSH key name')
                        n="$(cat "$HOME/n" 2>/dev/null || printf 0)"
                        printf '%d' $((n + 1)) >"$HOME/n"
                        ((n == 0)) && printf '' || printf 'mykey'
                        ;;
                    *)
                        printf '%s' "${2:-}"
                        ;;
                esac
            }
            prompt::select_one() {
                case "$1" in
                    'SSH key type')
                        printf 'ed25519'
                        ;;
                    'create a Host config block?')
                        printf 'none'
                        ;;
                esac
            }

            When call manage_ssh_keys::external
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'warn a key name is required'
            The contents of file "$HOME/log" should include 'generate mykey ed25519  '
        End

        It 'cancels when a settings prompt is cancelled'
            prompt::ask() { return 2; }

            When call manage_ssh_keys::external
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # manage_ssh_keys::main
    # ==========================================================================
    Describe 'manage_ssh_keys::main'

        It 'drives the workspace menu for an existing named workspace'
            helper::seed_input workspace.list Personal
            manage_ssh_keys::menu() { printf 'menu %s\n' "$1" >>"$HOME/log"; }

            When call manage_ssh_keys::main Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'menu Personal'
        End

        It 'fails when a named workspace does not exist'
            output::fatal() { printf 'fatal %s\n' "$1" >&2; }

            When call manage_ssh_keys::main Ghost
            The status should equal 2
            The stdout should be blank
            The stderr should include 'no such workspace: Ghost'
        End

        It 'warns and returns without prompting when there is no terminal'
            PROMPT_INPUT='/nonexistent'
            manage_ssh_keys::ask_target() { printf 'asked\n' >>"$HOME/log"; }

            When call manage_ssh_keys::main
            The status should be success
            The stdout should be blank
            The stderr should include 'interactive terminal'
            The path "$HOME/log" should not be exist
        End

        It 'routes to the external flow when the picker returns external'
            PROMPT_INPUT='/dev/null'
            manage_ssh_keys::ask_target() { printf 'external'; }
            manage_ssh_keys::external() { printf 'external\n' >>"$HOME/log"; }

            When call manage_ssh_keys::main
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'external'
        End

        It 'routes to the workspace menu when the picker returns a workspace'
            PROMPT_INPUT='/dev/null'
            manage_ssh_keys::ask_target() { printf 'workspace:Personal'; }
            manage_ssh_keys::menu() { printf 'menu %s\n' "$1" >>"$HOME/log"; }

            When call manage_ssh_keys::main
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'menu Personal'
        End

        It 'returns 2 when the picker is cancelled'
            PROMPT_INPUT='/dev/null'
            manage_ssh_keys::ask_target() { return 2; }

            When call manage_ssh_keys::main
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
        End

    End

End
