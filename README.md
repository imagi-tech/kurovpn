<p align="center">
  <h1 align="center">KUROVPN</h1>
  <p align="center">Multi-protocol VPN auto-installer and account manager for Ubuntu/Debian servers.</p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Ubuntu%2BDebian-orange" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/xray-24.12.18-green" alt="Xray">
  <img src="https://img.shields.io/badge/nginx-1.18-green" alt="Nginx">
</p>

---

## Overview

KUROVPN deploys a complete multi-protocol VPN server in a single command. It installs and configures 8 VPN protocols behind an Nginx TLS reverse proxy, with a full set of management tools, an automatic expiry sweeper, and an optional Telegram bot for remote administration.

**Key design principles:**
- **Valid JSON** — Xray configuration is always RFC 8259 compliant, mutated via `jq`, never sed-injected.
- **Modular** — Each protocol is an independent module; library code is shared.
- **Secure by default** — No hardcoded credentials, fail-closed admin bot, validated user input.
- **Idempotent** — Installer and modules can be re-run safely on an existing deployment.

## Supported Protocols

| Protocol | Transport | TLS Ports | Non-TLS Ports | Status |
|---|---|---|---|---|
| SSH / Dropbear | TCP + WebSocket (edu proxy) | 443 | 22, 3303, 109, 111, 69 | ✅ |
| VMess | WS / gRPC / HTTPUpgrade | 443, 53, 2095 | 80, 2082 | ✅ |
| VLess | WS / gRPC / HTTPUpgrade | 443, 53, 2095 | 80, 2082 | ✅ |
| Trojan | WS / gRPC / HTTPUpgrade | 443, 53, 2095 | 80, 2082 | ✅ |
| Shadowsocks | WebSocket | 443, 53 | 80 | ✅ |
| L2TP / IPsec + PPTP | Native (Libreswan) | — | udp 1701, tcp 1723 | ✅ |
| WireGuard | Native | — | udp 2048 | ✅ |
| BadVPN (UDPGW) | UDP game accelerator | — | udp 7300 | ✅ |
| NoobZVPNS | TCP / TLS / WebSocket | 9443 | 8080 | ⚠️ |
| VLESS Reality | XTLS-Vision | Roadmap | — | 🚧 |
| Hysteria2 | QUIC | Roadmap | — | 🚧 |

> ⚠️ NoobZVPNS: upstream repository has restructured and no longer provides downloadable binaries. The installer skips it gracefully; re-enable when binaries are available.

## Prerequisites

