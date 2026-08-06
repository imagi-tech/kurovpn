# KUROVPN

VPN Auto-Installer & Manager — one command to deploy a multi-protocol VPN server.

> **Status:** Under active development. See the [plan](#roadmap) below.

## Protocols

| Protocol | Transport | TLS | Status |
|---|---|---|---|
| SSH / Dropbear | TCP + WebSocket | — | Planned |
| VMess | WS / gRPC / HTTPUpgrade | Optional | Planned |
| VLess | WS / gRPC / HTTPUpgrade | Optional | Planned |
| Trojan | WS / gRPC / HTTPUpgrade | Optional | Planned |
| Shadowsocks | WebSocket | Optional | Planned |
| L2TP / IPsec | Native | IPsec | Planned |
| WireGuard | Native | — | Planned |
| NoobZVPNS | TCP TLS / WebSocket | Yes | Planned |
| BadVPN (UDPGW) | UDP | — | Planned |
| VLESS Reality | XTLS-Vision | Yes | Roadmap |
| Hysteria2 | QUIC | Yes | Roadmap |

## Quick Start

```bash
git clone https://github.com/imagi-tech/kurovpn.git
cd kurovpn
sudo ./install.sh --domain your-domain.com --email admin@your-domain.com
```

## Management Commands

| Command | Description |
|---|---|
| `menu` | Main dashboard |
| `menu-ssh` | SSH account manager |
| `menu-xray` | Xray (VMess/VLess/Trojan/SS) manager |
| `menu-set` | System settings |
| `Menu-WGF` | WireGuard manager |
| `lmenu` | L2TP/IPsec manager |
| `nmenu` | NoobZVPN manager |
| `bmenu` | Backup & restore |
| `dm-menu` | Domain & certificate |
| `botmenu` | Telegram bot setup |
| `xp` | Auto-expiry sweeper (cron) |

## Uninstall

```bash
sudo ./uninstall.sh
```

## Roadmap

- [x] Phase 1 — Repo cleanup & rebrand
- [ ] Phase 2 — Core installer rewrite (modular, JSON-validated)
- [ ] Phase 3 — Commands rewrite (jq-based user management)
- [ ] Phase 4 — Uninstaller & verification tools
- [ ] Phase 5 — Telegram bot fixes
- [ ] Phase 6 — New protocols
- [ ] Phase 7 — Complete documentation

## License

MIT — see [LICENSE](LICENSE).
