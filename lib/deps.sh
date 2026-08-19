#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/deps.sh — system dependency installation

source "$SCRIPT_DIR/lib/common.sh"

install_deps() {
    log_step "Installing system dependencies"

    apt-get update -y -qq

    local packages=(
        curl wget
        unzip zip
        jq
        net-tools
        socat
        htop
        figlet
        ruby
        dos2unix
        lsb-release
        speedtest-cli
        inetutils-ping
        iptables
        iptables-persistent
        netfilter-persistent
        nginx
        dropbear
        openssl
        libreadline-dev
        zlib1g-dev
        libssl-dev
        apt-transport-https
        libxml-parser-perl
        libpcre3-dev
        make cmake g++ gcc
        build-essential
        python3 python3-pip
        binutils
        qrencode
        vnstat
    )

    # Install ruby's lolcat gem
    apt-get install -y -qq ruby 2>/dev/null || true
    gem install lolcat 2>/dev/null || true

    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections

    for pkg in "${packages[@]}"; do
        if dpkg -s "$pkg" &>/dev/null; then
            log_info "Already installed: $pkg"
        else
            apt-get install -y -qq "$pkg" 2>/dev/null || log_warn "Could not install $pkg"
        fi
    done

    # Ensure /etc/nginx/logs exists
    mkdir -p /etc/nginx/logs
    touch /etc/nginx/logs/error.log
    chmod 777 /etc/nginx/logs/error.log

    # Remove interfering packages
    log_info "Removing conflicting packages..."
    apt-get -y --purge remove apache2* samba* bind9* sendmail* unscd 2>/dev/null || true
    apt-get autoremove -y -qq 2>/dev/null || true
    apt-get autoclean -y -qq 2>/dev/null || true

    log_info "System dependencies ready"
}

# ── Create KUROVPN directory tree ──────────────────────
create_dirs() {
    log_step "Creating directory structure"

    mkdir -p /etc/kurovpn/ssl
    mkdir -p /etc/kurovpn/users
    mkdir -p /etc/xray
    mkdir -p /etc/funny/limit/ssh/ip
    mkdir -p /etc/funny/limit/xray/ip
    mkdir -p /etc/funny/limit/xray/quota
    mkdir -p /etc/slowdns
    mkdir -p /etc/websocket
    mkdir -p /etc/v2ray
    mkdir -p /etc/noobzvpns
    mkdir -p /var/log/xray
    mkdir -p /var/lib/crot
    mkdir -p /home/vps/public_html

    touch /var/log/xray/{access,error,akses}.log
    chmod +x /var/log/xray/*.log 2>/dev/null || true

    touch /etc/funny/.l2tp /etc/funny/.noob /etc/funny/.wg
    touch /etc/funny/limit/ssh/ip/syslog
    echo "9999999" > /etc/funny/limit/ssh/ip/syslog

    log_info "Directories created"
}
