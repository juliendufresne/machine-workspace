# Specs for the clone-repo helper installer. TEST_FLAG keeps the functions
# non-readonly so the spec can source lib/clone_script.sh (which pulls in the state
# store, the output library and the workspace primitives) without making them
# readonly; helper::isolate redirects the state store and HOME to fresh per-example
# temp directories. The install path is exercised through wrapper::clone_script::install,
# which points PROJECT_ROOT at a temp repo holding a known clone-repo source, so the
# copy is asserted against that source and nothing outside the temp tree is touched;
# output::run is reduced to running its command and state::created is stubbed to log.
Describe 'lib/clone_script.sh'
    TEST_FLAG=true
    Include lib/clone_script.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # clone_script::source_path
    # ==========================================================================
    Describe 'clone_script::source_path'

        It 'is libexec/clone-repo under PROJECT_ROOT'
            PROJECT_ROOT=/repo
            When call clone_script::source_path
            The status should be success
            The stdout should equal '/repo/libexec/clone-repo'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # clone_script::dest_path
    # ==========================================================================
    Describe 'clone_script::dest_path'

        It 'is clone-repo under the workspace path'
            When call clone_script::dest_path /home/ada/Workspace/Personal
            The status should be success
            The stdout should equal '/home/ada/Workspace/Personal/clone-repo'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # clone_script::deploy
    # ==========================================================================
    Describe 'clone_script::deploy'

        It 'copies the source to the destination and makes it executable'
            printf 'SOURCE-SCRIPT\n' >"$HOME/source"

            When call clone_script::deploy "$HOME/source" "$HOME/dest"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/dest" should equal 'SOURCE-SCRIPT'
            The path "$HOME/dest" should be executable
        End

    End

    # ==========================================================================
    # clone_script::install
    # ==========================================================================
    # PROJECT_ROOT is redirected to a temp repo holding a known clone-repo source;
    # output::run is reduced to running its command so the real copy happens, and
    # state::created logs its call so the manifest recording is asserted.
    Describe 'clone_script::install'

        output::run() { shift; "$@"; }
        state::created() { printf 'created %s %s\n' "$1" "$2" >>"$HOME/log"; }

        wrapper::clone_script::install() {
            local -i exit_status
            local real_root

            real_root="${PROJECT_ROOT:-}"
            PROJECT_ROOT="$(mktemp -d -t shellspec-clone_script-XXXXXXXXXX)"
            mkdir -p "$PROJECT_ROOT/libexec"
            printf 'SOURCE-SCRIPT\n' >"$PROJECT_ROOT/libexec/clone-repo"

            clone_script::install "$@"
            exit_status=$?

            rm -rf "$PROJECT_ROOT"
            PROJECT_ROOT="$real_root"

            return "$exit_status"
        }

        It 'copies the source to the workspace root as an executable file'
            mkdir -p "$HOME/ws"

            When call wrapper::clone_script::install Personal "$HOME/ws"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/ws/clone-repo" should equal 'SOURCE-SCRIPT'
            The path "$HOME/ws/clone-repo" should be executable
        End

        It 'records the destination in the manifest on first creation'
            mkdir -p "$HOME/ws"

            When call wrapper::clone_script::install Personal "$HOME/ws"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "created workspace@personal $HOME/ws/clone-repo"
        End

        It 'does not re-record the manifest when the helper already exists'
            mkdir -p "$HOME/ws"
            : >"$HOME/ws/clone-repo"

            When call wrapper::clone_script::install Personal "$HOME/ws"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/log" should not be exist
        End

        It 'overwrites an existing helper on re-run'
            mkdir -p "$HOME/ws"
            printf 'OLD\n' >"$HOME/ws/clone-repo"

            When call wrapper::clone_script::install Personal "$HOME/ws"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/ws/clone-repo" should equal 'SOURCE-SCRIPT'
        End

    End

End
