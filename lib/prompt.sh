#!/usr/bin/env bash
set -euo pipefail
# Interactive prompts: the free-text, single-select, and multi-select inputs the
# tool asks on a terminal. prompt::ask reads a line with a default; prompt::ask_secret
# reads one silently (a passphrase); prompt::read_key maps one keystroke to a logical
# navigation token; prompt::select_one drives a single-select list; prompt::select_multi
# drives a checkbox checklist. All read keystrokes from PROMPT_INPUT and draw to
# PROMPT_OUTPUT (each defaulting to /dev/tty and overridable to make the loops
# testable). The cancel convention is a reserved exit status 2 (Esc, or q on a
# select), so a caller distinguishes a user abort from an empty answer:
# v="$(prompt::ask ...)" || { (($?==2)) && ...; }. With no terminal each falls back
# to a non-interactive default, so an unattended run never blocks. Sourced by the
# workspace unit's definition flow.

! declare -F prompt::ask &>/dev/null || return 0

# ─── Functions ────────────────────────────────────────────────────────────────

#--------------------------------------------------
# Function:
#   prompt::ask <prompt> [<default>]
#
# Description:
#   Reads one line of free text and prints it to stdout, showing "<prompt>
#   [<default>]: " (or "<prompt>: " with no default) on PROMPT_OUTPUT. A blank
#   entry - Enter pressed straight away, or end of input - resolves to <default>.
#   A lone Escape cancels (exit status 2), so the caller can abort the current
#   step. The first keystroke is read silently to detect that Escape, then echoed
#   and the rest of the line read normally, so what the user types still appears.
#   With no terminal (PROMPT_INPUT or PROMPT_OUTPUT cannot be opened, as in an
#   unattended run) it emits the default without prompting. When PROMPT_HELP is set
#   its help line is printed above the prompt (a no-op otherwise). Draws the prompt
#   to PROMPT_OUTPUT and reads keystrokes from PROMPT_INPUT; stdout carries only the
#   resolved value.
#
# Arguments:
#   <prompt>     The label shown before the input
#   <default>    The value used on a blank entry (optional, defaults to empty)
#
# Returns:
#   0 when a value was resolved (printed to stdout)
#   2 when the user pressed Escape to cancel
#
# Example:
#   name="$(prompt::ask 'workspace name' Personal)" || { (($? == 2)) && return 2; }
#--------------------------------------------------
prompt::ask() {
    local default
    local -i fd
    local first
    local input
    local label
    local output
    local rest
    local -i status
    local value

    label="${1:?prompt required}"
    default="${2:-}"
    input="${PROMPT_INPUT:-/dev/tty}"
    output="${PROMPT_OUTPUT:-/dev/tty}"

    # No terminal: resolve to the default unattended. Probe by opening each
    # descriptor (a /dev/tty node can pass -r/-w yet fail to open with no
    # controlling terminal), discarding the open error.
    if ! { : <"$input"; } 2>/dev/null || ! { : >>"$output"; } 2>/dev/null
    then
        printf '%s' "$default"

        return 0
    fi

    # Print this input's help line above the prompt when one was passed
    # (PROMPT_HELP), then prompt as usual. A no-op when no help was set.
    [[ -z "${PROMPT_HELP:-}" ]] || printf '%s\n\n' "$PROMPT_HELP" >>"$output"

    if [[ -n "$default" ]]
    then
        printf '%s [%s]: ' "$label" "$default" >>"$output"
    else
        printf '%s: ' "$label" >>"$output"
    fi

    exec {fd}<"$input"

    status=0
    rest=''
    if ! IFS= read -rsn1 -u "$fd" first
    then
        value="$default"                          # end of input: a blank entry
    else
        case "$first" in
            '')
                value="$default"                  # Enter straight away
                ;;
            $'\e')
                read -rsn2 -t 1 -u "$fd" rest || true   # drain a lone Escape's tail
                status=2                                # cancel
                ;;
            *)
                printf '%s' "$first" >>"$output"        # echo the silently-read char
                IFS= read -r -u "$fd" rest || true     # then the rest of the line
                value="$first$rest"
                [[ -n "$value" ]] || value="$default"
                ;;
        esac
    fi

    exec {fd}<&-
    printf '\n' >>"$output"                         # close the prompt line

    ((status == 0)) || return "$status"

    printf '%s' "$value"
}
[[ -v TEST_FLAG ]] || readonly -f prompt::ask

