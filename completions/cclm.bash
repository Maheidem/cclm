# bash completion for cclm.
#
# Install:
#   - system-wide: copy to $(brew --prefix)/etc/bash_completion.d/ (macOS)
#     or /etc/bash_completion.d/ (Linux)
#   - per-user: source it from ~/.bashrc:
#       source /path/to/cclm.bash

_cclm_complete() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local flags="--lms --llama --zai --remote --host= --resume --dry-run --print-env"
    local config_dir="${CCLM_CONFIG_DIR:-$HOME/.config/cclm}"
    local state="$config_dir/.last_session"

    # --host <TAB> — suggest recently-used host from last session
    if [[ "$prev" == "--host" ]]; then
        local hosts=""
        if [[ -r "$state" ]] && command -v jq >/dev/null 2>&1; then
            hosts="$(jq -r '.remote_host // empty' "$state" 2>/dev/null)"
        fi
        COMPREPLY=( $(compgen -W "$hosts" -- "$cur") )
        return 0
    fi

    # --host=<TAB> — same, but with the --host= prefix already consumed
    if [[ "$cur" == --host=* ]]; then
        local partial="${cur#--host=}"
        local hosts=""
        if [[ -r "$state" ]] && command -v jq >/dev/null 2>&1; then
            hosts="$(jq -r '.remote_host // empty' "$state" 2>/dev/null)"
        fi
        local matches=( $(compgen -W "$hosts" -- "$partial") )
        COMPREPLY=( "${matches[@]/#/--host=}" )
        return 0
    fi

    # Leading dash — complete flags
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
        return 0
    fi

    # Otherwise — complete profile slugs (basename minus .json)
    local profiles=""
    if [[ -d "$config_dir" ]]; then
        local f base
        shopt -q nullglob
        local _had_nullglob=$?
        shopt -s nullglob
        for f in "$config_dir"/*.json; do
            base="${f##*/}"
            profiles+="${base%.json} "
        done
        (( _had_nullglob == 0 )) || shopt -u nullglob
    fi
    COMPREPLY=( $(compgen -W "$profiles" -- "$cur") )
    return 0
}

complete -F _cclm_complete cclm
