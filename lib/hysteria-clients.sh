#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/hysteria-clients.sh — jq-based Hysteria2 user management

HYSTERIA_CONFIG="/etc/hysteria/config.yaml"
HYSTERIA_DNS_CONFIG="/etc/hysteria/config-dns.yaml"
HYSTERIA_AUTH_SCRIPT="/usr/lib/kurovpn/hy2_auth.sh"
HYSTERIA_TOKENS_FILE="/etc/hysteria/allowed_tokens.txt"
OBFS_KEY_FILE="/etc/hysteria/obfs.key"
USERS_FILE="/etc/kurovpn/users.json"

hy_ensure_auth_script() {
    mkdir -p /usr/lib/kurovpn /etc/hysteria
    cat > "$HYSTERIA_AUTH_SCRIPT" << 'AUTH_EOF'
#!/bin/bash
AUTH_STR="$2"
TOKENS_FILE="/etc/hysteria/allowed_tokens.txt"
[[ -z "$AUTH_STR" || ! -f "$TOKENS_FILE" ]] && exit 1
if grep -qxF "$AUTH_STR" "$TOKENS_FILE" 2>/dev/null; then
    exit 0
fi
exit 1
AUTH_EOF
    chmod 755 "$HYSTERIA_AUTH_SCRIPT"
}

hy_get_obfs_key() {
    if [[ -s "$OBFS_KEY_FILE" ]]; then
        tr -d '\r\n ' < "$OBFS_KEY_FILE"
        return
    fi
    mkdir -p /etc/hysteria
    local key
    key=$(openssl rand -hex 8 2>/dev/null || head -c 8 /dev/urandom | xxd -p 2>/dev/null || echo "kuro$(openssl rand -hex 6)")
    echo -n "$key" > "$OBFS_KEY_FILE"
    chmod 600 "$OBFS_KEY_FILE"
    echo -n "$key"
}

hy_regen() {
    local domain
    domain=$(cat /etc/xray/domain 2>/dev/null || echo "localhost")

    hy_ensure_auth_script

    # Populate token file supporting both single-password and username:password clients (e.g. Happ/sing-box)
    local tmp_tokens="${HYSTERIA_TOKENS_FILE}.tmp.$$"
    > "$tmp_tokens"
    while read -r u p; do
        [[ -z "$p" ]] && continue
        echo "$p" >> "$tmp_tokens"
        [[ -n "$u" ]] && echo "${u}:${p}" >> "$tmp_tokens"
        [[ -n "$u" ]] && echo "${u}" >> "$tmp_tokens"
    done < <(jq -r '.hysteria2[]? | "\(.user) \(.password)"' "$USERS_FILE" 2>/dev/null)

    if [[ ! -s "$tmp_tokens" ]]; then
        local fallback_key
        fallback_key=$(openssl rand -hex 12 2>/dev/null || echo "kurofallback")
        echo "$fallback_key" >> "$tmp_tokens"
    fi
    mv "$tmp_tokens" "$HYSTERIA_TOKENS_FILE"
    chmod 600 "$HYSTERIA_TOKENS_FILE"

    local auth_yaml="auth:
  type: command
  command: ${HYSTERIA_AUTH_SCRIPT}"

    # 1. Standard instance (:443 UDP, un-obfuscated QUIC)
    cat > "$HYSTERIA_CONFIG" << HYCONF
listen: :443
protocol: udp

tls:
  cert: /etc/xray/xray.crt
  key: /etc/xray/xray.key

${auth_yaml}

masquerade:
  type: proxy
  proxy:
    url: https://${domain}/
    rewriteHost: true

speedTest: false
disableUDP: false
HYCONF

    # 2. Port 53 DNS Bypass instance (:53 UDP, Salamander obfuscated to bypass ISP DPI)
    local obfs_key
    obfs_key=$(hy_get_obfs_key)

    cat > "$HYSTERIA_DNS_CONFIG" << HYDNSCONF
listen: :53
protocol: udp

tls:
  cert: /etc/xray/xray.crt
  key: /etc/xray/xray.key

obfs:
  type: salamander
  salamander:
    password: ${obfs_key}

${auth_yaml}

masquerade:
  type: proxy
  proxy:
    url: https://${domain}/
    rewriteHost: true

speedTest: false
disableUDP: false
HYDNSCONF

    chmod 600 "$HYSTERIA_CONFIG" "$HYSTERIA_DNS_CONFIG"
    systemctl restart hysteria 2>/dev/null || true
    systemctl restart hysteria-dns 2>/dev/null || true
}

hy_add_user() {
    local user="$1" password="$2" exp="$3"
    local today
    today=$(date +%Y-%m-%d)

    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --arg user "$user" --arg pass "$password" --arg exp "$exp" --arg created "$today" \
        '(.hysteria2 //= []) | .hysteria2 += [{"user": $user, "password": $pass, "exp": $exp, "created": $created}]' \
        "$USERS_FILE" > "$tmpfile" 2>/dev/null
    if [[ -s "$tmpfile" ]] && jq . "$tmpfile" >/dev/null 2>&1; then
        mv "$tmpfile" "$USERS_FILE"
        chmod 600 "$USERS_FILE"
    else
        rm -f "$tmpfile"
        return 1
    fi

    hy_regen
}

hy_del_user() {
    local user="$1"
    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --arg user "$user" \
        '(.hysteria2 //= []) | .hysteria2 |= map(select(.user != $user))' \
        "$USERS_FILE" > "$tmpfile" 2>/dev/null
    if [[ -s "$tmpfile" ]] && jq . "$tmpfile" >/dev/null 2>&1; then
        mv "$tmpfile" "$USERS_FILE"
        chmod 600 "$USERS_FILE"
        source /usr/lib/kurovpn/subscription.sh 2>/dev/null || true
        sub_build_user "$user" 2>/dev/null || true
        rm -f "/var/www/html/sub/$user" "/var/www/html/sub/$user.txt" 2>/dev/null || true
    else
        rm -f "$tmpfile"
        return 1
    fi

    hy_regen
}

hy_user_exists() {
    local user="$1"
    local count
    count=$(jq --arg user "$user" \
        '.hysteria2 // [] | map(select(.user == $user)) | length' "$USERS_FILE" 2>/dev/null || echo 0)
    [[ "$count" -gt 0 ]]
}
