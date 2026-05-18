#!/usr/bin/env bash

# Creates and manages systemd service files for controlling plymouth animation timing

set -e

SERVICE_SHUTDOWN="/etc/systemd/system/plymouth-wait-for-shutdown.service"
SERVICE_ANIMATION="/etc/systemd/system/plymouth-wait-for-animation.service"

# ── Helpers ───────────────────────────────────────────────────────────────────

die() { echo "error: $1" >&2; exit 1; }

check_root() {
    [[ $EUID -eq 0 ]] || die "run this script as root or with sudo"
}

check_systemd() {
    command -v systemctl &>/dev/null || die "systemd not found"
}

reload_systemd() {
    systemctl daemon-reload
}

# ── Service Writers ───────────────────────────────────────────────────────────

write_shutdown_service() {
    local duration="${1:-5}"

    cat > "$SERVICE_SHUTDOWN" <<EOF
[Unit]
Description=Plymouth wait for shutdown animation
DefaultDependencies=no
After=plymouth-start.service
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/bin/sleep ${duration}
RemainAfterExit=yes

[Install]
WantedBy=shutdown.target reboot.target halt.target
EOF

    echo "written: $SERVICE_SHUTDOWN (duration: ${duration}s)"
}

write_animation_service() {
    local duration="${1:-3}"

    cat > "$SERVICE_ANIMATION" <<EOF
[Unit]
Description=Plymouth wait for boot animation
DefaultDependencies=no
After=plymouth-start.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/sleep ${duration}
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF

    echo "written: $SERVICE_ANIMATION (duration: ${duration}s)"
}

# ── Enable/Disable ────────────────────────────────────────────────────────────

enable_services() {
    local services=()

    [[ -f "$SERVICE_SHUTDOWN" ]] && services+=("plymouth-wait-for-shutdown.service")
    [[ -f "$SERVICE_ANIMATION" ]] && services+=("plymouth-wait-for-animation.service")

    [[ ${#services[@]} -eq 0 ]] && { echo "no services to enable — run 'create' first"; return; }

    for svc in "${services[@]}"; do
        systemctl enable "$svc" && echo "enabled: $svc"
    done
}

disable_services() {
    for svc in plymouth-wait-for-shutdown.service plymouth-wait-for-animation.service; do
        if systemctl is-enabled "$svc" &>/dev/null; then
            systemctl disable "$svc" && echo "disabled: $svc"
        fi
    done
}

remove_services() {
    disable_services
    rm -f "$SERVICE_SHUTDOWN" "$SERVICE_ANIMATION"
    reload_systemd
    echo "service files removed"
}

status_services() {
    echo ""
    for svc in plymouth-wait-for-shutdown.service plymouth-wait-for-animation.service; do
        local file
        if [[ "$svc" == *shutdown* ]]; then
            file="$SERVICE_SHUTDOWN"
        else
            file="$SERVICE_ANIMATION"
        fi

        if [[ -f "$file" ]]; then
            local duration
            duration=$(grep "ExecStart=/bin/sleep" "$file" | awk '{print $2}')
            local enabled
            enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "disabled")
            printf "  %-45s duration: %ss  status: %s\n" "$svc" "$duration" "$enabled"
        else
            printf "  %-45s not created\n" "$svc"
        fi
    done
    echo ""
}

# ── Interactive Create ────────────────────────────────────────────────────────

interactive_create() {
    echo ""
    echo "configure plymouth animation durations"
    echo ""

    read -rp "boot animation duration in seconds [default: 3]: " boot_dur
    boot_dur="${boot_dur:-3}"
    [[ "$boot_dur" =~ ^[0-9]+$ ]] || die "invalid value: $boot_dur"

    read -rp "shutdown animation duration in seconds [default: 5]: " shut_dur
    shut_dur="${shut_dur:-5}"
    [[ "$shut_dur" =~ ^[0-9]+$ ]] || die "invalid value: $shut_dur"

    write_animation_service "$boot_dur"
    write_shutdown_service "$shut_dur"
    reload_systemd
    enable_services

    echo ""
    echo "services created and enabled"
    echo "changes take effect on next boot/shutdown"
}

# ── Main ──────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
usage: $(basename "$0") [command]

commands:
  create      interactive setup for both service files
  enable      enable existing service files
  disable     disable service files without removing them
  remove      disable and delete service files
  status      show current service status and durations

run without arguments to show this help
EOF
}

main() {
    check_root
    check_systemd

    case "${1:-}" in
        create)  interactive_create ;;
        enable)  enable_services; reload_systemd ;;
        disable) disable_services; reload_systemd ;;
        remove)  remove_services ;;
        status)  status_services ;;
        *) usage ;;
    esac
}

main "$@"
