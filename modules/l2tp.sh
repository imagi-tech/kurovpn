#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/l2tp.sh -- L2TP/IPsec + PPTP installation

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/net.sh"

VPN_IPSEC_PSK="kurovpn-psk"
L2TP_USER="vpnuser"
L2TP_PASS=""

compile_libreswan() {
    log_info "Compiling Libreswan 3.32"
    if /usr/local/sbin/ipsec --version 2>/dev/null | grep -q "3.32"; then
        log_info "Libreswan 3.32 already installed"
        return
    fi

    mkdir -p /opt/src
    cd /opt/src

    local swan_file="libreswan-3.32.tar.gz"
    wget -t 3 -T 30 -nv -O "$swan_file" "https://github.com/libreswan/libreswan/archive/v3.32.tar.gz" \
        || wget -t 3 -T 30 -nv -O "$swan_file" "https://download.libreswan.org/$swan_file" \
        || die "Failed to download Libreswan"

    rm -rf /opt/src/libreswan-3.32
    tar xzf "$swan_file" && rm -f "$swan_file"
    cd libreswan-3.32 || die "Failed to enter libreswan directory"

    cat > Makefile.inc.local << 'MAKE_EOF'
WERROR_CFLAGS = -w
USE_DNSSEC = false
USE_DH2 = true
USE_DH31 = false
USE_NSS_AVA_COPY = true
USE_NSS_IPSEC_PROFILE = false
USE_GLIBC_KERN_FLIP_HEADERS = true
MAKE_EOF

    if ! grep -qs IFLA_XFRM_LINK /usr/include/linux/if_link.h; then
        echo "USE_XFRM_INTERFACE_IFLA_HEADER = true" >> Makefile.inc.local
    fi

    local nprocs
    nprocs=$(nproc)
    make -j"$nprocs" -s base && make -s install-base || die "Libreswan build failed"

    cd /opt/src
    rm -rf /opt/src/libreswan-3.32

    if ! /usr/local/sbin/ipsec --version 2>/dev/null | grep -qF "3.32"; then
        die "Libreswan 3.32 failed to build"
    fi
    log_info "Libreswan 3.32 compiled successfully"
}

install_l2tp() {
    log_step "Installing L2TP/IPsec + PPTP"

    local pub_ip=$(get_public_ip)
    local net_iface=$(get_default_iface)

    L2TP_PASS=$(openssl rand -hex 8 2>/dev/null || echo "changeme123")

    apt-get install -y -qq openssl xl2tpd pptpd \
        libnss3-dev libnspr4-dev pkg-config libpam0g-dev \
        libcap-ng-dev libcap-ng-utils libselinux1-dev \
        libcurl4-nss-dev flex bison gcc make libnss3-tools \
        libevent-dev ppp libsystemd-dev 2>/dev/null || true

    compile_libreswan

    local l2tp_net="192.168.42.0/24"
    local l2tp_local="192.168.42.1"
    local l2tp_pool="192.168.42.10-192.168.42.250"
    local xauth_net="192.168.43.0/24"
    local xauth_pool="192.168.43.10-192.168.43.250"

    # ipsec.conf
    cat > /etc/ipsec.conf << IPSEC_EOF
version 2.0
config setup
  virtual-private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!${l2tp_net},%v4:!${xauth_net}
  protostack=netkey
  interfaces=%defaultroute
  uniqueids=no
conn shared
  left=%defaultroute
  leftid=${pub_ip}
  right=%any
  encapsulation=yes
  authby=secret
  pfs=no
  rekey=no
  keyingtries=5
  dpddelay=30
  dpdtimeout=120
  dpdaction=clear
  ikev2=never
  ike=aes256-sha2,aes128-sha2,aes256-sha1,aes128-sha1,aes256-sha2;modp1024,aes128-sha1;modp1024
  phase2alg=aes_gcm-null,aes128-sha1,aes256-sha1,aes256-sha2_512,aes128-sha2,aes256-sha2
  sha2-truncbug=no
conn l2tp-psk
  auto=add
  leftprotoport=17/1701
  rightprotoport=17/%any
  type=transport
  phase2=esp
  also=shared
conn xauth-psk
  auto=add
  leftsubnet=0.0.0.0/0
  rightaddresspool=${xauth_pool}
  modecfgdns=8.8.8.8,8.8.4.4
  leftxauthserver=yes
  rightxauthclient=yes
  leftmodecfgserver=yes
  rightmodecfgclient=yes
  modecfgpull=yes
  xauthby=file
  ike-frag=yes
  cisco-unity=yes
  also=shared
include /etc/ipsec.d/*.conf
IPSEC_EOF

    echo "%any  %any  : PSK \"$VPN_IPSEC_PSK\"" > /etc/ipsec.secrets

    # xl2tpd
    cat > /etc/xl2tpd/xl2tpd.conf << EOF
[global]
port = 1701
[lns default]
ip range = $l2tp_pool
local ip = $l2tp_local
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat > /etc/ppp/options.xl2tpd << 'EOF'
+mschap-v2
ipcp-accept-local
ipcp-accept-remote
noccp
auth
mtu 1280
mru 1280
proxyarp
lcp-echo-failure 4
lcp-echo-interval 30
connect-delay 5000
ms-dns 8.8.8.8
ms-dns 8.8.4.4
EOF

    # PPTP
    cat > /etc/pptpd.conf << EOF
option /etc/ppp/options.pptpd
logwtmp
localip 192.168.41.1
remoteip 192.168.41.10-100
EOF

    cat > /etc/ppp/options.pptpd << 'EOF'
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
ms-dns 8.8.8.8
ms-dns 8.8.4.4
proxyarp
lock
nobsdcomp
novj
novjccomp
nologfd
EOF

    # Create default L2TP user
    local pass_enc=$(openssl passwd -1 "$L2TP_PASS")
    echo "$L2TP_USER l2tpd $L2TP_PASS *" > /etc/ppp/chap-secrets
    echo "$L2TP_USER:$pass_enc:xauth-psk" > /etc/ipsec.d/passwd

    # iptables
    iptables -t nat -I POSTROUTING -s "$l2tp_net" -o "$net_iface" -j MASQUERADE 2>/dev/null || true
    iptables -t nat -I POSTROUTING -s "$xauth_net" -o "$net_iface" -j MASQUERADE 2>/dev/null || true
    iptables -t nat -I POSTROUTING -s 192.168.41.0/24 -o "$net_iface" -j MASQUERADE 2>/dev/null || true
    save_iptables

    chmod 600 /etc/ipsec.secrets /etc/ppp/chap-secrets /etc/ipsec.d/passwd 2>/dev/null || true

    svc_enable xl2tpd
    svc_enable ipsec
    svc_enable pptpd
    svc_restart xl2tpd
    svc_restart ipsec
    svc_restart pptpd

    log_info "L2TP/IPsec installed. Default user: $L2TP_USER / $L2TP_PASS (PSK: $VPN_IPSEC_PSK)"
    log_info "PPTP installed (use add-l2tp to create more users)"
}
