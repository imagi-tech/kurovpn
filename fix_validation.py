import os
import re

MENU_DIR = "/home/azureuser/vpn_script/menu_files"

loop_pattern = re.compile(r'until \[\[ \$user =~\s*\^\[a-z[A-Z]?a-z0-9_\]\+\$ && \$\{client_exists\} == .0. \]\]; do\s+echo -e ".*?===================*.*?\[.*?\].*?===================*.*?"\s+read -p "Username: " user\s+client_exists=\$\(grep -w \$user /etc/xray/config.json \| wc -l\)\s+if \[\[ \$\{client_exists\} == .1. \]\]; then\s+clear\s+echo -e ".*?Already Exist Name.*?"\s+fi\s+done', re.DOTALL)

# Let's use a simpler string replacement for the loop structure since regex multiline can be finicky.
# Wait, let's just find "until [[ $user =~ " and replace everything up to "done"
# Let's write a more robust parser.

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original = content
    
    # Fix Trojan Chinese Header
    content = content.replace("[ 创建 Trojan 帐 ]", "[ Create Trojan Account ]")
    content = content.replace("Information Account", "Account Information")
    content = content.replace("Information Account Trojan", "Account Information Trojan")

    # Replace the faulty until loops
    # Let's find blocks starting with "until [[ $user =~" and ending with the next "done\n"
    # and replace it with a clean while loop
    
    parts = content.split("until [[ $user =~ ^[a-za-z0-9_]+$ && ${client_exists} == '0' ]]; do")
    if len(parts) > 1:
        new_content = parts[0]
        for part in parts[1:]:
            sub_parts = part.split("done\n", 1)
            if len(sub_parts) == 2:
                # The block inside is sub_parts[0]
                # We will inject our own loop
                
                # Determine the title from the inside block
                title_match = re.search(r'\[(.*?)\]', sub_parts[0])
                title = title_match.group(1) if title_match else "Create Account"
                
                clean_loop = f"""echo -e "\\n===================\\n[ {title} ]\\n===================\\n"
user=""
while true; do
    read -p "Username: " user
    if [[ ! "$user" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo "Error: Invalid username. Use alphanumeric characters only."
        continue
    fi
    if grep -qw "$user" /etc/xray/config.json 2>/dev/null; then
        echo "Error: Username '$user' already exists!"
        continue
    fi
    break
done
"""
                new_content += clean_loop + sub_parts[1]
            else:
                new_content += "until [[ $user =~ ^[a-za-z0-9_]+$ && ${client_exists} == '0' ]]; do" + part
        content = new_content

    # Fix read -p "Active Time: " masaaktif to also be validated
    content = re.sub(r'read -p "Active Time: " masaaktif', r'until [[ $masaaktif =~ ^[0-9]+$ ]]; do\n    read -p "Active Time (days): " masaaktif\ndone', content)
    content = re.sub(r'read -p "Active time: " masaaktif', r'until [[ $masaaktif =~ ^[0-9]+$ ]]; do\n    read -p "Active time (days): " masaaktif\ndone', content)

    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Fixed loop in {os.path.basename(filepath)}")

for file in ["add-vmess", "add-vless", "add-trojan", "add-ssws"]:
    filepath = os.path.join(MENU_DIR, file)
    if os.path.isfile(filepath):
        fix_file(filepath)

print("Done.")
