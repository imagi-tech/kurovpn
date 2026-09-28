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
  <img src="https://img.shields.io/badge/proxy-http%20%7C%20socks5-teal" alt="Proxy">
  <img src="https://img.shields.io/badge/diagnostics-40%2F40%20passed-brightgreen" alt="Diagnostics">
</p>

---

## Overview

**KUROVPN** deploys an enterprise-grade multi-protocol VPN server in a single command. It configures high-speed modern VPN and proxy protocols behind an optimized Nginx TLS reverse proxy and native Xray Core, featuring a calibrated Terminal UI (TUI), native dynamic subscription engine, automatic Let's Encrypt SSL lifecycle, kernel BBR congestion optimization, automated expiration cleanup, and disaster recovery backup systems.

### Key Architectural Highlights
- **RFC 8259 Compliant** — Xray configurations are strictly maintained via safe JSON manipulation with zero sed-injection or config corruption.
- **True Multi-Protocol Support** — Native support for VMess, VLess, VLess Reality, Trojan, Shadowsocks-2022 (Blake3), Hysteria 2 (QUIC), WireGuard, SSH/Dropbear WebSocket, and **HTTP & SOCKS5 Proxies**.
- **Dedicated HTTP & SOCKS5 Proxies (Menu 5)** — Built-in authenticated proxies on standard ports (`80` for HTTP, `1080` for SOCKS5) with per-user authentication, automated expiration tracking, and renewal.
- **Hysteria 2 Dual-Instance & UDP Port 53 Obfs Bypass** — Native Hysteria 2 deployment supporting both port `443` (standard QUIC) and DNS port `53/udp` with Salamander obfuscation for bypassing carrier Deep Packet Inspection (DPI) and ISP DNS blocks.
- **Dynamic Subscription Engine** — Automatically serves both Base64 (`/sub/<user>`) and Plaintext (`/sub/<user>.txt`) subscription links over HTTPS with inline terminal QR codes.
- **One-Command In-Place Updater** — `kurovpn-update` pulls and installs the latest scripts and libraries without disrupting user databases, active connections, or SSL certificates.
- **Interactive SSH Banner Engine** — Full ANSI colored SSH login banners with custom text editing, presets, and live toggles across OpenSSH and Dropbear.
- **Calibrated TUI Experience** — Zero broken border characters, mobile terminal (Termius/JuiceSSH) compatibility, real-time CPU/RAM/Disk metrics, and non-root auto-elevation.
- **Fully Automated Operations** — `xp` cron sweeper cleans expired accounts across all protocols every 15 minutes without downtime; `kurovpn-verify` runs live diagnostics.

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
| **Xray VMess** | WS / gRPC / HTTPUpgrade | `443`, `53`, `2095` | `2082` | ✅ Active |
| **Xray VLess** | WS / gRPC / HTTPUpgrade | `443`, `53`, `2095` | `2082` | ✅ Active |
| **VLESS Reality** | XTLS-RPRX-Vision (Direct) | `8443` | — | ✅ Active |
| **Xray Trojan** | WS / gRPC / HTTPUpgrade | `443`, `53`, `2095` | `2082` | ✅ Active |
| **Shadowsocks-2022** | 2022-BLAKE3-AES-128-GCM | `10010` | — | ✅ Active |
| **Hysteria 2** | QUIC / UDP (BBR Congestion) | `443/udp` (Standard), `53/udp` (Salamander Obfs) | — | ✅ Active |
| **WireGuard** | Linux Kernel Module (`wg0`) | — | `2048/udp` | ✅ Active |
| **SSH & Dropbear** | OpenSSH & Dropbear + WS Proxy | `443`, `77`, `2080` | `22`, `109`, `111`, `69`, `3303` | ✅ Active |
| **HTTP Proxy** | Native Xray Core | — | `80` (Auth Required) | ✅ Active |
| **SOCKS5 Proxy** | Native Xray Core | — | `1080` (Auth Required) | ✅ Active |
| **BadVPN (UDPGW)** | UDP Game / VOIP Accelerator | — | `udp 7300` | ✅ Active |
| **NoobZVPNS** | TCP / TLS / WebSocket | `9443` | `8088` | ⚠️ Optional |

---

## Terminal User Interface (TUI)

Launch the central management console from any terminal by typing:
```bash
menu
```

```
╔════════════════════════════════════════════════════════╗
║ KUROVPN                                vpn.example.com ║
╠────────────────────────────────────────────────────────╣
║ › KUROVPN › Core                                       ║
╚════════════════════════════════════════════════════════╝

  Server: vpn.example.com (68.211.88.80)
  OS:     Ubuntu 24.04.1 LTS
  Uptime: 2 days, 10 hours, 28 minutes

  CPU:  [░░░░░░░░░░░░] 2% (2 Core)
  RAM:  [████░░░░░░░░] 34% (316MB / 916MB)
  Disk: [██████░░░░░░] 54% (115G / 214G)

  [ Active Services ]
  ● Xray   ● Nginx   ● Hysteria2   ● WireGuard
  ● SSH    ● Dropbear   ● Proxy   ○ Bot

  Registered Clients: 10 total across protocols

╭────────────────────────────────────────────────────────╮
│ Protocol & System Management                           │
│                                                        │
│  1) SSH & Dropbear           6) Subscriptions          │
│  2) Xray Core Protocols      7) TCP BBR Booster        │
│  3) Hysteria 2 (QUIC)        8) Settings & Logs        │
│  4) WireGuard VPN            9) Bot & Backup           │
│  5) HTTP & SOCKS5 Proxy     10) Domain & Cert          │
╰────────────────────────────────────────────────────────╯

  U) Update KUROVPN   V) Full Diagnostics   X) Exit
```

