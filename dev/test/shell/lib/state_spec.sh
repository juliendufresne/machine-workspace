# Specs for the persistent state store. TEST_FLAG keeps the functions
# non-readonly so the spec can source lib/state.sh without running an entrypoint;
# helper::isolate redirects the state store ($XDG_STATE_HOME/workspace) and HOME to
# fresh per-example temp directories. state::input calls output::fatal and
# state::remember/recall call runner::unit_name, neither defined in this file, so
# both are stubbed below. The MACHINE_SETUP_INPUTS_WORKING overlay is normally
# unset; examples that set it cover the overlay branches, and examples that leave it
# unset cover the committed-path branches.
Describe 'lib/state.sh'
    TEST_FLAG=true
    Include lib/state.sh

    BeforeEach 'helper::isolate'

    # state::input fails through output::fatal, which lives in lib/output.sh.
    output::fatal() { printf '%s\n' "$1" >&2; }

    # state::remember and state::recall key on the current unit name, a runner
    # primitive not sourced here.
    runner::unit_name() { printf 'git'; }

    # ==========================================================================
    # state::_root
    # ==========================================================================
    Describe 'state::_root'

        It 'prints the store root under XDG_STATE_HOME'
            When call state::_root
            The status should be success
            The stdout should equal "$XDG_STATE_HOME/workspace"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::_dir
    # ==========================================================================
    Describe 'state::_dir'

        It 'creates the sub-directory and prints its path'
            When call state::_dir inputs
            The status should be success
            The stdout should equal "$XDG_STATE_HOME/workspace/inputs"
            The path "$XDG_STATE_HOME/workspace/inputs" should be exist
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::_key
    # ==========================================================================
    Describe 'state::_key'

        It 'replaces unsafe characters with underscores'
            When call state::_key 'workspaces/api@/srv/api'
            The status should be success
            The stdout should equal 'workspaces_api@_srv_api'
            The stderr should be blank
        End

        It 'keeps characters in the safe set unchanged'
            When call state::_key 'git'
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::_envname
    # ==========================================================================
    Describe 'state::_envname'

        It 'upper-cases and replaces non-alphanumerics with underscores'
            When call state::_envname git.name
            The status should be success
            The stdout should equal 'GIT_NAME'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::_put
    # ==========================================================================
    Describe 'state::_put'

        It 'writes the value with no trailing newline, creating parents'
            When call state::_put "$HOME/nested/dir/file" 'Ada'
            The status should be success
            The stdout should be blank
            The contents of file "$HOME/nested/dir/file" should equal 'Ada'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::ask
    # ==========================================================================
    Describe 'state::ask'

        It 'reuses a value already entered this run in the working overlay'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"
            mkdir -p "$HOME/working"
            printf 'overlay' >"$HOME/working/some.name"

            When call state::ask some.name 'Prompt text'
            The status should be success
            The stdout should be blank
            The contents of file "$HOME/working/some.name" should equal 'overlay'
            The path "$XDG_STATE_HOME/workspace/inputs/some.name" should not be exist
            The stderr should be blank
        End

        It 'reuses a value saved on an earlier run (committed)'
            helper::seed_input some.name 'committed'

            When call state::ask some.name 'Prompt text'
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/some.name" should equal 'committed'
            The stderr should be blank
        End

        It 'takes the value from the environment variable when nothing is saved'
            SOME_NAME=from-env

            When call state::ask some.name 'Prompt text'
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/some.name" should equal 'from-env'
            The stderr should be blank
        End

        It 'writes the env value into the working overlay when one is active'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"
            mkdir -p "$HOME/working"
            SOME_NAME=from-env

            When call state::ask some.name 'Prompt text'
            The status should be success
            The stdout should be blank
            The contents of file "$HOME/working/some.name" should equal 'from-env'
            The path "$XDG_STATE_HOME/workspace/inputs/some.name" should not be exist
            The stderr should be blank
        End

        It 'prompts when nothing is saved and no env var is set'
            Data 'typed-value'

            When call state::ask some.name 'Prompt text'
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/some.name" should equal 'typed-value'
            The stderr should be blank
        End

        It 'prints the help line above the prompt when PROMPT_HELP is set'
            Data 'typed-value'
            PROMPT_HELP='help line'

            When call state::ask some.name 'Prompt text'
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/some.name" should equal 'typed-value'
            The stderr should include 'help line'
        End

    End

    # ==========================================================================
    # state::set
    # ==========================================================================
    Describe 'state::set'

        It 'writes the value to the committed inputs directory'
            When call state::set workspace.personal.path /srv/personal
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.path" should equal '/srv/personal'
            The stderr should be blank
        End

        It 'writes the value to the working overlay when one is active'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"

            When call state::set workspace.personal.path /srv/personal
            The status should be success
            The stdout should be blank
            The contents of file "$HOME/working/workspace.personal.path" should equal '/srv/personal'
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.path" should not be exist
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::input
    # ==========================================================================
    Describe 'state::input'

        It 'prints the value from the working overlay when one is present'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"
            mkdir -p "$HOME/working"
            printf 'overlay' >"$HOME/working/git.name"

            When call state::input git.name
            The status should be success
            The stdout should equal 'overlay'
            The stderr should be blank
        End

        It 'prints the committed value when no overlay holds it'
            helper::seed_input git.name 'Ada'

            When call state::input git.name
            The status should be success
            The stdout should equal 'Ada'
            The stderr should be blank
        End

        It 'fails through output::fatal when no value was saved'
            When call state::input git.name
            The status should be failure
            The stdout should be blank
            The stderr should include 'no saved input: git.name'
        End

    End

    # ==========================================================================
    # state::unset
    # ==========================================================================
    Describe 'state::unset'

        It 'removes a committed input'
            helper::seed_input git.name 'Ada'

            When call state::unset git.name
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/inputs/git.name" should not be exist
            The stderr should be blank
        End

        It 'is a no-op when the input was never saved'
            When call state::unset git.name
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'also removes the working overlay copy when an overlay is active'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"
            mkdir -p "$HOME/working"
            printf 'overlay' >"$HOME/working/git.name"
            helper::seed_input git.name 'Ada'

            When call state::unset git.name
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/inputs/git.name" should not be exist
            The path "$HOME/working/git.name" should not be exist
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::unset_prefix
    # ==========================================================================
    Describe 'state::unset_prefix'

        It 'removes every committed input under the prefix'
            helper::seed_input workspace.personal.path /srv/personal
            helper::seed_input workspace.personal.name Personal
            helper::seed_input workspace.acme.path /srv/acme

            When call state::unset_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.path" should not be exist
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.name" should not be exist
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.acme.path" should be exist
            The stderr should be blank
        End

        It 'is a no-op when the prefix matches nothing'
            When call state::unset_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'also clears the working overlay under the prefix when active'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"
            mkdir -p "$HOME/working"
            printf 'x' >"$HOME/working/workspace.personal.path"
            printf 'y' >"$HOME/working/workspace.acme.path"

            When call state::unset_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The path "$HOME/working/workspace.personal.path" should not be exist
            The path "$HOME/working/workspace.acme.path" should be exist
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::commit
    # ==========================================================================
    Describe 'state::commit'

        It 'is a no-op when no overlay is active'
            When call state::commit git.name
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'moves working-overlay inputs down to the committed directory'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"
            mkdir -p "$HOME/working"
            printf 'Ada' >"$HOME/working/git.name"
            printf 'ada@x' >"$HOME/working/git.email"

            When call state::commit git.name git.email
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/git.name" should equal 'Ada'
            The contents of file "$XDG_STATE_HOME/workspace/inputs/git.email" should equal 'ada@x'
            The path "$HOME/working/git.name" should not be exist
            The stderr should be blank
        End

        It 'skips a name with no working copy'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"
            mkdir -p "$HOME/working"

            When call state::commit git.name
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/inputs/git.name" should not be exist
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::commit_prefix
    # ==========================================================================
    Describe 'state::commit_prefix'

        It 'is a no-op when no overlay is active'
            When call state::commit_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'moves every overlay input under the prefix down to committed'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"
            mkdir -p "$HOME/working"
            printf '/srv' >"$HOME/working/workspace.personal.path"
            printf 'Personal' >"$HOME/working/workspace.personal.name"

            When call state::commit_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.path" should equal '/srv'
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.name" should equal 'Personal'
            The path "$HOME/working/workspace.personal.path" should not be exist
            The stderr should be blank
        End

        It 'is a no-op when the prefix matches nothing in the overlay'
            MACHINE_SETUP_INPUTS_WORKING="$HOME/working"
            mkdir -p "$HOME/working"

            When call state::commit_prefix workspace.personal.
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.personal.path" should not be exist
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::commit_line_append
    # ==========================================================================
    Describe 'state::commit_line_append'

        It 'creates the list file with the first entry'
            When call state::commit_line_append workspace.list Personal
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.list" should equal 'Personal'
            The stderr should be blank
        End

        It 'appends a newline-separated entry to a non-empty list'
            helper::seed_input workspace.list Personal

            When call state::commit_line_append workspace.list Acme
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.list" should equal "$(printf 'Personal\nAcme')"
            The stderr should be blank
        End

        It 'does not add an entry that is already listed'
            helper::seed_input workspace.list "$(printf 'Personal\nAcme')"

            When call state::commit_line_append workspace.list Personal
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.list" should equal "$(printf 'Personal\nAcme')"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::commit_line_remove
    # ==========================================================================
    Describe 'state::commit_line_remove'

        It 'is a no-op when the list file is missing'
            When call state::commit_line_remove workspace.list Personal
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.list" should not be exist
            The stderr should be blank
        End

        It 'rewrites the list without a middle entry, preserving order'
            helper::seed_input workspace.list "$(printf 'Personal\nAcme\nWork')"

            When call state::commit_line_remove workspace.list Acme
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.list" should equal "$(printf 'Personal\nWork')"
            The stderr should be blank
        End

        It 'removes the file entirely when the only entry is removed'
            helper::seed_input workspace.list Personal

            When call state::commit_line_remove workspace.list Personal
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/inputs/workspace.list" should not be exist
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::list_append
    # ==========================================================================
    Describe 'state::list_append'

        It 'appends a value to an existing newline list'
            helper::seed_input workspace.personal.providers github.com

            When call state::list_append workspace.personal.providers gitlab.com
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.providers" should equal "$(printf 'github.com\ngitlab.com')"
            The stderr should be blank
        End

        It 'does not duplicate a value already present'
            helper::seed_input workspace.personal.providers github.com

            When call state::list_append workspace.personal.providers github.com
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.providers" should equal 'github.com'
            The stderr should be blank
        End

        It 'creates the list when it does not exist yet'
            When call state::list_append workspace.personal.ssh.extra_keys backup
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/inputs/workspace.personal.ssh.extra_keys" should equal 'backup'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::own
    # ==========================================================================
    Describe 'state::own'

        It 'creates an owned-marker under managed/'
            When call state::own git
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/managed/git" should be exist
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::disown
    # ==========================================================================
    Describe 'state::disown'

        It 'removes the owned-marker'
            state::own git

            When call state::disown git
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/managed/git" should not be exist
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::owned
    # ==========================================================================
    Describe 'state::owned'

        It 'is true when the unit has an owned-marker'
            state::own git

            When call state::owned git
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the unit has no marker'
            When call state::owned git
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::remember
    # ==========================================================================
    Describe 'state::remember'

        It 'records the prior value the first time'
            When call state::remember user.name Ada
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/config/git/user.name" should equal 'Ada'
            The stderr should be blank
        End

        It 'keeps the first captured value on a later call'
            state::remember user.name Ada

            When call state::remember user.name Grace
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/config/git/user.name" should equal 'Ada'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::recall
    # ==========================================================================
    Describe 'state::recall'

        It 'prints a remembered prior value'
            state::remember user.name Ada

            When call state::recall user.name
            The status should be success
            The stdout should equal 'Ada'
            The stderr should be blank
        End

        It 'prints nothing when nothing was recorded'
            When call state::recall user.name
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::created
    # ==========================================================================
    Describe 'state::created'

        It 'appends a path to the instance manifest'
            When call state::created 'workspaces/api@/srv/api' /srv/api/.git
            The status should be success
            The stdout should be blank
            The contents of file "$XDG_STATE_HOME/workspace/manifests/workspaces_api@_srv_api" should equal '/srv/api/.git'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::forget
    # ==========================================================================
    Describe 'state::forget'

        It 'removes the instance manifest'
            state::created 'workspace@personal' /srv/personal/.git

            When call state::forget 'workspace@personal'
            The status should be success
            The stdout should be blank
            The path "$XDG_STATE_HOME/workspace/manifests/workspace@personal" should not be exist
            The stderr should be blank
        End

        It 'is a no-op when the manifest is missing'
            When call state::forget 'workspace@personal'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # state::contains_only_created
    # ==========================================================================
    Describe 'state::contains_only_created'

        It 'fails when the manifest is missing'
            mkdir -p "$HOME/tree"

            When call state::contains_only_created 'workspace@personal' "$HOME/tree"
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'succeeds when every path under the root was recorded'
            mkdir -p "$HOME/tree/sub"
            : >"$HOME/tree/file"
            : >"$HOME/tree/sub/nested"
            state::created 'workspace@personal' "$HOME/tree/sub"
            state::created 'workspace@personal' "$HOME/tree/file"
            state::created 'workspace@personal' "$HOME/tree/sub/nested"

            When call state::contains_only_created 'workspace@personal' "$HOME/tree"
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'fails when a foreign path is present under the root'
            mkdir -p "$HOME/tree"
            : >"$HOME/tree/file"
            : >"$HOME/tree/foreign"
            state::created 'workspace@personal' "$HOME/tree/file"

            When call state::contains_only_created 'workspace@personal' "$HOME/tree"
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

End
