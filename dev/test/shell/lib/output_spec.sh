# Specs for the shared terminal output helpers. TEST_FLAG keeps the functions
# non-readonly so the spec can source the fragment and override collaborators;
# helper::isolate redirects HOME so the spinner's scratch files stay in temp.
# Under shellspec stdout and stderr are pipes, not terminals, so
# output::color_enabled is false by default and the plain (non-colour) branches
# run; the colour branches are exercised by overriding output::color_enabled to
# return 0 inside the relevant examples.
Describe 'lib/output.sh'
    TEST_FLAG=true
    Include lib/output.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # output::color_enabled
    # ==========================================================================
    Describe 'output::color_enabled'

        It 'reports no colour when the descriptor is not a terminal'
            When call output::color_enabled 1
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::stage
    # ==========================================================================
    Describe 'output::stage'

        It 'prints a plain stage header when colour is off'
            When call output::stage 'Installing git'
            The status should be success
            The stdout should include '▶ Installing git'
            The stderr should be blank
        End

        It 'prints a coloured stage header when colour is on'
            output::color_enabled() { return 0; }

            When call output::stage 'Installing git'
            The status should be success
            The stdout should include 'Installing git'
            The stdout should include '[1;35m'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::log
    # ==========================================================================
    Describe 'output::log'

        It 'prints a plain phase heading to stderr when colour is off'
            When call output::log 'Installing the selected units...'
            The status should be success
            The stdout should be blank
            The stderr should include '» Installing the selected units...'
        End

        It 'prints a coloured phase heading to stderr when colour is on'
            output::color_enabled() { return 0; }

            When call output::log 'Installing the selected units...'
            The status should be success
            The stdout should be blank
            The stderr should include 'Installing the selected units...'
            The stderr should include '[1m'
        End

    End

    # ==========================================================================
    # output::group
    # ==========================================================================
    Describe 'output::group'

        It 'prints a plain indented sub-header when colour is off'
            When call output::group 'ssh'
            The status should be success
            The stdout should include '» ssh'
            The stderr should be blank
        End

        It 'prints a coloured indented sub-header when colour is on'
            output::color_enabled() { return 0; }

            When call output::group 'ssh'
            The status should be success
            The stdout should include 'ssh'
            The stdout should include '[1m'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::success
    # ==========================================================================
    Describe 'output::success'

        It 'prints a plain success line at the default level'
            When call output::success 'Installing the git package'
            The status should be success
            The stdout should include '✓ Installing the git package'
            The stderr should be blank
        End

        It 'prints a success line at level 2 with deeper indent'
            When call output::success 'done' 2
            The status should be success
            The stdout should include '✓ done'
            The stderr should be blank
        End

        It 'prints a coloured success line when colour is on'
            output::color_enabled() { return 0; }

            When call output::success 'Installing the git package'
            The status should be success
            The stdout should include 'Installing the git package'
            The stdout should include '[0;32m'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::info
    # ==========================================================================
    Describe 'output::info'

        It 'prints a plain info line at the default level'
            When call output::info 'already installed'
            The status should be success
            The stdout should include '• already installed'
            The stderr should be blank
        End

        It 'prints an info line at level 2 with deeper indent'
            When call output::info 'nothing to do' 2
            The status should be success
            The stdout should include '• nothing to do'
            The stderr should be blank
        End

        It 'prints a coloured info line when colour is on'
            output::color_enabled() { return 0; }

            When call output::info 'already installed'
            The status should be success
            The stdout should include 'already installed'
            The stdout should include '[2m'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::warn
    # ==========================================================================
    Describe 'output::warn'

        It 'prints a plain warning line to stderr when colour is off'
            When call output::warn 'git is still present'
            The status should be success
            The stdout should be blank
            The stderr should include '! git is still present'
        End

        It 'prints a coloured warning line to stderr when colour is on'
            output::color_enabled() { return 0; }

            When call output::warn 'git is still present'
            The status should be success
            The stdout should be blank
            The stderr should include 'git is still present'
            The stderr should include '[0;33m'
        End

    End

    # ==========================================================================
    # output::error
    # ==========================================================================
    Describe 'output::error'

        It 'prints a plain error line to stderr when colour is off'
            When call output::error 'Installing the git package'
            The status should be success
            The stdout should be blank
            The stderr should include '✗ Installing the git package'
        End

        It 'prints a coloured error line to stderr when colour is on'
            output::color_enabled() { return 0; }

            When call output::error 'Installing the git package'
            The status should be success
            The stdout should be blank
            The stderr should include 'Installing the git package'
            The stderr should include '[0;31m'
        End

    End

    # ==========================================================================
    # output::fatal
    # ==========================================================================
    Describe 'output::fatal'

        It 'prints a plain program-level error to stderr when colour is off'
            When call output::fatal 'requirements not met'
            The status should be success
            The stdout should be blank
            The stderr should equal 'error: requirements not met'
        End

        It 'prints a coloured program-level error to stderr when colour is on'
            output::color_enabled() { return 0; }

            When call output::fatal 'requirements not met'
            The status should be success
            The stdout should be blank
            The stderr should include 'error: requirements not met'
            The stderr should include '[0;31m'
        End

    End

    # ==========================================================================
    # output::_spinner
    # ==========================================================================
    Describe 'output::_spinner'

        # The loop never returns on its own. Rather than background it (which
        # escapes the coverage tracker), stub sleep to break out after the first
        # tick so the loop body runs once in-process and exits cleanly.
        It 'writes a spinner frame with the message on each tick'
            output::color_enabled() { return 0; }
            sleep() { exit 0; }

            When run output::_spinner 'msg'
            The status should be success
            The stdout should include 'msg'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # output::_start
    # ==========================================================================
    Describe 'output::_start'

        It 'does nothing off a terminal'
            When call output::_start 'msg'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'prints the first frame and records the spinner pid on a terminal'
            output::color_enabled() { return 0; }
            output::_spinner() { sleep 5; }

            When call output::_start 'msg'
            The status should be success
            The stdout should include 'msg'
            The stderr should be blank
            The variable _OUTPUT_SPINNER_PID should not equal 0
            # Reap the backgrounded stub so no spinner lingers.
            kill "$_OUTPUT_SPINNER_PID" 2>/dev/null || true
            wait "$_OUTPUT_SPINNER_PID" 2>/dev/null || true
        End

    End

    # ==========================================================================
    # output::_stop
    # ==========================================================================
    Describe 'output::_stop'

        It 'does nothing off a terminal'
            When call output::_stop 'msg'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'kills the running spinner and resets the pid on a terminal'
            output::color_enabled() { return 0; }
            sleep 5 &
            _OUTPUT_SPINNER_PID=$!

            When call output::_stop 'msg'
            The status should be success
            The stdout should not be blank
            The stderr should be blank
            The variable _OUTPUT_SPINNER_PID should equal 0
        End

        It 'erases the line without killing when no spinner is running'
            output::color_enabled() { return 0; }
            _OUTPUT_SPINNER_PID=0

            When call output::_stop 'msg'
            The status should be success
            The stdout should not be blank
            The stderr should be blank
            The variable _OUTPUT_SPINNER_PID should equal 0
        End

    End

    # ==========================================================================
    # output::run
    # ==========================================================================
    Describe 'output::run'

        # Stub the spinner endpoints so no background process is started.
        output::_start() { :; }
        output::_stop() { :; }

        It 'prints a success line and returns 0 when the command succeeds'
            When call output::run 'Installing git' true
            The status should be success
            The stdout should include '✓ Installing git'
            The stderr should be blank
        End

        It 'prints an error line plus the captured output and returns the command status on failure'
            When call output::run 'Installing git' sh -c 'echo boom; exit 3'
            The status should equal 3
            The stdout should be blank
            The stderr should include '✗ Installing git'
            The stderr should include 'boom'
        End

        It 'prints an error line with no trace when the failing command is silent'
            When call output::run 'Installing git' sh -c 'exit 4'
            The status should equal 4
            The stdout should be blank
            The stderr should include '✗ Installing git'
        End

    End

End
