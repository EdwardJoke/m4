_mein() {
    local cur prev words cword
    _init_completion || return

    local subcommands="init new clean help"

    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$subcommands" -- "$cur"))
        return
    fi

    local cmd="${words[1]}"
    case "$cmd" in
        init|new)
            ;;
        clean|help)
            ;;
    esac
} && complete -F _mein mein
