# KUROVPN Telegram Bot Controller

## Overview
A fully interactive Telegram bot that replaces SSH access for managing your VPN server. Control all protocols directly from your phone.

## Architecture
```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Telegram   │────▶│  bot.py (Python) │────▶│  System Commands │
│   (Admin)    │◀────│  (stdlib only)   │◀────│  (bash, wg, etc) │
│              │     │                  │     │                  │
└──────────────┘     └──────────────────┘     └─────────────────┘
                            │
                     ┌──────┴──────┐
                     │ Admin Auth  │
                     │ /etc/funny/ │
                     │ .chatid     │
                     │ .keybot     │
                     └─────────────┘
```

## Features

### Protocol Management
| Protocol    | Create | Delete | Renew | List | Extra           |
|-------------|--------|--------|-------|------|-----------------|
| SSH         | ✅     | ✅     | ✅    | ✅   | Online users    |
| VMess       | ✅     | ✅     | —     | ✅   | Auto-link gen   |
| VLess       | ✅     | ✅     | —     | ✅   | Auto-link gen   |
| Trojan      | ✅     | ✅     | —     | ✅   | Auto-link gen   |
| Shadowsocks | ✅     | ✅     | —     | ✅   | Auto-link gen   |
| NoobzVPN    | ✅     | ✅     | —     | ✅   | —               |
| L2TP/IPsec  | ✅     | ✅     | —     | ✅   | —               |
| Wireguard   | ✅     | ✅     | —     | ✅   | View .conf file |

### System Management
- Restart individual or all services
- View bandwidth usage (vnstat)
- Server info (CPU, RAM, disk, uptime, all service statuses)

### Security
- Admin-only access via Telegram Chat ID whitelist
- All unauthorized messages are rejected and logged

## Installation

### Quick Install (from menu)
```bash
menu        # Select 7) Bot / Backup → 3) Telegram Bot Setup
            # Enter your bot token and chat ID → bot starts automatically
```
Send `/start` in Telegram to verify.

### Manual Install
```bash
# 1. Get a bot token from @BotFather on Telegram
# 2. Get your Chat ID from @userinfobot

# 3. Save credentials and start
echo "YOUR_BOT_TOKEN" > /etc/funny/.keybot
echo "YOUR_CHAT_ID"  > /etc/funny/.chatid
systemctl enable --now kurovpn-bot

# 4. Verify
journalctl -u kurovpn-bot -f
```

No pip dependencies required — bot.py uses only Python standard library.

## Usage
1. Open Telegram and find your bot
2. Send `/start` for the command list
3. Use commands like `/add_vmess`, `/list`, `/status`, `/verify`
4. Interactive commands accept `username|days` format
5. Only whitelisted admin chat IDs can use the bot

## Files
- `Plugin/bot.py` — Main bot source code (stdlib only, no pip deps)
- `Plugin/kurovpn-bot.service` — Systemd service unit
- `commands/botmenu` — CLI installer (saves token + starts bot, deployed by install.sh)
