#!/usr/bin/env python3
"""
KUROVPN Telegram Bot Controller
================================
A fully interactive Telegram bot for managing VPN protocols:
  - SSH accounts
  - Xray (VMess, VLess, Trojan, Shadowsocks)
  - NoobzVPN
  - L2TP/IPsec
  - Wireguard
  - System management (restart, status, backup)

Requires: python-telegram-bot==21.10
Install:  pip3 install python-telegram-bot==21.10

Usage:    python3 /opt/kurovpn/bot.py
"""

import os
import re
import json
import uuid
import base64
import subprocess
import logging
from datetime import datetime, timedelta
from functools import wraps

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    ConversationHandler,
    MessageHandler,
    filters,
    ContextTypes,
)

# ═══════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════
BOT_TOKEN_FILE = "/etc/funny/.keybot"
ADMIN_CHATID_FILE = "/etc/funny/.chatid"
DOMAIN_FILE = "/etc/xray/domain"
XRAY_CONFIG = "/etc/xray/config.json"
WG_PARAMS = "/etc/wireguard/params"
WG_CONF = "/etc/wireguard/wg0.conf"
WG_CLIENTS_DIR = "/etc/wireguard/clients"
NOOB_DB = "/etc/funny/.noob"
L2TP_DB = "/etc/funny/.l2tp"
WG_DB = "/etc/funny/.wg"

logging.basicConfig(
    format="%(asctime)s - KUROVPN-BOT - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

# Conversation states
(
    SSH_USERNAME, SSH_PASSWORD, SSH_DAYS,
    XRAY_PROTO, XRAY_USERNAME, XRAY_DAYS,
    NOOB_USERNAME, NOOB_PASSWORD, NOOB_DAYS,
    L2TP_USERNAME, L2TP_PASSWORD, L2TP_DAYS,
    WG_USERNAME, WG_DAYS,
    DEL_CONFIRM,
    RENEW_DAYS,
) = range(16)


# ═══════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════
def read_file(path: str, default: str = "") -> str:
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        return default


def get_domain() -> str:
    return read_file(DOMAIN_FILE, "localhost")


def get_public_ip() -> str:
    try:
        return subprocess.check_output(
            ["curl", "-s", "ifconfig.me"], timeout=5
        ).decode().strip()
    except Exception:
        return "0.0.0.0"


def run_cmd(cmd: str, timeout: int = 30) -> str:
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "[timeout]"
    except Exception as e:
        return f"[error: {e}]"


def service_status(name: str) -> str:
    code = subprocess.call(
        ["systemctl", "is-active", "--quiet", name],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return "🟢 ON" if code == 0 else "🔴 OFF"


def get_admin_ids() -> list:
    raw = read_file(ADMIN_CHATID_FILE)
    if not raw:
        return []
    return [int(x.strip()) for x in raw.split(",") if x.strip().lstrip("-").isdigit()]


def admin_only(func):
    """Decorator to restrict access to admin chat IDs only."""
    @wraps(func)
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        user_id = update.effective_user.id
        admins = get_admin_ids()
        if admins and user_id not in admins:
            await update.effective_message.reply_text(
                "⛔ Access denied. Your Chat ID is not authorized."
            )
            logger.warning(f"Unauthorized access attempt by {user_id}")
            return ConversationHandler.END
        return await func(update, context)
    return wrapper


# ═══════════════════════════════════════════════════════
# Main Menu
# ═══════════════════════════════════════════════════════
def main_menu_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("🔐 SSH", callback_data="menu_ssh"),
            InlineKeyboardButton("⚡ Xray", callback_data="menu_xray"),
        ],
        [
            InlineKeyboardButton("🌐 NoobzVPN", callback_data="menu_noobz"),
            InlineKeyboardButton("🔒 L2TP", callback_data="menu_l2tp"),
        ],
        [
            InlineKeyboardButton("🛡 Wireguard", callback_data="menu_wg"),
            InlineKeyboardButton("⚙️ System", callback_data="menu_system"),
        ],
        [InlineKeyboardButton("📊 Server Info", callback_data="server_info")],
    ])


@admin_only
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    domain = get_domain()
    ip = get_public_ip()
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    🖥 <b>KUROVPN PANEL</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"  Domain : <code>{domain}</code>\n"
        f"  IP     : <code>{ip}</code>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  Select a menu below:"
    )
    if update.callback_query:
        await update.callback_query.edit_message_text(
            text, reply_markup=main_menu_keyboard(), parse_mode="HTML"
        )
    else:
        await update.message.reply_text(
            text, reply_markup=main_menu_keyboard(), parse_mode="HTML"
        )


# ═══════════════════════════════════════════════════════
# Server Info
# ═══════════════════════════════════════════════════════
@admin_only
async def server_info(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    uptime = run_cmd("uptime -p")
    cpu = run_cmd("top -bn1 | grep 'Cpu(s)' | awk '{print $2\"%\"}'")
    mem = run_cmd("free -h | awk 'NR==2{printf \"%s/%s (%.1f%%)\", $3,$2,$3*100/$2}'")
    disk = run_cmd("df -h / | awk 'NR==2{printf \"%s/%s (%s)\", $3,$2,$5}'")
    os_info = run_cmd("lsb_release -sd 2>/dev/null || cat /etc/os-release | head -1")
    domain = get_domain()
    ip = get_public_ip()

    services = {
        "SSH": service_status("ssh"),
        "Xray": service_status("xray"),
        "Nginx": service_status("nginx"),
        "NoobzVPN": service_status("noobzvpns"),
        "Dropbear": service_status("dropbear"),
        "Wireguard": service_status("wg-quick@wg0"),
        "L2TP": service_status("xl2tpd"),
        "IPsec": service_status("ipsec"),
    }
    svc_text = "\n".join(f"  {k:12s}: {v}" for k, v in services.items())

    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    📊 <b>SERVER INFO</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"  OS     : {os_info}\n"
        f"  Domain : {domain}\n"
        f"  IP     : {ip}\n"
        f"  Uptime : {uptime}\n"
        f"  CPU    : {cpu}\n"
        f"  RAM    : {mem}\n"
        f"  Disk   : {disk}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    <b>SERVICES</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"{svc_text}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")]
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


# ═══════════════════════════════════════════════════════
# SSH Management
# ═══════════════════════════════════════════════════════
def ssh_menu_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("➕ Create", callback_data="ssh_create"),
            InlineKeyboardButton("🗑 Delete", callback_data="ssh_delete"),
        ],
        [
            InlineKeyboardButton("🔄 Renew", callback_data="ssh_renew"),
            InlineKeyboardButton("📋 List", callback_data="ssh_list"),
        ],
        [
            InlineKeyboardButton("👥 Online", callback_data="ssh_online"),
        ],
        [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")],
    ])


