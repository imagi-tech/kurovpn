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
#    "reality": [],
#    "ss2022": [],
#    "hysteria2": [],
#    "ssh": [],
#    "proxy": [],
#    "wireguard": [],
#    "noobzvpns": []
#  }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || source /usr/lib/kurovpn/common.sh 2>/dev/null || true

USERS_FILE="${USERS_FILE:-/etc/kurovpn/users.json}"

# ── Initialize users.json if it doesn't exist ───────────
init_users_db() {
    mkdir -p "$(dirname "$USERS_FILE")" 2>/dev/null || true
    if [[ ! -f "$USERS_FILE" ]] || ! jq empty "$USERS_FILE" 2>/dev/null; then
        cat > "$USERS_FILE" << 'EOF'
{
  "vmess": [],
  "vless": [],
  "trojan": [],
  "shadowsocks": [],
  "reality": [],
  "ss2022": [],
  "hysteria2": [],
  "ssh": [],
  "proxy": [],
  "wireguard": [],
  "noobzvpns": []
}
EOF
        chmod 600 "$USERS_FILE"
        log_info "Initialized user database: $USERS_FILE" 2>/dev/null || true
    fi
}

# ── Validate username ──────────────────────────────────
valid_username() {
    [[ "$1" =~ ^[a-zA-Z0-9_]+$ ]]
}

# ── Check if user exists ───────────────────────────────
user_exists() {
    local proto="$1" user="$2"
    [[ "$proto" == "ss" ]] && proto="shadowsocks"
    [[ ! -f "$USERS_FILE" ]] && return 1
    local count
    count=$(jq --arg proto "$proto" --arg user "$user" \
        '.[$proto] // [] | map(select(.user == $user)) | length' "$USERS_FILE" 2>/dev/null || echo 0)
    [[ "$count" -gt 0 ]]
}

users_exists() {
    user_exists "$@"
}

# ── Add a user entry ───────────────────────────────────
# $1: protocol (vmess|vless|trojan|shadowsocks|ssh|proxy|wireguard|noobzvpns|reality|ss2022|hysteria2)
# $2: username
# $3: expiry date (YYYY-MM-DD)
# $4: extra JSON fields (e.g. '"uuid":"abc-123","email":"bob"')
users_add() {
    local proto="$1" user="$2" exp="$3" extra="$4"
    [[ "$proto" == "ss" ]] && proto="shadowsocks"
    local today
    today=$(date +%Y-%m-%d)

    init_users_db

    local entry
    entry=$(jq -n --arg u "$user" --arg e "$exp" --arg c "$today" \
        '{user: $u, exp: $e, created: $c}' | sed 's/}$//')
    if [[ -n "$extra" ]]; then
        extra="${extra#,}"
        entry="${entry},${extra}}"
    else
        entry="${entry}}"
    fi

    # Validate JSON syntax before writing
    if ! echo "$entry" | jq empty >/dev/null 2>&1; then
        echo "Error: users_add: invalid JSON generated for user $user" >&2
        return 1
    fi

    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --argjson entry "$entry" --arg proto "$proto" \
        '.[$proto] = ((.[$proto] // []) + [$entry])' "$USERS_FILE" > "$tmpfile" 2>/dev/null

    if [[ -s "$tmpfile" ]] && jq empty "$tmpfile" >/dev/null 2>&1; then
        mv "$tmpfile" "$USERS_FILE"
        chmod 600 "$USERS_FILE"
    else
        rm -f "$tmpfile"
        echo "Error: users_add: failed to update $USERS_FILE for user $user" >&2
        return 1
    fi

    # Auto-generate subscription links
    source /usr/lib/kurovpn/subscription.sh 2>/dev/null || source "$SCRIPT_DIR/lib/subscription.sh" 2>/dev/null || true
    sub_build_user "$user" 2>/dev/null || true
}

# ── Remove a user entry ────────────────────────────────
users_del() {
    local proto="$1" user="$2"
    [[ "$proto" == "ss" ]] && proto="shadowsocks"

    init_users_db

    local tmpfile="${USERS_FILE}.tmp.$$"
    jq --arg proto "$proto" --arg user "$user" \
        '.[$proto] |= (if . then map(select(.user != $user)) else [] end)' "$USERS_FILE" > "$tmpfile" 2>/dev/null

    if [[ -s "$tmpfile" ]] && jq empty "$tmpfile" >/dev/null 2>&1; then
        mv "$tmpfile" "$USERS_FILE"
        chmod 600 "$USERS_FILE"
    else
        rm -f "$tmpfile"
        echo "Error: users_del: failed to update $USERS_FILE for user $user" >&2
        return 1
    fi

    # Update or remove subscription links
    source /usr/lib/kurovpn/subscription.sh 2>/dev/null || source "$SCRIPT_DIR/lib/subscription.sh" 2>/dev/null || true
    local remaining
    remaining=$(jq -r --arg user "$user" '[to_entries[].value[]? | select(.user == $user)] | length' "$USERS_FILE" 2>/dev/null || echo 0)
    if [[ "$remaining" -eq 0 ]]; then
        rm -f "/var/www/html/sub/$user" "/var/www/html/sub/$user.txt" 2>/dev/null || true
    else
        sub_build_user "$user" 2>/dev/null || true
    fi
}

# ── List users for a protocol ──────────────────────────
users_list() {
    local proto="$1"
    [[ "$proto" == "ss" ]] && proto="shadowsocks"
    jq -r ".\"$proto\"[]? | .user + \" \" + .exp" "$USERS_FILE" 2>/dev/null
}

# ── Get expired users (relative to today) ──────────────
users_get_expired() {
    local now
    now=$(date +%Y-%m-%d)
    jq -r --arg now "$now" '
        to_entries[] | .key as $proto |
        .value[]? | select(.exp < $now) |
        "\($proto) \(.user) \(.exp)"
    ' "$USERS_FILE" 2>/dev/null
}
