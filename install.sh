#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  Usage: sudo ./install.sh --domain vpn.example.com --email admin@example.com

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# ── Auto-Bootstrap for curl | bash execution ───────────
if [ ! -f "$SCRIPT_DIR/lib/common.sh" ]; then
    echo -e "\033[0;34m[INFO]\033[0m  Fetching KUROVPN package from repository..."
    TMP_BOOTSTRAP_DIR="/tmp/kurovpn-bootstrap-$$"
    mkdir -p "$TMP_BOOTSTRAP_DIR"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://github.com/imagi-tech/kurovpn/archive/refs/heads/main.tar.gz" | tar -xz --strip-components=1 -C "$TMP_BOOTSTRAP_DIR"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "https://github.com/imagi-tech/kurovpn/archive/refs/heads/main.tar.gz" | tar -xz --strip-components=1 -C "$TMP_BOOTSTRAP_DIR"
    else
        apt-get update -qq && apt-get install -y -qq curl tar >/dev/null 2>&1
        curl -fsSL "https://github.com/imagi-tech/kurovpn/archive/refs/heads/main.tar.gz" | tar -xz --strip-components=1 -C "$TMP_BOOTSTRAP_DIR"
    fi
    exec bash "$TMP_BOOTSTRAP_DIR/install.sh" "$@"
fi

# ── Source Libraries ───────────────────────────────────
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/deps.sh"
source "$SCRIPT_DIR/lib/net.sh"
source "$SCRIPT_DIR/lib/cert.sh"
source "$SCRIPT_DIR/lib/users.sh"

# ── Source Modules ─────────────────────────────────────
source "$SCRIPT_DIR/modules/ssh.sh"
source "$SCRIPT_DIR/modules/nginx.sh"
source "$SCRIPT_DIR/modules/xray.sh"
source "$SCRIPT_DIR/modules/hysteria2.sh"
source "$SCRIPT_DIR/modules/wireguard.sh"
source "$SCRIPT_DIR/modules/l2tp.sh"
source "$SCRIPT_DIR/modules/noobzvpns.sh"
source "$SCRIPT_DIR/modules/badvpn.sh"

# ── Verify installation ───────────────────────────────
verify_install() {
    log_step "Verifying services"

    local svcs=(
        "nginx"
        "xray"
        "dropbear"
        "ssh" "sshd"
        "wg-quick@wg0"
        "xl2tpd"
        "ipsec"
        "noobzvpns"
        "badvpn"
        "hysteria"
        "edu"
        "cron"
        "netfilter-persistent"
    )

    local ok=0 fail=0
    for svc in "${svcs[@]}"; do
        # If optional service unit does not exist on this distro, skip silently
        if [[ "$svc" == "noobzvpns" ]] && ! systemctl list-unit-files "$svc.service" &>/dev/null; then
            continue
        fi
        if svc_active "$svc"; then
            log_info "  OK : $svc"
            ok=$((ok + 1))
        else
            svc_start "$svc" 2>/dev/null || true
            if svc_active "$svc"; then
                log_info "  OK : $svc (started)"
                ok=$((ok + 1))
            else
                log_warn "  FAIL: $svc"
                fail=$((fail + 1))
            fi
        fi
    done

    echo ""
    log_info "Services: ${ok} active, ${fail} with issues"

    # Test Xray config validity
    if /usr/bin/xray run -test -config /etc/xray/config.json &>/dev/null; then
        log_info "Xray configuration: VALID"
    else
        log_warn "Xray configuration: INVALID"
    fi
}