#--------------------------------------------------
# Function:
#   prompt::ask_secret <prompt>
#
# Description:
#   Reads one secret (a passphrase) silently and prints it to stdout, the hidden
#   counterpart to prompt::ask. The value is never echoed: the label is drawn to
#   PROMPT_OUTPUT, the line is read without echo from PROMPT_INPUT, and a closing
#   newline is written to PROMPT_OUTPUT, so stdout carries only the secret. With no
#   terminal (PROMPT_INPUT or PROMPT_OUTPUT cannot be opened, as in an unattended
#   run) it resolves to the empty secret without prompting, so a run never blocks.
#   When PROMPT_HELP is set its help line is printed above the prompt (a no-op
#   otherwise). The caller is expected to keep the value in a local and never persist
#   it. Unlike prompt::ask there is no default and no cancel: a blank entry is a
#   valid empty secret.
#
# Arguments:
#   <prompt>  The label shown before the silent input
#
# Returns:
#   0 on success (the secret, possibly empty, is printed to stdout)
#
# Example:
#   passphrase="$(prompt::ask_secret 'GPG key passphrase for Personal')"
#--------------------------------------------------
prompt::ask_secret() {
    local -i fd
    local input
    local label
    local output
    local value

    label="${1:?prompt required}"
    input="${PROMPT_INPUT:-/dev/tty}"
    output="${PROMPT_OUTPUT:-/dev/tty}"

    # No terminal: resolve to the empty secret unattended (same open probe as
    # prompt::ask), so a run never blocks.
    if ! { : <"$input"; } 2>/dev/null || ! { : >>"$output"; } 2>/dev/null
    then
        printf ''

        return 0
    fi

    # Print this input's help line above the prompt when one was passed
    # (PROMPT_HELP), then prompt as usual. A no-op when no help was set.
    [[ -z "${PROMPT_HELP:-}" ]] || printf '%s\n\n' "$PROMPT_HELP" >>"$output"

    printf '%s: ' "$label" >>"$output"

    exec {fd}<"$input"
    IFS= read -rs -u "$fd" value || true          # read the line without echoing it
    exec {fd}<&-

    printf '\n' >>"$output"                       # close the silent prompt line

    printf '%s' "$value"
}
[[ -v TEST_FLAG ]] || readonly -f prompt::ask_secret

#--------------------------------------------------
# Function:
#   prompt::read_key <fd>
#
# Description:
#   Reads one keystroke from file descriptor <fd> and prints a logical key token
#   to stdout: 'up', 'down', 'toggle', 'confirm', or 'cancel'. The mapping covers
#   both arrow keys (the ESC '[A' / ESC '[B' sequences) and the vi-style 'j'/'k'
#   keys for movement, the space bar for toggling, Enter for confirming, and a
#   bare Escape or 'q' for cancelling. An unrecognised key prints nothing so the
#   caller ignores it. Reads from <fd> only (with echo suppressed); no other side
#   effects.
#
# Arguments:
#   <fd>  An open file descriptor to read the keystroke from
#
# Returns:
#   0 when a keystroke was read (its token, if any, is printed)
#   1 when <fd> is at end of input, so the caller can treat it as a confirm
#
# Example:
#   key="$(prompt::read_key "$fd")" || key='confirm'
#--------------------------------------------------
prompt::read_key() {
    local fd
    local key
    local rest

    fd="${1:?file descriptor required}"

    IFS= read -rsn1 -u "$fd" key || return 1

    case "$key" in
        '')
            printf 'confirm'
            ;;
        ' ')
            printf 'toggle'
            ;;
        j | J)
            printf 'down'
            ;;
        k | K)
            printf 'up'
            ;;
        q | Q)
            printf 'cancel'
            ;;
        $'\e')
            # An escape sequence: the two trailing bytes name the arrow key. A
            # short timeout means a lone Escape falls through as a cancel.
            read -rsn2 -t 1 -u "$fd" rest || rest=''

            case "$rest" in
                '[A')
                    printf 'up'
                    ;;
                '[B')
                    printf 'down'
                    ;;
                *)
                    printf 'cancel'
                    ;;
            esac
            ;;
        *)
            : # Unrecognised key; print nothing so the caller ignores it.
            ;;
    esac
}
[[ -v TEST_FLAG ]] || readonly -f prompt::read_key

