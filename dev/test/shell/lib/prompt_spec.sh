# Specs for the interactive prompts. TEST_FLAG keeps the functions non-readonly so
# the spec can Include the file and exercise them. The free-text and select loops
# are driven through PROMPT_INPUT/PROMPT_OUTPUT pointed at temp files, so no terminal
# is needed and stdout carries only the resolved value. prompt::read_key is driven
# by writing raw bytes to a temp file and opening a numbered descriptor on it
# (inherited by the `When call` subshell); helper::isolate redirects HOME for those.
Describe 'lib/prompt.sh'
    TEST_FLAG=true
    Include lib/prompt.sh

    # ==========================================================================
    # prompt::ask
    # ==========================================================================
    Describe 'prompt::ask'

        wrapper::prompt::ask() {
            local -i exit_status
            local keys
            local tmp_in
            local tmp_out

            keys="$1"
            shift

            tmp_in="$(mktemp -t shellspec-prompt-in-XXXXXXXXXX)"
            tmp_out="$(mktemp -t shellspec-prompt-out-XXXXXXXXXX)"
            printf '%b' "$keys" >"$tmp_in"

            PROMPT_INPUT="$tmp_in" PROMPT_OUTPUT="$tmp_out" prompt::ask "$@"
            exit_status=$?

            rm -f "$tmp_in" "$tmp_out"

            return "$exit_status"
        }

        It 'returns the default on a blank entry'
            When call wrapper::prompt::ask '\n' 'workspace name' Personal
            The status should be success
            The stdout should equal 'Personal'
            The stderr should be blank
        End

        It 'returns the typed value'
            When call wrapper::prompt::ask 'Acme\n' 'workspace name' Personal
            The status should be success
            The stdout should equal 'Acme'
            The stderr should be blank
        End

        It 'cancels with status 2 on a lone Escape'
            When call wrapper::prompt::ask '\033' 'workspace name' Personal
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
        End

        It 'emits the default when no terminal is available'
            PROMPT_INPUT='/nonexistent'
            PROMPT_OUTPUT='/dev/null'
            When call prompt::ask 'workspace name' Personal
            The status should be success
            The stdout should equal 'Personal'
            The stderr should be blank
        End

        It 'prints the PROMPT_HELP help line above the prompt'
            PROMPT_INPUT="$SHELLSPEC_TMPBASE/prompt-ask-help-in"
            PROMPT_OUTPUT="$SHELLSPEC_TMPBASE/prompt-ask-help-out"
            printf '\n' >"$PROMPT_INPUT"
            : >"$PROMPT_OUTPUT"

            PROMPT_HELP='Names this workspace.'
            When call prompt::ask 'workspace name' Personal
            The status should be success
            The stdout should equal 'Personal'
            The stderr should be blank
            The contents of file "$PROMPT_OUTPUT" should include 'Names this workspace.'
        End

    End

    # ==========================================================================
    # prompt::ask_secret
    # ==========================================================================
    Describe 'prompt::ask_secret'

        wrapper::prompt::ask_secret() {
            local -i exit_status
            local keys
            local tmp_in
            local tmp_out

            keys="$1"
            shift

            tmp_in="$(mktemp -t shellspec-secret-in-XXXXXXXXXX)"
            tmp_out="$(mktemp -t shellspec-secret-out-XXXXXXXXXX)"
            printf '%b' "$keys" >"$tmp_in"

            PROMPT_INPUT="$tmp_in" PROMPT_OUTPUT="$tmp_out" prompt::ask_secret "$@"
            exit_status=$?

            rm -f "$tmp_in" "$tmp_out"

            return "$exit_status"
        }

        It 'reads and returns the secret'
            When call wrapper::prompt::ask_secret 'hunter2\n' 'GPG key passphrase'
            The status should be success
            The stdout should equal 'hunter2'
            The stderr should be blank
        End

        It 'returns the empty secret on a blank entry'
            When call wrapper::prompt::ask_secret '\n' 'GPG key passphrase'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'emits the empty secret when no terminal is available'
            PROMPT_INPUT='/nonexistent'
            PROMPT_OUTPUT='/dev/null'
            When call prompt::ask_secret 'GPG key passphrase'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'prints the PROMPT_HELP help line above the prompt'
            PROMPT_INPUT="$SHELLSPEC_TMPBASE/prompt-secret-help-in"
            PROMPT_OUTPUT="$SHELLSPEC_TMPBASE/prompt-secret-help-out"
            printf 'hunter2\n' >"$PROMPT_INPUT"
            : >"$PROMPT_OUTPUT"

            PROMPT_HELP='Protects the private key at rest.'
            When call prompt::ask_secret 'GPG key passphrase'
            The status should be success
            The stdout should equal 'hunter2'
            The stderr should be blank
            The contents of file "$PROMPT_OUTPUT" should include 'Protects the private key at rest.'
        End

    End

    # ==========================================================================
    # prompt::read_key
    # ==========================================================================
    # Driven by writing raw bytes to a temp file and opening a numbered descriptor
    # on it (inherited by the `When call` subshell); helper::isolate redirects HOME.
    Describe 'prompt::read_key'
        BeforeEach 'helper::isolate'

        # Open a numbered descriptor on a bytes file, call read_key, close it. The
        # descriptor is opened in the example body before `When call`; the call's
        # subshell inherits it.

        It 'maps a newline (Enter) to confirm'
            printf '\n' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'confirm'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps space to toggle'
            printf ' ' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'toggle'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps lowercase j to down'
            printf 'j' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'down'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps uppercase J to down'
            printf 'J' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'down'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps lowercase k to up'
            printf 'k' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'up'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps uppercase K to up'
            printf 'K' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'up'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps lowercase q to cancel'
            printf 'q' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'cancel'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps uppercase Q to cancel'
            printf 'Q' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'cancel'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps the up-arrow escape sequence to up'
            printf '\033[A' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'up'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps the down-arrow escape sequence to down'
            printf '\033[B' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'down'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps an unknown escape sequence to cancel'
            printf '\033[C' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'cancel'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'maps a lone Escape (no trailing bytes) to cancel'
            printf '\033' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should equal 'cancel'
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'prints nothing for an unrecognised key'
            printf 'z' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be success
            The stdout should be blank
            The stderr should be blank
            exec {kfd}<&-
        End

        It 'fails at end of input'
            printf '' >"$HOME/keys"
            exec {kfd}<"$HOME/keys"
            When call prompt::read_key "$kfd"
            The status should be failure
            The stdout should be blank
            The stderr should be blank
            exec {kfd}<&-
        End

    End

    # ==========================================================================
    # prompt::select_one
    # ==========================================================================
    Describe 'prompt::select_one'

        wrapper::prompt::select_one() {
            local -i exit_status
            local keys
            local tmp_in
            local tmp_out

            keys="$1"
            shift

            tmp_in="$(mktemp -t shellspec-select-one-in-XXXXXXXXXX)"
            tmp_out="$(mktemp -t shellspec-select-one-out-XXXXXXXXXX)"
            printf '%b' "$keys" >"$tmp_in"

            PROMPT_INPUT="$tmp_in" PROMPT_OUTPUT="$tmp_out" prompt::select_one 'Choose' "$@"
            exit_status=$?

            rm -f "$tmp_in" "$tmp_out"

            return "$exit_status"
        }

        It 'selects the highlighted option on Enter'
            When call wrapper::prompt::select_one '\n' "$(printf 'ed25519\ted25519 (recommended)')" "$(printf 'rsa\trsa')"
            The status should be success
            The stdout should equal 'ed25519'
            The stderr should be blank
        End

        It 'navigates down and selects the next option'
            When call wrapper::prompt::select_one '\033[B\n' "$(printf 'ed25519\ted25519 (recommended)')" "$(printf 'rsa\trsa')"
            The status should be success
            The stdout should equal 'rsa'
            The stderr should be blank
        End

        It 'cancels with status 2 on q'
            When call wrapper::prompt::select_one 'q' "$(printf 'ed25519\ted25519 (recommended)')" "$(printf 'rsa\trsa')"
            The status should equal 2
            The stdout should be blank
            The stderr should be blank
        End

        It 'emits the first option when no terminal is available'
            PROMPT_INPUT='/nonexistent'
            PROMPT_OUTPUT='/dev/null'
            When call prompt::select_one 'Key type' "$(printf 'ed25519\ted25519')" "$(printf 'rsa\trsa')"
            The status should be success
            The stdout should equal 'ed25519'
            The stderr should be blank
        End

        It 'prints the PROMPT_HELP help line above the list'
            PROMPT_INPUT="$SHELLSPEC_TMPBASE/prompt-select-one-help-in"
            PROMPT_OUTPUT="$SHELLSPEC_TMPBASE/prompt-select-one-help-out"
            printf '\n' >"$PROMPT_INPUT"
            : >"$PROMPT_OUTPUT"

            PROMPT_HELP='Pick the signing algorithm.'
            When call prompt::select_one 'Choose' "$(printf 'ed25519\ted25519 (recommended)')" "$(printf 'rsa\trsa')"
            The status should be success
            The stdout should equal 'ed25519'
            The stderr should be blank
            The contents of file "$PROMPT_OUTPUT" should include 'Pick the signing algorithm.'
        End

    End

    # ==========================================================================
    # prompt::select_multi
    # ==========================================================================
    # Driven by pointing PROMPT_INPUT at a regular file holding a keystroke sequence
    # and PROMPT_OUTPUT at a writable temp file, so the redraw loop runs without a
    # real tty; assertions are on stdout (the selected names), never the escape-laden
    # drawing. helper::isolate redirects HOME.
    Describe 'prompt::select_multi'
        BeforeEach 'helper::isolate'

        # The non-interactive emit path: it prints names whose state is 1, one per
        # line, skipping the redraw loop.

        It 'emits nothing when given no entries'
            export PROMPT_INPUT="$HOME/in"
            export PROMPT_OUTPUT="$HOME/out"
            : >"$PROMPT_INPUT"
            When call prompt::select_multi 'Choose'
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'emits the pre-selected names when the input cannot be opened'
            export PROMPT_INPUT=/nonexistent/path/in
            export PROMPT_OUTPUT="$HOME/out"
            When call prompt::select_multi 'Choose' \
                "$(printf '1\tgit\tVersion control')" \
                "$(printf '0\tdiscord\tChat')" \
                "$(printf '1\tssh\tRemote access')"
            The status should be success
            The line 1 of stdout should equal 'git'
            The line 2 of stdout should equal 'ssh'
            The stderr should be blank
        End

        It 'emits the pre-selected names when the output cannot be opened'
            export PROMPT_INPUT="$HOME/in"
            export PROMPT_OUTPUT=/nonexistent/path/out
            : >"$PROMPT_INPUT"
            When call prompt::select_multi 'Choose' \
                "$(printf '0\tgit\tVersion control')" \
                "$(printf '1\tssh\tRemote access')"
            The status should be success
            The stdout should equal 'ssh'
            The stderr should be blank
        End

        # The interactive redraw loop: PROMPT_INPUT is a regular file (passes the
        # `: <input` probe) holding a keystroke sequence, PROMPT_OUTPUT a writable
        # temp file (passes `: >>output`). prompt::read_key reads each byte from the
        # descriptor the loop opens.

        It 'runs the redraw loop, toggling under the cursor and confirming'
            export PROMPT_INPUT="$HOME/in"
            export PROMPT_OUTPUT="$HOME/out"
            # down (wraps onto next), toggle git off? cursor starts at 0 (git).
            # Sequence: toggle git -> down -> toggle discord -> up -> down -> down
            # wraps -> unrecognised 'z' (redraw) -> Enter confirm.
            # 'j'=down, 'k'=up, ' '=toggle, 'z'=ignored, '\n'=confirm.
            printf ' jk j z\n' >"$PROMPT_INPUT"
            When call prompt::select_multi 'Choose' \
                "$(printf '0\tgit\tVersion control')" \
                "$(printf '0\tssh\tRemote access')"
            The status should be success
            # Start cursor=0 (git). keys in order:
            #   ' ' toggle git -> git on
            #   'j' down -> cursor=1 (ssh)
            #   'k' up   -> cursor=0 (git)
            #   ' ' toggle git -> git off
            #   'j' down -> cursor=1 (ssh)
            #   ' ' toggle ssh -> ssh on
            #   'z' unrecognised -> redraw, no change
            #   '\n' confirm
            # Final selected: ssh.
            The stdout should equal 'ssh'
            The stderr should be blank
        End

        It 'wraps the cursor up from the top and down from the bottom'
            export PROMPT_INPUT="$HOME/in"
            export PROMPT_OUTPUT="$HOME/out"
            # bytes: 'k' ' ' 'j' 'k' ' ' 'j' ' ' '\n'
            printf 'k jk j \n' >"$PROMPT_INPUT"
            When call prompt::select_multi 'Choose' \
                "$(printf '0\tgit\tVersion control')" \
                "$(printf '0\tssh\tRemote access')"
            The status should be success
            # cursor=0
            #   'k' up   -> wraps to 1 (ssh)
            #   ' ' toggle ssh -> ssh on
            #   'j' down -> wraps to 0 (git)
            #   'k' up   -> wraps to 1 (ssh)
            #   ' ' toggle ssh -> ssh off
            #   'j' down -> wraps to 0 (git)
            #   ' ' toggle git -> git on
            #   '\n' confirm
            # Final selected: git.
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'breaks on cancel, emitting the entries unchanged'
            export PROMPT_INPUT="$HOME/in"
            export PROMPT_OUTPUT="$HOME/out"
            # toggle git on, then 'q' cancel -> break before any confirm.
            printf ' q' >"$PROMPT_INPUT"
            When call prompt::select_multi 'Choose' \
                "$(printf '0\tgit\tVersion control')" \
                "$(printf '1\tssh\tRemote access')"
            The status should be success
            # cursor=0; ' ' toggles git on; 'q' cancels (break). On break the
            # current states are emitted: git on, ssh stays on.
            The line 1 of stdout should equal 'git'
            The line 2 of stdout should equal 'ssh'
            The stderr should be blank
        End

        It 'confirms at end of input (read_key failure treated as confirm)'
            export PROMPT_INPUT="$HOME/in"
            export PROMPT_OUTPUT="$HOME/out"
            # toggle git on, then EOF -> read_key returns 1 -> key='confirm'.
            printf ' ' >"$PROMPT_INPUT"
            When call prompt::select_multi 'Choose' \
                "$(printf '0\tgit\tVersion control')"
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
        End

        It 'prints the header to the output'
            export PROMPT_INPUT="$HOME/in"
            export PROMPT_OUTPUT="$HOME/out"
            printf '\n' >"$PROMPT_INPUT"
            When call prompt::select_multi 'Choose your tools:' "$(printf '1\tgit\tVersion control')"
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
            The contents of file "$PROMPT_OUTPUT" should include 'Choose your tools:'
        End

        It 'prints the PROMPT_HELP line to the output'
            export PROMPT_INPUT="$HOME/in"
            export PROMPT_OUTPUT="$HOME/out"
            export PROMPT_HELP='Toggling on installs the unit.'
            printf '\n' >"$PROMPT_INPUT"
            When call prompt::select_multi 'Choose' "$(printf '1\tgit\tVersion control')"
            The status should be success
            The stdout should equal 'git'
            The stderr should be blank
            The contents of file "$PROMPT_OUTPUT" should include 'Toggling on installs the unit.'
        End

    End

End
