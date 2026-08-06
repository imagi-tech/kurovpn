#!/usr/bin/env python3
"""
KUROVPN Telegram Bot — Admin-only VPN account management.
https://github.com/imagi-tech/kurovpn

Security model:
  - Fail-closed: if no admin chat IDs are configured, the bot refuses ALL commands.
  - No shell=True anywhere — all subprocess calls use list args.
  - Admin IDs read from /etc/funny/.chatid (one per line).

Usage:
  python3 bot.py
  (reads BOT_TOKEN from /etc/funny/.keybot)
"""

from __future__ import annotations

import os
import json
import subprocess
import sys
import urllib.request
import urllib.parse
import time
from typing import Optional, Set

# ── Configuration ──────────────────────────────────────
KEYBOT_FILE = "/etc/funny/.keybot"
CHATID_FILE = "/etc/funny/.chatid"
DOMAIN_FILE = "/etc/xray/domain"

def load_token() -> Optional[str]:
    try:
        with open(KEYBOT_FILE) as f:
            return f.read().strip()
    except FileNotFoundError:
        return None

def load_admins() -> Set[int]:
    admins = set()
    try:
        with open(CHATID_FILE) as f:
            for line in f:
                line = line.strip()
                if line:
                    admins.add(int(line))
    except (FileNotFoundError, ValueError):
        pass
    return admins

def get_domain() -> str:
    try:
        with open(DOMAIN_FILE) as f:
            return f.read().strip()
    except FileNotFoundError:
        return "unknown"

TOKEN = load_token()
ADMIN_IDS = load_admins()
DOMAIN = get_domain()

if not TOKEN:
    print("[FATAL] No bot token found in", KEYBOT_FILE)
    sys.exit(1)

API_URL = f"https://api.telegram.org/bot{TOKEN}"

# ── Admin check ────────────────────────────────────────
def is_admin(user_id: int) -> bool:
    if not ADMIN_IDS:
        return False  # fail-closed: no admins = no access
    return user_id in ADMIN_IDS

# ── Telegram API helpers ───────────────────────────────
def api_call(method: str, data: dict) -> dict:
    url = f"{API_URL}/{method}"
    encoded = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=encoded)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())

def send_message(chat_id: int, text: str, reply_markup: Optional[dict] = None) -> dict:
    data = {"chat_id": chat_id, "text": text, "parse_mode": "HTML"}
    if reply_markup:
        data["reply_markup"] = json.dumps(reply_markup)
    return api_call("sendMessage", data)

def answer_callback(callback_id: str, text: str = ""):
    api_call("answerCallbackQuery", {"callback_query_id": callback_id, "text": text})

