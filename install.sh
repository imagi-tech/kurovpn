#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  Usage: sudo ./install.sh --domain vpn.example.com --email admin@example.com

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
        "pptpd"
        "noobzvpns"
        "badvpn"
        "hysteria"
        "edu"
        "cron"
        "netfilter-persistent"
    )

    local ok=0 fail=0
    for svc in "${svcs[@]}"; do
        if svc_active "$svc"; then
            log_info "  OK : $svc"
            ((ok++))
        else
            svc_start "$svc" 2>/dev/null || true
            if svc_active "$svc"; then
                log_info "  OK : $svc (started)"
                ((ok++))
            else
                log_warn "  FAIL: $svc"
                ((fail++))
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
        "menu" "menu-ssh" "menu-xray" "menu-set"
        "Menu-WGF" "nmenu" "lmenu" "bmenu" "botmenu" "dm-menu"
        "addssh" "add-l2tp" "add-ssws" "add-trojan" "add-vless" "add-vmess"
        "add-reality" "add-ss2022" "add-hysteria2"
        "backup" "xp" "kurovpn-verify"
    )

    for cmd in "${cmd_list[@]}"; do
        if [[ -f "$SCRIPT_DIR/commands/$cmd" ]]; then
            cp "$SCRIPT_DIR/commands/$cmd" "/usr/bin/$cmd"
            chmod +x "/usr/bin/$cmd"
        else
            log_warn "Command not found: $cmd (skipping)"
        fi
    done

    # Install UI library
    if [[ -f "$SCRIPT_DIR/lib/ui.sh" ]]; then
        cp "$SCRIPT_DIR/lib/ui.sh" "/usr/lib/kurovpn/ui.sh"
        chmod 644 "/usr/lib/kurovpn/ui.sh"
    fi

    # Install Xray client management library
    if [[ -f "$SCRIPT_DIR/lib/xray-clients.sh" ]]; then
        cp "$SCRIPT_DIR/lib/xray-clients.sh" "/usr/lib/kurovpn/xray-clients.sh"
        chmod 644 "/usr/lib/kurovpn/xray-clients.sh"
    fi

    # Install Hysteria2 client management library
    if [[ -f "$SCRIPT_DIR/lib/hysteria-clients.sh" ]]; then
        cp "$SCRIPT_DIR/lib/hysteria-clients.sh" "/usr/lib/kurovpn/hysteria-clients.sh"
        chmod 644 "/usr/lib/kurovpn/hysteria-clients.sh"
    fi

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

    # 2. TLS certificate
    issue_cert "$domain" "$ARG_IP_VERSION"

    # 3. Nginx (after cert)
    install_nginx "$domain"

    # 4. Xray (after nginx)
    install_xray "$domain"

    # 5. Hysteria2 (QUIC, after TLS cert)
    install_hysteria2 "$domain"

    # 6. SSH + Dropbear + edu WS
    install_ssh

    # 7. WireGuard
    install_wireguard

    # 8. L2TP/IPsec + PPTP
    install_l2tp

    # 9. NoobZVPNS
    install_noobzvpns

    # 10. BadVPN
    install_badvpn

    # 11. Management commands
    install_commands

    # 12. Cron + iptables persistence
    setup_cron
    save_iptables

    # 13. Final verification
    verify_install

    # 14. Summary
    show_summary "$domain"
}

main "$@"
