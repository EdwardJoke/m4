#compdef m4c

_m4c() {
    local context state state_descr line
    typeset -A opt_args

    _arguments -C \
        '(-d --debug)'{-d,--debug}'[Show bytecode before execution]' \
        '(-f --format)'{-f,--format}'[Format source code and print]' \
        '(-p --pretty)'{-p,--pretty}'[Colored error output for terminal readability]' \
        '--native[Emit QBE IR instead of running via bytecode VM]' \
        '--zon[Structured error output in ZON format]' \
        '--json[Structured error output in JSON format]' \
        '--yaml[Structured error output in YAML format]' \
        '(-o --output)'{-o,--output}'[Output binary path (build only)]:output file:_files' \
        '--target[Target architecture for build]:target:(amd64_apple arm64_apple arm64 amd64_sysv rv64)' \
        '-D[QBE optimization level]:level:(fast small)' \
        '1: :->cmds' \
        '*: :->args'

    case "$state" in
        cmds)
            _alternative 'subcommands:subcommand:((
                help\:"Show CLI help"
                version\:"Show version"
                lint\:"Parse and type-check"
                build\:"Compile to native binary"
                explain\:"Explain an error code"
            ))' 'files:file:_files -g "*.m4"'
            ;;
        args)
            case "$line[1]" in
                help)     _arguments '*: :(help version lint build explain --zon --json --yaml)' ;;
                version)  _arguments '*: :(--zon --json --yaml)' ;;
                lint)     _arguments '*: :(--zon --json --yaml)' && _files -g "*.m4" ;;
                build)    _arguments '*: :(-o --output --target -D --zon --json --yaml)' && _files -g "*.m4" ;;
                explain)  _arguments '*: :(--zon --json --yaml)' ;;
                *)        _files -g "*.m4" ;;
            esac
            ;;
    esac
}

_m4c "$@"
