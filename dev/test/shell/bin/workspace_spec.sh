# Specs for the entrypoint's dispatch. TEST_FLAG keeps workspace::main and the
# sourced functions non-readonly so the spec can Include bin/workspace (which
# sources lib/output.sh and the three actions) and then mock each action's main;
# helper::isolate redirects HOME so the mock log lands in the temp tree. The
# action mains are mocked to record the action and the args they were called with
# instead of doing any work, so each case asserts the action the dispatcher routed
# to, including the exit-2 usage error for an unknown action.
Describe 'bin/workspace'
    TEST_FLAG=true
    Include bin/workspace

    # ==========================================================================
    # workspace::main
    # ==========================================================================
    Describe 'workspace::main'

        create::main() { local out="create"; (($#)) && out="$out $*"; printf '%s' "$out" >>"$HOME/log"; }
        remove::main() { local out="remove"; (($#)) && out="$out $*"; printf '%s' "$out" >>"$HOME/log"; }
        show::main() { local out="show"; (($#)) && out="$out $*"; printf '%s' "$out" >>"$HOME/log"; }

        BeforeEach 'helper::isolate'

        It 'routes to the create action with no argument'
            When call workspace::main
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "create"
        End

        It 'routes to the create action on create'
            When call workspace::main create
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "create"
        End

        It 'passes the name through to the create action'
            When call workspace::main create Personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "create Personal"
        End

        It 'routes to the remove action on remove'
            When call workspace::main remove
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "remove"
        End

        It 'routes to the show action on show'
            When call workspace::main show
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/log" should equal "show"
        End

        It 'fails with exit 2 on an unknown action'
            When call workspace::main frobnicate
            The status should equal 2
            The stdout should be blank
            The stderr should include 'unknown action'
            The path "$HOME/log" should not be exist
        End

    End

End
