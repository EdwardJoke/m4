_m4c() {
    local cur prev words cword
    _init_completion || return

    local subcommands="help version lint build explain"
    local global_flags="-d --debug -f --format -p --pretty --native --zon --json --yaml"
    local build_flags="-o --output --target -D"

    if [[ $cword -eq 1 ]]; then
        case "$prev" in
            -d|--debug|-f|--format|-p|--pretty|--native|--zon|--json|--yaml)
                _filedir '@(m4)'
                return
                ;;
            -o|--output)
                _filedir
                return
                ;;
            --target)
                COMPREPLY=($(compgen -W "amd64_apple arm64_apple arm64 amd64_sysv rv64" -- "$cur"))
                return
                ;;
            -D)
                COMPREPLY=($(compgen -W "fast small" -- "$cur"))
                return
                ;;
            *)
                COMPREPLY=($(compgen -W "$subcommands $global_flags" -- "$cur"))
                [[ $COMPREPLY == */* ]] && COMPREPLY=()
                return
                ;;
        esac
    fi

    local cmd="${words[1]}"
    case "$cmd" in
        help)
            COMPREPLY=($(compgen -W "$subcommands --zon --json --yaml" -- "$cur"))
            ;;
        version)
            COMPREPLY=($(compgen -W "--zon --json --yaml" -- "$cur"))
            ;;
        lint)
            COMPREPLY=($(compgen -W "--zon --json --yaml" -- "$cur"))
            [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir '@(m4)'
            ;;
        build)
            COMPREPLY=($(compgen -W "$build_flags --zon --json --yaml" -- "$cur"))
            [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir '@(m4)'
            ;;
        explain)
            COMPREPLY=($(compgen -W "--zon --json --yaml" -- "$cur"))
            ;;
        *)
            COMPREPLY=($(compgen -W "$subcommands $global_flags" -- "$cur"))
            [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir '@(m4)'
            ;;
    esac
} && complete -F _m4c m4c
