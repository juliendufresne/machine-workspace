# Specs for the root install.sh bootstrap. TEST_FLAG keeps the sourced functions
# non-readonly and stops the final `main "$@"` from running when the file is
# sourced; REPOSITORY_URL is still set on source. helper::isolate redirects HOME
# and the state store to fresh temp directories per example. git, command and the
# install.sh helper functions are stubbed as shell functions so nothing outside the
# temp tree is touched.
Describe 'install.sh'
    TEST_FLAG=true
    Include install.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # require_bash
    # ==========================================================================
    Describe 'require_bash'

        It 'fails when bash is not on PATH'
            command() { return 1; }

            When call require_bash
            The status should be failure
            The stdout should be blank
            The stderr should include 'bash is required'
        End

        It 'fails when bash is too old on the minor version'
            command() { :; }
            bash() { printf '4.1'; }

            When call require_bash
            The status should be failure
            The stdout should be blank
            The stderr should include 'requires bash'
        End

        It 'fails when bash is too old on the major version'
            command() { :; }
            bash() { printf '3.2'; }

            When call require_bash
            The status should be failure
            The stdout should be blank
            The stderr should include 'requires bash'
        End

        It 'fails when the bash version cannot be read'
            command() { :; }
            bash() { return 1; }

            When call require_bash
            The status should be failure
            The stdout should be blank
            The stderr should include 'requires bash'
        End

        It 'succeeds with a new enough bash'
            command() { :; }
            bash() { printf '5.2'; }

            When call require_bash
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # normalize_git_url
    # ==========================================================================
    Describe 'normalize_git_url'

        It 'normalizes the HTTPS form'
            When call normalize_git_url 'https://github.com/o/r.git'
            The status should be success
            The stdout should equal 'o/r'
            The stderr should be blank
        End

        It 'normalizes the scp-style SSH form'
            When call normalize_git_url 'git@github.com:o/r.git'
            The status should be success
            The stdout should equal 'o/r'
            The stderr should be blank
        End

        It 'strips a trailing slash'
            When call normalize_git_url 'https://github.com/o/r/'
            The status should be success
            The stdout should equal 'o/r'
            The stderr should be blank
        End

        It 'normalizes a host-alias scp form'
            When call normalize_git_url 'gh-work:o/r.git'
            The status should be success
            The stdout should equal 'o/r'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # same_repo
    # ==========================================================================
    Describe 'same_repo'

        It 'matches when origin normalizes to the installed repository'
            git() { printf 'git@github.com:juliendufresne/machine-workspace.git\n'; }

            When call same_repo "$HOME/repo"
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'does not match a different repository'
            git() { printf 'https://github.com/someone/other.git\n'; }

            When call same_repo "$HOME/repo"
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'does not match when there is no origin remote or it is not a repo'
            git() { return 1; }

            When call same_repo "$HOME/repo"
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # main
    # ==========================================================================
    Describe 'main'

        # Keep install_dir under the temp tree.
        setup_data() { export XDG_DATA_HOME="$HOME/data"; }
        BeforeEach 'setup_data'

        It 'fails when git is not on PATH'
            command() { return 1; }

            When call main
            The status should be failure
            The stdout should be blank
            The stderr should include 'git is required'
        End

        It 'fails when require_bash fails'
            command() { :; }
            require_bash() { return 1; }

            When call main
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'updates an existing checkout and runs bin/workspace'
            command() { :; }
            require_bash() { return 0; }
            git() { :; }

            mkdir -p "$HOME/data/workspace/.git" "$HOME/data/workspace/bin"
            printf '#!/bin/sh\nexit 0\n' >"$HOME/data/workspace/bin/workspace"
            chmod +x "$HOME/data/workspace/bin/workspace"

            When call main
            The status should be success
            The stdout should include 'Updating'
            The stdout should include 'Running'
            The stderr should be blank
        End

        It 'fails when git pull fails on an existing checkout'
            command() { :; }
            require_bash() { return 0; }
            git() { return 1; }

            mkdir -p "$HOME/data/workspace/.git"

            When call main
            The status should be failure
            The stdout should include 'Updating'
            The stderr should include 'git pull --ff-only failed'
        End

        It 'refuses an install dir holding a different repository'
            command() { :; }
            require_bash() { return 0; }
            same_repo() { return 1; }

            mkdir -p "$HOME/data/workspace"

            When call main
            The status should be failure
            The stdout should be blank
            The stderr should include 'Refusing to overwrite'
        End

        It 'clones into a missing install dir and runs bin/workspace'
            command() { :; }
            require_bash() { return 0; }
            # git clone <url> <dest>: $3 is the destination directory.
            git() {
                mkdir -p "$3/bin"
                printf '#!/bin/sh\nexit 0\n' >"$3/bin/workspace"
                chmod +x "$3/bin/workspace"
            }

            When call main
            The status should be success
            The stdout should include 'Cloning'
            The stdout should include 'Running'
            The stderr should be blank
        End

        It 'fails when git clone fails'
            command() { :; }
            require_bash() { return 0; }
            git() { return 1; }

            When call main
            The status should be failure
            The stdout should include 'Cloning'
            The stderr should include 'git clone failed'
        End

    End

End
