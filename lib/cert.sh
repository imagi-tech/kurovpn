#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/cert.sh — TLS certificate issuance via acme.sh (official)

source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || source /usr/lib/kurovpn/common.sh 2>/dev/null || true

CERT_DIR="/etc/xray"

# ── Wrapper to execute acme.sh with pinned root environment ────
run_acme() {
    export HOME=/root
    export LE_CONFIG_HOME="/root/.acme.sh"
    /root/.acme.sh/acme.sh --home /root/.acme.sh --config-home /root/.acme.sh "$@"
}

# ── Install acme.sh from official source ───────────────
install_acme() {
    log_info "Installing acme.sh (official)"
    if [[ -d /root/.acme.sh && -f /root/.acme.sh/acme.sh ]]; then
        log_info "acme.sh already installed, verifying CA"
        run_acme --set-default-ca --server letsencrypt 2>/dev/null || true
        return
    fi
    local acme_installer
    acme_installer=$(mktemp)
    curl -sL https://get.acme.sh -o "$acme_installer"
    HOME=/root bash "$acme_installer" 2>&1 | grep -v "^#" || true
    rm -f "$acme_installer"

    run_acme --upgrade --auto-upgrade 2>/dev/null || true
    run_acme --set-default-ca --server letsencrypt 2>/dev/null || true
    log_info "acme.sh ready"
}

# ── Issue TLS certificate ──────────────────────────────
issue_cert() {
    local domain="$1" ipv="$2" force="${3:-false}"

    # Skip if cert already exists and is valid and renewal is not forced
    if [[ "$force" != "true" && -s "$CERT_DIR/xray.crt" && -s "$CERT_DIR/xray.key" ]] && openssl x509 -in "$CERT_DIR/xray.crt" -noout -checkend 86400 &>/dev/null; then
        log_info "Certificate already exists and is valid for $domain"
        return 0
    fi

    log_step "Issuing TLS certificate for $domain"

    install_acme

    # Backup existing certificates in case renewal fails
    [[ -s "$CERT_DIR/xray.crt" ]] && cp -p "$CERT_DIR/xray.crt" "$CERT_DIR/xray.crt.bak" 2>/dev/null || true
    [[ -s "$CERT_DIR/xray.key" ]] && cp -p "$CERT_DIR/xray.key" "$CERT_DIR/xray.key.bak" 2>/dev/null || true

    svc_stop nginx 2>/dev/null || true

    local issue_args="--issue -d $domain --standalone -k ec-256 --server letsencrypt"
    if [[ "$ipv" == "6" ]]; then
        issue_args="$issue_args --listen-v6"
    fi
    if [[ "$force" == "true" ]]; then
        issue_args="$issue_args --force"
    fi

    log_info "Requesting certificate (this may take a moment)..."
    mkdir -p "$CERT_DIR"

    local issue_ok=false
    if run_acme $issue_args 2>&1; then
        if run_acme --installcert -d "$domain" \
            --fullchainpath "$CERT_DIR/xray.crt" \
            --keypath "$CERT_DIR/xray.key" \
            --ecc 2>&1; then
            if [[ -s "$CERT_DIR/xray.crt" && -s "$CERT_DIR/xray.key" ]]; then
                issue_ok=true
            fi
        fi
    fi

    if [[ "$issue_ok" != "true" ]]; then
        log_warn "ACME cert install did not produce certificate. Checking recovery..."
        if [[ -s "$CERT_DIR/xray.crt.bak" && -s "$CERT_DIR/xray.key.bak" ]]; then
            log_info "Restoring previous working certificate from backup..."
            cp -p "$CERT_DIR/xray.crt.bak" "$CERT_DIR/xray.crt"
            cp -p "$CERT_DIR/xray.key.bak" "$CERT_DIR/xray.key"
        fi
        if [[ ! -s "$CERT_DIR/xray.crt" || ! -s "$CERT_DIR/xray.key" ]]; then
            log_warn "Generating self-signed fallback certificate..."
            openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
                -keyout "$CERT_DIR/xray.key" -out "$CERT_DIR/xray.crt" \
                -days 365 -subj "/CN=$domain" 2>/dev/null || \
            openssl req -x509 -nodes -newkey rsa:2048 \
                -keyout "$CERT_DIR/xray.key" -out "$CERT_DIR/xray.crt" \
                -days 365 -subj "/CN=$domain" 2>/dev/null || true
        fi
    fi

    rm -f "$CERT_DIR/xray.crt.bak" "$CERT_DIR/xray.key.bak" 2>/dev/null || true
    chmod 644 "$CERT_DIR/xray.crt" 2>/dev/null || true
    chmod 600 "$CERT_DIR/xray.key" 2>/dev/null || true

    log_info "Certificate ready in $CERT_DIR/"
}
