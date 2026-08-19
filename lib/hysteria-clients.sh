#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/hysteria-clients.sh — jq-based Hysteria2 user management

HYSTERIA_CONFIG="/etc/hysteria/config.yaml"
USERS_FILE="/etc/kurovpn/users.json"

hy_regen() {
    local domain
    domain=$(cat /etc/xray/domain 2>/dev/null || echo "localhost")

    local count
    count=$(jq '.hysteria2 | length' "$USERS_FILE" 2>/dev/null || echo 0)

    local auth_yaml=""
    if [[ "$count" -gt 0 ]]; then
        auth_yaml="auth:
  type: userpass
  userpass:"
        while read -r u p; do
            [[ -z "$u" || -z "$p" ]] && continue
            auth_yaml="${auth_yaml}
    ${u}: ${p}"
        done < <(jq -r '.hysteria2[]? | "\(.user) \(.password)"' "$USERS_FILE" 2>/dev/null)
    else
        local placeholder
        placeholder=$(head -c 16 /dev/urandom 2>/dev/null | base64 -w0 2>/dev/null || openssl rand -hex 16)
        auth_yaml="auth:
  type: userpass
  userpass:
    defaultuser: ${placeholder}"
    fi

    cat > "$HYSTERIA_CONFIG" << HYCONF
server: :443
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

    chmod 600 "$HYSTERIA_CONFIG"
    systemctl restart hysteria 2>/dev/null || true
}

hy_add_user() {
    local user="$1" password="$2" exp="$3"
    local today
    today=$(date +%Y-%m-%d)

    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --arg user "$user" --arg pass "$password" --arg exp "$exp" --arg created "$today" \
        '.hysteria2 += [{"user": $user, "password": $pass, "exp": $exp, "created": $created}]' \
        "$USERS_FILE" > "$tmpfile"
    mv "$tmpfile" "$USERS_FILE"
    chmod 600 "$USERS_FILE"

    hy_regen
}

hy_del_user() {
    local user="$1"
    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --arg user "$user" \
        '.hysteria2 |= map(select(.user != $user))' \
        "$USERS_FILE" > "$tmpfile"
    mv "$tmpfile" "$USERS_FILE"
    chmod 600 "$USERS_FILE"

    hy_regen
}

hy_user_exists() {
    local user="$1"
    local count
    count=$(jq --arg user "$user" \
        '.hysteria2 | map(select(.user == $user)) | length' "$USERS_FILE")
    [[ "$count" -gt 0 ]]
}