@admin_only
async def menu_ssh(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    🔐 <b>SSH MENU</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  Manage SSH/Dropbear accounts"
    )
    await query.edit_message_text(text, reply_markup=ssh_menu_keyboard(), parse_mode="HTML")


@admin_only
async def ssh_create_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    await query.edit_message_text("🔐 <b>Create SSH Account</b>\n\nEnter username:", parse_mode="HTML")
    return SSH_USERNAME


@admin_only
async def ssh_create_username(update: Update, context: ContextTypes.DEFAULT_TYPE):
    username = update.message.text.strip()
    if not re.match(r'^[a-zA-Z0-9_]+$', username):
        await update.message.reply_text("❌ Invalid username. Use only letters, numbers, underscores.")
        return SSH_USERNAME
    # Check if user exists
    if run_cmd(f"id {username} 2>/dev/null"):
        await update.message.reply_text("❌ Username already exists. Try another.")
        return SSH_USERNAME
    context.user_data["ssh_user"] = username
    await update.message.reply_text(f"Username: <code>{username}</code>\n\nEnter password:", parse_mode="HTML")
    return SSH_PASSWORD


@admin_only
async def ssh_create_password(update: Update, context: ContextTypes.DEFAULT_TYPE):
    password = update.message.text.strip()
    if len(password) < 3:
        await update.message.reply_text("❌ Password too short (min 3 chars).")
        return SSH_PASSWORD
    context.user_data["ssh_pass"] = password
    await update.message.reply_text("Enter active days (e.g. 30):")
    return SSH_DAYS


@admin_only
async def ssh_create_days(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        days = int(update.message.text.strip())
    except ValueError:
        await update.message.reply_text("❌ Enter a valid number.")
        return SSH_DAYS

    username = context.user_data["ssh_user"]
    password = context.user_data["ssh_pass"]
    exp_date = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    domain = get_domain()

    # Create the user
    run_cmd(f'useradd -e {exp_date} -s /bin/false -M {username}')
    run_cmd(f'echo "{username}:{password}" | chpasswd')
    run_cmd("systemctl restart dropbear")

    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  ✅ <b>SSH Account Created</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"  Hostname : <code>{domain}</code>\n"
        f"  Username : <code>{username}</code>\n"
        f"  Password : <code>{password}</code>\n"
        f"  Expired  : {exp_date}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  WS HTTP  : 80, 2082, 2080\n"
        "  WS HTTPS : 443, 53, 2095\n"
        "  Dropbear : 109\n"
        "  UDPGW    : 7300\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 SSH Menu", callback_data="menu_ssh")],
        [InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")],
    ])
    await update.message.reply_text(text, reply_markup=keyboard, parse_mode="HTML")
    context.user_data.clear()
    return ConversationHandler.END


@admin_only
async def ssh_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(
        "awk -F: '$3 >= 1000 && $1 != \"nobody\" {print $1}' /etc/passwd"
    )
    if not output:
        text = "📋 No SSH accounts found."
    else:
        lines = []
        for user in output.split("\n"):
            user = user.strip()
            if not user:
                continue
            exp = run_cmd(f"chage -l {user} | grep 'Account expires' | awk -F': ' '{{print $2}}'")
            status = run_cmd(f"passwd -S {user} | awk '{{print $2}}'")
            status_icon = "🟢" if status != "L" else "🔴"
            lines.append(f"  {status_icon} <code>{user:15s}</code> {exp}")

        text = (
            "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            "    📋 <b>SSH Accounts</b>\n"
            "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            + "\n".join(lines) + "\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"  Total: {len(lines)} account(s)"
        )

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 SSH Menu", callback_data="menu_ssh")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


