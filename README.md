<p align="center">
  <h1 align="center">KUROVPN</h1>
  <p align="center">Enterprise-Grade Multi-Protocol VPN Auto-Installer & Account Manager for Ubuntu/Debian Servers.</p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Ubuntu%2020.04%20%7C%2022.04%20%7C%2024.04%20%7C%20Debian%2011%20%7C%2012-orange" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/xray--core-v24.12.18-green" alt="Xray">
  <img src="https://img.shields.io/badge/hysteria--2-v2.12.0-purple" alt="Hysteria2">
  <img src="https://img.shields.io/badge/wireguard-kernel-blue" alt="WireGuard">
  <img src="https://img.shields.io/badge/qa%20suite-100%25%20passed-brightgreen" alt="QA Status">
</p>

---

## Overview

**KUROVPN** deploys an enterprise-grade multi-protocol VPN server in a single command. It configures 8+ high-speed VPN protocols behind an optimized Nginx TLS reverse proxy, featuring a calibrated Terminal UI (TUI), native dynamic subscription engine, automatic Let's Encrypt SSL lifecycle, kernel BBR congestion optimization, automated expiration cleanup, and disaster recovery backup systems.

### Key Architectural Highlights
- **RFC 8259 Compliant** — Xray configurations are strictly maintained via `jq` manipulation with zero sed-injection or JSON corruption.
- **True Multi-Protocol Support** — Native support for VMess, VLess, VLess Reality, Trojan, Shadowsocks-2022 (Blake3), Hysteria 2 (QUIC), WireGuard, SSH/Dropbear WebSocket, and L2TP/IPsec.
- **Dynamic Subscription Engine** — Automatically serves both Base64 (`/sub/<user>`) and Plaintext (`/sub/<user>.txt`) subscription links over HTTPS with inline terminal QR codes.
- **Calibrated TUI Experience** — Zero broken border characters, mobile terminal (Termius/JuiceSSH) compatibility, real-time CPU/RAM/Disk metrics, and non-root auto-elevation.
- **Fully Automated Operations** — `xp` cron sweeper cleans expired accounts every 15 minutes without downtime; `kurovpn-verify` runs 38-point live diagnostics.

---

## Quick Start (One-Line Installation)

Deploy KUROVPN instantly on any clean Ubuntu or Debian server:

### Interactive Installation (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/imagi-tech/kurovpn/main/install.sh | sudo bash
```
*or using `wget`:*
```bash
wget -qO- https://raw.githubusercontent.com/imagi-tech/kurovpn/main/install.sh | sudo bash
```

### Unattended / Non-Interactive Installation
```bash
curl -fsSL https://raw.githubusercontent.com/imagi-tech/kurovpn/main/install.sh | sudo bash -s -- --domain vpn.example.com --email admin@example.com --yes
```

---

## Supported Protocols & Ports

| Protocol | Transport / Core | TLS Ports | Non-TLS Ports | Status |
| :--- | :--- | :--- | :--- | :---: |
| **Xray VMess** | WS / gRPC / HTTPUpgrade | `443`, `53`, `2095` | `80`, `2082` | ✅ Active |
| **Xray VLess** | WS / gRPC / HTTPUpgrade | `443`, `53`, `2095` | `80`, `2082` | ✅ Active |
| **VLESS Reality** | XTLS-RPRX-Vision (Direct) | `8443` | — | ✅ Active |
| **Xray Trojan** | WS / gRPC / HTTPUpgrade | `443`, `53`, `2095` | `80`, `2082` | ✅ Active |
| **Shadowsocks-2022** | 2022-BLAKE3-AES-128-GCM | `10010` | — | ✅ Active |
| **Hysteria 2** | QUIC / UDP (BBR Congestion) | `443/udp` | — | ✅ Active |
| **WireGuard** | Linux Kernel Module (`wg0`) | — | `2048/udp` | ✅ Active |
| **SSH & Dropbear** | OpenSSH & Dropbear + WS Proxy | `443`, `77` | `22`, `109`, `111`, `69`, `3303` | ✅ Active |
| **L2TP / IPsec & PPTP** | xl2tpd + Libreswan + pptpd | — | `udp 500, 4500, 1701`, `tcp 1723` | ✅ Active |
| **BadVPN (UDPGW)** | UDP Game / VOIP Accelerator | — | `udp 7300` | ✅ Active |
| **NoobZVPNS** | TCP / TLS / WebSocket | `9443` | `8080` | ⚠️ Optional |

---

## Terminal User Interface (TUI)

Launch the central management console from any terminal by typing:
```bash
menu
```

```
╔════════════════════════════════════════════════════════╗
║ KUROVPN                           drr.imagitech.online ║
╠────────────────────────────────────────────────────────╣
║ › KUROVPN › Core                                       ║
╚════════════════════════════════════════════════════════╝

  Server: drr.imagitech.online (135.232.221.18)
  OS:     Ubuntu 20.04.3 LTS
  Uptime: 1 week, 6 days, 13 hours, 15 minutes

  CPU:  [░░░░░░░░░░░░] 0% (2 Core)
  RAM:  [████░░░░░░░░] 34% (316MB / 916MB)
  Disk: [██████░░░░░░] 54% (115G / 214G)

  [ Active Services ]
  ● Xray   ● Nginx   ● Hysteria2   ● WireGuard
  ● SSH    ● Dropbear   ● L2TP   ○ Bot

  Registered Clients: 45 total across protocols

