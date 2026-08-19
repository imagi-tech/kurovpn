#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/subscription.sh — Dynamic client subscription engine

SUB_DIR="/var/www/html/sub"
USERS_FILE="/etc/kurovpn/users.json"
DOMAIN_FILE="/etc/xray/domain"

sub_init() {
    mkdir -p "$SUB_DIR" 2>/dev/null || true
    chmod 755 "$SUB_DIR" 2>/dev/null || true
}

sub_get_domain() {
    cat "$DOMAIN_FILE" 2>/dev/null || curl -s ifconfig.me || echo "localhost"
}

# Generate subscription files for a single user
sub_build_user() {
    local user="$1"
    [[ -z "$user" ]] && return 1
    
    sub_init
    local domain
    domain=$(sub_get_domain)
    
    local links=()

    # 1. VMess
    local vmess_uuid
    vmess_uuid=$(jq -r --arg u "$user" '.vmess[]? | select(.user == $u) | .uuid' "$USERS_FILE" 2>/dev/null | head -1)
    if [[ -n "$vmess_uuid" && "$vmess_uuid" != "null" ]]; then
        local v_tls v_grpc v_http
        v_tls=$(jq -nc --arg u "$user-VMess-TLS" --arg d "$domain" --arg id "$vmess_uuid" \
            '{v:"2",ps:$u,add:$d,port:"443",id:$id,aid:"0",net:"ws",path:"/vmess",type:"none",host:$d,tls:"tls"}' | base64 -w 0)
        v_grpc=$(jq -nc --arg u "$user-VMess-gRPC" --arg d "$domain" --arg id "$vmess_uuid" \
            '{v:"2",ps:$u,add:$d,port:"443",id:$id,aid:"0",net:"grpc",path:"vmess-grpc",type:"none",host:$d,tls:"tls"}' | base64 -w 0)
        v_http=$(jq -nc --arg u "$user-VMess-HTTP" --arg d "$domain" --arg id "$vmess_uuid" \
            '{v:"2",ps:$u,add:$d,port:"80",id:$id,aid:"0",net:"ws",path:"/vmess",type:"none",host:$d,tls:"none"}' | base64 -w 0)
        links+=("vmess://$v_tls")
        links+=("vmess://$v_grpc")
        links+=("vmess://$v_http")
    fi

    # 2. VLess
    local vless_uuid
    vless_uuid=$(jq -r --arg u "$user" '.vless[]? | select(.user == $u) | .uuid' "$USERS_FILE" 2>/dev/null | head -1)
    if [[ -n "$vless_uuid" && "$vless_uuid" != "null" ]]; then
        links+=("vless://${vless_uuid}@${domain}:443?path=/vless&security=tls&encryption=none&host=${domain}&type=ws&sni=${domain}#${user}-VLess-WS")
        links+=("vless://${vless_uuid}@${domain}:443?mode=gun&security=tls&encryption=none&authority=${domain}&type=grpc&serviceName=vless-grpc&sni=${domain}#${user}-VLess-gRPC")
        links+=("vless://${vless_uuid}@${domain}:80?path=/vless&security=none&encryption=none&host=${domain}&type=ws#${user}-VLess-NTLS")
    fi

    # 3. Reality (VLess XTLS Vision)
    local reality_uuid
    reality_uuid=$(jq -r --arg u "$user" '.reality[]? | select(.user == $u) | .uuid' "$USERS_FILE" 2>/dev/null | head -1)
    if [[ -n "$reality_uuid" && "$reality_uuid" != "null" ]]; then
        local pbk
        pbk=$(cat /etc/xray/reality-pub 2>/dev/null || echo "")
        links+=("vless://${reality_uuid}@${domain}:8443?security=reality&encryption=none&pbk=${pbk}&headerType=none&type=tcp&flow=xtls-rprx-vision&sni=www.microsoft.com#${user}-VLess-REALITY")
    fi

    # 4. Trojan
    local trojan_pass
    trojan_pass=$(jq -r --arg u "$user" '.trojan[]? | select(.user == $u) | .password // .user' "$USERS_FILE" 2>/dev/null | head -1)
    if [[ -n "$trojan_pass" && "$trojan_pass" != "null" ]]; then
        links+=("trojan://${trojan_pass}@${domain}:443?path=%2ftrojan&security=tls&host=${domain}&type=ws&sni=${domain}#${user}-Trojan-WS")
        links+=("trojan://${trojan_pass}@${domain}:443?mode=gun&security=tls&authority=${domain}&type=grpc&serviceName=trojan-grpc&sni=${domain}#${user}-Trojan-gRPC")
    fi

    # 5. Shadowsocks 2022
    local ss2022_pass
    ss2022_pass=$(jq -r --arg u "$user" '.ss2022[]? | select(.user == $u) | .password' "$USERS_FILE" 2>/dev/null | head -1)
    if [[ -n "$ss2022_pass" && "$ss2022_pass" != "null" ]]; then
        local ss_enc
        ss_enc=$(echo -n "2022-blake3-aes-128-gcm:${ss2022_pass}" | base64 -w 0)
        links+=("ss://${ss_enc}@${domain}:10010#${user}-SS-2022")
    fi

    # 6. Hysteria 2
    local hy2_pass
    hy2_pass=$(jq -r --arg u "$user" '.hysteria2[]? | select(.user == $u) | .password // .auth' "$USERS_FILE" 2>/dev/null | head -1)
    if [[ -n "$hy2_pass" && "$hy2_pass" != "null" ]]; then
        links+=("hy2://${hy2_pass}@${domain}:443?sni=${domain}&insecure=0#${user}-Hysteria2")
    fi

    # If no links generated, clean up and exit
    if [[ ${#links[@]} -eq 0 ]]; then
        rm -f "$SUB_DIR/$user" "$SUB_DIR/$user.txt" 2>/dev/null || true
        return 0
    fi

    # Write raw plain text file
    printf "%s\n" "${links[@]}" > "$SUB_DIR/$user.txt"
    
    # Write Base64 encoded subscription file (for V2Ray / Shadowrocket / NekoBox)
    printf "%s\n" "${links[@]}" | base64 -w 0 > "$SUB_DIR/$user"
    
    chmod 644 "$SUB_DIR/$user" "$SUB_DIR/$user.txt" 2>/dev/null || true
}

sub_remove_user() {
    local user="$1"
    rm -f "$SUB_DIR/$user" "$SUB_DIR/$user.txt" 2>/dev/null || true
}

sub_update_all() {
    sub_init
    [[ ! -f "$USERS_FILE" ]] && return 0
    
    local all_users
    all_users=$(jq -r 'to_entries[].value[]?.user' "$USERS_FILE" 2>/dev/null | sort -u)
    for u in $all_users; do
        sub_build_user "$u"
    done
}

sub_url() {
    local user="$1"
    local domain
    domain=$(sub_get_domain)
    echo "https://${domain}/sub/${user}"
}
