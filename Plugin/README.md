# KUROVPN Telegram Bot Controller

## Overview
A fully interactive Telegram bot that replaces SSH access for managing your VPN server. Control all protocols directly from your phone.

## Architecture
```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Telegram   │────▶│  bot.py (Python) │────▶│  System Commands │
│   (Admin)    │◀────│  python-telegram  │◀────│  (bash, wg, etc) │
│              │     │  -bot v21.10     │     │                  │
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
menu    # Select Option 7 → Telegram Bot
        # 1. Setup Bot Token & Chat ID
        # 2. Install Bot Controller
```

### Manual Install
```bash
# 1. Get a bot token from @BotFather on Telegram
# 2. Get your Chat ID from @userinfobot

# 3. Save credentials
echo "YOUR_BOT_TOKEN" > /etc/funny/.keybot
echo "YOUR_CHAT_ID" > /etc/funny/.chatid

# 4. Install dependency
pip3 install python-telegram-bot==21.10

# 5. Deploy
mkdir -p /opt/kurovpn
cp Plugin/bot.py /opt/kurovpn/bot.py
cp Plugin/kurovpn-bot.service /etc/systemd/system/

# 6. Start
systemctl daemon-reload
systemctl enable kurovpn-bot
systemctl start kurovpn-bot

# 7. Verify
journalctl -u kurovpn-bot -f
```

## Usage
1. Open Telegram and find your bot
2. Send `/start` or `/menu`
3. Navigate using inline keyboard buttons
4. Create accounts with guided step-by-step prompts
5. Send `/cancel` at any time to abort an operation

## Files
- `Plugin/bot.py` — Main bot source code
- `Plugin/kurovpn-bot.service` — Systemd service unit
- `menu_files/botmenu` — CLI installer/manager menu
