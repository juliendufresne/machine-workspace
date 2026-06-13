# Specs for the shared ~/.gitconfig IncludeIf helpers. TEST_FLAG keeps the
# functions non-readonly so the spec can source the fragment; helper::isolate
# redirects HOME, so every ~/.gitconfig edit stays in the per-example temp tree and
# the real config is never touched.
Describe 'lib/gitconfig.sh'
    TEST_FLAG=true
    Include lib/gitconfig.sh

    BeforeEach 'helper::isolate'

    # ==========================================================================
    # gitconfig::path
    # ==========================================================================
    Describe 'gitconfig::path'

        It 'is the gitconfig under HOME'
            When call gitconfig::path
            The status should be success
            The stdout should equal "$HOME/.gitconfig"
            The stderr should be blank
        End

    End

    # ==========================================================================
    # gitconfig::marker::begin
    # ==========================================================================
    Describe 'gitconfig::marker::begin'

        It 'embeds the label in the begin marker'
            When call gitconfig::marker::begin personal
            The status should be success
            The stdout should equal '# >>> workspace gitconfig personal >>>'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # gitconfig::marker::end
    # ==========================================================================
    Describe 'gitconfig::marker::end'

        It 'embeds the label in the end marker'
            When call gitconfig::marker::end personal
            The status should be success
            The stdout should equal '# <<< workspace gitconfig personal <<<'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # gitconfig::block::display
    # ==========================================================================
    Describe 'gitconfig::block::display'

        It 'renders the includeIf stanza wrapped in the markers'
            When call gitconfig::block::display personal /ws/Personal /ws/Personal/.gitconfig
            The status should be success
            The line 1 of stdout should equal '# >>> workspace gitconfig personal >>>'
            The line 2 of stdout should equal '[includeIf "gitdir:/ws/Personal/"]'
            The line 4 of stdout should equal '# <<< workspace gitconfig personal <<<'
            The stderr should be blank
        End

        It 'points the include at the identity gitconfig'
            When call gitconfig::block::display personal /ws/Personal /ws/Personal/.gitconfig
            The status should be success
            The stdout should include 'path = /ws/Personal/.gitconfig'
            The stderr should be blank
        End

    End

    # ==========================================================================
    # gitconfig::block::exist
    # ==========================================================================
    Describe 'gitconfig::block::exist'

        It 'is true when the config carries the labelled block'
            gitconfig::block::add personal /ws/Personal /ws/Personal/.gitconfig

            When call gitconfig::block::exist personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the config exists without the block'
            printf '[user]\n\tname = Ada\n' >"$HOME/.gitconfig"

            When call gitconfig::block::exist personal
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

        It 'is false when the config is absent'
            When call gitconfig::block::exist personal
            The status should be failure
            The stdout should be blank
            The stderr should be blank
        End

    End

    # ==========================================================================
    # gitconfig::block::add
    # ==========================================================================
    Describe 'gitconfig::block::add'

        It 'appends the block below existing content'
            printf '[user]\n\tname = Ada\n' >"$HOME/.gitconfig"

            When call gitconfig::block::add personal /ws/Personal /ws/Personal/.gitconfig
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/.gitconfig" should include '[user]'
            The contents of file "$HOME/.gitconfig" should include '# >>> workspace gitconfig personal >>>'
        End

        It 'creates the config when it is absent'
            When call gitconfig::block::add personal /ws/Personal /ws/Personal/.gitconfig
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/.gitconfig" should include 'path = /ws/Personal/.gitconfig'
        End

    End

    # ==========================================================================
    # gitconfig::block::remove
    # ==========================================================================
    Describe 'gitconfig::block::remove'

        It 'removes only the labelled block and keeps the rest'
            printf '[user]\n\tname = Ada\n' >"$HOME/.gitconfig"
            gitconfig::block::add personal /ws/Personal /ws/Personal/.gitconfig

            When call gitconfig::block::remove personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
            The contents of file "$HOME/.gitconfig" should not include 'workspace gitconfig personal'
            The contents of file "$HOME/.gitconfig" should include 'name = Ada'
        End

        It 'does nothing when the config is absent'
            When call gitconfig::block::remove personal
            The status should be success
            The stdout should be blank
            The stderr should be blank
        End

    End

End
