#compdef mein

_mein() {
    local context state state_descr line
    typeset -A opt_args

    _arguments -C \
        '(-v --version){-v,--version}'[Show version] \
        '1: :->cmds' \
        '*: :->args'

    case "$state" in
        cmds)
            _alternative 'subcommands:subcommand:((
                init\:"Initialize a new m4 project"
                new\:"Alias for init"
                clean\:"Clean build artifacts and caches"
                help\:"Show help"
                completions\:"Generate shell completions"
                version\:"Show version"
            ))'
            ;;
        args)
            case "$line[1]" in
                init|new|completions|version) ;;
                clean|help) ;;
            esac
            ;;
    esac
}

_mein "$@"
