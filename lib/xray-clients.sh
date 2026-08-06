#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/xray-clients.sh -- jq-based Xray client management
#
#  Protocol-to-port mapping:
#    vmess:  23456 (ws), 31234 (grpc), 8001 (httpupgrade)
#    vless:  14016 (ws), 24456 (grpc), 8003 (httpupgrade)
#    trojan: 25432 (ws), 33456 (grpc), 8002 (httpupgrade)
#    ss:     10004 (ws)

XRAY_CONFIG="/etc/xray/config.json"
USERS_FILE="/etc/kurovpn/users.json"

# ── Inbound ports for each protocol ────────────────────
VMESS_PORTS=(23456 31234 8001)
VLESS_PORTS=(14016 24456 8003)
TROJAN_PORTS=(25432 33456 8002)
SS_PORTS=(10004)

get_ports() {
    case "$1" in
        vmess)  echo "${VMESS_PORTS[@]}" ;;
        vless)  echo "${VLESS_PORTS[@]}" ;;
        trojan) echo "${TROJAN_PORTS[@]}" ;;
        ss|shadowsocks) echo "${SS_PORTS[@]}" ;;
    esac
}

# ── Generate a new Xray UUID ───────────────────────────
gen_uuid() {
    /usr/bin/xray uuid 2>/dev/null || uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid
}

# ── Validate username ──────────────────────────────────
valid_username() {
    [[ "$1" =~ ^[a-zA-Z0-9_]+$ ]]
}

# ── Check if user exists in users.json ─────────────────
user_exists() {
    local proto="$1" user="$2"
    local count
    count=$(jq --arg proto "$proto" --arg user "$user" \
        '.[$proto] | map(select(.user == $user)) | length' "$USERS_FILE" 2>/dev/null || echo 0)
    [[ "$count" -gt 0 ]]
}

# ── Add a client to all inbounds of a protocol ─────────
# $1: protocol (vmess|vless|trojan|ss)
# $2: JSON client object (e.g. '{"id":"abc","email":"bob"}')
xray_add_client() {
    local proto="$1" client_json="$2"
    local ports=($(get_ports "$proto"))
    local tmpfile="${XRAY_CONFIG}.tmp.$$"

    local jq_filter="."
    for port in "${ports[@]}"; do
        jq_filter="${jq_filter} | (.inbounds[] | select(.port == ${port}) | .settings.clients) += [${client_json}]"
        jq_filter=". as \$root | \$root"
    done

    # Simpler approach: iterate ports
    cp "$XRAY_CONFIG" "$tmpfile"
    for port in "${ports[@]}"; do
        jq --argjson client "$client_json" \
            "(.inbounds[] | select(.port == $port) | .settings.clients) += [\$client]" \
            "$tmpfile" > "${tmpfile}.2"
        mv "${tmpfile}.2" "$tmpfile"
    done
    mv "$tmpfile" "$XRAY_CONFIG"
    chmod 644 "$XRAY_CONFIG"

    # Validate (warnings are OK, we only care about "Configuration OK")
    if ! /usr/bin/xray run -test -config "$XRAY_CONFIG" 2>/dev/null | grep -q "Configuration OK"; then
        echo "Error: Xray config validation failed after adding client." >&2
        return 1
    fi

    systemctl restart xray 2>/dev/null || true
}

# ── Remove a client from all inbounds by uuid/email ────
xray_del_client() {
    local proto="$1" field="$2" value="$3"
    local ports=($(get_ports "$proto"))
    local tmpfile="${XRAY_CONFIG}.tmp.$$"

    cp "$XRAY_CONFIG" "$tmpfile"
    for port in "${ports[@]}"; do
        jq --arg val "$value" \
            "(.inbounds[] | select(.port == $port) | .settings.clients) |= map(select(.\"$field\" != \$val))" \
            "$tmpfile" > "${tmpfile}.2"
        mv "${tmpfile}.2" "$tmpfile"
    done
    mv "$tmpfile" "$XRAY_CONFIG"
    chmod 644 "$XRAY_CONFIG"

    if ! /usr/bin/xray run -test -config "$XRAY_CONFIG" 2>/dev/null | grep -q "Configuration OK"; then
        echo "Error: Xray config validation failed after deleting client." >&2
        return 1
    fi

    systemctl restart xray 2>/dev/null || true
}

# ── List clients for a protocol ────────────────────────
xray_list_clients() {
    local proto="$1" port="$2"
    jq -r --argjson port "$port" \
        '.inbounds[] | select(.port == $port) | .settings.clients[] | .email' \
        "$XRAY_CONFIG" 2>/dev/null
}

# ── Count online xray users by checking access log ─────
xray_online_count() {
    grep -c "accepted" /var/log/xray/access.log 2>/dev/null || echo 0
}

# ── Helper: create client JSON based on protocol ───────
make_vmess_client() { echo "{\"id\":\"$1\",\"alterId\":0,\"email\":\"$2\"}"; }
make_vless_client() { echo "{\"id\":\"$1\",\"email\":\"$2\"}"; }
make_trojan_client() { echo "{\"password\":\"$1\",\"email\":\"$2\"}"; }
make_ss_client() { echo "{\"password\":\"$1\",\"method\":\"aes-128-gcm\",\"email\":\"$2\"}"; }

# ── User database helpers ───────────────────────────────
users_add() {
    local proto="$1" user="$2" exp="$3" extra="$4"
    local today=$(date +%Y-%m-%d)
    local entry='{"user":"'"$user"'","exp":"'"$exp"'","created":"'"$today"'"'
    [[ -n "$extra" ]] && entry="$entry,$extra"
    entry="$entry}"
    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --argjson entry "$entry" --arg proto "$proto" \
        '.[$proto] += [$entry]' "$USERS_FILE" > "$tmpfile"
    mv "$tmpfile" "$USERS_FILE"
    chmod 600 "$USERS_FILE"
}

users_del() {
    local proto="$1" user="$2"
    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --arg proto "$proto" --arg user "$user" \
        '.[$proto] |= map(select(.user != $user))' "$USERS_FILE" > "$tmpfile"
    mv "$tmpfile" "$USERS_FILE"
    chmod 600 "$USERS_FILE"
}
