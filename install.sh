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

# NOTE: Management commands (menu, add-*, etc.) will be installed in Phase 3.
# For now, install only runs infrastructure setup.

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

    # 5. SSH + Dropbear + edu WS
    install_ssh

    # 6. WireGuard
    install_wireguard

    # 7. L2TP/IPsec + PPTP
    install_l2tp

    # 8. NoobZVPNS
    install_noobzvpns

    # 9. BadVPN
    install_badvpn

    # 10. Cron + iptables persistence (user-management cron added in Phase 3)
    setup_cron
    save_iptables

    # 11. Final verification
    verify_install

    # 12. Summary
    show_summary "$domain"
}

main "$@"