@admin_only
async def ssh_delete(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(
        "awk -F: '$3 >= 1000 && $1 != \"nobody\" {print $1}' /etc/passwd"
    )
    if not output:
        await query.edit_message_text("📋 No SSH accounts to delete.",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 SSH Menu", callback_data="menu_ssh")]]))
        return

    buttons = []
    for user in output.strip().split("\n"):
        user = user.strip()
        if user:
            buttons.append([InlineKeyboardButton(f"🗑 {user}", callback_data=f"ssh_del_{user}")])
    buttons.append([InlineKeyboardButton("🔙 SSH Menu", callback_data="menu_ssh")])

    await query.edit_message_text(
        "🗑 <b>Select SSH account to delete:</b>",
        reply_markup=InlineKeyboardMarkup(buttons),
        parse_mode="HTML",
    )


@admin_only
async def ssh_del_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    username = query.data.replace("ssh_del_", "")

    run_cmd(f"userdel {username}")
    run_cmd(f"rm -rf /etc/funny/limit/ssh/ip/{username}")

    text = f"✅ SSH account <code>{username}</code> deleted."
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 SSH Menu", callback_data="menu_ssh")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


@admin_only
async def ssh_renew(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd("awk -F: '$3 >= 1000 && $1 != \"nobody\" {print $1}' /etc/passwd")
    if not output:
        await query.edit_message_text("📋 No SSH accounts to renew.",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 SSH Menu", callback_data="menu_ssh")]]))
        return

    buttons = []
    for user in output.strip().split("\n"):
        user = user.strip()
        if user:
            buttons.append([InlineKeyboardButton(f"🔄 {user}", callback_data=f"ssh_ren_{user}")])
    buttons.append([InlineKeyboardButton("🔙 SSH Menu", callback_data="menu_ssh")])
    await query.edit_message_text("🔄 <b>Select SSH account to renew:</b>",
        reply_markup=InlineKeyboardMarkup(buttons), parse_mode="HTML")


@admin_only
async def ssh_ren_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    username = query.data.replace("ssh_ren_", "")
    context.user_data["renew_user"] = username
    context.user_data["renew_type"] = "ssh"
    await query.edit_message_text(f"🔄 Renewing <code>{username}</code>\n\nEnter days to extend:", parse_mode="HTML")
    return RENEW_DAYS


@admin_only
async def ssh_online(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(
        "who | awk '{print $1}' | sort | uniq -c | sort -rn"
    )
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    👥 <b>SSH Online Users</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    )
    if output:
        text += output + "\n"
    else:
        text += "  No users currently online.\n"
    text += "━━━━━━━━━━━━━━━━━━━━━━━━━"

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 SSH Menu", callback_data="menu_ssh")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


# ═══════════════════════════════════════════════════════
# Xray Management
# ═══════════════════════════════════════════════════════
def xray_menu_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("➕ VMess", callback_data="xray_vmess"),
            InlineKeyboardButton("➕ VLess", callback_data="xray_vless"),
        ],
        [
            InlineKeyboardButton("➕ Trojan", callback_data="xray_trojan"),
            InlineKeyboardButton("➕ SS", callback_data="xray_ss"),
        ],
        [
            InlineKeyboardButton("🗑 Delete", callback_data="xray_delete"),
            InlineKeyboardButton("📋 List", callback_data="xray_list"),
        ],
        [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")],
    ])


@admin_only
async def menu_xray(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    ⚡ <b>XRAY MENU</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  Manage VMess/VLess/Trojan/SS"
    )
    await query.edit_message_text(text, reply_markup=xray_menu_keyboard(), parse_mode="HTML")


@admin_only
async def xray_create_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    proto = query.data.replace("xray_", "")
    context.user_data["xray_proto"] = proto
    await query.edit_message_text(
        f"⚡ <b>Create {proto.upper()} Account</b>\n\nEnter username:",
        parse_mode="HTML",
    )
    return XRAY_USERNAME


@admin_only
async def xray_create_username(update: Update, context: ContextTypes.DEFAULT_TYPE):
    username = update.message.text.strip()
    if not re.match(r'^[a-zA-Z0-9_]+$', username):
        await update.message.reply_text("❌ Invalid username.")
        return XRAY_USERNAME
    # Check if exists in xray config
    exists = run_cmd(f"grep -cw '{username}' {XRAY_CONFIG}")
    if exists and int(exists) > 0:
        await update.message.reply_text("❌ Username already exists in Xray config.")
        return XRAY_USERNAME
    context.user_data["xray_user"] = username
    await update.message.reply_text("Enter active days (e.g. 30):")
    return XRAY_DAYS


@admin_only
async def xray_create_days(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        days = int(update.message.text.strip())
    except ValueError:
        await update.message.reply_text("❌ Enter a valid number.")
        return XRAY_DAYS

    proto = context.user_data["xray_proto"]
    username = context.user_data["xray_user"]
    domain = get_domain()
    exp = (datetime.now() + timedelta(days=days)).strftime("%y-%m-%d")
    new_uuid = run_cmd("xray uuid") or str(uuid.uuid4())

    # Insert into xray config based on protocol
    if proto == "vmess":
        tag = "#vmess"
        entry = f'### {username} {exp}\n,{{"id": "{new_uuid}","alterid": 0,"email": "{username}"}}'
        run_cmd(f"sed -i '/{tag}$/a\\{entry}' {XRAY_CONFIG}")

        vmess_json = json.dumps({
            "v": "2", "ps": username, "add": domain, "port": "443",
            "id": new_uuid, "aid": "0", "net": "ws", "path": "/vmessws",
            "type": "none", "host": domain, "tls": "tls"
        })
        link = "vmess://" + base64.b64encode(vmess_json.encode()).decode()
        port_info = "Port TLS: 443 | HTTP: 80\nPath: /vmessws"

    elif proto == "vless":
        tag = "#vless"
        entry = f'### {username} {exp}\n,{{"id": "{new_uuid}","email": "{username}"}}'
        run_cmd(f"sed -i '/{tag}$/a\\{entry}' {XRAY_CONFIG}")
        link = f"vless://{new_uuid}@{domain}:443?path=/vlessws&security=tls&encryption=none&host={domain}&type=ws&sni={domain}#{username}"
        port_info = "Port TLS: 443 | HTTP: 80\nPath: /vlessws"

    elif proto == "trojan":
        tag = "#trojan"
        entry = f'### {username} {exp}\n,{{"password": "{username}","email": "{username}"}}'
        run_cmd(f"sed -i '/{tag}$/a\\{entry}' {XRAY_CONFIG}")
        link = f"trojan://{username}@{domain}:443?path=%2ftrojanws&security=tls&host={domain}&type=ws&sni={domain}#{username}"
        port_info = "Port: 443\nPath: /trojanws"

    elif proto == "ss":
        tag = "#ssws"
        entry = f'### {username} {exp}\n,{{"password": "{new_uuid}","method": "aes-128-gcm","email": "{username}"}}'
        run_cmd(f"sed -i '/{tag}$/a\\{entry}' {XRAY_CONFIG}")
        ss_cred = base64.b64encode(f"aes-128-gcm:{new_uuid}".encode()).decode()
        link = f"ss://{ss_cred}@{domain}:443?path=/ssws&security=tls&host={domain}&type=ws&sni={domain}#{username}"
        port_info = "Port: 443\nPath: /ssws\nCipher: aes-128-gcm"

    run_cmd("systemctl daemon-reload && systemctl restart xray")

    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"  ✅ <b>{proto.upper()} Account Created</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"  Hostname : <code>{domain}</code>\n"
        f"  Username : <code>{username}</code>\n"
        f"  UUID     : <code>{new_uuid}</code>\n"
        f"  Expired  : {exp}\n"
        f"  {port_info}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"  <code>{link}</code>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 Xray Menu", callback_data="menu_xray")],
        [InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")],
    ])
    await update.message.reply_text(text, reply_markup=keyboard, parse_mode="HTML")
    context.user_data.clear()
    return ConversationHandler.END


@admin_only
async def xray_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(f"grep -E '^### ' {XRAY_CONFIG} | cut -d ' ' -f 2-3 | sort | uniq")
    if not output:
        text = "📋 No Xray accounts found."
    else:
        lines = [f"  <code>{line.strip()}</code>" for line in output.split("\n") if line.strip()]
        text = (
            "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            "    📋 <b>Xray Accounts</b>\n"
            "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            + "\n".join(lines) + "\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"  Total: {len(lines)} account(s)"
        )

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 Xray Menu", callback_data="menu_xray")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


@admin_only
async def xray_delete(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(f"grep -E '^### ' {XRAY_CONFIG} | cut -d ' ' -f 2 | sort | uniq")
    if not output:
        await query.edit_message_text("📋 No Xray accounts to delete.",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Xray Menu", callback_data="menu_xray")]]))
        return

    buttons = []
    for user in output.strip().split("\n"):
        user = user.strip()
        if user:
            buttons.append([InlineKeyboardButton(f"🗑 {user}", callback_data=f"xray_del_{user}")])
    buttons.append([InlineKeyboardButton("🔙 Xray Menu", callback_data="menu_xray")])
    await query.edit_message_text("🗑 <b>Select Xray account to delete:</b>",
        reply_markup=InlineKeyboardMarkup(buttons), parse_mode="HTML")


@admin_only
async def xray_del_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    username = query.data.replace("xray_del_", "")

    exp = run_cmd(f"grep -wE '^### {username}' {XRAY_CONFIG} | cut -d ' ' -f 3 | head -1")
    run_cmd(f"sed -i '/^### {username} {exp}/,/^}},{{/d' {XRAY_CONFIG}")
    run_cmd("systemctl restart xray")

    text = f"✅ Xray account <code>{username}</code> deleted."
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 Xray Menu", callback_data="menu_xray")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


# ═══════════════════════════════════════════════════════
# NoobzVPN Management
# ═══════════════════════════════════════════════════════
def noobz_menu_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("➕ Create", callback_data="noobz_create"),
            InlineKeyboardButton("🗑 Delete", callback_data="noobz_delete"),
        ],
        [InlineKeyboardButton("📋 List", callback_data="noobz_list")],
        [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")],
    ])


@admin_only
async def menu_noobz(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    🌐 <b>NOOBZVPN MENU</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  Manage NoobzVPN accounts"
    )
    await query.edit_message_text(text, reply_markup=noobz_menu_keyboard(), parse_mode="HTML")


@admin_only
async def noobz_create_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    await query.edit_message_text("🌐 <b>Create NoobzVPN Account</b>\n\nEnter username:", parse_mode="HTML")
    return NOOB_USERNAME


@admin_only
async def noobz_create_username(update: Update, context: ContextTypes.DEFAULT_TYPE):
    username = update.message.text.strip()
    context.user_data["noobz_user"] = username
    await update.message.reply_text("Enter password:")
    return NOOB_PASSWORD


@admin_only
async def noobz_create_password(update: Update, context: ContextTypes.DEFAULT_TYPE):
    password = update.message.text.strip()
    context.user_data["noobz_pass"] = password
    await update.message.reply_text("Enter active days (e.g. 30):")
    return NOOB_DAYS


@admin_only
async def noobz_create_days(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        days = int(update.message.text.strip())
    except ValueError:
        await update.message.reply_text("❌ Enter a valid number.")
        return NOOB_DAYS

    username = context.user_data["noobz_user"]
    password = context.user_data["noobz_pass"]
    domain = get_domain()
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")

    run_cmd(f'noobzvpns --add-user "{username}" "{password}"')
    run_cmd(f'noobzvpns --expired-user "{username}" "{days}"')

    # Track in database
    with open(NOOB_DB, "a") as f:
        f.write(f"### {username} {exp}\n")

    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  ✅ <b>NoobzVPN Account Created</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"  Hostname : <code>{domain}</code>\n"
        f"  Username : <code>{username}</code>\n"
        f"  Password : <code>{password}</code>\n"
        f"  Expired  : {exp}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  TCP STD  : 8080\n"
        "  TCP SSL  : 9443\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 NoobzVPN Menu", callback_data="menu_noobz")],
        [InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")],
    ])
    await update.message.reply_text(text, reply_markup=keyboard, parse_mode="HTML")
    context.user_data.clear()
    return ConversationHandler.END