#--------------------------------------------------
# Function:
#   prompt::select_one <prompt> <option>...
#
# Description:
#   Drives a single-select list over the given options and prints the value of the
#   one the user confirms to stdout. Each <option> is a tab-separated
#   '<value>\t<label>' pair: the label is shown, the value is printed. The arrow
#   keys (or j/k) move the highlight and Enter confirms; Esc or q cancels (exit
#   status 2). The list is drawn to PROMPT_OUTPUT and keystrokes are read from
#   PROMPT_INPUT (both default to /dev/tty, overridable for tests). With no
#   terminal it prints the first option's value without prompting, so an
#   unattended run still resolves a choice. When PROMPT_HELP is set its help line is
#   printed above the list (a no-op otherwise). Draws the list to PROMPT_OUTPUT and
#   consumes keystrokes from PROMPT_INPUT; stdout carries only the chosen value.
#
# Arguments:
#   <prompt>      The header shown above the list
#   <option>...   One or more '<value>\t<label>' pairs
#
# Returns:
#   0 when a value was chosen (printed to stdout)
#   2 when the user cancelled, or no options were given
#
# Example:
#   prompt::select_one 'Key type' "$(printf 'ed25519\ted25519 (recommended)')" "$(printf 'rsa\trsa')"
#--------------------------------------------------
prompt::select_one() {
    local -i cursor
    local -i drawn
    local -i fd
    local -i index
    local input
    local item
    local key
    local -a labels
    local marker
    local output
    local prompt
    local -a values

    prompt="${1:?prompt required}"
    shift

    input="${PROMPT_INPUT:-/dev/tty}"
    output="${PROMPT_OUTPUT:-/dev/tty}"

    values=()
    labels=()
    for item in "$@"
    do
        values+=("${item%%$'\t'*}")
        labels+=("${item#*$'\t'}")
    done

    ((${#values[@]} > 0)) || return 2             # nothing to choose

    # No terminal: resolve to the first option unattended (same open probe as
    # prompt::ask and prompt::select_multi).
    if ! { : <"$input"; } 2>/dev/null || ! { : >>"$output"; } 2>/dev/null
    then
        printf '%s' "${values[0]}"

        return 0
    fi

    # Print this input's help line above the list, once, before the redraw loop so
    # navigation does not flicker it (PROMPT_HELP). A no-op when no help was set.
    [[ -z "${PROMPT_HELP:-}" ]] || printf '%s\n\n' "$PROMPT_HELP" >>"$output"

    printf '%s\n' "$prompt" >>"$output"

    cursor=0
    drawn=0
    exec {fd}<"$input"

    while true
    do
        # Redraw in place: after the first frame, jump back up over the rows just
        # drawn, then clear and rewrite each line.
        ((! drawn)) || printf '%b' "\033[${#values[@]}A" >>"$output"
        drawn=1

        for ((index = 0; index < ${#values[@]}; index++))
        do
            marker=' '
            ((index != cursor)) || marker='>'

            printf '%b  %s %s\n' "\033[2K" "$marker" "${labels[index]}" >>"$output"
        done

        key="$(prompt::read_key "$fd")" || key='confirm'
        case "$key" in
            up)
                ((cursor > 0)) && cursor=$((cursor - 1)) || cursor=$((${#values[@]} - 1))
                ;;
            down)
                ((cursor < ${#values[@]} - 1)) && cursor=$((cursor + 1)) || cursor=0
                ;;
            confirm)
                break
                ;;
            cancel)
                exec {fd}<&-

                return 2
                ;;
            *)
                : # Toggle or an unrecognised key; redraw unchanged.
                ;;
        esac
    done

    exec {fd}<&-

    printf '%s' "${values[cursor]}"
}
[[ -v TEST_FLAG ]] || readonly -f prompt::select_one

#--------------------------------------------------
# Function:
#   prompt::select_multi <header> <entry>...
#
# Description:
#   Drives an interactive checklist over the given entries and prints the names
#   the user leaves selected, one per line, to stdout. <header> is the line shown
#   above the checklist, so a caller (such as the uninstall menu) can make clear
#   what toggling an entry on will do. Each <entry> is a tab-separated
#   '<state>\t<name>\t<description>' triple, where <state> is 1 for pre-selected
#   and 0 otherwise. The arrow keys (or j/k) move the highlight, space toggles the
#   entry under it, and Enter confirms; the checklist is drawn to PROMPT_OUTPUT and
#   keystrokes are read from PROMPT_INPUT (both default to /dev/tty, and are
#   overridable to make the loop testable). When there is nothing to choose from,
#   or no terminal is available (PROMPT_INPUT or PROMPT_OUTPUT cannot be opened, as
#   in an unattended run), it skips the interaction and emits the pre-selected
#   entries as-is, so a selection still resolves. When PROMPT_HELP is set its help
#   line is printed above the checklist (a no-op otherwise). Draws the checklist to
#   PROMPT_OUTPUT and consumes keystrokes from PROMPT_INPUT; stdout carries only the
#   result.
#
# Arguments:
#   <header>    The line shown above the checklist
#   <entry>...  Zero or more '<state>\t<name>\t<description>' triples
#
# Returns:
#   0 when a selection was produced (possibly empty)
#
# Example:
#   prompt::select_multi 'Select units to set up.' "$(printf '1\tgit\tVersion control')"
#--------------------------------------------------
prompt::select_multi() {
    local box
    local -i cursor
    local -a descs
    local -i drawn
    local -i fd
    local header
    local -i index
    local input
    local interactive
    local item
    local key
    local marker
    local -a names
    local output
    local -a states

    header="${1:?header required}"
    shift

    input="${PROMPT_INPUT:-/dev/tty}"
    output="${PROMPT_OUTPUT:-/dev/tty}"

    names=()
    descs=()
    states=()
    for item in "$@"
    do
        states+=("${item%%$'\t'*}")
        item="${item#*$'\t'}"
        names+=("${item%%$'\t'*}")
        descs+=("${item#*$'\t'}")
    done

    # Drive the checklist only when there is something to choose from and the
    # terminal can actually be opened, for reading keystrokes and drawing to;
    # otherwise fall through to the final emit, which prints the pre-selected
    # entries as-is so an unattended run still resolves a selection. A permission
    # test (-r/-w) is not enough: a /dev/tty device node can pass it yet fail to
    # open when there is no controlling terminal (an unattended run, such as the
    # install-test container), so probe by opening each descriptor and discarding
    # the open error.
    interactive=''
    if ((${#names[@]} > 0)) \
        && { : <"$input"; } 2>/dev/null \
        && { : >>"$output"; } 2>/dev/null
    then
        interactive=1
    fi

    if [[ -n "$interactive" ]]
    then
        # Print the help line once, before the list and its redraw loop, so
        # navigation does not flicker it (PROMPT_HELP). A no-op when no help was set.
        [[ -z "${PROMPT_HELP:-}" ]] || printf '%s\n\n' "$PROMPT_HELP" >>"$output"

        printf '%s\n' "$header" >>"$output"

        cursor=0
        drawn=0
        exec {fd}<"$input"

        while true
        do
            # Redraw in place: after the first frame, jump the cursor back up over
            # the rows just drawn, then clear and rewrite each line.
            ((! drawn)) || printf '%b' "\033[${#names[@]}A" >>"$output"
            drawn=1

            for ((index = 0; index < ${#names[@]}; index++))
            do
                marker=' '
                ((index != cursor)) || marker='>'
                box='[ ]'
                ((! states[index])) || box='[x]'

                printf '%b  %s %s %-12s %s\n' "\033[2K" "$marker" "$box" "${names[index]}" "${descs[index]}" >>"$output"
            done

            key="$(prompt::read_key "$fd")" || key='confirm'
            case "$key" in
                up)
                    ((cursor > 0)) && cursor=$((cursor - 1)) || cursor=$((${#names[@]} - 1))
                    ;;
                down)
                    ((cursor < ${#names[@]} - 1)) && cursor=$((cursor + 1)) || cursor=0
                    ;;
                toggle)
                    states[cursor]=$((1 - states[cursor]))
                    ;;
                confirm | cancel)
                    break
                    ;;
                *)
                    : # Unrecognised key; redraw unchanged.
                    ;;
            esac
        done

        exec {fd}<&-
    fi

    for ((index = 0; index < ${#names[@]}; index++))
    do
        ((! states[index])) || printf '%s\n' "${names[index]}"
    done
}
[[ -v TEST_FLAG ]] || readonly -f prompt::select_multi
