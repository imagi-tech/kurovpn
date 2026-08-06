#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/ssh.sh — SSH hardening, Dropbear, edu WebSocket proxy

source "$SCRIPT_DIR/lib/common.sh"

install_ssh() {
    log_step "Configuring SSH & Dropbear"

    # ── SSH: ensure port 22 and add port 3303 ──────────
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
    ensure_line /etc/ssh/sshd_config "Port 22"
    ensure_line /etc/ssh/sshd_config "Port 3303"

    svc_restart sshd 2>/dev/null || svc_restart ssh

    # ── Dropbear ───────────────────────────────────────
    log_info "Configuring Dropbear"

    # Banner
    cat > /etc/issue.net << 'DROPBEAR_BANNER'
========================================
           KUROVPN Server
    https://github.com/imagi-tech/kurovpn
========================================
 No DDOS | No Torrent | No Mining
 No Hacking | No Spam
========================================
DROPBEAR_BANNER

    # Dropbear config: ports 111 (main), 109 (WS), 69 (fallback)
    cat > /etc/default/dropbear << 'DROPBEAR_CONF'
NO_START=0
DROPBEAR_PORT=111
DROPBEAR_EXTRA_ARGS="-p 109 -p 69"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
DROPBEAR_CONF

    ensure_line /etc/shells "/bin/false"
    ensure_line /etc/shells "/usr/sbin/nologin"

    # Kill any running dropbear instances
    pkill dropbear 2>/dev/null || true
    svc_restart dropbear

    log_info "SSH & Dropbear configured (ports 22, 3303, 109, 111, 69)"

    # ── edu WebSocket SSH proxy ─────────────────────────
    install_edu
}

install_edu() {
    log_info "Installing edu WebSocket proxy"

    # Copy ws binary from repo
    cp "$SCRIPT_DIR/bin/ws" /usr/bin/ws
    chmod +x /usr/bin/ws

    # Copy config
    cp "$SCRIPT_DIR/bin/config.yaml" /usr/bin/config.yaml

    # Systemd service
    cat > /etc/systemd/system/edu.service << 'EDU_UNIT'
[Unit]
Description=KUROVPN WebSocket SSH Proxy
After=network-online.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/bin/ws -f /usr/bin/config.yaml
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EDU_UNIT

    systemctl daemon-reload
    svc_enable edu
    svc_start edu

    log_info "edu WebSocket proxy installed"
}