@admin_only
async def noobz_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd("noobzvpns --info-all-user 2>/dev/null")
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    📋 <b>NoobzVPN Accounts</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    )
    text += (output if output else "  No accounts found.") + "\n━━━━━━━━━━━━━━━━━━━━━━━━━"

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 NoobzVPN Menu", callback_data="menu_noobz")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


@admin_only
async def noobz_delete(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(f"grep -E '^### ' {NOOB_DB} 2>/dev/null | cut -d ' ' -f 2 | sort | uniq")
    if not output:
        await query.edit_message_text("📋 No NoobzVPN accounts to delete.",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 NoobzVPN Menu", callback_data="menu_noobz")]]))
        return

    buttons = []
    for user in output.strip().split("\n"):
        user = user.strip()
        if user:
            buttons.append([InlineKeyboardButton(f"🗑 {user}", callback_data=f"noobz_del_{user}")])
    buttons.append([InlineKeyboardButton("🔙 NoobzVPN Menu", callback_data="menu_noobz")])
    await query.edit_message_text("🗑 <b>Select NoobzVPN account to delete:</b>",
        reply_markup=InlineKeyboardMarkup(buttons), parse_mode="HTML")


@admin_only
async def noobz_del_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    username = query.data.replace("noobz_del_", "")

    run_cmd(f'noobzvpns --remove-user "{username}"')
    exp = run_cmd(f"grep -w '^### {username}' {NOOB_DB} | cut -d ' ' -f 3 | head -1")
    run_cmd(f"sed -i '/^### {username} {exp}/d' {NOOB_DB}")

    text = f"✅ NoobzVPN account <code>{username}</code> deleted."
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 NoobzVPN Menu", callback_data="menu_noobz")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


# ═══════════════════════════════════════════════════════
# L2TP Management
# ═══════════════════════════════════════════════════════
def l2tp_menu_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("➕ Create", callback_data="l2tp_create"),
            InlineKeyboardButton("🗑 Delete", callback_data="l2tp_delete"),
        ],
        [InlineKeyboardButton("📋 List", callback_data="l2tp_list")],
        [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")],
    ])


