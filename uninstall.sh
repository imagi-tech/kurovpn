#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  uninstall.sh — clean removal of all KUROVPN components

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }

echo ""
echo -e "${RED}============================================${NC}"
echo -e "${RED}  KUROVPN UNINSTALLER${NC}"
echo -e "${RED}============================================${NC}"
echo ""
echo -e "This will remove ALL KUROVPN components:"
echo -e "  - SSH/Dropbear port changes"
echo -e "  - Xray, Nginx, WireGuard, L2TP/IPsec, PPTP"
echo -e "  - NoobZVPNS, BadVPN, edu WS proxy"
echo -e "  - Configuration files (/etc/xray, /etc/kurovpn, etc.)"
echo -e "  - Cron jobs and iptables rules"
echo ""
read -p "Type 'yes' to confirm: " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 0; }

# ── Stop and disable services ──────────────────────────
info "Stopping services..."

SERVICES=(
    xray nginx dropbear edu badvpn noobzvpns hysteria
    "wg-quick@wg0" "wg-quick@wgcf"
    xl2tpd ipsec pptpd
)

for svc in "${SERVICES[@]}"; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done

# ── Remove systemd unit files ──────────────────────────
info "Removing systemd units..."
rm -f /etc/systemd/system/xray.service
rm -f /etc/systemd/system/nginx.service
rm -f /etc/systemd/system/edu.service
rm -f /etc/systemd/system/badvpn.service
rm -f /etc/systemd/system/noobzvpns.service
rm -f /etc/systemd/system/kurovpn-bot.service
rm -f /etc/systemd/system/hysteria.service
systemctl daemon-reload

# ── Remove binaries ────────────────────────────────────
info "Removing installed binaries..."
rm -f /usr/bin/xray /usr/bin/ws /usr/bin/badvpn /usr/bin/noobzvpns /usr/bin/hysteria
rm -f /usr/bin/config.yaml

# Remove KUROVPN commands (if installed in Phase 3)
rm -f /usr/bin/menu /usr/bin/menu-ssh /usr/bin/menu-xray /usr/bin/menu-set
rm -f /usr/bin/Menu-WGF /usr/bin/nmenu /usr/bin/lmenu
rm -f /usr/bin/bmenu /usr/bin/botmenu /usr/bin/dm-menu
rm -f /usr/bin/addssh /usr/bin/add-l2tp /usr/bin/add-ssws
rm -f /usr/bin/add-trojan /usr/bin/add-vless /usr/bin/add-vmess
rm -f /usr/bin/add-reality /usr/bin/add-ss2022 /usr/bin/add-hysteria2
rm -f /usr/bin/backup /usr/bin/xp /usr/bin/kurovpn-verify

# ── Remove library directory ───────────────────────────
rm -rf /usr/lib/kurovpn

# ── Remove configuration directories ───────────────────
info "Removing configuration files..."
rm -rf /etc/xray
rm -rf /etc/kurovpn
rm -rf /etc/funny
rm -rf /etc/noobzvpns
rm -rf /etc/hysteria
rm -rf /etc/wireguard
rm -rf /etc/v2ray
rm -rf /etc/slowdns
rm -rf /etc/websocket
rm -rf /var/log/xray
rm -rf /var/lib/crot
rm -rf /home/vps/public_html
rm -rf /opt/kurovpn
rm -rf /opt/src         # Libreswan build dir
rm -rf /root/.acme.sh    # acme.sh installation

# ── Remove cron ────────────────────────────────────────
info "Removing cron..."
rm -f /etc/cron.d/kurovpn

# ── Restore SSH to default (port 22 only) ──────────────
info "Restoring SSH to default..."
sed -i '/^Port 3303$/d' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/^#Port 22/Port 22/' /etc/ssh/sshd_config 2>/dev/null || true
systemctl restart sshd 2>/dev/null || systemctl restart ssh

# ── Remove dropbear completely ─────────────────────────
info "Removing Dropbear..."
apt-get -y --purge remove dropbear 2>/dev/null || true
rm -f /etc/issue.net /etc/default/dropbear

# ── Remove nginx ───────────────────────────────────────
info "Removing Nginx..."
apt-get -y --purge remove nginx nginx-common nginx-core 2>/dev/null || true
rm -rf /etc/nginx

# ── Remove WireGuard packages ──────────────────────────
info "Removing WireGuard..."
apt-get -y --purge remove wireguard wireguard-tools 2>/dev/null || true

# ── Remove L2TP/IPsec packages ─────────────────────────
info "Removing L2TP/IPsec..."
apt-get -y --purge remove xl2tpd pptpd libreswan 2>/dev/null || true
rm -rf /usr/local/lib/ipsec /usr/local/sbin/ipsec /usr/local/libexec/ipsec 2>/dev/null
rm -f /etc/ipsec.conf /etc/ipsec.secrets /etc/xl2tpd/xl2tpd.conf 2>/dev/null
rm -rf /etc/ipsec.d /etc/xl2tpd 2>/dev/null
rm -f /etc/ppp/options.xl2tpd /etc/pptpd.conf /etc/ppp/options.pptpd 2>/dev/null
rm -f /etc/systemd/system/multi-user.target.wants/ipsec.service 2>/dev/null

# ── Clean iptables ─────────────────────────────────────
info "Cleaning iptables rules..."
iptables -F 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -X 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
iptables -t mangle -X 2>/dev/null || true

# Restore default policies
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

save_iptables() {
    iptables-save > /etc/iptables.up.rules 2>/dev/null || true
    netfilter-persistent save 2>/dev/null || true
}
save_iptables

# ── Unstick resolv.conf ────────────────────────────────
chattr -i /etc/resolv.conf 2>/dev/null || true

# ── apt cleanup ────────────────────────────────────────
info "Cleaning apt..."
apt-get autoremove -y -qq 2>/dev/null || true

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  KUROVPN has been uninstalled.${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  Note: User SSH accounts and files in /home/ were not removed."
echo "  Note: System packages (curl, nginx, etc.) are preserved."
echo "        Run 'apt-get autoremove --purge' to clean if needed."
echo ""
