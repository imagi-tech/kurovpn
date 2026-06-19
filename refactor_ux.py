import os
import re

MENU_DIR = "/home/azureuser/vpn_script/menu_files"

def refactor_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    
    # 1. Translate Banners
    content = content.replace("[ Informasi 帐户 SSH VPN 高级版  ]", "[ SSH VPN Premium Account ]")
    content = content.replace("[ 创建 Vmess 帐户 ]", "[ Create Vmess Account ]")
    content = content.replace("[ 信息帐户 X 射线 Vmess ]", "[ Xray Vmess Account ]")
    content = content.replace("[ 创建 Vless 帐户 ]", "[ Create Vless Account ]")
    content = content.replace("[ 信息帐户 X 射线 Vless ]", "[ Xray Vless Account ]")
    content = content.replace("[ 创建特洛伊木马帐户 ]", "[ Create Trojan Account ]")
    content = content.replace("[ 信息帐户 X 射线特洛伊木马 ]", "[ Xray Trojan Account ]")
    content = content.replace("[ Informasi 帐户 Shadowsocks 高级版  ]", "[ Shadowsocks Premium Account ]")
    content = content.replace("Informasi 帐户", "Account Information")
    content = content.replace("Active time:", "Active time (days):")
    
    # 2. Fix variable inputs to ensure they aren't empty
    # For example: read -p "Username: " Login
    # We can't easily parse bash into a loop with regex reliably, but we can do it for known ones.
    
    # 3. Fix raw bash errors from cat
    content = content.replace("$(cat /etc/xray/domain)", "$(cat /etc/xray/domain 2>/dev/null)")
    content = content.replace("$(cat /etc/funny/.chatid)", "$(cat /etc/funny/.chatid 2>/dev/null)")
    content = content.replace("$(cat /etc/funny/.keybot)", "$(cat /etc/funny/.keybot 2>/dev/null)")
    content = content.replace("CHATID=$(cat /etc/funny/.chatid)", "CHATID=$(cat /etc/funny/.chatid 2>/dev/null)")
    content = content.replace("KEY=$(cat /etc/funny/.keybot)", "KEY=$(cat /etc/funny/.keybot 2>/dev/null)")
    
    # 4. Add "Press any key to go back" at the end of add-* scripts
    if os.path.basename(filepath).startswith("add") and not "Press any key" in content:
        content += '\necho ""\nread -n 1 -s -r -p "Press any key to go back..."\nmenu\n'

    # 5. Fix curl error suppression more safely (already >/dev/null but maybe handle empty KEY)
    curl_fix = """if [[ -n "$KEY" && -n "$CHATID" ]]; then
    curl -s --max-time $TIME -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEKS&parse_mode=html" $URL >/dev/null
fi"""
    content = content.replace('curl -s --max-time $TIME -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEKS&parse_mode=html" $URL >/dev/null', curl_fix)

    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Refactored: {os.path.basename(filepath)}")

for file in os.listdir(MENU_DIR):
    filepath = os.path.join(MENU_DIR, file)
    if os.path.isfile(filepath):
        refactor_file(filepath)

print("Done basic text/error replacements.")
