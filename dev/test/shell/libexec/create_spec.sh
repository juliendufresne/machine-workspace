# Specs for the create action. TEST_FLAG keeps the functions non-readonly so the
# spec can source libexec/create (which pulls in the UI libraries, the registry and
# the identity toolkit) without running its entrypoint; helper::isolate redirects
# the state store and HOME. The interactive primitives (prompt::*), the
# hidden passphrase prompt (prompt::ask_secret), output::*, and the identity
# helpers are stubbed where a test drives a flow or the provisioning, so no key is
# generated, nothing is prompted, and nothing outside the temp tree is touched. The
# registry is seeded through helper::seed_input and asserted through state::input.
Describe 'libexec/create'
    TEST_FLAG=true
    Include libexec/create

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # create::ask_name
    # ==========================================================================
    Describe 'create::ask_name'

        It 'offers Personal as the default when no Personal workspace exists yet'
            prompt::ask() { printf '%s' "${2:-}"; }

            When call create::ask_name
            The status should be success
            The stdout should equal 'Personal'
            The stderr should be blank
        End

        It 'requires an explicit name when a Personal workspace already exists'
            helper::seed_input workspace.list Personal
            prompt::ask() { printf 'default=[%s]\n' "${2:-}" >>"$HOME/asklog"; printf 'Acme'; }

            When call create::ask_name
            The status should be success
            The stdout should equal 'Acme'
            The stderr should be blank
            The contents of file "$HOME/asklog" should equal 'default=[]'
        End

        It 'rejects a duplicate name and re-prompts, carrying the reason into the help line'
            helper::seed_input workspace.list Personal
            prompt::ask() {
                local -i n

                printf '%s\n' "${PROMPT_HELP:-}" >>"$HOME/helplog"
                n="$(cat "$HOME/n" 2>/dev/null || printf 0)"
                printf '%d' $((n + 1)) >"$HOME/n"
                ((n == 0)) && printf 'Personal' || printf 'Acme'
            }

            When call create::ask_name
            The status should be success
            The stdout should equal 'Acme'
            The stderr should be blank
            The contents of file "$HOME/helplog" should include 'already exists'
        End

        It 'cancels when the prompt is cancelled'
            prompt::ask() { return 2; }

            When call create::ask_name
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # create::ensure_dir
    # ==========================================================================
    Describe 'create::ensure_dir'

        output::run() { shift; "$@"; }
        output::warn() { printf '%s\n' "$1" >&2; }
        state::created() { :; }

        It 'creates the workspace directory when missing and records it'
            helper::seed_input workspace.personal.path "$HOME/ws/personal"

            When call create::ensure_dir Personal new
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/ws/personal" should be directory
        End

        It 'accepts an existing directory in edit mode'
            helper::seed_input workspace.personal.path "$HOME/ws/personal"
            mkdir -p "$HOME/ws/personal"

            When call create::ensure_dir Personal edit
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'rejects an existing directory in new mode and signals a re-prompt'
            helper::seed_input workspace.personal.path "$HOME/ws/personal"
            mkdir -p "$HOME/ws/personal"

            When call create::ensure_dir Personal new
            The status should be failure
            The stdout should be blank
            The stderr should include 'already exists'
        End

        It 'rejects a path that exists but is not a directory and signals a re-prompt'
            helper::seed_input workspace.personal.path "$HOME/ws/personal"
            mkdir -p "$HOME/ws"
            : >"$HOME/ws/personal"

            When call create::ensure_dir Personal edit
            The status should be failure
            The stdout should be blank
            The stderr should include 'not a directory'
        End

    End

    # ==========================================================================
    # create::one::path
    # ==========================================================================
    Describe 'create::one::path'

        create::ensure_dir() { :; }

        It 'defaults to ~/Workspace/<name> and persists the path'
            prompt::ask() { printf '%s' "${2:-}"; }

            When call create::one::path Personal new path
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.path" should equal "$HOME/Workspace/Personal"
        End

        It 'prepends ~/Workspace to a relative answer'
            prompt::ask() { printf 'code/personal'; }

            When call create::one::path Personal new path
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.path" should equal "$HOME/Workspace/code/personal"
        End

        It 'writes the resolved path into the caller out-param'
            prompt::ask() { printf '%s' "${2:-}"; }
            wrapper::create::one::path() {
                local -i exit_status
                local out

                create::one::path Personal new out
                exit_status=$?

                printf '%s' "$out"

                return "${exit_status}"
            }

            When call wrapper::create::one::path
            The status should be success
            The stdout should equal "$HOME/Workspace/Personal"
            The stderr should be blank
        End

        It 're-prompts a new-workspace path collision until a fresh path is given'
            prompt::ask() {
                local -i n

                n="$(cat "$HOME/n" 2>/dev/null || printf 0)"
                printf '%d' $((n + 1)) >"$HOME/n"
                ((n == 0)) && printf '/taken' || printf '/fresh'
            }
            create::ensure_dir() { [[ "$(state::input workspace.personal.path)" == /fresh ]]; }

            When call create::one::path Personal new path
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.path" should equal '/fresh'
        End

    End

    # ==========================================================================
    # create::one::register_name
    # ==========================================================================
    Describe 'create::one::register_name'

        It 'appends the name to the list and records its display mapping'
            helper::seed_input workspace.list Personal

            When call create::one::register_name 'Acme Corp'
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.list" should equal "$(printf 'Personal\nAcme Corp')"
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.acme-corp.display" should equal 'Acme Corp'
        End

        It 'does not duplicate a name already listed under its slug'
            helper::seed_input workspace.list Personal

            When call create::one::register_name personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.list" should equal 'Personal'
        End

    End

    # ==========================================================================
    # create::one::mark_directory::write
    # ==========================================================================
    Describe 'create::one::mark_directory::write'

        It 'writes a managed notice naming the workspace and the managing repository'
            When call create::one::mark_directory::write "$HOME/marker" Personal "$HOME/src/machine-workspace"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/marker" should include 'managed by the workspace tool'
            The contents of file "$HOME/marker" should include 'Workspace:  Personal'
            The contents of file "$HOME/marker" should include "Managed by: $HOME/src/machine-workspace"
        End

    End

    # ==========================================================================
    # create::one::mark_directory
    # ==========================================================================
    Describe 'create::one::mark_directory'

        output::run() { shift; "$@"; }

        It 'records the marker in the manifest and stamps it with the managing root'
            PROJECT_ROOT="$HOME/src/machine-workspace"
            create::one::mark_directory::write() { printf 'write %s %s %s\n' "$1" "$2" "$3" >>"$HOME/log"; }
            state::created() { printf 'created %s %s\n' "$1" "$2" >>"$HOME/log"; }

            When call create::one::mark_directory Personal "$HOME/ws"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "$(printf 'created workspace@personal %s/ws/.workspace-managed\nwrite %s/ws/.workspace-managed Personal %s/src/machine-workspace' "$HOME" "$HOME" "$HOME")"
        End

        It 'does not re-record the marker in the manifest when it already exists'
            PROJECT_ROOT="$HOME/src/machine-workspace"
            mkdir -p "$HOME/ws"
            printf 'stamp\n' >"$HOME/ws/.workspace-managed"
            create::one::mark_directory::write() { :; }
            state::created() { printf 'created\n' >>"$HOME/log"; }

            When call create::one::mark_directory Personal "$HOME/ws"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # create::one::gitconfig
    # ==========================================================================
    Describe 'create::one::gitconfig'

        output::run() { shift; "$@"; }
        prompt::ask() {
            case "$1" in
                *user.name*)
                    printf 'Ada Lovelace'
                    ;;
                *user.email*)
                    printf 'ada@example.com'
                    ;;
            esac
        }
        gitconfig::block::exist() { return 1; }
        gitconfig::block::add() { printf 'gitconfig_block_add %s %s %s\n' "$1" "$2" "$3" >>"$HOME/log"; }
        state::created() { printf 'created %s %s\n' "$1" "$2" >>"$HOME/log"; }

        It 'persists the identity, writes only the user config to the gitconfig and links the tree into ~/.gitconfig'
            helper::seed_input workspace.personal.path "$HOME/ws"
            mkdir -p "$HOME/ws"

            When call create::one::gitconfig Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.last.user.name" should equal 'Ada Lovelace'
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.last.user.email" should equal 'ada@example.com'
            The contents of file "$HOME/log" should include "created workspace@personal $HOME/ws/.gitconfig"
            The contents of file "$HOME/ws/.gitconfig" should include 'name = Ada Lovelace'
            The contents of file "$HOME/ws/.gitconfig" should include 'email = ada@example.com'
            The contents of file "$HOME/ws/.gitconfig" should not include 'signingKey'
            The contents of file "$HOME/ws/.gitconfig" should not include 'gpgsign'
            The contents of file "$HOME/log" should include "gitconfig_block_add personal $HOME/ws $HOME/ws/.gitconfig"
        End

        It 'skips the link when the IncludeIf block already exists'
            helper::seed_input workspace.personal.path "$HOME/ws"
            mkdir -p "$HOME/ws"
            gitconfig::block::exist() { return 0; }

            When call create::one::gitconfig Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should not include 'gitconfig_block_add'
        End

        It 'cancels when the identity prompt is cancelled'
            helper::seed_input workspace.personal.path "$HOME/ws"
            prompt::ask() { return 2; }

            When call create::one::gitconfig Personal
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # create::one::gpg
    # ==========================================================================
    Describe 'create::one::gpg'

        output::run() { shift; "$@"; }
        output::info() { printf 'info %s\n' "$1" >>"$HOME/log"; }
        workspace::git::user_email() { printf 'ada@example.com'; }
        workspace::git::user_name() { printf 'Ada'; }
        prompt::ask() { printf '%s' "${2:-}"; }
        prompt::ask_secret() { printf 'asked %s\n' "$1" >>"$HOME/log"; printf 'PASS'; }
        gpg::generate() { : >"$HOME/gen"; printf 'gpg_keygen %s %s\n' "$1" "$2" >>"$HOME/log"; }
        gpg::register() { printf 'gpg_register %s\n' "$1" >>"$HOME/log"; }

        It 'asks then generates the key, writes only the signing config to the gitconfig, and registers it'
            helper::seed_input workspace.personal.path "$HOME/ws"
            mkdir -p "$HOME/ws"
            gpg::key_id_from_email() { [[ -f "$HOME/gen" ]] && printf 'KEYID'; }
            prompt::select_one() {
                case "$1" in
                    'create a GPG signing key?')
                        printf 'yes'
                        ;;
                    'GPG key type')
                        printf 'ed25519'
                        ;;
                esac
            }

            When call create::one::gpg Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'gpg_keygen Ada ada@example.com'
            The contents of file "$HOME/ws/.gitconfig" should include 'signingKey = KEYID'
            The contents of file "$HOME/ws/.gitconfig" should include 'gpgsign = true'
            The contents of file "$HOME/ws/.gitconfig" should not include 'name = '
            The contents of file "$HOME/log" should include 'gpg_register KEYID'
        End

        It 'reuses an existing key without prompting or generating, but still writes the signing config'
            helper::seed_input workspace.personal.path "$HOME/ws"
            mkdir -p "$HOME/ws"
            gpg::key_id_from_email() { printf 'KEYID'; }
            prompt::select_one() { printf 'choose\n' >>"$HOME/log"; printf 'yes'; }

            When call create::one::gpg Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'reusing'
            The contents of file "$HOME/log" should not include 'choose'
            The contents of file "$HOME/log" should not include 'gpg_keygen'
            The contents of file "$HOME/ws/.gitconfig" should include 'signingKey = KEYID'
            The contents of file "$HOME/ws/.gitconfig" should include 'gpgsign = true'
        End

        It 'generates nothing when the user declines'
            helper::seed_input workspace.personal.path "$HOME/ws"
            gpg::key_id_from_email() { return 1; }
            prompt::select_one() { printf 'no'; }

            When call create::one::gpg Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

        It 'clears stale signing config when the user declines'
            helper::seed_input workspace.personal.path "$HOME/ws"
            mkdir -p "$HOME/ws"
            git config -f "$HOME/ws/.gitconfig" user.signingKey OLDKEY
            git config -f "$HOME/ws/.gitconfig" commit.gpgsign true
            git config -f "$HOME/ws/.gitconfig" tag.gpgsign true
            gpg::key_id_from_email() { return 1; }
            prompt::select_one() { printf 'no'; }

            When call create::one::gpg Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/ws/.gitconfig" should not include 'signingKey'
            The contents of file "$HOME/ws/.gitconfig" should not include 'gpgsign'
        End

        It 'cancels when a sub-prompt is cancelled'
            helper::seed_input workspace.personal.path "$HOME/ws"
            gpg::key_id_from_email() { return 1; }
            prompt::select_one() { return 2; }

            When call create::one::gpg Personal
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # create::one
    # ==========================================================================
    Describe 'create::one'

        output::run() { shift; "$@"; }
        output::stage() { :; }
        output::success() { printf 'success %s\n' "$1" >>"$HOME/log"; }
        create::one::mark_directory() { printf 'mark_directory %s %s\n' "$1" "$2" >>"$HOME/log"; }
        create::one::register_name() { printf 'register %s\n' "$1" >>"$HOME/log"; }
        create::one::gitconfig() { printf 'gitconfig\n' >>"$HOME/log"; }
        create::one::gpg() { printf 'gpg\n' >>"$HOME/log"; }
        manage_ssh_keys::menu() { printf 'ssh\n' >>"$HOME/log"; }
        state::created() { :; }

        It 'registers and stamps the marker right after path creation, then provisions in order'
            create::one::path() { local -n ref="$3"; printf 'workspace_path %s\n' "$2" >>"$HOME/log"; ref="$HOME/ws"; }

            When call create::one Personal new
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "$(printf 'workspace_path new\nregister Personal\nmark_directory Personal %s/ws\ngitconfig\ngpg\nssh\nsuccess Workspace Personal created' "$HOME")"
        End

        It 'confirms an edit with the edited message'
            create::one::path() { local -n ref="$3"; ref="$HOME/ws"; }

            When call create::one Personal edit
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should include 'success Workspace Personal edited'
        End

        It 'aborts and returns 2 when a step is cancelled'
            create::one::path() { return 2; }

            When call create::one Personal new
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

    End

    # ==========================================================================
    # create::interactive
    # ==========================================================================
    Describe 'create::interactive'

        It 'warns and returns without prompting when there is no terminal'
            PROMPT_INPUT='/nonexistent'
            prompt::select_one() { printf 'choose\n' >>"$HOME/log"; printf 'exit'; }

            When call create::interactive
            The status should be success
            The stdout should be blank
            The stderr should include 'interactive terminal'
            The path "$HOME/log" should not be exist
        End

        It 'creates a new workspace then exits'
            PROMPT_INPUT='/dev/null'
            prompt::select_one() {
                local -i n

                n="$(cat "$HOME/n" 2>/dev/null || printf 0)"
                printf '%d' $((n + 1)) >"$HOME/n"
                ((n == 0)) && printf 'create' || printf 'exit'
            }
            create::ask_name() { printf 'Acme'; }
            create::one() { printf 'workspace %s %s\n' "$1" "$2" >>"$HOME/log"; }

            When call create::interactive
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'workspace Acme new'
        End

        It 'edits an existing workspace then exits'
            PROMPT_INPUT='/dev/null'
            helper::seed_input workspace.list Personal
            prompt::select_one() {
                local -i n

                n="$(cat "$HOME/n" 2>/dev/null || printf 0)"
                printf '%d' $((n + 1)) >"$HOME/n"
                ((n == 0)) && printf 'edit:Personal' || printf 'exit'
            }
            create::one() { printf 'workspace %s %s\n' "$1" "$2" >>"$HOME/log"; }

            When call create::interactive
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'workspace Personal edit'
        End

        It 'reports a cancelled creation and continues the menu'
            PROMPT_INPUT='/dev/null'
            prompt::select_one() {
                local -i n

                n="$(cat "$HOME/n" 2>/dev/null || printf 0)"
                printf '%d' $((n + 1)) >"$HOME/n"
                ((n == 0)) && printf 'create' || printf 'exit'
            }
            create::ask_name() { return 2; }
            output::info() { printf 'info %s\n' "$1" >>"$HOME/log"; }
            create::one() { printf 'workspace\n' >>"$HOME/log"; }

            When call create::interactive
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'info workspace creation cancelled'
        End

    End

    # ==========================================================================
    # create::main
    # ==========================================================================
    Describe 'create::main'

        It 'drives the looping menu with no argument'
            create::interactive() { printf 'interactive\n' >>"$HOME/log"; }

            When call create::main
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'interactive'
        End

        It 'edits an existing named workspace'
            helper::seed_input workspace.list Personal
            create::one() { printf 'workspace %s %s\n' "$1" "$2" >>"$HOME/log"; }

            When call create::main Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'workspace Personal edit'
        End

        It 'defines a new named workspace'
            create::one() { printf 'workspace %s %s\n' "$1" "$2" >>"$HOME/log"; }

            When call create::main Acme
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal 'workspace Acme new'
        End

    End

End
