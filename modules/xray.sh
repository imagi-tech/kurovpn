#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/xray.sh — Official Xray-core install + valid JSON config generation

source "$SCRIPT_DIR/lib/common.sh"

XRAY_VERSION="24.12.18"
XRAY_CONFIG="/etc/xray/config.json"

REALITY_PRIVKEY="/etc/xray/reality-key"
REALITY_PUBFILE="/etc/xray/reality-pub"

gen_reality_keys() {
    if [[ -f "$REALITY_PRIVKEY" && -f "$REALITY_PUBFILE" ]]; then
        REALITY_PUBKEY=$(cut -d' ' -f1 "$REALITY_PUBFILE" 2>/dev/null)
        REALITY_SHORTID=$(cut -d' ' -f2 "$REALITY_PUBFILE" 2>/dev/null)
        if [[ -n "$REALITY_PUBKEY" && -n "$REALITY_SHORTID" ]]; then
            log_info "Reality keypair already exists"
            return
        fi
    fi
    log_info "Generating Reality x25519 keypair"
    local keys
    keys=$(/usr/bin/xray x25519 2>/dev/null)
    local priv
    priv=$(echo "$keys" | grep "Private key:" | awk '{print $3}')
    local pub
    pub=$(echo "$keys" | grep "Public key:" | awk '{print $3}')
    local sid
    sid=$(openssl rand -hex 8 2>/dev/null)
    echo "$priv" > "$REALITY_PRIVKEY"
    echo "$pub $sid" > "$REALITY_PUBFILE"
    chmod 600 "$REALITY_PRIVKEY" "$REALITY_PUBFILE"
    REALITY_PUBKEY="$pub"
    REALITY_SHORTID="$sid"
    log_info "Reality keypair generated"
}

# ── Install Xray-core from official XTLS release ───────
install_xray_core() {
    log_step "Installing Xray-core v${XRAY_VERSION}"

    if [[ -f /usr/bin/xray ]] && /usr/bin/xray version 2>/dev/null | grep -q "$XRAY_VERSION"; then
        log_info "Xray $XRAY_VERSION already installed"
        return
    fi

    local url="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip"
    local tmpdir
    tmpdir=$(mktemp -d)

    log_info "Downloading Xray-core..."
    curl -sL "$url" -o "$tmpdir/xray.zip" || die "Failed to download Xray-core"

    unzip -o "$tmpdir/xray.zip" -d "$tmpdir" >/dev/null
    cp "$tmpdir/xray" /usr/bin/xray
    chmod +x /usr/bin/xray

    # Download geoip/geosite dat files
    curl -sL "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/geoip.dat" -o /usr/share/xray/geoip.dat 2>/dev/null || true
    curl -sL "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/geosite.dat" -o /usr/share/xray/geosite.dat 2>/dev/null || true

    mkdir -p /usr/share/xray
    rm -rf "$tmpdir"

    /usr/bin/xray version 2>/dev/null | head -2
    log_info "Xray-core installed"
}

# ── Generate valid Xray config ─────────────────────────
generate_xray_config() {
    local domain="$1"
    log_info "Generating valid Xray config"

    gen_reality_keys

    local reality_pub="${REALITY_PUBKEY:-}"
    local reality_sid="${REALITY_SHORTID:-}"
    local reality_priv
    reality_priv=$(cat "$REALITY_PRIVKEY" 2>/dev/null || echo "")
    local server_psk
    server_psk=$(head -c 32 /dev/urandom 2>/dev/null | base64 -w0 2>/dev/null || openssl rand -base64 32 2>/dev/null)

    local default_uuid
    default_uuid=$(/usr/bin/xray uuid 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")

    cat > "$XRAY_CONFIG" << XRAY_CONF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "loglevel": "info"
  },
  "api": {
    "services": ["StatsService"],
    "tag": "api"
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },
    {
      "listen": "127.0.0.1",
      "port": 10004,
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-128-gcm",
        "clients": [],
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/ssws"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 14016,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 23456,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 25432,
      "protocol": "trojan",
      "settings": {
        "decryption": "none",
        "clients": [],
        "udp": true
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/t"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 24456,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": []
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vless-grpc"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 31234,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vmess-grpc"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 33456,
      "protocol": "trojan",
      "settings": {
        "decryption": "none",
        "clients": [],
        "udp": true
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "trojan-grpc"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 8001,
      "protocol": "vmess",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "httpupgrade",
        "httpupgradeSettings": {
          "path": "/love"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 8002,
      "protocol": "trojan",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "httpupgrade",
        "httpupgradeSettings": {
          "path": "/dinda"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 8003,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "httpupgrade",
        "httpupgradeSettings": {
          "path": "/rere"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "listen": "0.0.0.0",
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${domain}:443",
          "xver": 0,
          "serverNames": ["${domain}"],
          "privateKey": "${reality_priv}",
          "shortIds": ["${reality_sid}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "listen": "0.0.0.0",
      "port": 10010,
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-128-gcm",
        "clients": [],
        "network": "tcp,udp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "blocked"
      },
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": ["bittorrent"]
      }
    ]
  }
}
XRAY_CONF

    # Validate config
    /usr/bin/xray run -test -config "$XRAY_CONFIG" 2>&1 || die "Xray config validation failed"
    log_info "Xray config is valid JSON"

    # Ensure domain is set for client links
    set_domain "$domain"
}

# ── Create Xray systemd service ────────────────────────
install_xray_service() {
    log_info "Creating Xray systemd service"

    cat > /etc/systemd/system/xray.service << 'XRAY_UNIT'
[Unit]
Description=Xray Core Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
XRAY_UNIT

    systemctl daemon-reload
    svc_enable xray
    svc_restart xray

    sleep 2
    if svc_active xray; then
        log_info "Xray service running"
    else
        log_warn "Xray service may have issues — check 'systemctl status xray'"
    fi
}

# ── Full Xray install ──────────────────────────────────
install_xray() {
    local domain="$1"
    install_xray_core
    generate_xray_config "$domain"
    install_xray_service
}
