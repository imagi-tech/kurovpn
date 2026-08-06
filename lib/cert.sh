#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/cert.sh — TLS certificate issuance via acme.sh (official)

source "$SCRIPT_DIR/lib/common.sh"

CERT_DIR="/etc/xray"

# ── Install acme.sh from official source ───────────────
install_acme() {
    log_info "Installing acme.sh (official)"
    if [[ -d /root/.acme.sh ]]; then
        log_info "acme.sh already installed, skipping"
        return
    fi
    local acme_installer
    acme_installer=$(mktemp)
    curl -sL https://get.acme.sh -o "$acme_installer"
    bash "$acme_installer" 2>&1 | grep -v "^#" || true
    rm -f "$acme_installer"

    /root/.acme.sh/acme.sh --upgrade --auto-upgrade 2>/dev/null || true
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null || true
    log_info "acme.sh ready"
}

# ── Issue TLS certificate ──────────────────────────────
issue_cert() {
    local domain="$1" ipv="$2"

    log_step "Issuing TLS certificate for $domain"

    install_acme

    # Stop nginx if running (standalone mode needs port 80)
    svc_stop nginx 2>/dev/null || true

    local issue_args="--issue -d $domain --standalone -k ec-256"
    if [[ "$ipv" == "6" ]]; then
        issue_args="$issue_args --listen-v6"
    fi

    log_info "Requesting certificate (this may take a moment)..."
    /root/.acme.sh/acme.sh $issue_args 2>&1 || die "Certificate issuance failed for $domain"

    # Install certs to /etc/xray/
    mkdir -p "$CERT_DIR"
    /root/.acme.sh/acme.sh --installcert -d "$domain" \
        --fullchainpath "$CERT_DIR/xray.crt" \
        --keypath "$CERT_DIR/xray.key" \
        --ecc 2>&1 || die "Certificate installation failed"

    chmod 644 "$CERT_DIR/xray.crt" 2>/dev/null || true
    chmod 600 "$CERT_DIR/xray.key" 2>/dev/null || true

    log_info "Certificate installed to $CERT_DIR/"
}