# ── Subprocess runner (secure: no shell) ───────────────
def run(cmd, stdin_str: str = "") -> tuple:
    """Run command with list args, optionally pipe stdin string. Returns (rc, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, input=stdin_str, capture_output=True, text=True, timeout=30)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"

def run_ssh(user: str, password: str, days: str) -> str:
    cmd = ["/usr/bin/addssh"]
    stdin = f"{user}\n{password}\n{days}\n2\n"
    rc, out, err = run(cmd, stdin)
    if rc != 0:
        return f"Error: {err or out}"
    return out.strip()

def run_vmess(user: str, days: str) -> str:
    cmd = ["/usr/bin/add-vmess"]
    stdin = f"{user}\n{days}\n"
    rc, out, err = run(cmd, stdin)
    if rc != 0:
        return f"Error: {err or out}"
    return out.strip()

def run_vless(user: str, days: str) -> str:
    cmd = ["/usr/bin/add-vless"]
    stdin = f"{user}\n{days}\n"
    rc, out, err = run(cmd, stdin)
    if rc != 0:
        return f"Error: {err or out}"
    return out.strip()

def run_trojan(user: str, days: str) -> str:
    cmd = ["/usr/bin/add-trojan"]
    stdin = f"{user}\n{days}\n"
    rc, out, err = run(cmd, stdin)
    if rc != 0:
        return f"Error: {err or out}"
    return out.strip()

def run_ss(user: str, days: str) -> str:
    cmd = ["/usr/bin/add-ssws"]
    stdin = f"{user}\n{days}\n"
    rc, out, err = run(cmd, stdin)
    if rc != 0:
        return f"Error: {err or out}"
    return out.strip()

def run_reality(user: str, days: str) -> str:
    cmd = ["/usr/bin/add-reality"]
    stdin = f"{user}\n{days}\n"
    rc, out, err = run(cmd, stdin)
    if rc != 0:
        return f"Error: {err or out}"
    return out.strip()

def run_ss2022(user: str, days: str) -> str:
    cmd = ["/usr/bin/add-ss2022"]
    stdin = f"{user}\n{days}\n"
    rc, out, err = run(cmd, stdin)
    if rc != 0:
        return f"Error: {err or out}"
    return out.strip()

def run_hysteria2(user: str, days: str) -> str:
    cmd = ["/usr/bin/add-hysteria2"]
    stdin = f"{user}\n{days}\n"
    rc, out, err = run(cmd, stdin)
    if rc != 0:
        return f"Error: {err or out}"
    return out.strip()

def run_verify() -> str:
    rc, out, err = run(["/usr/bin/kurovpn-verify"])
    return out.strip()

def run_backup() -> str:
    rc, out, err = run(["/usr/bin/backup"])
    return f"Backup: {out.strip() or 'completed'}"

# ── State machine for interactive commands ─────────────
# Map: (chat_id, username) -> {"command": "...", "step": int, "data": {}}
pending: dict = {}

def start_interactive(chat_id: int, username: str, command: str, data: dict, prompt: str):
    pending[(chat_id, username)] = {"command": command, "step": 1, "data": data}
    send_message(chat_id, prompt)

# ── Command handlers ───────────────────────────────────
def cmd_start(chat_id: int, username: str):
    if not is_admin(chat_id):
        send_message(chat_id, "Access denied. This bot is admin-only.")
        return
    send_message(chat_id, f"<b>KUROVPN Bot</b>\nDomain: {DOMAIN}\n\n"
                           "Commands:\n"
                           "/add_vmess /add_vless /add_trojan /add_ss /add_ssh\n"
                           "/add_reality /add_hysteria2 /add_ss2022\n"
                           "/list — List all xray users\n"
                           "/status — Service status\n"
                           "/verify — Run full verification\n"
                           "/backup — Create backup")

def cmd_add_vmess(chat_id: int, username: str):
    start_interactive(chat_id, username, "add_vmess", {},
        "📟 <b>Create VMess Account</b>\n\nSend: <code>username|days</code>\nExample: <code>alice|30</code>")

def cmd_add_vless(chat_id: int, username: str):
    start_interactive(chat_id, username, "add_vless", {},
        "📟 <b>Create VLess Account</b>\n\nSend: <code>username|days</code>\nExample: <code>bob|30</code>")

def cmd_add_trojan(chat_id: int, username: str):
    start_interactive(chat_id, username, "add_trojan", {},
        "📟 <b>Create Trojan Account</b>\n\nSend: <code>username|days</code>\nExample: <code>carol|30</code>")

def cmd_add_ss(chat_id: int, username: str):
    start_interactive(chat_id, username, "add_ss", {},
        "📟 <b>Create Shadowsocks Account</b>\n\nSend: <code>username|days</code>\nExample: <code>dave|30</code>")

def cmd_add_ssh(chat_id: int, username: str):
    start_interactive(chat_id, username, "add_ssh", {},
        "&#x1F4DF; <b>Create SSH Account</b>\n\nSend: <code>username|password|days</code>\nExample: <code>eve|mypass|30</code>")

def cmd_add_reality(chat_id: int, username: str):
    start_interactive(chat_id, username, "add_reality", {},
        "&#x1F4DF; <b>Create VLESS-Reality Account</b>\n\nSend: <code>username|days</code>\nExample: <code>frank|30</code>")

def cmd_add_hysteria2(chat_id: int, username: str):
    start_interactive(chat_id, username, "add_hysteria2", {},
        "&#x1F4DF; <b>Create Hysteria2 Account</b>\n\nSend: <code>username|days</code>\nExample: <code>grace|30</code>")

def cmd_add_ss2022(chat_id: int, username: str):
    start_interactive(chat_id, username, "add_ss2022", {},
        "&#x1F4DF; <b>Create Shadowsocks-2022 Account</b>\n\nSend: <code>username|days</code>\nExample: <code>hank|30</code>")

def cmd_status(chat_id: int, username: str):
    for svc in ["nginx", "xray", "hysteria", "dropbear", "edu", "wg-quick@wg0", "xl2tpd", "ipsec"]:
        rc, out, err = run(["systemctl", "is-active", svc])
        status = "🟢" if "active" in out else "🔴"
        send_message(chat_id, f"{status} {svc}")

def cmd_verify(chat_id: int, username: str):
    send_message(chat_id, "Running verification...")
    result = run_verify()
    send_message(chat_id, f"<pre>{result}</pre>")

def cmd_backup(chat_id: int, username: str):
    result = run_backup()
    send_message(chat_id, result)

def cmd_list(chat_id: int, username: str):
    users_file = "/etc/kurovpn/users.json"
    try:
        with open(users_file) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        send_message(chat_id, "No user database found.")
        return

    lines = []
    for proto in ["vmess", "vless", "trojan", "shadowsocks", "reality", "ss2022", "hysteria2"]:
        users = data.get(proto, [])
        if users:
            lines.append(f"\n<b>{proto.upper()}</b> ({len(users)} users)")
            for u in users:
                lines.append(f"  {u['user']} — exp: {u['exp']}")

    if not lines:
        send_message(chat_id, "No Xray users found.")
    else:
        send_message(chat_id, "\n".join(lines)[:4000])

def cmd_help(chat_id: int, username: str):
    cmd_start(chat_id, username)

# ── Handle interactive responses ───────────────────────
def handle_interactive(chat_id: int, username: str, text: str):
    key = (chat_id, username)
    if key not in pending:
        return False

    state = pending[key]
    command = state["command"]
    parts = text.split("|")

    if command == "add_vmess":
        if len(parts) != 2:
            send_message(chat_id, "Format: <code>username|days</code>")
            return True
        user, days = parts[0].strip(), parts[1].strip()
        if not days.isdigit():
            send_message(chat_id, "Days must be a number.")
            return True
        send_message(chat_id, f"Creating VMess: {user} ({days} days)...")
        result = run_vmess(user, days)
        send_message(chat_id, f"<pre>{result[-3500:]}</pre>")

    elif command == "add_vless":
        if len(parts) != 2:
            send_message(chat_id, "Format: <code>username|days</code>")
            return True
        user, days = parts[0].strip(), parts[1].strip()
        if not days.isdigit():
            send_message(chat_id, "Days must be a number.")
            return True
        send_message(chat_id, f"Creating VLess: {user} ({days} days)...")
        result = run_vless(user, days)
        send_message(chat_id, f"<pre>{result[-3500:]}</pre>")

    elif command == "add_trojan":
        if len(parts) != 2:
            send_message(chat_id, "Format: <code>username|days</code>")
            return True
        user, days = parts[0].strip(), parts[1].strip()
        if not days.isdigit():
            send_message(chat_id, "Days must be a number.")
            return True
        send_message(chat_id, f"Creating Trojan: {user} ({days} days)...")
        result = run_trojan(user, days)
        send_message(chat_id, f"<pre>{result[-3500:]}</pre>")

    elif command == "add_ss":
        if len(parts) != 2:
            send_message(chat_id, "Format: <code>username|days</code>")
            return True
        user, days = parts[0].strip(), parts[1].strip()
        if not days.isdigit():
            send_message(chat_id, "Days must be a number.")
            return True
        send_message(chat_id, f"Creating SS: {user} ({days} days)...")
        result = run_ss(user, days)
        send_message(chat_id, f"<pre>{result[-3500:]}</pre>")

    elif command == "add_ssh":
        if len(parts) != 3:
            send_message(chat_id, "Format: <code>username|password|days</code>")
            return True
        user, password, days = parts[0].strip(), parts[1].strip(), parts[2].strip()
        if not days.isdigit():
            send_message(chat_id, "Days must be a number.")
            return True
        if len(password) < 6:
            send_message(chat_id, "Password must be at least 6 characters.")
            return True
        send_message(chat_id, f"Creating SSH: {user} ({days} days)...")
        result = run_ssh(user, password, days)
        send_message(chat_id, f"<pre>{result[-3500:]}</pre>")

    elif command == "add_reality":
        if len(parts) != 2:
            send_message(chat_id, "Format: <code>username|days</code>")
            return True
        user, days = parts[0].strip(), parts[1].strip()
        if not days.isdigit():
            send_message(chat_id, "Days must be a number.")
            return True
        send_message(chat_id, f"Creating Reality: {user} ({days} days)...")
        result = run_reality(user, days)
        send_message(chat_id, f"<pre>{result[-3500:]}</pre>")

    elif command == "add_hysteria2":
        if len(parts) != 2:
            send_message(chat_id, "Format: <code>username|days</code>")
            return True
        user, days = parts[0].strip(), parts[1].strip()
        if not days.isdigit():
            send_message(chat_id, "Days must be a number.")
            return True
        send_message(chat_id, f"Creating Hysteria2: {user} ({days} days)...")
        result = run_hysteria2(user, days)
        send_message(chat_id, f"<pre>{result[-3500:]}</pre>")

    elif command == "add_ss2022":
        if len(parts) != 2:
            send_message(chat_id, "Format: <code>username|days</code>")
            return True
        user, days = parts[0].strip(), parts[1].strip()
        if not days.isdigit():
            send_message(chat_id, "Days must be a number.")
            return True
        send_message(chat_id, f"Creating SS-2022: {user} ({days} days)...")
        result = run_ss2022(user, days)
        send_message(chat_id, f"<pre>{result[-3500:]}</pre>")

    else:
        send_message(chat_id, "Unknown command.")

    del pending[key]
    return True

# ── Message dispatcher ─────────────────────────────────
COMMANDS = {
    "/start": cmd_start, "/help": cmd_help,
    "/add_vmess": cmd_add_vmess, "/add_vless": cmd_add_vless,
    "/add_trojan": cmd_add_trojan, "/add_ss": cmd_add_ss,
    "/add_ssh": cmd_add_ssh,
    "/add_reality": cmd_add_reality, "/add_hysteria2": cmd_add_hysteria2,
    "/add_ss2022": cmd_add_ss2022,
    "/list": cmd_list, "/status": cmd_status,
    "/verify": cmd_verify, "/backup": cmd_backup,
}

def handle_message(msg: dict):
    chat = msg.get("chat", {})
    from_user = msg.get("from", {})
    chat_id = chat.get("id", 0)
    user_id = from_user.get("id", 0)
    username = from_user.get("username", from_user.get("first_name", str(user_id)))
    text = msg.get("text", "").strip()

    if not text:
        return

    if not is_admin(user_id):
        send_message(chat_id, "Access denied. This bot is admin-only.\nContact the server admin to whitelist your ID.")
        return

    # Check interactive state
    if handle_interactive(chat_id, username, text):
        return

    # Check commands
    parts = text.split()
    cmd = parts[0].lower()
    matched = None
    for prefix, handler in COMMANDS.items():
        if cmd.startswith(prefix):
            matched = handler
            break

    if matched:
        matched(chat_id, username)
    else:
        send_message(chat_id, "Unknown command. Use /start for help.")

# ── Polling loop ───────────────────────────────────────
def main():
    print(f"[INFO] KUROVPN Bot started")
    print(f"[INFO] Admins: {ADMIN_IDS if ADMIN_IDS else 'NONE (bot will refuse all commands)'}")
    print(f"[INFO] Domain: {DOMAIN}")

    offset = 0
    while True:
        try:
            data = {"offset": offset, "timeout": 30, "allowed_updates": ["message"]}
            url = f"{API_URL}/getUpdates"
            encoded = urllib.parse.urlencode(data).encode()
            req = urllib.request.Request(url, data=encoded)
            with urllib.request.urlopen(req, timeout=35) as resp:
                result = json.loads(resp.read())
        except Exception as e:
            print(f"[WARN] Poll error: {e}")
            time.sleep(5)
            continue

        if not result.get("ok"):
            time.sleep(3)
            continue

        for update in result.get("result", []):
            offset = update["update_id"] + 1
            msg = update.get("message")
            if msg:
                try:
                    handle_message(msg)
                except Exception as e:
                    print(f"[ERROR] Processing message: {e}")

if __name__ == "__main__":
    main()