@admin_only
async def menu_l2tp(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    🔒 <b>L2TP/IPSEC MENU</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  Manage L2TP/IPsec PSK accounts"
    )
    await query.edit_message_text(text, reply_markup=l2tp_menu_keyboard(), parse_mode="HTML")


@admin_only
async def l2tp_create_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    await query.edit_message_text("🔒 <b>Create L2TP Account</b>\n\nEnter username:", parse_mode="HTML")
    return L2TP_USERNAME


@admin_only
async def l2tp_create_username(update: Update, context: ContextTypes.DEFAULT_TYPE):
    username = update.message.text.strip()
    context.user_data["l2tp_user"] = username
    await update.message.reply_text("Enter password:")
    return L2TP_PASSWORD


@admin_only
async def l2tp_create_password(update: Update, context: ContextTypes.DEFAULT_TYPE):
    password = update.message.text.strip()
    context.user_data["l2tp_pass"] = password
    await update.message.reply_text("Enter active days (e.g. 30):")
    return L2TP_DAYS


@admin_only
async def l2tp_create_days(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        days = int(update.message.text.strip())
    except ValueError:
        await update.message.reply_text("❌ Enter a valid number.")
        return L2TP_DAYS

    username = context.user_data["l2tp_user"]
    password = context.user_data["l2tp_pass"]
    domain = get_domain()
    ip = get_public_ip()
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")

    # Add to chap-secrets and ipsec passwd
    with open("/etc/ppp/chap-secrets", "a") as f:
        f.write(f'"{username}" l2tpd "{password}" *\n')
    enc_pass = run_cmd(f'openssl passwd -1 "{password}"')
    with open("/etc/ipsec.d/passwd", "a") as f:
        f.write(f"{username}:{enc_pass}:xauth-psk\n")
    run_cmd("chmod 600 /etc/ppp/chap-secrets* /etc/ipsec.d/passwd*")

    # Track
    with open(L2TP_DB, "a") as f:
        f.write(f"### {username} {exp}\n")

    run_cmd("systemctl restart xl2tpd ipsec")

    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  ✅ <b>L2TP Account Created</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"  Hostname : <code>{domain}</code> / <code>{ip}</code>\n"
        f"  Username : <code>{username}</code>\n"
        f"  Password : <code>{password}</code>\n"
        f"  Key/Auth : <code>myvpn</code>\n"
        f"  Expired  : {exp}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 L2TP Menu", callback_data="menu_l2tp")],
        [InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")],
    ])
    await update.message.reply_text(text, reply_markup=keyboard, parse_mode="HTML")
    context.user_data.clear()
    return ConversationHandler.END


@admin_only
async def l2tp_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(f"grep -E '^### ' {L2TP_DB} 2>/dev/null | cut -d ' ' -f 2-3 | column -t | sort | uniq")
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    📋 <b>L2TP Accounts</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    )
    if output:
        lines = [f"  <code>{l.strip()}</code>" for l in output.split("\n") if l.strip()]
        text += "\n".join(lines) + f"\n━━━━━━━━━━━━━━━━━━━━━━━━━\n  Total: {len(lines)} account(s)"
    else:
        text += "  No accounts found.\n━━━━━━━━━━━━━━━━━━━━━━━━━"

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 L2TP Menu", callback_data="menu_l2tp")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


