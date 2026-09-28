#!/usr/bin/env python3
"""
KUROVPN Proxy Helper & User Manager
Handles HTTP & SOCKS5 proxy users, authentication, and expiration.
Synchronizes between /etc/xray/config.json and /etc/kurovpn/users.json.
"""
import sys
import os
import json
import re
from datetime import datetime, timedelta

XRAY_CFG = "/etc/xray/config.json"
USERS_FILE = "/etc/kurovpn/users.json"

def load_json(path, default=None):
    if not os.path.exists(path):
        return default if default is not None else {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        sys.stderr.write(f"Error loading {path}: {e}\n")
        return default if default is not None else {}

def save_json(path, data):
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.replace(tmp, path)

def get_xray_proxy_accounts():
    config = load_json(XRAY_CFG)
    accounts = {}
    for ib in config.get("inbounds", []):
        tag = ib.get("tag", "")
        if "proxy" in tag:
            for acc in ib.get("settings", {}).get("accounts", []):
                u = acc.get("user")
                p = acc.get("pass")
                if u:
                    accounts[u] = p
    return accounts

def user_exists_anywhere(username):
    users_db = load_json(USERS_FILE)
    for p in users_db.get("proxy", []):
        if p.get("user") == username:
            return True
    xray_accs = get_xray_proxy_accounts()
    if username in xray_accs:
        return True
    return False

def get_user_info(username):
    users_db = load_json(USERS_FILE)
    xray_accs = get_xray_proxy_accounts()
    found = None
    for p in users_db.get("proxy", []):
        if p.get("user") == username:
            found = dict(p)
            break
    if not found and username in xray_accs:
        found = {
            "user": username,
            "password": xray_accs[username],
            "created": datetime.now().strftime("%Y-%m-%d"),
            "exp": (datetime.now() + timedelta(days=365)).strftime("%Y-%m-%d")
        }
    return found

def cmd_exists(username):
    if user_exists_anywhere(username):
        print("EXISTS")
        sys.exit(0)
    else:
        print("NOT_FOUND")
        sys.exit(1)

def cmd_get(username):
    info = get_user_info(username)
    if not info:
        sys.stderr.write(f"Error: User '{username}' not found.\n")
        sys.exit(1)
    print(json.dumps(info))

def cmd_add(username, password, days_str):
    if not re.match(r"^[a-zA-Z0-9_]{2,32}$", username):
        sys.stderr.write("Error: Username must be 2-32 alphanumeric characters or underscore.\n")
        sys.exit(2)
        
    if not password:
        sys.stderr.write("Error: Password cannot be empty.\n")
        sys.exit(2)
        
    try:
        days = int(days_str)
        if days <= 0:
            raise ValueError()
    except ValueError:
        sys.stderr.write("Error: Duration (days) must be a positive integer.\n")
        sys.exit(2)

    if user_exists_anywhere(username):
        sys.stderr.write(f"Error: User '{username}' already exists!\n")
        sys.exit(1)

    today = datetime.now()
    exp_date = (today + timedelta(days=days)).strftime("%Y-%m-%d")
    today_str = today.strftime("%Y-%m-%d")

    # Update Xray config (HTTP port 80 and SOCKS5 port 1080)
    xray_cfg = load_json(XRAY_CFG)
    updated_xray = 0
    for ib in xray_cfg.get("inbounds", []):
        tag = ib.get("tag", "")
        if "proxy" in tag and ib.get("settings", {}).get("accounts") is not None:
            accts = ib["settings"]["accounts"]
            if not any(a.get("user") == username for a in accts):
                accts.append({"user": username, "pass": password})
                updated_xray += 1
    save_json(XRAY_CFG, xray_cfg)

    # Update users.json
    users_db = load_json(USERS_FILE)
    if "proxy" not in users_db:
        users_db["proxy"] = []
    
    users_db["proxy"] = [p for p in users_db["proxy"] if p.get("user") != username]
    users_db["proxy"].append({
        "user": username,
        "password": password,
        "created": today_str,
        "exp": exp_date
    })
    save_json(USERS_FILE, users_db)

    print(f"SUCCESS:{username}:{password}:{exp_date}:{days}")

def cmd_del(username):
    if not user_exists_anywhere(username):
        sys.stderr.write(f"Error: User '{username}' not found.\n")
        sys.exit(1)

    # Remove from Xray config
    xray_cfg = load_json(XRAY_CFG)
    removed_xray = 0
    for ib in xray_cfg.get("inbounds", []):
        if "accounts" in ib.get("settings", {}):
            before = len(ib["settings"]["accounts"])
            ib["settings"]["accounts"] = [
                a for a in ib["settings"]["accounts"] if a.get("user") != username
            ]
            removed_xray += (before - len(ib["settings"]["accounts"]))
    save_json(XRAY_CFG, xray_cfg)

    # Remove from users.json
    users_db = load_json(USERS_FILE)
    if "proxy" in users_db:
        users_db["proxy"] = [p for p in users_db["proxy"] if p.get("user") != username]
        save_json(USERS_FILE, users_db)

    print(f"SUCCESS:Deleted '{username}' ({removed_xray} inbounds cleaned)")

def cmd_renew(username, days_str):
    if not user_exists_anywhere(username):
        sys.stderr.write(f"Error: User '{username}' not found.\n")
        sys.exit(1)

    try:
        days = int(days_str)
        if days <= 0:
            raise ValueError()
    except ValueError:
        sys.stderr.write("Error: Additional days must be a positive integer.\n")
        sys.exit(2)

    users_db = load_json(USERS_FILE)
    if "proxy" not in users_db:
        users_db["proxy"] = []

    user_entry = None
    for p in users_db["proxy"]:
        if p.get("user") == username:
            user_entry = p
            break

    today = datetime.now().date()
    if not user_entry:
        xray_accs = get_xray_proxy_accounts()
        pwd = xray_accs.get(username, "kuro2024")
        old_date = today
        new_date = today + timedelta(days=days)
        user_entry = {
            "user": username,
            "password": pwd,
            "created": today.strftime("%Y-%m-%d"),
            "exp": new_date.strftime("%Y-%m-%d")
        }
        users_db["proxy"].append(user_entry)
        old_str = today.strftime("%Y-%m-%d")
        new_str = user_entry["exp"]
    else:
        old_str = user_entry.get("exp", today.strftime("%Y-%m-%d"))
        try:
            old_date = datetime.strptime(old_str, "%Y-%m-%d").date()
        except Exception:
            old_date = today

        base_date = max(today, old_date)
        new_date = base_date + timedelta(days=days)
        new_str = new_date.strftime("%Y-%m-%d")
        user_entry["exp"] = new_str

    save_json(USERS_FILE, users_db)
    print(f"SUCCESS:{username}:{old_str}:{new_str}:{days}")

def cmd_change(username, new_pass):
    if not user_exists_anywhere(username):
        sys.stderr.write(f"Error: User '{username}' not found.\n")
        sys.exit(1)

    if not new_pass:
        sys.stderr.write("Error: New password cannot be empty.\n")
        sys.exit(2)

    # Update Xray config
    xray_cfg = load_json(XRAY_CFG)
    for ib in xray_cfg.get("inbounds", []):
        tag = ib.get("tag", "")
        if "proxy" in tag and "accounts" in ib.get("settings", {}):
            for a in ib["settings"]["accounts"]:
                if a.get("user") == username:
                    a["pass"] = new_pass
    save_json(XRAY_CFG, xray_cfg)

    # Update users.json
    users_db = load_json(USERS_FILE)
    if "proxy" in users_db:
        for p in users_db["proxy"]:
            if p.get("user") == username:
                p["password"] = new_pass
        save_json(USERS_FILE, users_db)

    print(f"SUCCESS:{username}:{new_pass}")

def cmd_list():
    users_db = load_json(USERS_FILE)
    proxy_users = users_db.get("proxy", [])
    xray_accs = get_xray_proxy_accounts()

    existing_usernames = {p.get("user") for p in proxy_users}
    for u, p in xray_accs.items():
        if u not in existing_usernames:
            proxy_users.append({
                "user": u,
                "password": p,
                "created": datetime.now().strftime("%Y-%m-%d"),
                "exp": (datetime.now() + timedelta(days=365)).strftime("%Y-%m-%d")
            })

    today = datetime.now().date()
    result = []
    for u in proxy_users:
        uname = u.get("user", "")
        pwd = u.get("password", "")
        exp_s = u.get("exp", "never")
        c_date = u.get("created", "-")
        status = "Active"
        days_left = "-"
        if exp_s and exp_s != "never":
            try:
                exp_d = datetime.strptime(exp_s, "%Y-%m-%d").date()
                diff = (exp_d - today).days
                days_left = str(diff)
                if diff < 0:
                    status = "Expired"
            except Exception:
                pass
        result.append({
            "user": uname,
            "password": pwd,
            "exp": exp_s,
            "created": c_date,
            "status": status,
            "days_left": days_left
        })
    return result

def cmd_list_formatted():
    users = cmd_list()
    if not users:
        print("EMPTY")
        return
    for u in users:
        print(f"{u['user']}|{u['password']}|{u['exp']}|{u['status']}|{u['days_left']}|{u['created']}")

def cmd_creds():
    config = load_json(XRAY_CFG)
    for ib in config.get("inbounds", []):
        tag = ib.get("tag", "")
        if "proxy" not in tag:
            continue
        accts = ib.get("settings", {}).get("accounts", [])
        port = ib.get("port", "?")
        proto = ib.get("protocol", "?").upper()
        if accts:
            for a in accts:
                u = a.get("user")
                p = a.get("pass")
                print(f"  {proto:6} :{port:<5}  Auth: {u}:{p}")
        else:
            print(f"  {proto:6} :{port:<5}  Auth: none (open)")

def cmd_sweep():
    now_str = datetime.now().strftime("%Y-%m-%d")
    users_db = load_json(USERS_FILE)
    expired = []
    for p in users_db.get("proxy", []):
        exp = p.get("exp", "")
        if exp and exp < now_str:
            expired.append(p.get("user"))
    
    count = 0
    for user in expired:
        if user:
            cmd_del(user)
            count += 1
    print(f"SWEPT:{count}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: proxy_helper.py [creds|list|list_formatted|exists USER|get USER|add USER PASS DAYS|del USER|renew USER DAYS|change USER PASS|sweep]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "creds":
        cmd_creds()
    elif cmd == "list":
        print(json.dumps(cmd_list(), indent=2))
    elif cmd == "list_formatted":
        cmd_list_formatted()
    elif cmd == "exists" and len(sys.argv) >= 3:
        cmd_exists(sys.argv[2])
    elif cmd == "get" and len(sys.argv) >= 3:
        cmd_get(sys.argv[2])
    elif cmd == "add" and len(sys.argv) >= 5:
        cmd_add(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "del" and len(sys.argv) >= 3:
        cmd_del(sys.argv[2])
    elif cmd == "renew" and len(sys.argv) >= 4:
        cmd_renew(sys.argv[2], sys.argv[3])
    elif cmd == "change" and len(sys.argv) >= 4:
        cmd_change(sys.argv[2], sys.argv[3])
    elif cmd == "sweep":
        cmd_sweep()
    else:
        sys.stderr.write("Invalid arguments.\n")
        sys.exit(1)