# ── Install commands to /usr/bin ───────────────────────
install_commands() {
    log_step "Installing management commands"

    mkdir -p /usr/lib/kurovpn

    local cmd_list=(
        "menu" "menu-ssh" "menu-xray" "menu-hy2" "menu-set"
        "Menu-WGF" "nmenu" "lmenu" "bmenu" "botmenu" "dm-menu"
        "addssh" "add-l2tp" "add-ssws" "add-trojan" "add-vless" "add-vmess"
        "add-reality" "add-ss2022" "add-hysteria2"
        "backup" "xp" "bbr" "sub" "kurovpn-verify" "kurovpn-update"
    )

    for cmd in "${cmd_list[@]}"; do
        if [[ -f "$SCRIPT_DIR/commands/$cmd" ]]; then
            cp "$SCRIPT_DIR/commands/$cmd" "/usr/bin/$cmd"
            chmod +x "/usr/bin/$cmd"
        else
            log_warn "Command not found: $cmd (skipping)"
        fi
    done

    # Install all library files
    for lib in "$SCRIPT_DIR"/lib/*.sh; do
        [[ -f "$lib" ]] && cp "$lib" "/usr/lib/kurovpn/"
    done
    chmod 644 /usr/lib/kurovpn/*.sh 2>/dev/null || true

    # Install BBR module library
    if [[ -f "$SCRIPT_DIR/modules/bbr.sh" ]]; then
        cp "$SCRIPT_DIR/modules/bbr.sh" "/usr/lib/kurovpn/bbr.sh"
        chmod 644 "/usr/lib/kurovpn/bbr.sh"
    fi

    # Initialize subscriptions directory
    mkdir -p /var/www/html/sub
    chmod 755 /var/www/html/sub 2>/dev/null || true

    # Deploy Telegram bot
    if [[ -f "$SCRIPT_DIR/Plugin/bot.py" ]]; then
        mkdir -p /opt/kurovpn
        cp "$SCRIPT_DIR/Plugin/bot.py" /opt/kurovpn/bot.py
        chmod +x /opt/kurovpn/bot.py
    fi

    # Deploy bot systemd service
    if [[ -f "$SCRIPT_DIR/Plugin/kurovpn-bot.service" ]]; then
        cp "$SCRIPT_DIR/Plugin/kurovpn-bot.service" /etc/systemd/system/kurovpn-bot.service
        systemctl daemon-reload 2>/dev/null || true
    fi

    # Deploy uninstall as a command
    if [[ -f "$SCRIPT_DIR/uninstall.sh" ]]; then
        cp "$SCRIPT_DIR/uninstall.sh" /usr/bin/uninstall
        chmod +x /usr/bin/uninstall
    fi

    log_info "Commands and libraries installed"
}

# ── Main Installation ──────────────────────────────────
main() {
    require_root
    parse_args "$@"
    show_banner

    local domain email

    domain=$(ask_domain)
    email=$(ask_email)

    log_info "Domain    : $domain"
    log_info "Email     : $email"
    log_info "IP mode   : $ARG_IP_VERSION"
    echo ""

    # 1. System prep
    detect_os
    set_dns
    install_deps
    create_dirs
    init_users_db

    # 2. Deploy management commands early so tools and menus are immediately accessible
    install_commands

    # 3. TLS certificate
    issue_cert "$domain" "$ARG_IP_VERSION"

    # 4. Nginx (after cert)
    install_nginx "$domain"

    # 5. Xray (after nginx)
    install_xray "$domain"

    # 6. Hysteria2 (QUIC, after TLS cert)
    install_hysteria2 "$domain"

    # 7. SSH + Dropbear + edu WS
    install_ssh

    # 8. WireGuard
    install_wireguard

    # 9. L2TP/IPsec + PPTP (optional legacy protocol)
    install_l2tp || log_warn "L2TP/IPsec setup encountered warnings (skipping)"

    # 10. NoobZVPNS (optional)
    install_noobzvpns || log_warn "NoobZVPNS setup encountered warnings (skipping)"

    # 11. BadVPN (optional UDP gateway)
    install_badvpn || log_warn "BadVPN setup encountered warnings (skipping)"

    # 12. Cron + iptables persistence
    setup_cron
    save_iptables

    # 13. Final verification
    verify_install

    # 14. Summary
    show_summary "$domain"
}

main "$@"
