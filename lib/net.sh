#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/net.sh — network detection, DNS, firewall helpers

source "$SCRIPT_DIR/lib/common.sh"

# ── Get public IP ──────────────────────────────────────
get_public_ip() {
    local ip
    ip=$(curl -s --max-time 5 ipinfo.io/ip 2>/dev/null) \
     || ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null) \
     || ip=$(curl -s --max-time 5 icanhazip.com 2>/dev/null)
    echo "$ip"
}

# ── Get default network interface ──────────────────────
get_default_iface() {
    ip -4 route show default | awk '{print $5}' | head -1
}

# ── Set DNS ────────────────────────────────────────────
set_dns() {
    log_info "Setting DNS resolvers"

    if svc_active "systemd-resolved" 2>/dev/null; then
        local iface=$(get_default_iface)
        resolvectl dns "$iface" 1.1.1.1 8.8.8.8 2>/dev/null || true
    fi

    # Replace resolv.conf with a static file
    chattr -i /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf
    {
        echo "nameserver 1.1.1.1"
        echo "nameserver 8.8.8.8"
    } > /etc/resolv.conf
    chattr +i /etc/resolv.conf 2>/dev/null || true
    log_info "DNS: 1.1.1.1, 8.8.8.8"
}

# ── Write domain to file ───────────────────────────────
set_domain() {
    local domain="$1"
    echo "$domain" > /etc/xray/domain
    log_info "Domain set: $domain"
}

# ── Save iptables rules ────────────────────────────────
save_iptables() {
    iptables-save > /etc/iptables.up.rules 2>/dev/null
    netfilter-persistent save 2>/dev/null || true
    netfilter-persistent reload 2>/dev/null || true
}

# ── Enable IP forwarding ───────────────────────────────
enable_ip_forwarding() {
    log_info "Enabling IP forwarding"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

    ensure_line /etc/sysctl.conf "net.ipv4.ip_forward=1"
    ensure_line /etc/sysctl.conf "net.ipv6.conf.all.forwarding=1"
    sysctl -p >/dev/null 2>&1 || true
}

# ── Cron management ────────────────────────────────────
setup_cron() {
    log_step "Setting up cron jobs"

    local cronfile="/etc/cron.d/kurovpn"

    cat > "$cronfile" << 'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Remove expired VPN accounts every 15 minutes
0,15,30,45 * * * * root /usr/bin/xp >/dev/null 2>&1

# Backup daily at midnight, 6am, noon, 6pm
0 0,6,12,18 * * * root /usr/bin/backup >/dev/null 2>&1
EOF

    chmod 644 "$cronfile"
    svc_restart cron
    log_info "Cron jobs configured"
}
