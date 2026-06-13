# Specs for the shared ~/.ssh/config helpers. TEST_FLAG keeps the functions
# non-readonly so the spec can source the fragment; helper::isolate redirects HOME,
# so every ~/.ssh edit stays in the per-example temp tree and the real config is
# never touched. ssh_config::is_macos is stubbed wherever a write depends on the
# platform, so the base fragments are deterministic regardless of the host.
Describe 'lib/ssh_config.sh'
    TEST_FLAG=true
    Include lib/ssh_config.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # ssh_config::host::alias
    # ==========================================================================
    Describe 'ssh_config::host::alias'

        It 'joins the host and the workspace name with a hyphen'
            When call ssh_config::host::alias github.com personal
            The status should be success
            The stdout should equal 'github.com-personal'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::filepath
    # ==========================================================================
    Describe 'ssh_config::filepath'

        It 'is the config under .ssh in HOME'
            When call ssh_config::filepath
            The status should be success
            The stdout should equal "$HOME/.ssh/config"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::subdir
    # ==========================================================================
    Describe 'ssh_config::subdir'

        It 'is the config.d directory under .ssh in HOME'
            When call ssh_config::subdir
            The status should be success
            The stdout should equal "$HOME/.ssh/config.d"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::host::filepath
    # ==========================================================================
    Describe 'ssh_config::host::filepath'

        It 'joins the config.d directory and the fragment name'
            When call ssh_config::host::filepath 20-personal-github.com
            The status should be success
            The stdout should equal "$HOME/.ssh/config.d/20-personal-github.com"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::host::filename
    # ==========================================================================
    Describe 'ssh_config::host::filename'

        It 'names the fragment by workspace then host with the 20- prefix'
            When call ssh_config::host::filename github.com personal
            The status should be success
            The stdout should equal '20-personal-github.com'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::marker::begin
    # ==========================================================================
    Describe 'ssh_config::marker::begin'

        It 'embeds the tag in the begin marker'
            When call ssh_config::marker::begin include
            The status should be success
            The stdout should equal '# >>> workspace identity include >>>'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::marker::end
    # ==========================================================================
    Describe 'ssh_config::marker::end'

        It 'embeds the tag in the end marker'
            When call ssh_config::marker::end include
            The status should be success
            The stdout should equal '# <<< workspace identity include <<<'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::is_macos
    # ==========================================================================
    Describe 'ssh_config::is_macos'

        It 'is true when uname reports Darwin'
            uname() { printf 'Darwin\n'; }

            When call ssh_config::is_macos
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when uname reports another kernel'
            uname() { printf 'Linux\n'; }

            When call ssh_config::is_macos
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::host::display
    # ==========================================================================
    Describe 'ssh_config::host::display'

        It 'renders the host stanza with the user, agent, key and identities-only'
            When call ssh_config::host::display github.com-personal github.com git /key/path
            The status should be success
            The line 1 of stdout should equal 'Host github.com-personal'
            The line 2 of stdout should equal '    HostName github.com'
            The line 3 of stdout should equal '    User git'
            The line 4 of stdout should equal '    AddKeysToAgent yes'
            The line 5 of stdout should equal '    IdentityFile /key/path'
            The line 6 of stdout should equal '    IdentitiesOnly yes'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::create_base_files
    # ==========================================================================
    Describe 'ssh_config::create_base_files'

        It 'writes the global base fragment and skips the macos one off macOS'
            ssh_config::is_macos() { return 1; }

            When call ssh_config::create_base_files
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/.ssh/config.d/00-base" should include 'IdentitiesOnly yes'
            The path "$HOME/.ssh/config.d/10-macos" should not be exist
        End

        It 'writes the macos keychain fragment on macOS'
            ssh_config::is_macos() { return 0; }

            When call ssh_config::create_base_files
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/.ssh/config.d/10-macos" should include 'UseKeychain yes'
        End

    End

    # ==========================================================================
    # ssh_config::include_dir::ensure_present
    # ==========================================================================
    Describe 'ssh_config::include_dir::ensure_present'

        ssh_config::is_macos() { return 1; }

        It 'prepends the include line and writes the base fragment'
            mkdir -p "$HOME/.ssh"
            printf 'Host other\n' >"$HOME/.ssh/config"

            When call ssh_config::include_dir::ensure_present
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The line 1 of contents of file "$HOME/.ssh/config" should equal '# >>> workspace identity include >>>'
            The contents of file "$HOME/.ssh/config" should include 'Include config.d/*'
            The contents of file "$HOME/.ssh/config" should include 'Host other'
            The contents of file "$HOME/.ssh/config.d/00-base" should include 'IdentitiesOnly yes'
        End

        It 'does not duplicate the include line on a second call'
            ssh_config::include_dir::ensure_present
            ssh_config::include_dir::ensure_present

            When call grep -c 'Include config.d/' "$HOME/.ssh/config"
            The status should be success
            The stdout should equal '1'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::host::exist
    # ==========================================================================
    Describe 'ssh_config::host::exist'

        It 'is true when the identity fragment exists'
            mkdir -p "$HOME/.ssh/config.d"
            : >"$HOME/.ssh/config.d/20-personal-github.com"

            When call ssh_config::host::exist 20-personal-github.com
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the identity fragment is absent'
            When call ssh_config::host::exist 20-personal-github.com
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::host::add
    # ==========================================================================
    Describe 'ssh_config::host::add'

        ssh_config::is_macos() { return 1; }

        It 'writes the identity fragment and ensures the include line'
            mkdir -p "$HOME/.ssh"
            printf 'Host other\n    HostName example.com\n' >"$HOME/.ssh/config"

            When call ssh_config::host::add 20-personal-github.com github.com-personal github.com git /key/path
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/.ssh/config.d/20-personal-github.com" should include 'Host github.com-personal'
            The contents of file "$HOME/.ssh/config.d/20-personal-github.com" should include 'User git'
            The contents of file "$HOME/.ssh/config.d/20-personal-github.com" should include 'IdentityFile /key/path'
            The contents of file "$HOME/.ssh/config" should include 'Include config.d/*'
            The contents of file "$HOME/.ssh/config" should include 'Host other'
        End

        It 'restricts the identity fragment to the owner'
            ssh_config::host::add 20-personal-github.com github.com-personal github.com git /key/path

            When call stat -c '%a' "$HOME/.ssh/config.d/20-personal-github.com"
            The status should be success
            The stdout should equal '600'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::host::do_remove
    # ==========================================================================
    Describe 'ssh_config::host::do_remove'

        It 'removes the identity fragment'
            mkdir -p "$HOME/.ssh/config.d"
            : >"$HOME/.ssh/config.d/20-personal-github.com"

            When call ssh_config::host::do_remove 20-personal-github.com
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/.ssh/config.d/20-personal-github.com" should not be exist
        End

        It 'does nothing when the fragment is absent'
            When call ssh_config::host::do_remove 20-personal-github.com
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # ssh_config::host::remove
    # ==========================================================================
    Describe 'ssh_config::host::remove'

        output::run() { shift; "$@"; }

        It 'removes the present host config block'
            mkdir -p "$HOME/.ssh/config.d"
            : >"$HOME/.ssh/config.d/20-personal-github.com"

            When call ssh_config::host::remove github.com personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The path "$HOME/.ssh/config.d/20-personal-github.com" should not be exist
        End

        It 'leaves an absent block alone'
            When call ssh_config::host::remove github.com personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

End
