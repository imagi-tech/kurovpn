#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  modules/nginx.sh — Nginx reverse proxy TLS termination

source "$SCRIPT_DIR/lib/common.sh"

install_nginx() {
    log_step "Configuring Nginx reverse proxy"

    local domain="$1"

    # Free port 53 from systemd-resolved stub listener
    if svc_active "systemd-resolved" 2>/dev/null; then
        log_info "Disabling systemd-resolved DNS stub on port 53"
        sed -i 's/^#*DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
        svc_restart systemd-resolved 2>/dev/null || true
    fi

    # Remove default configs
    rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

    # Generate nginx config
    generate_nginx_conf "$domain"

    # Validate
    nginx -t 2>&1 || die "Nginx configuration test failed"

    # Systemd override for nginx (if needed)
    cat > /etc/systemd/system/nginx.service << 'NGINX_UNIT'
[Unit]
Description=A high-performance web server and reverse proxy
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
NGINX_UNIT

    systemctl daemon-reload
    svc_enable nginx
    svc_restart nginx

    log_info "Nginx configured and running"
}

generate_nginx_conf() {
    local domain="$1"

    cat > /etc/nginx/nginx.conf << NGINX_CONF
# KUROVPN Nginx Configuration
# https://github.com/imagi-tech/kurovpn

user www-data;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format main '[\$time_local] \$remote_addr "\$http_referer" "\$http_user_agent"';
    access_log /var/log/nginx/access.log main;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ""      close;
    }

    map \$remote_addr \$proxy_forwarded_elem {
        ~^[0-9.]+$        "for=\$remote_addr";
        ~^[0-9A-Fa-f:.]+$ "for=\"[\$remote_addr]\"";
        default           "for=unknown";
    }

    map \$http_forwarded \$proxy_add_forwarded {
        "~^(,[ \\t]*)*([!#\$%&'*+.^_\`|~0-9A-Za-z-]+=([!#\$%&'*+.^_\`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?(;([!#\$%&'*+.^_\`|~0-9A-Za-z-]+=([!#\$%&'*+.^_\`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?)*([ \\t]*,([ \\t]*([!#\$%&'*+.^_\`|~0-9A-Za-z-]+=([!#\$%&'*+.^_\`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?(;([!#\$%&'*+.^_\`|~0-9A-Za-z-]+=([!#\$%&'*+.^_\`|~0-9A-Za-z-]+|\"([\\t \\x21\\x23-\\x5B\\x5D-\\x7E\\x80-\\xFF]|\\\\[\\t \\x21-\\x7E\\x80-\\xFF])*\"))?)*)?)*\$" "\$http_forwarded, \$proxy_forwarded_elem";
        default "\$proxy_forwarded_elem";
    }

    # Admin panel on port 89/855
    server {
        listen 89;
        listen [::]:89;
        listen 855 ssl http2 reuseport;
        listen [::]:855 ssl http2 reuseport;
        ssl_certificate /etc/xray/xray.crt;
        ssl_certificate_key /etc/xray/xray.key;
        ssl_ciphers EECDH+CHACHA20:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:!MD5;
        ssl_protocols TLSv1.2 TLSv1.3;
        root /home/vps/public_html;
    }

    # Main VPN server (multi-port, multi-protocol)
    server {
        listen 80;
        listen [::]:80;
        listen 2082;
        listen [::]:2082;
        listen 443 ssl http2 reuseport;
        listen [::]:443 ssl http2 reuseport;
        listen 53 ssl http2 reuseport;
        listen [::]:53 ssl http2 reuseport;
        listen 2095 ssl http2 reuseport;
        listen [::]:2095 ssl http2 reuseport;
        ssl_certificate /etc/xray/xray.crt;
        ssl_certificate_key /etc/xray/xray.key;
        ssl_ciphers EECDH+CHACHA20:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:!MD5;
        ssl_protocols TLSv1.2 TLSv1.3;
        root /var/www/html;

        # SSH WebSocket (Dropbear on port 109)
        location / {
            if (\$http_upgrade != "Upgrade") { rewrite /(.*) / break; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:77;
            proxy_http_version 1.1;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;
            add_header Access-Control-Allow-Headers "Authorization, Content-Type";
        }

        # Shadowsocks WS
        location ~ /ssws {
            if (\$http_upgrade != "Websocket") { rewrite /(.*) /ssws break; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:10004;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

        # VMess WS
        location ~ /vmess {
            if (\$http_upgrade != "Websocket") { rewrite /(.*) /vmess break; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:23456;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

        # VLess WS
        location ~ /vless {
            if (\$http_upgrade != "Websocket") { rewrite /(.*) /vless break; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:14016;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

        # Trojan WS
        location ~ /t {
            if (\$http_upgrade != "Websocket") { rewrite /(.*) /t break; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:25432;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

        # VMess HTTPUpgrade
        location ~ /love {
            if (\$http_upgrade != "Websocket") { rewrite /(.*) /love break; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:8001;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
        }

        # Trojan HTTPUpgrade
        location ~ /dinda {
            if (\$http_upgrade != "Websocket") { rewrite /(.*) /dinda break; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:8002;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
        }

        # VLess HTTPUpgrade
        location ~ /rere {
            if (\$http_upgrade != "Websocket") { rewrite /(.*) /rere break; }
            proxy_redirect off;
            proxy_pass http://127.0.0.1:8003;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
        }

        # VMess gRPC
        location ^~ /vmess-grpc {
            proxy_redirect off;
            grpc_set_header X-Real-IP \$remote_addr;
            grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            grpc_set_header Host \$http_host;
            grpc_pass grpc://127.0.0.1:31234;
        }

        # VLess gRPC
        location ^~ /vless-grpc {
            proxy_redirect off;
            grpc_set_header X-Real-IP \$remote_addr;
            grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            grpc_set_header Host \$http_host;
            grpc_pass grpc://127.0.0.1:24456;
        }

        # Trojan gRPC
        location ^~ /trojan-grpc {
            proxy_redirect off;
            grpc_set_header X-Real-IP \$remote_addr;
            grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            grpc_set_header Host \$http_host;
            grpc_pass grpc://127.0.0.1:33456;
        }
    }
}
NGINX_CONF

    log_info "Nginx configuration written"
}
