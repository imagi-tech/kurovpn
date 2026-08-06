#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/wireguard.sh — WireGuard installation

source "$SCRIPT_DIR/lib/common.sh"

WG_CONF="/etc/wireguard/wg0.conf"
WG_PARAMS="/etc/wireguard/params"
WG_PORT=2048
WG_NET="10.66.66.0/24"
WG_IP="10.66.66.1"

install_wireguard() {
    log_step "Installing WireGuard"

    if [[ -f "$WG_PARAMS" ]] && svc_active "wg-quick@wg0"; then
        log_info "WireGuard already installed and running"
        return
    fi

    # Detect public interface
    local pub_nic
    pub_nic=$(ip -4 route show default | awk '{print $5}' | head -1)
    if [[ -z "$pub_nic" ]]; then
        log_error "Could not detect default network interface"
        pub_nic=$(ip -4 link show | grep -v lo | grep "state UP" | awk -F': ' '{print $2}' | head -1)
    fi
    log_info "Public interface: $pub_nic"

    # Install WireGuard
    apt-get install -y -qq wireguard wireguard-tools iptables 2>/dev/null || die "Failed to install WireGuard"

    mkdir -p /etc/wireguard /etc/wireguard/clients

    # Generate keys
    local server_priv server_pub
    server_priv=$(wg genkey)
    server_pub=$(echo "$server_priv" | wg pubkey)

    # Save params
    cat > "$WG_PARAMS" << EOF
SERVER_PUB_NIC=$pub_nic
SERVER_WG_NIC=wg0
SERVER_WG_IPV4=$WG_IP
SERVER_PORT=$WG_PORT
SERVER_PRIV_KEY=$server_priv
SERVER_PUB_KEY=$server_pub
EOF
    chmod 600 "$WG_PARAMS"

    # Write wg0.conf
    cat > "$WG_CONF" << EOF
[Interface]
Address = $WG_IP/24
ListenPort = $WG_PORT
PrivateKey = $server_priv
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $pub_nic -j MASQUERADE;
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $pub_nic -j MASQUERADE;
EOF
    chmod 600 "$WG_CONF"

    # Firewall rules
    iptables -t nat -I POSTROUTING -s "$WG_NET" -o "$pub_nic" -j MASQUERADE 2>/dev/null || true
    iptables -I INPUT 1 -i wg0 -j ACCEPT 2>/dev/null || true
    iptables -I FORWARD 1 -i "$pub_nic" -o wg0 -j ACCEPT 2>/dev/null || true
    iptables -I FORWARD 1 -i wg0 -o "$pub_nic" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT 1 -i "$pub_nic" -p udp --dport "$WG_PORT" -j ACCEPT 2>/dev/null || true

    save_iptables
    enable_ip_forwarding

    # Start WireGuard
    svc_enable "wg-quick@wg0"
    svc_start "wg-quick@wg0"

    if svc_active "wg-quick@wg0"; then
        log_info "WireGuard running on port $WG_PORT"
    else
        log_warn "WireGuard service may have issues"
    fi
}