@admin_only
async def l2tp_delete(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(f"grep -E '^### ' {L2TP_DB} 2>/dev/null | cut -d ' ' -f 2 | sort | uniq")
    if not output:
        await query.edit_message_text("📋 No L2TP accounts to delete.",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 L2TP Menu", callback_data="menu_l2tp")]]))
        return

    buttons = []
    for user in output.strip().split("\n"):
        user = user.strip()
        if user:
            buttons.append([InlineKeyboardButton(f"🗑 {user}", callback_data=f"l2tp_del_{user}")])
    buttons.append([InlineKeyboardButton("🔙 L2TP Menu", callback_data="menu_l2tp")])
    await query.edit_message_text("🗑 <b>Select L2TP account to delete:</b>",
        reply_markup=InlineKeyboardMarkup(buttons), parse_mode="HTML")


@admin_only
async def l2tp_del_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    username = query.data.replace("l2tp_del_", "")

    run_cmd(f"sed -i '/^\"{username}\" l2tpd/d' /etc/ppp/chap-secrets")
    run_cmd(f"sed -i '/^{username}:\\$1\\$/d' /etc/ipsec.d/passwd")
    exp = run_cmd(f"grep -w '^### {username}' {L2TP_DB} | cut -d ' ' -f 3 | head -1")
    run_cmd(f"sed -i '/^### {username} {exp}/d' {L2TP_DB}")
    run_cmd("chmod 600 /etc/ppp/chap-secrets* /etc/ipsec.d/passwd*")

    text = f"✅ L2TP account <code>{username}</code> deleted."
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 L2TP Menu", callback_data="menu_l2tp")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


# ═══════════════════════════════════════════════════════
# Wireguard Management
# ═══════════════════════════════════════════════════════
def wg_menu_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("➕ Create", callback_data="wg_create"),
            InlineKeyboardButton("🗑 Delete", callback_data="wg_delete"),
        ],
        [
            InlineKeyboardButton("📋 List", callback_data="wg_list"),
            InlineKeyboardButton("📄 Config", callback_data="wg_config_list"),
        ],
        [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")],
    ])


@admin_only
async def menu_wg(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    🛡 <b>WIREGUARD MENU</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  Manage Wireguard accounts"
    )
    await query.edit_message_text(text, reply_markup=wg_menu_keyboard(), parse_mode="HTML")


@admin_only
async def wg_create_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    await query.edit_message_text("🛡 <b>Create Wireguard Account</b>\n\nEnter username:", parse_mode="HTML")
    return WG_USERNAME


@admin_only
async def wg_create_username(update: Update, context: ContextTypes.DEFAULT_TYPE):
    username = update.message.text.strip()
    if not re.match(r'^[a-zA-Z0-9_]+$', username):
        await update.message.reply_text("❌ Invalid username.")
        return WG_USERNAME
    context.user_data["wg_user"] = username
    await update.message.reply_text("Enter active days (e.g. 30):")
    return WG_DAYS


@admin_only
async def wg_create_days(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        days = int(update.message.text.strip())
    except ValueError:
        await update.message.reply_text("❌ Enter a valid number.")
        return WG_DAYS

    username = context.user_data["wg_user"]
    # Delegate to the shell script Menu-WGF for the heavy lifting
    # But we do it inline here for the bot
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    domain = get_domain()
    ip = get_public_ip()

    # Load WG params
    wg_params = {}
    if os.path.exists(WG_PARAMS):
        for line in open(WG_PARAMS):
            if "=" in line:
                k, v = line.strip().split("=", 1)
                wg_params[k] = v

    server_pub_key = wg_params.get("SERVER_PUB_KEY", "")
    server_port = wg_params.get("SERVER_PORT", "2048")

    # Generate keys
    client_priv = run_cmd("wg genkey")
    client_pub = run_cmd(f"echo '{client_priv}' | wg pubkey")
    client_psk = run_cmd("wg genpsk")

    # Find next IP
    last_ip = run_cmd(f"grep -oP '10\\.66\\.66\\.\\K[0-9]+' {WG_CONF} | sort -n | tail -1")
    next_octet = max(int(last_ip) + 1, 2) if last_ip and last_ip.isdigit() else 2
    client_ip = f"10.66.66.{next_octet}"

    # Add to wg0.conf
    with open(WG_CONF, "a") as f:
        f.write(f"\n### {username} {exp}\n[Peer]\nPublicKey = {client_pub}\nPresharedKey = {client_psk}\nAllowedIPs = {client_ip}/32\n")

    # Save client config
    os.makedirs(WG_CLIENTS_DIR, exist_ok=True)
    config_content = (
        f"[Interface]\nPrivateKey = {client_priv}\nAddress = {client_ip}/32\nDNS = 1.1.1.1, 8.8.8.8\n\n"
        f"[Peer]\nPublicKey = {server_pub_key}\nPresharedKey = {client_psk}\n"
        f"Endpoint = {ip}:{server_port}\nAllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 25\n"
    )
    config_path = f"{WG_CLIENTS_DIR}/{username}.conf"
    with open(config_path, "w") as f:
        f.write(config_content)

    # Track
    with open(WG_DB, "a") as f:
        f.write(f"### {username} {exp}\n")

    # Reload
    run_cmd("wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || systemctl restart wg-quick@wg0")

    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  ✅ <b>Wireguard Account Created</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"  Hostname  : <code>{domain}</code>\n"
        f"  Username  : <code>{username}</code>\n"
        f"  Client IP : <code>{client_ip}</code>\n"
        f"  Port      : {server_port}\n"
        f"  Expired   : {exp}\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("📄 Get Config", callback_data=f"wg_cfg_{username}")],
        [InlineKeyboardButton("🔙 WG Menu", callback_data="menu_wg")],
        [InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")],
    ])
    await update.message.reply_text(text, reply_markup=keyboard, parse_mode="HTML")
    context.user_data.clear()
    return ConversationHandler.END


@admin_only
async def wg_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(f"grep -E '^### ' {WG_DB} 2>/dev/null | cut -d ' ' -f 2-3 | sort | uniq")
    if not output:
        text = "📋 No Wireguard accounts found."
    else:
        lines = [f"  <code>{l.strip()}</code>" for l in output.split("\n") if l.strip()]
        text = (
            "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            "    📋 <b>Wireguard Accounts</b>\n"
            "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            + "\n".join(lines) + f"\n"
            f"━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            f"  Total: {len(lines)} account(s)"
        )

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 WG Menu", callback_data="menu_wg")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


