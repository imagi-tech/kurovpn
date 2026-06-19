#!/bin/bash
#
#  |=================================================================================|
#  • Autoscript AIO Lite Menu By FN Project                                          |
#  • FN Project Developer @Rerechan02 | @PR_Aiman | @farell_aditya_ardian            |
#  • Copyright 2024 18 Marc Indonesia [ Kebumen ] | [ Johor ] | [ 上海，中国 ]       |
#  |=================================================================================|
#
[[ -e $(which curl) ]] && if [[ -z $(cat /etc/resolv.conf | grep "1.1.1.1") ]]; then cat <(echo "nameserver 1.1.1.1") /etc/resolv.conf > /etc/resolv.conf.tmp && mv /etc/resolv.conf.tmp /etc/resolv.conf; fi
# Warna
red='\e[1;31m'
green='\e[0;32m'
cyan='\e[0;36m'
white='\e[037;1m'
grey='\e[1;36m'
NC='\e[0m'
# Tools
MYIP=$(curl -s ifconfig.me)
domain=$(cat /etc/xray/domain)
MYIP=$(curl ifconfig.me)
cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo )
cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
freq=$( awk -F: ' /cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo )
tram=$( free -m | awk 'NR==2 {print $2}' )
swap=$( free -m | awk 'NR==4 {print $2}' )
up=$(uptime|awk '{ $1=$2=$(NF-6)=$(NF-5)=$(NF-4)=$(NF-3)=$(NF-2)=$(NF-1)=$NF=""; print }')
OS5=$(uname -o )
OS1=$(lsb_release -sd)
f1=$(lsb_release -sc)
frem=$(free -h | grep "Mem:" | awk '{print $2 "/" $3 "/" $4}')
freswp=$(free -h | grep "Swap:" | awk '{print $2 "/" $3 "/" $4}')
cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 "% user, " $4 "% system, " $6 "% idle"}')
# Status Service
cek=$(service ssh status | grep active | cut -d ' ' -f5)
if [ "$cek" = "active" ]; then
stat=-f5
else
stat=-f7
fi
if systemctl is-active --quiet ssh; then ossh="${green}ON${NC}"; else ossh="${red}OFF${NC}"; fi
if systemctl is-active --quiet udp-custom; then udpn="${green}ON${NC}"; else udpn="${red}OFF${NC}"; fi
if systemctl is-active --quiet badvpn; then udpw="${green}ON${NC}"; else udpw="${red}OFF${NC}"; fi
if systemctl is-active --quiet nginx; then resngx="${green}ON${NC}"; else resngx="${red}OFF${NC}"; fi
if systemctl is-active --quiet noobzvpns; then noob="${green}ON${NC}"; else noob="${red}OFF${NC}"; fi
if systemctl is-active --quiet xray; then xstatus="${green}ON${NC}"; else xstatus="${red}OFF${NC}"; fi
if systemctl is-active --quiet wg-quick@wg0; then wgst="${green}ON${NC}"; else wgst="${red}OFF${NC}"; fi
clear
echo -e "================================================================================" | lolcat
echo -e " Autoscript VPN By FN Project | FN 项目的 Autoscript VPN | 丁达·普特里·辛迪亚尼 "
echo -e "================================================================================" | lolcat
echo -e "\e[037;1m Operating System:${green} $OS5 / $OS1 ${white}[${green} $f1 ${white}]"
echo -e "\e[037;1m CPU Model:${green} $cname"
echo -e "\e[037;1m Number Of Cores:${green} $cores"
echo -e "\e[037;1m CPU Frequency:${green} $freq MHz"
echo -e "\e[037;1m Total Amount Of RAM:${green} $tram MB"
echo -e "\e[037;1m System Uptime:${green} $up"
echo -e "\e[037;1m DOMAIN:${green} $domain ${white}/${green} $MYIP"
echo -e "\e[037;1m CPU Usage:${green} $cpu${NC}"
echo -e "\e[037;1m Ram VPS Total:${green} $frem${NC}"
echo -e "\e[037;1m Swap Ram VPS Total:${green} $freswp${NC}"
echo -e "================================================================================" | lolcat
echo -e " 安全外壳  : $ossh " " V2ray负载均衡  : $xstatus " " Nginx 负载 : $resngx "
echo -e " NoobzVPN 的 : $noob " " UDP 自定义 : $udpn " " 坏VPN / 乌德普格瓦 : $udpw "
echo -e " Wireguard  : $wgst "
echo -e "================================================================================" | lolcat
echo -e "${white} [ 1 ] •${white} MENU SSH" "          ${white} [ 4 ] •${white} MENU Warp Wireguard"
echo -e "${white} [ 2 ] •${white} MENU V2RAY" "        ${white} [ 5 ] •${white} MENU L2TP/IPSEC PSK"
echo -e "${white} [ 3 ] •${white} MENU NoobZVPN" "     ${white} [ 6 ] •${white} MENU SYSTEM"
echo -e "${white} [ 7 ] •${white} TELEGRAM BOT"
echo -e "================================================================================" | lolcat
echo -e "     KUROVPN Project | Powered by Imagi-Tech
"
read -p "Input Option [ 1 - 7 ] or x to exit : " apws
case $apws in
               1) clear ; menu-ssh ; exit ;;
               2) clear ; menu-xray ; exit ;;
               3) clear ; nmenu ; exit ;;
               4) clear ; Menu-WGF ; exit ;;
               5) clear ; lmenu ; exit ;;
               6) clear ; menu-set ; exit ;;
               7) clear ; botmenu ; exit ;;
               x|X) exit ;;
               *) menu ;;
esac
