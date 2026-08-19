#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/bbr.sh — Kernel TCP BBR Congestion Control & Network Optimization

SYSCTL_BBR_CONF="/etc/sysctl.d/99-kurovpn-bbr.conf"

bbr_is_active() {
    local cc qdisc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    [[ "$cc" == "bbr"* && "$qdisc" == "fq"* ]]
}

bbr_status_text() {
    local cc qdisc
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    if [[ "$cc" == "bbr"* ]]; then
        echo "BBR (Congestion: $cc, Qdisc: $qdisc)"
    else
        echo "Standard ($cc / $qdisc)"
    fi
}

bbr_enable() {
    echo "  [+] Checking kernel BBR support..."
    modprobe tcp_bbr 2>/dev/null || true
    
    local available
    available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
    if [[ "$available" != *"bbr"* ]]; then
        echo "  [-] Kernel does not support BBR directly. (Kernel 4.9+ required)"
        return 1
    fi

    echo "  [+] Applying high-performance TCP & BBR sysctl rules..."
    cat > "$SYSCTL_BBR_CONF" << 'EOF'
# KUROVPN Network & BBR Optimization
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Buffer Optimization
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Connection & FastOpen
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_notsent_lowat = 16384
net.core.somaxconn = 8192

# IP Forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

    sysctl -p "$SYSCTL_BBR_CONF" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true

    if bbr_is_active; then
        echo "  [✓] BBR TCP Speed Booster successfully activated!"
        return 0
    else
        echo "  [!] BBR enabled, but active qdisc or cc may require reboot."
        return 0
    fi
}

bbr_disable() {
    echo "  [+] Reverting TCP optimization to default..."
    rm -f "$SYSCTL_BBR_CONF"
    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
    sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || true
    sysctl --system >/dev/null 2>&1 || true
    echo "  [✓] TCP settings restored to default."
}