@admin_only
async def wg_delete(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(f"grep -E '^### ' {WG_DB} 2>/dev/null | cut -d ' ' -f 2 | sort | uniq")
    if not output:
        await query.edit_message_text("📋 No Wireguard accounts to delete.",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 WG Menu", callback_data="menu_wg")]]))
        return

    buttons = []
    for user in output.strip().split("\n"):
        user = user.strip()
        if user:
            buttons.append([InlineKeyboardButton(f"🗑 {user}", callback_data=f"wg_del_{user}")])
    buttons.append([InlineKeyboardButton("🔙 WG Menu", callback_data="menu_wg")])
    await query.edit_message_text("🗑 <b>Select Wireguard account to delete:</b>",
        reply_markup=InlineKeyboardMarkup(buttons), parse_mode="HTML")


@admin_only
async def wg_del_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    username = query.data.replace("wg_del_", "")

    exp = run_cmd(f"grep -w '^### {username}' {WG_DB} | cut -d ' ' -f 3 | head -1")
    run_cmd(f"sed -i '/^### {username} {exp}/,/^$/d' {WG_CONF}")
    run_cmd(f"rm -f {WG_CLIENTS_DIR}/{username}.conf")
    run_cmd(f"sed -i '/^### {username} {exp}/d' {WG_DB}")
    run_cmd("wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || systemctl restart wg-quick@wg0")

    text = f"✅ Wireguard account <code>{username}</code> deleted."
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 WG Menu", callback_data="menu_wg")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


@admin_only
async def wg_show_config(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    username = query.data.replace("wg_cfg_", "")
    config_path = f"{WG_CLIENTS_DIR}/{username}.conf"

    if os.path.exists(config_path):
        with open(config_path) as f:
            config = f.read()
        text = (
            f"📄 <b>Config: {username}</b>\n\n"
            f"<code>{config}</code>"
        )
    else:
        text = f"❌ Config not found for {username}."

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 WG Menu", callback_data="menu_wg")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


@admin_only
async def wg_config_list(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd(f"grep -E '^### ' {WG_DB} 2>/dev/null | cut -d ' ' -f 2 | sort | uniq")
    if not output:
        await query.edit_message_text("📋 No configs available.",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 WG Menu", callback_data="menu_wg")]]))
        return

    buttons = []
    for user in output.strip().split("\n"):
        user = user.strip()
        if user:
            buttons.append([InlineKeyboardButton(f"📄 {user}", callback_data=f"wg_cfg_{user}")])
    buttons.append([InlineKeyboardButton("🔙 WG Menu", callback_data="menu_wg")])
    await query.edit_message_text("📄 <b>Select client to view config:</b>",
        reply_markup=InlineKeyboardMarkup(buttons), parse_mode="HTML")


# ═══════════════════════════════════════════════════════
# System Management
# ═══════════════════════════════════════════════════════
def system_menu_keyboard():
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("🔄 Restart All", callback_data="sys_restart_all"),
            InlineKeyboardButton("📊 Bandwidth", callback_data="sys_bandwidth"),
        ],
        [
            InlineKeyboardButton("🔄 Xray", callback_data="sys_restart_xray"),
            InlineKeyboardButton("🔄 SSH", callback_data="sys_restart_ssh"),
        ],
        [
            InlineKeyboardButton("🔄 Nginx", callback_data="sys_restart_nginx"),
            InlineKeyboardButton("🔄 WG", callback_data="sys_restart_wg"),
        ],
        [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")],
    ])


@admin_only
async def menu_system(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    ⚙️ <b>SYSTEM MENU</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "  Restart services & monitor"
    )
    await query.edit_message_text(text, reply_markup=system_menu_keyboard(), parse_mode="HTML")


@admin_only
async def sys_restart(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer("Restarting...")

    action = query.data.replace("sys_restart_", "")
    if action == "all":
        run_cmd("systemctl restart ssh dropbear nginx xray noobzvpns wg-quick@wg0 xl2tpd ipsec 2>/dev/null")
        text = "✅ All services restarted."
    elif action == "xray":
        run_cmd("systemctl restart xray")
        text = "✅ Xray restarted."
    elif action == "ssh":
        run_cmd("systemctl restart ssh dropbear")
        text = "✅ SSH & Dropbear restarted."
    elif action == "nginx":
        run_cmd("systemctl restart nginx")
        text = "✅ Nginx restarted."
    elif action == "wg":
        run_cmd("systemctl restart wg-quick@wg0")
        text = "✅ Wireguard restarted."
    else:
        text = "❌ Unknown service."

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 System Menu", callback_data="menu_system")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


@admin_only
async def sys_bandwidth(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()

    output = run_cmd("vnstat --oneline 2>/dev/null")
    if not output or "Error" in output:
        output = run_cmd("vnstat -d 5 2>/dev/null") or "vnstat not available."

    text = (
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "    📊 <b>BANDWIDTH</b>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"<code>{output[:3500]}</code>\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━"
    )
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 System Menu", callback_data="menu_system")],
    ])
    await query.edit_message_text(text, reply_markup=keyboard, parse_mode="HTML")


# ═══════════════════════════════════════════════════════
# Renew handler (shared across protocols)
# ═══════════════════════════════════════════════════════
@admin_only
async def renew_days_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        days = int(update.message.text.strip())
    except ValueError:
        await update.message.reply_text("❌ Enter a valid number.")
        return RENEW_DAYS

    username = context.user_data.get("renew_user", "")
    renew_type = context.user_data.get("renew_type", "")

    if renew_type == "ssh":
        exp_raw = run_cmd(f"chage -l {username} | grep 'Account expires' | awk -F': ' '{{print $2}}'")
        new_exp = (datetime.now() + timedelta(days=days)).strftime("%Y/%m/%d")
        run_cmd(f"passwd -u {username} 2>/dev/null")
        run_cmd(f"usermod -e {new_exp} {username}")
        text = f"✅ SSH <code>{username}</code> extended by {days} days.\nNew expiry: {new_exp}"

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("🔙 Main Menu", callback_data="main_menu")],
    ])
    await update.message.reply_text(text, reply_markup=keyboard, parse_mode="HTML")
    context.user_data.clear()
    return ConversationHandler.END


