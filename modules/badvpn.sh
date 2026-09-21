#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/badvpn.sh -- BadVPN UDP game accelerator (port 7300)

source "$SCRIPT_DIR/lib/common.sh"

install_badvpn() {
    log_step "Installing BadVPN UDP Gateway"

    # Stop service if running to avoid 'Text file busy'
    systemctl stop badvpn 2>/dev/null || true

    # Copy pre-compiled binary from repo safely
    cp "$SCRIPT_DIR/bin/badvpn" /usr/bin/badvpn.tmp 2>/dev/null || true
    if [[ -f /usr/bin/badvpn.tmp ]]; then
        chmod +x /usr/bin/badvpn.tmp
        mv -f /usr/bin/badvpn.tmp /usr/bin/badvpn
    else
        install -m 755 "$SCRIPT_DIR/bin/badvpn" /usr/bin/badvpn 2>/dev/null || true
    fi

    # Systemd service
    cat > /etc/systemd/system/badvpn.service << 'BADVPN_UNIT'
[Unit]
Description=BadVPN UDP Gateway (Port 7300)
After=network-online.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/bin/badvpn --listen-addr 127.0.0.1:7300 --max-clients 500
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
BADVPN_UNIT

    systemctl daemon-reload
    svc_enable badvpn
    svc_start badvpn

    log_info "BadVPN installed on UDP port 7300"
}
