#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/users.sh — central user database (/etc/kurovpn/users.json)
#
#  Schema:
#  {
#    "vmess": [],
#    "vless": [],
#    "trojan": [],
#    "shadowsocks": [],
#    "ssh": [],
#    "l2tp": [],
#    "wireguard": [],
#    "noobzvpns": []
#  }

source "$SCRIPT_DIR/lib/common.sh"

USERS_FILE="/etc/kurovpn/users.json"

# ── Initialize users.json if it doesn't exist ───────────
init_users_db() {
    if [[ ! -f "$USERS_FILE" ]]; then
        cat > "$USERS_FILE" << 'EOF'
{
  "vmess": [],
  "vless": [],
  "trojan": [],
  "shadowsocks": [],
  "ssh": [],
  "l2tp": [],
  "wireguard": [],
  "noobzvpns": []
}
EOF
        chmod 600 "$USERS_FILE"
        log_info "Initialized user database: $USERS_FILE"
    fi
}

# ── Add a user entry ───────────────────────────────────
# $1: protocol (vmess|vless|trojan|shadowsocks|ssh|l2tp|wireguard|noobzvpns)
# $2: username
# $3: expiry date (YYYY-MM-DD)
# $4: extra JSON fields (e.g. '"uuid":"abc-123","email":"bob"')
users_add() {
    local proto="$1" user="$2" exp="$3" extra="$4"
    local today
    today=$(date +%Y-%m-%d)

    if [[ -z "$extra" ]]; then
        extra=''
    else
        extra=",$extra"
    fi

    local entry
    entry=$(jq -n --arg u "$user" --arg e "$exp" --arg c "$today" \
        '{user: $u, exp: $e, created: $c}' \
        | sed 's/}$//')
    if [[ -n "$extra" ]]; then
        entry="${entry}${extra}}"
    else
        entry="${entry}}"
    fi

    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --argjson entry "$entry" --arg proto "$proto" \
        '.[$proto] += [$entry]' "$USERS_FILE" > "$tmpfile"
    mv "$tmpfile" "$USERS_FILE"
    chmod 600 "$USERS_FILE"
}

# ── Remove a user entry ────────────────────────────────
users_del() {
    local proto="$1" user="$2"
    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --arg proto "$proto" --arg user "$user" \
        '.[$proto] |= map(select(.user != $user))' "$USERS_FILE" > "$tmpfile"
    mv "$tmpfile" "$USERS_FILE"
    chmod 600 "$USERS_FILE"
}

# ── List users for a protocol ──────────────────────────
users_list() {
    local proto="$1"
    jq -r ".\"$proto\"[] | .user + \" \" + .exp" "$USERS_FILE" 2>/dev/null
}

# ── Get expired users (relative to today) ──────────────
users_get_expired() {
    local now
    now=$(date +%Y-%m-%d)
    jq -r --arg now "$now" '
        to_entries[] | .key as $proto |
        .value[] | select(.exp < $now) |
        "\($proto) \(.user) \(.exp)"
    ' "$USERS_FILE" 2>/dev/null
}

# ── Check if user exists ───────────────────────────────
users_exists() {
    local proto="$1" user="$2"
    local count
    count=$(jq --arg proto "$proto" --arg user "$user" \
        '.[$proto] | map(select(.user == $user)) | length' "$USERS_FILE")
    [[ "$count" -gt 0 ]]
}