- **Server:** Ubuntu 20.04+, or Debian 11+. x86_64 or arm64.
- **Domain:** A domain or subdomain with an A record pointing to your server's public IP.
- **Ports:** TCP 80 and 443 open to the internet (Let's Encrypt HTTP-01 validation).
- **User:** Root or passwordless sudo.

## Quick Start

```bash
git clone https://github.com/imagi-tech/kurovpn.git
cd kurovpn
sudo ./install.sh --domain vpn.example.com --email admin@example.com
```

That's it. KUROVPN installs all protocols, issues a Let's Encrypt certificate, and starts all services. After installation, run `menu` to manage accounts.

### Install options

```
./install.sh [OPTIONS]

  -d, --domain DOMAIN      Domain name (A record must point to this server)
  -e, --email EMAIL        Admin email for Let's Encrypt registration
  --ip-version 4|6         IPv4 (default) or IPv6 for certificate
  --with-warp              Install Cloudflare WARP on WireGuard
  -y, --yes                Non-interactive (requires --domain and --email)
  -h, --help               Show help
```

### Example: full unattended install

```bash
sudo ./install.sh --domain vpn.imagitech.online --email admin@imagitech.online --yes --ip-version 4
```

## Management Commands

After installation, the following commands are available in `/usr/bin/`:

### Account Management

| Command | Description |
|---|---|
| `menu` | Main dashboard — service status overview, submenu dispatcher |
| `menu-ssh` | SSH account manager (create, trial, list, delete, renew, online users) |
| `menu-xray` | Xray account manager (VMess, VLess, Trojan, Shadowsocks) |
| `lmenu` | L2TP/IPsec account manager (create, list, delete, renew) |
| `Menu-WGF` | WireGuard client manager (create, list, delete, show config) |
| `nmenu` | NoobZVPNS account manager (if installed) |

### Quick Account Creation

| Command | Creates |
|---|---|
| `addssh` | SSH account (OpenSSH + Dropbear + WebSocket) |
| `add-vmess` | VMess account (WS + gRPC + HTTPUpgrade links) |
| `add-vless` | VLess account (WS + gRPC + HTTPUpgrade links) |
| `add-trojan` | Trojan account (WS + gRPC + HTTPUpgrade links) |
| `add-ssws` | Shadowsocks WebSocket account |
| `add-l2tp` | L2TP/IPsec account |

### System Operations

| Command | Description |
|---|---|
| `menu-set` | System settings — restart all services, speedtest, htop, timezone, bandwidth |
| `dm-menu` | Domain & certificate management — set domain, renew cert, Cloudflare auto-DNS |
| `bmenu` | Backup & restore — create tarball, restore from local file, bot setup |
| `botmenu` | Telegram bot — save credentials, deploy bot.py, enable systemd service |
| `kurovpn-verify` | **27-point diagnostic** — services, configuration, ports, and management checks |
| `xp` | Auto-expiry sweeper — runs via cron every 15 min, removes expired accounts |
| `backup` | Creates a timestamped `tar.gz` of all configuration files in `/root/` |

## Protocol Details

### VMess / VLess / Trojan

All three proxy protocols share the same Nginx reverse proxy with multiple transports:

**TLS endpoints (port 443, 53, 2095):**
- WS: `/vmess` (VMess), `/vless` (VLess), `/t` (Trojan)
- gRPC: `vmess-grpc`, `vless-grpc`, `trojan-grpc`
- HTTPUpgrade: `/love` (VMess), `/rere` (VLess), `/dinda` (Trojan)

**Non-TLS endpoints (port 80, 2082):**
- WS: same paths as TLS, no encryption

**Client config generation:** Each `add-*` command prints ready-to-paste client links in `vmess://`, `vless://`, and `trojan://` URI format.

### Shadowsocks

- TLS WebSocket on port 443, path `/ssws`.
- Method: AES-128-GCM.
- `add-ssws` prints an `ss://` SIP002 URI with Base64-encoded credentials.

### SSH (Dropbear + WebSocket)

| Port | Protocol | Notes |
|---|---|---|
| 22 | OpenSSH | Default port |
| 3303 | OpenSSH | Alternate port |
| 109 | Dropbear | Direct Dropbear |
| 111 | Dropbear | Direct Dropbear |
| 69 | Dropbear | Direct Dropbear |
| 443, 80 | WebSocket → Dropbear | TLS/Non-TLS; payload drops through to port 109 |

**Payload (for WS-capable clients):**
```
GET / HTTP/1.1[crlf]Host: your-domain.com[crlf]Upgrade: websocket[crlf][crlf]
```

### WireGuard

- Server network: `10.66.66.0/24`
- Listen port: `2048/udp`
- Client configs stored in `/etc/wireguard/clients/`
- `Menu-WGF` manages client creation with automatic IP allocation.

### L2TP/IPsec + PPTP

- Libreswan (apt package), xl2tpd, pptpd.
- Pre-shared key for IPsec.
- PPTP on `tcp/1723`, L2TP/IPsec on `udp/1701`.
- `add-l2tp` handles credential creation and chap-secrets management.

## Uninstall

```bash
sudo ./uninstall.sh
```

Removes all KUROVPN-installed services, configuration files, cron jobs, iptables rules, and binaries. User home directories are preserved. You will be prompted to confirm.

## Verification

```bash
kurovpn-verify
```

Runs a 27-point health check covering:
- **10 services:** nginx, xray, dropbear, ssh, edu, wireguard, xl2tpd, ipsec, pptpd, badvpn.
- **7 configuration checks:** Xray config valid JSON, domain set, TLS cert valid, users.json.
- **6 port checks:** 443, 80, 22, 109, 7300, 2048 all listening.
- **4 management checks:** menu, xp, backup commands present, cron installed.

## Telegram Bot

An admin-only Telegram bot for remote server management.

### Setup

```bash
# Interactive: saves token and chat ID, deploys bot.py, offers to enable systemd
botmenu

# Manual:
echo "BOT_TOKEN" > /etc/funny/.keybot
echo "CHAT_ID"  > /etc/funny/.chatid
cp Plugin/bot.py /opt/kurovpn/bot.py
systemctl enable --now kurovpn-bot
```

### Commands

| Command | Action |
|---|---|
| `/start` | Show available commands |
| `/add_vmess` | Create VMess account (interactive: `username\|days`) |
| `/add_vless` | Create VLess account |
| `/add_trojan` | Create Trojan account |
| `/add_ss` | Create Shadowsocks account |
| `/add_ssh` | Create SSH account (interactive: `username\|password\|days`) |
| `/list` | List all Xray users with expiry dates |
| `/status` | Check each service status |
| `/verify` | Run `kurovpn-verify` and return results |
| `/backup` | Create configuration backup |

### Security

- **Admin-only:** Only chat IDs listed in `/etc/funny/.chatid` can use the bot.
- **Fail-closed:** If no admin IDs are configured, the bot refuses ALL commands.
- **No shell injection:** All operations use Python's `subprocess` with list arguments (no `shell=True`).
- **Stateless:** Credentials and user data are never stored by the bot; all state lives on the server.

## Architecture

```
kurovpn/
├── install.sh             Entry point — argument-driven, modular orchestration
├── uninstall.sh           Clean reverse-install (prompted confirmation)
├── lib/                   Shared libraries
│   ├── common.sh            Logging, colors, OS detection, CLI arg parsing
│   ├── deps.sh              APT package installation, directory creation
│   ├── net.sh               DNS resolver config, IP detection, firewall, cron
│   ├── cert.sh              TLS certificate via official acme.sh (Let's Encrypt)
│   ├── users.sh             User database initialization (/etc/kurovpn/users.json)
│   └── xray-clients.sh      jq-based Xray client CRUD (valid JSON) + user DB helpers
├── modules/               Protocol installers (each is idempotent)
│   ├── ssh.sh               SSH hardening, Dropbear, edu WebSocket proxy
│   ├── nginx.sh             Nginx reverse proxy with TLS termination
│   ├── xray.sh              Official Xray-core download, valid JSON config generation
│   ├── wireguard.sh         WireGuard tunnel + iptables + IP forwarding
│   ├── l2tp.sh              L2TP/IPsec (apt libreswan) + PPTP
│   ├── noobzvpns.sh         NoobZVPNS (skipped if binary unavailable)
│   └── badvpn.sh            BadVPN UDP gateway
├── commands/              Management tools → installed to /usr/bin/
│   ├── menu, menu-ssh, menu-xray, menu-set
│   ├── Menu-WGF, lmenu, nmenu, bmenu, botmenu, dm-menu
│   ├── add-vmess, add-vless, add-trojan, add-ssws, addssh, add-l2tp
│   ├── xp, backup, kurovpn-verify
├── Plugin/                Telegram bot
│   ├── bot.py               Admin-only bot (subprocess-based, fail-closed)
│   └── kurovpn-bot.service  systemd unit
├── bin/                   Vendored binaries (ws, badvpn)
├── templates/             Reference config files
└── README.md, LICENSE, .gitignore
```

### User data flow

```
add-vmess → jq + users.json → valid JSON config.json → xray restart
               ↓
          users.json (metadata: uuid, expiry, created)
               ↓
          xp cron (reads users.json → removes expired → jq del from config)
               ↓
          kurovpn-verify (reads both files → 27 checks)
```

## Security

- **No hardcoded credentials** — all secrets are either generated at install time or provided via prompt.
- **TLS everywhere** — all proxy traffic is TLS-terminated by Nginx with a valid Let's Encrypt certificate (auto-renewed).
- **Valid JSON** — Xray config is always valid RFC 8259. No sed-fragment injection. All mutations validated by `xray run -test`.
- **Input validation** — all user-facing commands validate usernames (regex), expiry dates (positive integers), and passwords (minimum length).
- **Firewall** — iptables rules set up per protocol and persisted with netfilter-persistent.
- **Admin-only bot** — Telegram bot gate-checks every command against a whitelist. Fails closed.
- **No remote restore** — the backup/restore system only restores KUROVPN files from verified local archives (never overwrites `/etc/passwd` from a remote URL).
- **Remove the original Cloudflare API key:** The commit history prior to `8ab01b4` contained a live Cloudflare global API key (`dm-menu`). This has been removed and the function now prompts at runtime. Rotate the exposed key on your Cloudflare account.

## Troubleshooting

### Install fails at certificate issuance
Ensure ports 80 and 443 are open from the internet to your server. On cloud providers, check the firewall/security group settings. Verify your domain A/AAAA record points to the server's public IP.

### Nginx fails to start (port 53 in use)
If systemd-resolved is listening on port 53, the installer disables its DNS stub (`DNSStubListener=no`). If you manually re-enabled it, run: `sed -i 's/^DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf && systemctl restart systemd-resolved`.

### Xray fails to start after adding users
Run `xray run -test -config /etc/xray/config.json` to check for duplicate emails or malformed JSON. Run `jq . /etc/xray/config.json > /dev/null` to validate JSON.

### kurovpn-verify shows failures
```bash
kurovpn-verify                     # Full check
systemctl status <service>         # Check a specific service
journalctl -u <service> -n 50      # View recent logs
```

### Bot doesn't respond
```bash
systemctl status kurovpn-bot
journalctl -u kurovpn-bot -f       # Live log
cat /etc/funny/.chatid             # Are admin IDs configured?
cat /etc/funny/.keybot             # Is the bot token set?
```

### Services don't restart
Run `systemctl reset-failed` if services show as "failed" after crash testing, then restart them individually.

## FAQ

**Q: Can I install on CentOS / Rocky / Alma?**  
Currently only Ubuntu 20.04+ and Debian 11+ are supported (apt-based). RHEL-family support is planned.

**Q: How do I add multiple admin IDs to the Telegram bot?**  
Edit `/etc/funny/.chatid` and add one chat ID per line, then restart the bot.

**Q: Can I skip certain protocols during install?**  
Not yet — the full stack is installed by default. Protocol-selective install is planned.

**Q: How often does the certificate renew?**  
acme.sh renews automatically via its own cron job (checks daily). You can manually renew with `dm-menu` → option 2.

**Q: Where are the user accounts stored?**  
Xray user metadata in `/etc/kurovpn/users.json` (valid JSON). Xray clients are stored in `/etc/xray/config.json` inbounds. SSH users are system accounts. L2TP users in `/etc/ppp/chap-secrets`.

**Q: How do I change the server's domain?**  
Run `dm-menu` → option 1, enter the new domain, then renew the certificate (option 2). Make sure the DNS A record is updated first.

## Roadmap

| Phase | Status | Description |
|---|---|---|
| 1 | ✅ Done | Repo cleanup, rebrand to KUROVPN, security audit |
| 2 | ✅ Done | Modular installer with official Xray + valid JSON config |
| 3 | ✅ Done | Commands rewrite — jq-based account management, all bugs fixed |
| 4 | ✅ Done | Uninstaller verification, 27-point `kurovpn-verify` tool |
| 5 | ✅ Done | Secure Telegram bot — admin-only, subprocess-based |
| 6 | 🚧 | New protocols: VLESS Reality (XTLS-Vision), Hysteria2 |
| 7 | ✅ Done | Comprehensive documentation |

## License

MIT — see [LICENSE](LICENSE).
