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
    curl -sL "$url" -o "$tmpdir/hysteria" || die "Failed to download Hysteria2"

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

    local auth_yaml=""
    local users
    users=$(jq -r '.hysteria2[]?' /etc/kurovpn/users.json 2>/dev/null)

    if [[ -n "$users" ]]; then
        local lastpass
        lastpass=$(jq -r '.hysteria2[-1].password' /etc/kurovpn/users.json 2>/dev/null)
        auth_yaml="auth:
  type: password
  password: ${lastpass}"
    else
        local placeholder
        placeholder=$(head -c 24 /dev/urandom 2>/dev/null | base64 -w0 2>/dev/null || openssl rand -base64 24)
        auth_yaml="auth:
  type: password
  password: ${placeholder}"
    fi

    cat > "$HYSTERIA_CONFIG" << HYCONF
server: :443
protocol: udp

tls:
  cert: /etc/xray/xray.crt
  key: /etc/xray/xray.key

${auth_yaml}
masquerade:
  type: proxy
  proxy:
    url: https://${domain}/
    rewriteHost: true

speedTest: false
disableUDP: false
HYCONF

    chmod 600 "$HYSTERIA_CONFIG"
    log_info "Hysteria2 config written"
}

install_hysteria_service() {
    log_info "Creating Hysteria2 systemd service"

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

    systemctl daemon-reload
    svc_enable hysteria
    svc_restart hysteria

    sleep 2
    if svc_active hysteria; then
        log_info "Hysteria2 service running"
    else
        log_warn "Hysteria2 service may have issues — check 'systemctl status hysteria'"
    fi
}
