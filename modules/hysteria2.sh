#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/hysteria2.sh — Hysteria2 QUIC proxy server (UDP)

source "$SCRIPT_DIR/lib/common.sh"

HYSTERIA_VERSION="2.12.0"
HYSTERIA_CONFIG="/etc/hysteria/config.yaml"
HYSTERIA_BIN="/usr/bin/hysteria"

install_hysteria2() {
    local domain="$1"
    log_step "Installing Hysteria2 v${HYSTERIA_VERSION}"

    if [[ -f "$HYSTERIA_BIN" ]] && "$HYSTERIA_BIN" version 2>/dev/null | grep -q "$HYSTERIA_VERSION"; then
        log_info "Hysteria2 ${HYSTERIA_VERSION} already installed"
        regenerate_hysteria_config "$domain"
        return
    fi

    local arch
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)       die "Hysteria2: unsupported arch $(uname -m)" ;;
    esac

    local url="https://github.com/apernet/hysteria/releases/download/app/v${HYSTERIA_VERSION}/hysteria-linux-${arch}"
    local tmpdir
    tmpdir=$(mktemp -d)

    log_info "Downloading Hysteria2..."
    curl -sL --proto '=https' --tlsv1.2 "$url" -o "$tmpdir/hysteria" || die "Failed to download Hysteria2"

    local expected_sha="2de3650bf3464af49238160c94487c6edcefb53fbd09a8961cfcdb692cd817c5"
    if [[ "$arch" == "amd64" && "$HYSTERIA_VERSION" == "2.12.0" ]]; then
        local actual_sha
        actual_sha=$(sha256sum "$tmpdir/hysteria" 2>/dev/null | awk '{print $1}')
        if [[ "$actual_sha" != "$expected_sha" ]]; then
            rm -rf "$tmpdir"
            die "Hysteria2 checksum verification failed! Expected: $expected_sha, got: $actual_sha"
        fi
        log_info "Hysteria2 SHA-256 checksum verified: OK"
    fi

    cp "$tmpdir/hysteria" "$HYSTERIA_BIN"
    chmod +x "$HYSTERIA_BIN"
    rm -rf "$tmpdir"

    log_info "Hysteria2 binary installed ($("$HYSTERIA_BIN" version 2>/dev/null | head -1))"

    mkdir -p /etc/hysteria

    regenerate_hysteria_config "$domain"
    install_hysteria_service
}

regenerate_hysteria_config() {
    local domain="$1"
    log_info "Regenerating Hysteria2 config"
    source "$SCRIPT_DIR/lib/hysteria-clients.sh" 2>/dev/null || source /usr/lib/kurovpn/hysteria-clients.sh 2>/dev/null || true
    if command -v hy_regen &>/dev/null; then
        hy_regen
    fi
    log_info "Hysteria2 config written"
}

install_hysteria_service() {
    log_info "Creating Hysteria2 systemd services"

    # 1. Standard Hysteria2 service (:443 UDP)
    cat > /etc/systemd/system/hysteria.service << 'HYUNIT'
[Unit]
Description=Hysteria2 QUIC Proxy Server
Documentation=https://github.com/apernet/hysteria
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
HYUNIT

    # 2. Port 53 DNS Bypass Hysteria2 service (:53 UDP + Salamander Obfuscation)
    cat > /etc/systemd/system/hysteria-dns.service << 'HYDNSUNIT'
[Unit]
Description=Hysteria2 QUIC Proxy Server (Port 53 DNS Obfuscated)
Documentation=https://github.com/apernet/hysteria
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/hysteria server -c /etc/hysteria/config-dns.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
HYDNSUNIT

    # Remove any legacy iptables port 53 UDP redirect rules since hysteria-dns binds directly to :53/udp
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 443 2>/dev/null || true
    iptables -t nat -D OUTPUT -p udp -o lo --dport 53 -j REDIRECT --to-ports 443 2>/dev/null || true
    ip6tables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 443 2>/dev/null || true

    systemctl daemon-reload
    svc_enable hysteria
    svc_restart hysteria
    svc_enable hysteria-dns
    svc_restart hysteria-dns

    sleep 2
    if svc_active hysteria && svc_active hysteria-dns; then
        log_info "Hysteria2 services running (Port 443 Standard & Port 53 DNS Salamander Obfs)"
    elif svc_active hysteria; then
        log_info "Hysteria2 standard service running (:443 UDP)"
    else
        log_warn "Hysteria2 service may have issues — check 'systemctl status hysteria hysteria-dns'"
    fi
}
