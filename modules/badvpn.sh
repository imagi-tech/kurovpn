#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/badvpn.sh -- BadVPN UDP game accelerator (port 7300)

source "$SCRIPT_DIR/lib/common.sh"

install_badvpn() {
    log_step "Installing BadVPN UDP Gateway"

    # Copy pre-compiled binary from repo
    cp "$SCRIPT_DIR/bin/badvpn" /usr/bin/badvpn
    chmod +x /usr/bin/badvpn

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