╭────────────────────────────────────────────────────────╮
│ Protocol & System Management                           │
│                                                        │
│  1) SSH & Dropbear           6) Subscriptions          │
│  2) Xray Core Protocols      7) TCP BBR Booster        │
│  3) Hysteria 2 (QUIC)        8) Settings & Logs        │
│  4) WireGuard VPN            9) Bot & Backup           │
│  5) L2TP / IPsec VPN       10) Domain & Cert           │
╰────────────────────────────────────────────────────────╯

  V) Run Full Diagnostics (Verify)   X) Exit
```

---

## CLI Management Reference

All management tools are installed globally into `/usr/bin/`:

### Primary Managers
| Command | Function |
|---|---|
| `menu` | Central interactive TUI dashboard |
| `menu-xray` | Dedicated Xray manager (VMess, VLess, Reality, Trojan, SS-2022) |
| `menu-hy2` | Dedicated Hysteria 2 QUIC manager (multi-user auth, config reload) |
| `menu-ssh` | SSH / Dropbear account manager (create, renew, delete, online check) |
| `Menu-WGF` | WireGuard client manager (auto-IP allocation, QR code generator) |
| `lmenu` | L2TP/IPsec & PPTP account manager |
| `sub` | Dynamic subscription manager & URL publisher |
| `bbr` | TCP BBR congestion control tuning & status |

### Direct Account Creation
| Command | Generated Protocol |
|---|---|
| `add-vmess` | VMess (WS + gRPC + HTTPUpgrade TLS & Non-TLS) |
| `add-vless` | VLess (WS + gRPC + HTTPUpgrade TLS & Non-TLS) |
| `add-reality` | VLESS-XTLS-Vision Reality (Direct port 8443) |
| `add-trojan` | Trojan (WS + gRPC TLS) |
| `add-ss2022` | Shadowsocks-2022 Blake3 (Direct port 10010) |
| `add-hysteria2` | Hysteria 2 QUIC (UDP 443 with BBR) |
| `addssh` | Linux SSH + Dropbear + WebSocket account |
| `add-l2tp` | L2TP/IPsec with pre-shared key |

### System & Diagnostic Utilities
| Command | Function |
|---|---|
| `kurovpn-verify` | **38-point live diagnostic check** (Services, Configs, Ports, Crons) |
| `xp` | Auto-expiry sweeper — runs via cron every 15 min |
| `backup` | Generates timestamped `.tar.gz` archive of all VPN configurations |
| `menu-set` | System control (reboot, service restart, speedtest, bandwidth) |
| `dm-menu` | Domain management, Let's Encrypt renewal, and Cloudflare DNS sync |
| `botmenu` | Telegram remote management bot configuration |

---

## Dynamic Subscription Engine

KUROVPN includes an automated subscription server hosted directly on Nginx:
- **Base64 Feed:** `https://your-domain.com/sub/<username>` (Compatible with Clash, v2rayN, Shadowrocket, Sing-box, Nekobox)
- **Plaintext Feed:** `https://your-domain.com/sub/<username>.txt` (Direct URI list)
- **Terminal QR Codes:** Instant scanning from mobile client cameras directly from the CLI output.

---

## System Requirements & Compatibility

- **Operating Systems:**
  - Ubuntu 24.04 LTS (Noble Numbat)
  - Ubuntu 22.04 LTS (Jammy Jellyfish)
  - Ubuntu 20.04 LTS (Focal Fossa)
  - Debian 12 (Bookworm)
  - Debian 11 (Bullseye)
- **Hardware Requirements:**
  - Minimum: 1 vCPU, 512 MB RAM, 10 GB Disk
  - Recommended: 2 vCPU, 1 GB+ RAM, 20 GB Disk
- **Network Requirements:**
  - Ports `80/tcp` and `443/tcp` accessible for Let's Encrypt certificate issuance.
  - A registered Domain Name pointing to your server's Public IPv4 address.

---

## Uninstallation

To cleanly remove KUROVPN and all associated services, run:
```bash
uninstall
```
*or via one-liner non-interactive flag:*
```bash
curl -fsSL https://raw.githubusercontent.com/imagi-tech/kurovpn/main/uninstall.sh | sudo bash -s -- --yes
```

The uninstaller removes all VPN services, restores iptables rules, purges configuration directories, and preserves your primary SSH connection on port 22.

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
