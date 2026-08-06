#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/noobzvpns.sh -- NoobZVPNS TLS/WebSocket VPN

source "$SCRIPT_DIR/lib/common.sh"

NOOBZ_VERSION="2.4.0"

install_noobzvpns() {
    log_step "Installing NoobZVPNS v${NOOBZ_VERSION}"

    # Download binary
    local url="https://github.com/noobz-id/noobzvpns/releases/download/v${NOOBZ_VERSION}/noobzvpns.linux.amd64"
    log_info "Downloading NoobZVPNS..."
    curl -sL "$url" -o /usr/bin/noobzvpns || die "Failed to download NoobZVPNS"
    chmod +x /usr/bin/noobzvpns

    # Download TLS cert/key
    curl -sL "https://raw.githubusercontent.com/noobz-id/noobzvpns/master/cert.pem" -o /etc/noobzvpns/cert.pem 2>/dev/null || true
    curl -sL "https://raw.githubusercontent.com/noobz-id/noobzvpns/master/key.pem" -o /etc/noobzvpns/key.pem 2>/dev/null || true
    chmod +x /etc/noobzvpns/* 2>/dev/null || true

    # Config
    cat > /etc/noobzvpns/config.json << 'EOF'
{
  "tcp_std": [8080],
  "tcp_ssl": [9443],
  "ssl_cert": "/etc/noobzvpns/cert.pem",
  "ssl_key": "/etc/noobzvpns/key.pem",
  "ssl_version": "AUTO",
  "conn_timeout": 60,
  "dns_resolver": "/etc/resolv.conf",
  "http_ok": "HTTP/1.1 101 Switching Protocols[crlf]Upgrade: websocket[crlf][crlf]"
}
EOF

    # Systemd unit
    cat > /etc/systemd/system/noobzvpns.service << 'EOF'
[Unit]
Description=NoobZVPNS Service
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/noobzvpns --config /etc/noobzvpns/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    svc_enable noobzvpns
    svc_start noobzvpns

    log_info "NoobZVPNS installed (TCP:8080, SSL:9443)"
}