async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data.clear()
    await update.message.reply_text("❌ Operation cancelled.",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🏠 Main Menu", callback_data="main_menu")]]))
    return ConversationHandler.END


# ═══════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════
def main():
    token = read_file(BOT_TOKEN_FILE)
    if not token:
        logger.error(f"Bot token not found. Set it in {BOT_TOKEN_FILE}")
        logger.error("Use the 'botmenu' command on your server to configure it.")
        return

    app = Application.builder().token(token).build()

    # Conversation handlers for multi-step account creation
    ssh_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(ssh_create_start, pattern="^ssh_create$")],
        states={
            SSH_USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, ssh_create_username)],
            SSH_PASSWORD: [MessageHandler(filters.TEXT & ~filters.COMMAND, ssh_create_password)],
            SSH_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, ssh_create_days)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    xray_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(xray_create_start, pattern="^xray_(vmess|vless|trojan|ss)$")],
        states={
            XRAY_USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, xray_create_username)],
            XRAY_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, xray_create_days)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    noobz_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(noobz_create_start, pattern="^noobz_create$")],
        states={
            NOOB_USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, noobz_create_username)],
            NOOB_PASSWORD: [MessageHandler(filters.TEXT & ~filters.COMMAND, noobz_create_password)],
            NOOB_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, noobz_create_days)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    l2tp_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(l2tp_create_start, pattern="^l2tp_create$")],
        states={
            L2TP_USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, l2tp_create_username)],
            L2TP_PASSWORD: [MessageHandler(filters.TEXT & ~filters.COMMAND, l2tp_create_password)],
            L2TP_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, l2tp_create_days)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    wg_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(wg_create_start, pattern="^wg_create$")],
        states={
            WG_USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, wg_create_username)],
            WG_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, wg_create_days)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    renew_conv = ConversationHandler(
        entry_points=[CallbackQueryHandler(ssh_ren_start, pattern="^ssh_ren_")],
        states={
            RENEW_DAYS: [MessageHandler(filters.TEXT & ~filters.COMMAND, renew_days_handler)],
        },
        fallbacks=[CommandHandler("cancel", cancel)],
    )

    # Register conversation handlers first (order matters)
    app.add_handler(ssh_conv)
    app.add_handler(xray_conv)
    app.add_handler(noobz_conv)
    app.add_handler(l2tp_conv)
    app.add_handler(wg_conv)
    app.add_handler(renew_conv)

    # Commands
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("menu", start))

    # Callback query handlers
    app.add_handler(CallbackQueryHandler(start, pattern="^main_menu$"))
    app.add_handler(CallbackQueryHandler(server_info, pattern="^server_info$"))

    # SSH
    app.add_handler(CallbackQueryHandler(menu_ssh, pattern="^menu_ssh$"))
    app.add_handler(CallbackQueryHandler(ssh_list, pattern="^ssh_list$"))
    app.add_handler(CallbackQueryHandler(ssh_delete, pattern="^ssh_delete$"))
    app.add_handler(CallbackQueryHandler(ssh_del_confirm, pattern="^ssh_del_"))
    app.add_handler(CallbackQueryHandler(ssh_renew, pattern="^ssh_renew$"))
    app.add_handler(CallbackQueryHandler(ssh_online, pattern="^ssh_online$"))

    # Xray
    app.add_handler(CallbackQueryHandler(menu_xray, pattern="^menu_xray$"))
    app.add_handler(CallbackQueryHandler(xray_list, pattern="^xray_list$"))
    app.add_handler(CallbackQueryHandler(xray_delete, pattern="^xray_delete$"))
    app.add_handler(CallbackQueryHandler(xray_del_confirm, pattern="^xray_del_"))

    # NoobzVPN
    app.add_handler(CallbackQueryHandler(menu_noobz, pattern="^menu_noobz$"))
    app.add_handler(CallbackQueryHandler(noobz_list, pattern="^noobz_list$"))
    app.add_handler(CallbackQueryHandler(noobz_delete, pattern="^noobz_delete$"))
    app.add_handler(CallbackQueryHandler(noobz_del_confirm, pattern="^noobz_del_"))

    # L2TP
    app.add_handler(CallbackQueryHandler(menu_l2tp, pattern="^menu_l2tp$"))
    app.add_handler(CallbackQueryHandler(l2tp_list, pattern="^l2tp_list$"))
    app.add_handler(CallbackQueryHandler(l2tp_delete, pattern="^l2tp_delete$"))
    app.add_handler(CallbackQueryHandler(l2tp_del_confirm, pattern="^l2tp_del_"))

    # Wireguard
    app.add_handler(CallbackQueryHandler(menu_wg, pattern="^menu_wg$"))
    app.add_handler(CallbackQueryHandler(wg_list, pattern="^wg_list$"))
    app.add_handler(CallbackQueryHandler(wg_delete, pattern="^wg_delete$"))
    app.add_handler(CallbackQueryHandler(wg_del_confirm, pattern="^wg_del_"))
    app.add_handler(CallbackQueryHandler(wg_show_config, pattern="^wg_cfg_"))
    app.add_handler(CallbackQueryHandler(wg_config_list, pattern="^wg_config_list$"))

    # System
    app.add_handler(CallbackQueryHandler(menu_system, pattern="^menu_system$"))
    app.add_handler(CallbackQueryHandler(sys_restart, pattern="^sys_restart_"))
    app.add_handler(CallbackQueryHandler(sys_bandwidth, pattern="^sys_bandwidth$"))

    logger.info("🚀 KUROVPN Bot started. Polling for updates...")
    app.run_polling(drop_pending_updates=True)


if __name__ == "__main__":
    main()
