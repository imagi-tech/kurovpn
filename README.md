# KUROVPN

VPN Auto-Installer & Manager — one command to deploy a multi-protocol VPN server.

> **Status:** Phases 1-3 complete. Core install + management commands verified on Ubuntu 20.04.

## Protocols

| Protocol | Transport | Ports | Status |
|---|---|---|---|
| SSH / Dropbear | TCP + WebSocket (edu proxy) | 22, 3303, 109, 111, 69 | ✅ Installed |
| VMess | WS / gRPC / HTTPUpgrade | 443, 80, 2082, 2095 | ✅ Installed |
| VLess | WS / gRPC / HTTPUpgrade | 443, 80, 2082, 2095 | ✅ Installed |
| Trojan | WS / gRPC / HTTPUpgrade | 443, 80, 2082, 2095 | ✅ Installed |
| Shadowsocks | WebSocket | 443 | ✅ Installed |
| L2TP / IPsec + PPTP | Native | udp 1701, tcp 1723 | ✅ Installed |
| WireGuard | Native | udp 2048 | ✅ Installed |
| BadVPN (UDPGW) | UDP | udp 7300 | ✅ Installed |
| NoobZVPNS | TCP TLS / WS | 8080, 9443 | ⚠️ Upstream unavailable |
| VLESS Reality | XTLS-Vision | Roadmap | 🚧 Phase 6 |
| Hysteria2 | QUIC | Roadmap | 🚧 Phase 6 |

## Quick Start

```bash
git clone https://github.com/imagi-tech/kurovpn.git
cd kurovpn
sudo ./install.sh --domain vpn.example.com --email admin@example.com
```

Options:
```
-d, --domain DOMAIN      Domain name (A record must point to server)
-e, --email EMAIL        Email for Let's Encrypt
--ip-version 4|6         IPv4 (default) or IPv6
--with-warp              Install Cloudflare WARP on WireGuard
-y, --yes                Non-interactive mode
```

## Management Commands

| Command | Description |
|---|---|
| `menu` | Main dashboard with service status |
| `menu-ssh` | SSH account: create, list, delete, renew, trial |
| `menu-xray` | Xray manager: VMess/VLess/Trojan/Shadowsocks |
| `menu-set` | System: restart services, speedtest, htop, timezone |
| `lmenu` | L2TP/IPsec: create, list, delete, renew |
| `Menu-WGF` | WireGuard: create, list, delete clients |
| `nmenu` | NoobZVPNS manager (if installed) |
| `dm-menu` | Domain & certificate renewal |
| `bmenu` | Backup & restore |
| `botmenu` | Telegram bot setup |
| `xp` | Auto-expiry sweeper (cron every 15 min) |
| `backup` | Manual backup to tar.gz |

## Architecture

```
install.sh              # Entry point: argument-driven, modular
├── lib/
│   ├── common.sh         # Logging, colors, OS detection, CLI parsing
│   ├── deps.sh           # APT dependency installation, directories
│   ├── net.sh            # DNS, IP detection, firewall, cron
│   ├── cert.sh           # acme.sh TLS certificate (official)
│   ├── users.sh          # Central user DB (/etc/kurovpn/users.json)
│   └── xray-clients.sh   # jq-based Xray client CRUD (valid JSON)
├── modules/
│   ├── ssh.sh            # SSH hardening + Dropbear + edu WS proxy
│   ├── nginx.sh          # Nginx reverse proxy TLS termination
│   ├── xray.sh           # Official Xray-core + valid JSON config
│   ├── wireguard.sh      # WireGuard tunnel
│   ├── l2tp.sh           # L2TP/IPsec (apt libreswan) + PPTP
│   ├── noobzvpns.sh      # NoobZVPNS (optional, gracefully skipped)
│   └── badvpn.sh         # BadVPN UDP gateway
├── commands/             # Management tools → /usr/bin/
│   ├── menu, menu-ssh, menu-xray, menu-set
│   ├── add-vmess, add-vless, add-trojan, add-ssws, addssh, add-l2tp
│   ├── xp, backup, bmenu, dm-menu, lmenu, nmenu, Menu-WGF, botmenu
├── templates/            # Config templates
├── bin/                  # Vendored binaries (ws, badvpn)
└── uninstall.sh          # Clean reverse-install
```

## Uninstall

```bash
sudo ./uninstall.sh
```

Removes all services, config files, cron jobs, and binaries. Prompts for confirmation.

## User Management

All accounts are managed through valid JSON — never sed-injected fragments. The Xray config at `/etc/xray/config.json` is always valid RFC 8259 JSON.

User metadata is stored in `/etc/kurovpn/users.json`:
```json
{
  "vmess": [{"user": "alice", "uuid": "...", "exp": "2026-09-05", "created": "2026-08-06"}],
  "vless": [],
  "trojan": [],
  "shadowsocks": [],
  "ssh": [],
  "l2tp": [],
  "wireguard": [],
  "noobzvpns": []
}
```

## Roadmap

- [x] Phase 1 — Repo cleanup & rebrand
- [x] Phase 2 — Modular installer (official Xray + valid JSON)
- [x] Phase 3 — Commands rewrite (jq-based, all audit bugs fixed)
- [ ] Phase 4 — Uninstall verification & final polish
- [ ] Phase 5 — Telegram bot fixes
- [ ] Phase 6 — New protocols (VLESS Reality, Hysteria2)
- [ ] Phase 7 — Comprehensive documentation

## License

MIT — see [LICENSE](LICENSE).
