#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/noobzvpns.sh -- NoobZVPNS TLS/WebSocket VPN (optional)

source "$SCRIPT_DIR/lib/common.sh"

install_noobzvpns() {
    log_step "Installing NoobZVPNS"

    local url="https://github.com/noobz-id/noobzvpns/releases/download/v1.3.1a/noobzvpns.x86_64"

    log_info "Downloading NoobZVPNS..."
    if curl -sLf "$url" -o /usr/bin/noobzvpns 2>/dev/null; then
        chmod +x /usr/bin/noobzvpns
    elif curl -sLf "https://github.com/noobz-id/noobzvpns/raw/master/noobzvpns.x86_64" -o /usr/bin/noobzvpns 2>/dev/null; then
        chmod +x /usr/bin/noobzvpns
    else
        log_warn "NoobZVPNS binary unavailable — skipping (manual install required)"
        return 0
    fi

    if [[ "$(wc -c < /usr/bin/noobzvpns)" -lt 1000 ]]; then
        log_warn "NoobZVPNS download appears invalid — skipping"
        rm -f /usr/bin/noobzvpns
        return 0
    fi

    mkdir -p /etc/noobzvpns
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

    curl -sLf "https://raw.githubusercontent.com/noobz-id/noobzvpns/master/cert.pem" -o /etc/noobzvpns/cert.pem 2>/dev/null || true
    curl -sLf "https://raw.githubusercontent.com/noobz-id/noobzvpns/master/key.pem" -o /etc/noobzvpns/key.pem 2>/dev/null || true

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
