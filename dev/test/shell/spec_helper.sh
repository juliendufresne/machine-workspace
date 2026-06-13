# shellspec spec helper, loaded via `--require spec_helper` (see .shellspec).
# Provides an isolated environment so specs never touch the real host: a private
# state store and HOME under the shellspec temp base, and the test flag that makes
# a script sourceable without executing its entrypoint.

# Point the state store and HOME at fresh per-example temp directories. TEST_FLAG
# keeps the sourced functions non-readonly so specs can mock them.
helper::isolate() {
    export TEST_FLAG=true
    export XDG_STATE_HOME="$SHELLSPEC_TMPBASE/state"
    export HOME="$SHELLSPEC_TMPBASE/home"
    rm -rf "$XDG_STATE_HOME" "$HOME"
    mkdir -p "$XDG_STATE_HOME" "$HOME"
}

# Seed a saved registry value, as if it had been collected on an earlier run.
# There is no inputs overlay in this tool, so every value lands directly in the
# committed inputs/ directory the store reads.
helper::seed_input() {
    local name="$1" value="$2" dir="$XDG_STATE_HOME/workspace/inputs"
    mkdir -p "$dir"
    printf '%s' "$value" >"$dir/$name"
}
