# Specs for the managed clone-repo helper. TEST_FLAG keeps the functions
# non-readonly so the spec can source libexec/clone-repo without running its
# entrypoint; helper::isolate redirects HOME to a fresh per-example temp tree, so
# the .workspace-managed marker and the ~/.ssh/config.d fragments the helper reads
# are set up there and nothing outside the temp tree is touched. For the main
# dispatch, clone_repo::workspace_root is stubbed to a temp workspace root, git is
# stubbed so no clone happens, and the menu/ask prompts are stubbed so the
# interactive form drives without a terminal.
Describe 'libexec/clone-repo'
    TEST_FLAG=true
    Include libexec/clone-repo

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # clone_repo::workspace_name
    # ==========================================================================
    Describe 'clone_repo::workspace_name'

        It 'parses the workspace name from the marker'
            mkdir -p "$HOME/ws"
            printf 'This directory is managed by the workspace tool.\n\nWorkspace:  Personal\nManaged by: /repo\n' >"$HOME/ws/.workspace-managed"

            When call clone_repo::workspace_name "$HOME/ws"
            The status should be success
            The stdout should equal 'Personal'
            The stderr should be blank
        End

        It 'fails when the marker is missing'
            mkdir -p "$HOME/ws"

            When call clone_repo::workspace_name "$HOME/ws"
            The status should equal 1
            The stdout should be blank
            The stderr should include 'no .workspace-managed marker'
        End

        It 'fails when the marker names no workspace'
            mkdir -p "$HOME/ws"
            printf 'This directory is managed by the workspace tool.\n' >"$HOME/ws/.workspace-managed"

            When call clone_repo::workspace_name "$HOME/ws"
            The status should equal 1
            The stdout should be blank
            The stderr should include 'names no workspace'
        End

    End

    # ==========================================================================
    # clone_repo::slug
    # ==========================================================================
    Describe 'clone_repo::slug'

        It 'lower-cases, hyphenates spaces, and strips other characters'
            When call clone_repo::slug 'Acme Corp!'
            The status should be success
            The stdout should equal 'acme-corp'
            The stderr should be blank
        End

        It 'keeps dots, underscores and hyphens'
            When call clone_repo::slug 'a.b_c-d'
            The status should be success
            The stdout should equal 'a.b_c-d'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # clone_repo::managed_providers
    # ==========================================================================
    Describe 'clone_repo::managed_providers'

        It 'lists the real hosts from the workspace fragments'
            mkdir -p "$HOME/.ssh/config.d"
            : >"$HOME/.ssh/config.d/00-base"
            : >"$HOME/.ssh/config.d/20-personal-github.com"
            : >"$HOME/.ssh/config.d/20-personal-gitlab.com"

            When call clone_repo::managed_providers personal
            The status should be success
            The stdout should equal "$(printf 'github.com\ngitlab.com')"
            The stderr should be blank
        End

        It 'prints nothing when the workspace manages no provider'
            mkdir -p "$HOME/.ssh/config.d"

            When call clone_repo::managed_providers personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # clone_repo::resolve_host
    # ==========================================================================
    Describe 'clone_repo::resolve_host'

        It 'expands the github shorthand to github.com'
            When call clone_repo::resolve_host github personal
            The status should be success
            The stdout should equal 'github.com'
            The stderr should be blank
        End

        It 'expands the gitlab shorthand to gitlab.com'
            When call clone_repo::resolve_host gitlab personal
            The status should be success
            The stdout should equal 'gitlab.com'
            The stderr should be blank
        End

        It 'expands the bitbucket shorthand to bitbucket.org'
            When call clone_repo::resolve_host bitbucket personal
            The status should be success
            The stdout should equal 'bitbucket.org'
            The stderr should be blank
        End

        It 'passes a literal host through unchanged'
            When call clone_repo::resolve_host git.example.com personal
            The status should be success
            The stdout should equal 'git.example.com'
            The stderr should be blank
        End

        It 'strips the workspace suffix from a configured alias'
            When call clone_repo::resolve_host github.com-personal personal
            The status should be success
            The stdout should equal 'github.com'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # clone_repo::parse_url
    # ==========================================================================
    Describe 'clone_repo::parse_url'

        It 'splits an HTTPS URL into host and path'
            When call clone_repo::parse_url 'https://github.com/o/r.git'
            The status should be success
            The stdout should equal "$(printf 'github.com\to/r.git')"
            The stderr should be blank
        End

        It 'splits an scp-style SSH URL into host and path'
            When call clone_repo::parse_url 'git@github.com:o/r.git'
            The status should be success
            The stdout should equal "$(printf 'github.com\to/r.git')"
            The stderr should be blank
        End

        It 'splits an ssh:// URL into host and path'
            When call clone_repo::parse_url 'ssh://git@github.com/o/r.git'
            The status should be success
            The stdout should equal "$(printf 'github.com\to/r.git')"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # clone_repo::repo_name
    # ==========================================================================
    Describe 'clone_repo::repo_name'

        It 'is the last path component with a trailing .git removed'
            When call clone_repo::repo_name juliendufresne/machine-workspace.git
            The status should be success
            The stdout should equal 'machine-workspace'
            The stderr should be blank
        End

        It 'is the last path component when there is no .git'
            When call clone_repo::repo_name o/r
            The status should be success
            The stdout should equal 'r'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # clone_repo::resolve_dest
    # ==========================================================================
    Describe 'clone_repo::resolve_dest'

        It 'returns the repo path under the root when it is free'
            When call clone_repo::resolve_dest "$HOME/ws" machine-workspace
            The status should be success
            The stdout should equal "$HOME/ws/machine-workspace"
            The stderr should be blank
        End

        It 'prompts for a new name when the default path already exists'
            mkdir -p "$HOME/ws/machine-workspace"
            clone_repo::ask() { printf 'other'; }

            When call clone_repo::resolve_dest "$HOME/ws" machine-workspace
            The status should be success
            The stdout should equal "$HOME/ws/other"
            The stderr should include 'already exists'
        End

    End

    # ==========================================================================
    # clone_repo::main
    # ==========================================================================
    # workspace_root points at a temp workspace root, git is stubbed so no clone
    # happens (its arguments are logged), and the prompts are stubbed so the
    # interactive form drives without a terminal. setup_ws lays down the marker and
    # one github.com fragment under the isolated HOME.
    Describe 'clone_repo::main'

        clone_repo::workspace_root() { printf '%s/ws' "$HOME"; }
        git() { printf 'git %s\n' "$*" >>"$HOME/gitlog"; }

        setup_ws() {
            mkdir -p "$HOME/ws" "$HOME/.ssh/config.d"
            printf 'Workspace:  Personal\n' >"$HOME/ws/.workspace-managed"
            : >"$HOME/.ssh/config.d/20-personal-github.com"
        }

        It 'clones through the alias for the two-argument provider form'
            setup_ws

            When call clone_repo::main github juliendufresne/machine-workspace
            The status should be success
            The stdout should include 'cloned'
            The stderr should be blank
            The contents of file "$HOME/gitlog" should include "clone -- git@github.com-personal:juliendufresne/machine-workspace.git $HOME/ws/machine-workspace"
        End

        It 'clones through the alias for a full URL'
            setup_ws

            When call clone_repo::main 'https://github.com/juliendufresne/machine-workspace.git'
            The status should be success
            The stdout should include 'cloned'
            The stderr should be blank
            The contents of file "$HOME/gitlog" should include "clone -- git@github.com-personal:juliendufresne/machine-workspace.git $HOME/ws/machine-workspace"
        End

        It 'lists only the managed providers and asks for the repo in the interactive form'
            setup_ws
            clone_repo::menu() { shift; printf 'menu:%s\n' "$*" >>"$HOME/menulog"; printf '1\n'; }
            clone_repo::ask() { printf 'juliendufresne/machine-workspace'; }

            When call clone_repo::main
            The status should be success
            The stdout should include 'cloned'
            The stderr should be blank
            The contents of file "$HOME/menulog" should equal 'menu:github.com'
            The contents of file "$HOME/gitlog" should include "clone -- git@github.com-personal:juliendufresne/machine-workspace.git $HOME/ws/machine-workspace"
        End

        It 'refuses with an error when the workspace has no key for the host'
            setup_ws

            When call clone_repo::main gitlab juliendufresne/machine-workspace
            The status should equal 1
            The stdout should include 'Clone'
            The stderr should include 'no SSH key for gitlab.com'
            The path "$HOME/gitlog" should not be exist
        End

        It 'fails with a usage error on too many arguments'
            setup_ws

            When call clone_repo::main a b c
            The status should equal 2
            The stdout should include 'Clone'
            The stderr should include 'usage'
        End

        It 'fails when not run from a workspace root'
            When call clone_repo::main github juliendufresne/machine-workspace
            The status should equal 1
            The stdout should include 'Clone'
            The stderr should include 'no .workspace-managed marker'
        End

        It 'fails when git is not installed'
            command() { return 1; }

            When call clone_repo::main github juliendufresne/machine-workspace
            The status should equal 1
            The stdout should include 'Clone'
            The stderr should include 'git is not installed'
        End

    End

End
