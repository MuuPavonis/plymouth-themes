#!/usr/bin/env bash


# Supports Arch-based and Ubuntu-based systems

set -e

THEMES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/themes"
PLYMOUTH_DIR="/usr/share/plymouth/themes"

# ── Helpers ──────────────────────────────────────────────────────────────────

die() { echo "error: $1" >&2; exit 1; }

check_root() {
    [[ $EUID -eq 0 ]] || die "run this script as root or with sudo"
}

detect_distro() {
    if command -v pacman &>/dev/null; then
        DISTRO="arch"
    elif command -v apt &>/dev/null; then
        DISTRO="ubuntu"
    else
        die "unsupported distribution — only Arch and Ubuntu based systems are supported"
    fi
}

check_plymouth() {
    if ! command -v plymouth-set-default-theme &>/dev/null; then
        echo "plymouth not found — installing..."
        if [[ $DISTRO == "arch" ]]; then
            pacman -S --noconfirm plymouth
        else
            apt install -y plymouth plymouth-themes
        fi
    fi
}

update_initramfs() {
    echo "updating initramfs..."
    if [[ $DISTRO == "arch" ]]; then
        mkinitcpio -p linux
    else
        update-initramfs -u
    fi
}

# ── Theme Discovery ───────────────────────────────────────────────────────────

get_local_themes() {
    local themes=()
    if [[ -d "$THEMES_DIR" ]]; then
        for dir in "$THEMES_DIR"/*/; do
            [[ -d "$dir" ]] && themes+=("$(basename "$dir")")
        done
    fi
    echo "${themes[@]}"
}

get_installed_themes() {
    local themes=()
    for dir in "$PLYMOUTH_DIR"/*/; do
        [[ -d "$dir" ]] && themes+=("$(basename "$dir")")
    done
    echo "${themes[@]}"
}

# ── Install ───────────────────────────────────────────────────────────────────

install_themes() {
    [[ -d "$THEMES_DIR" ]] || die "themes directory not found at: $THEMES_DIR"

    local themes
    read -ra themes <<< "$(get_local_themes)"

    [[ ${#themes[@]} -eq 0 ]] && die "no theme folders found in: $THEMES_DIR"

    echo "found ${#themes[@]} theme(s) — copying to $PLYMOUTH_DIR"

    for theme in "${themes[@]}"; do
        echo "  installing: $theme"
        cp -r "$THEMES_DIR/$theme" "$PLYMOUTH_DIR/"
    done

    echo "all themes installed"
}

# ── Theme Selection Menu ──────────────────────────────────────────────────────

select_theme() {
    local themes
    read -ra themes <<< "$(get_installed_themes)"

    [[ ${#themes[@]} -eq 0 ]] && die "no themes found in $PLYMOUTH_DIR"

    local current
    current=$(plymouth-set-default-theme 2>/dev/null || echo "none")

    echo ""
    echo "installed themes:"
    echo ""

    local i=1
    for theme in "${themes[@]}"; do
        if [[ "$theme" == "$current" ]]; then
            printf "  [%d] %s  <-- active\n" "$i" "$theme"
        else
            printf "  [%d] %s\n" "$i" "$theme"
        fi
        ((i++))
    done

    echo ""
    read -rp "select theme number (or press enter to cancel): " choice

    [[ -z "$choice" ]] && { echo "cancelled"; return; }

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#themes[@]} )); then
        die "invalid selection: $choice"
    fi

    local selected="${themes[$((choice - 1))]}"
    echo "setting theme: $selected"
    plymouth-set-default-theme -R "$selected" 2>/dev/null || {
        plymouth-set-default-theme "$selected"
        update_initramfs
    }

    echo "theme set to: $selected"
}

# ── Main ──────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
usage: $(basename "$0") [command]

commands:
  install     copy themes from ./themes/ to $PLYMOUTH_DIR
  select      interactive menu to set active theme
  list        list installed themes
  all         install then select

run without arguments to show this help
EOF
}

main() {
    check_root
    detect_distro
    check_plymouth

    case "${1:-}" in
        install) install_themes ;;
        select)  select_theme ;;
        list)
            echo "installed themes:"
            for t in $(get_installed_themes); do echo "  $t"; done
            ;;
        all)
            install_themes
            select_theme
            ;;
        *) usage ;;
    esac
}

main "$@"
