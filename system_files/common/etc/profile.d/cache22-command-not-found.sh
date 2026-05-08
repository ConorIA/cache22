# bash command_not_found_handle: when a command isn't on PATH, look it
# up in the package DB to remind the user this is an immutable image
# (don't reach for `pacman -S`) and suggest the right install path.

command_not_found_handle() {
    local cmd="$1"
    printf 'cache22: %s: command not found\n' "$cmd" >&2
    printf '\n' >&2
    printf '  This is an immutable bootc image. Install user software via:\n' >&2
    printf '    flatpak search %s\n' "$cmd" >&2
    printf '    cache22-shell     # CachyOS distrobox container with pacman + AUR\n' >&2
    return 127
}