---

## HTTP & SOCKS5 Proxy Management (Menu 5)

Accessible via `menu` (Option 5) or directly typing `lmenu`:

```
┌────────────────────────────────────────────────────────┐
│               HTTP & SOCKS5 Proxy                      │
└────────────────────────────────────────────────────────┘
  Proxy Account Management
   1) Create Proxy Account   (Username, Password, Expiry Days)
   2) List All Proxy Users   (Username, Password, Expiry, Status)
   3) Renew User Account     (Extend validity in days)
   4) Delete User Account    (Pre-validated deletion)
   5) Change User Password   (Update credentials)

  System & Connection
   6) Service & Port Status  (Live port 80/1080 check)
   7) Connection Info & Guide (Endpoints & mobile setup)
   8) Restart Proxy (Xray)   (Daemon reload)
```

### Proxy Connection Guide
- **Authenticated HTTP Proxy**: `http://<user>:<pass>@<domain>:80`
- **Authenticated SOCKS5 Proxy**: `socks5://<user>:<pass>@<domain>:1080`


### Quick CLI Testing
```bash
# Test HTTP Auth
curl -x http://user:pass@vpn.example.com:80 https://api.ipify.org

# Test SOCKS5 Auth
curl -x socks5h://user:pass@vpn.example.com:1080 https://api.ipify.org


```

---

## CLI Management Reference

All management tools are installed globally into `/usr/bin/`:

### Primary Managers
| Command | Function |
|---|---|
| `menu` | Central interactive TUI dashboard |
| `menu-xray` | Dedicated Xray manager (VMess, VLess, Reality, Trojan, SS-2022) |
| `menu-hy2` | Dedicated Hysteria 2 QUIC manager (multi-user auth, config reload, port 443 & port 53 Salamander Obfs) |
| `menu-ssh` | SSH / Dropbear account & ANSI banner manager |
| `Menu-WGF` | WireGuard client manager (auto-IP allocation, QR code generator) |
| `lmenu` | Dedicated HTTP & SOCKS5 proxy account manager (auth, open, expiry, renew) |
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
| `add-hysteria2` | Hysteria 2 QUIC (`hy2://` userpass auth, standard port 443 & Salamander obfs port 53) |
| `addssh` | Linux SSH + Dropbear + WebSocket account |

### System & Diagnostic Utilities
| Command | Function |
|---|---|
| `kurovpn-verify` | **Live diagnostic check** (Services, Configs, Ports, Crons) |
| `kurovpn-update` | **In-place code & library updater** — seamless update without losing accounts or certs |
| `xp` | Auto-expiry sweeper — runs via cron every 15 min |
| `backup` | Generates timestamped `.tar.gz` archive of all VPN configurations |
| `menu-set` | System control (reboot, service restart, speedtest, bandwidth) |
| `dm-menu` | Domain management, Let's Encrypt renewal, and Cloudflare DNS sync |

---

## In-Place Updates (`kurovpn-update`)

Update the KUROVPN management suite directly from GitHub without reinstalling the OS or interrupting active services:

```bash
kurovpn-update
```
- Fetches the latest commands, libraries, and TUI enhancements.
- Preserves all client accounts, credentials, expiration dates, and TLS certificates.
- Performs zero-downtime service reload.

---

## Dynamic Subscription Engine

KUROVPN includes a built-in subscription distribution engine:
- **Base64 Subscription**: `https://<domain>/sub/<username>` (Compatible with v2rayN, Shadowrocket, NekoBox, Happ, Sing-Box)
- **Plaintext Subscription**: `https://<domain>/sub/<username>.txt`
- Includes all enabled protocols: VMess, VLess, Reality, Trojan, SS-2022, Hysteria 2, and Proxies.

---

## System Requirements & Compatibility

### Supported Distributions
- **Ubuntu**: 20.04 LTS, 22.04 LTS, 24.04 LTS (Noble Numbat)
- **Debian**: 11 (Bullseye), 12 (Bookworm)

### Recommended Minimum Hardware
- **CPU**: 1 vCPU (2.0 GHz+)
- **RAM**: 1 GB+
- **Disk**: 15 GB+ SSD
- **Network**: KVM Virtualization, 1 Public IPv4 / IPv6 address, Ports `80` and `443` open.

---

## Uninstallation

To completely remove KUROVPN and restore the server to a clean state:

```bash
uninstall
```
*or via source repository:*
```bash
sudo ./uninstall.sh
```

---

## License

This project is open-source under the [MIT License](LICENSE).
Developed & Maintained by [Imagi-Tech](https://github.com/imagi-tech).
