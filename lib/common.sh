#!/bin/bash
#
#  KUROVPN -- VPN Auto-Installer & Manager
#  https://github.com/imagi-tech/kurovpn
#
#  lib/common.sh — shared logging, colors, OS detection, and helper functions

set -e

# ── Colors ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ── Logging ────────────────────────────────────────────
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}==>${NC} ${WHITE}$*${NC}\n"; }
die()       { log_error "$*"; exit 1; }

# ── Spinner for long commands ──────────────────────────
spinner() {
    local pid=$1 msg="${2:-Working}"
    local spin='-\|/'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r[%s] %s..." "${spin:$i:1}" "$msg"
        sleep 0.2
    done
    printf "\r\033[K"
    wait "$pid"
    return $?
}

# ── OS Detection ───────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION_ID=$VERSION_ID
    elif [[ -f /etc/debian_version ]]; then
        OS_ID=debian
        OS_VERSION_ID=$(cat /etc/debian_version | cut -d. -f1)
    else
        die "Unsupported operating system"
    fi

    case "$OS_ID" in
        ubuntu)
            [[ "$OS_VERSION_ID" =~ ^(20|22|24)\. ]] || die "Ubuntu $OS_VERSION_ID not supported (need 20.04+)"
            ;;
        debian)
            [[ "$OS_VERSION_ID" =~ ^(11|12|13) ]] || die "Debian $OS_VERSION_ID not supported (need 11+)"
            ;;
        *)
            die "Unsupported OS: $OS_ID"
            ;;
    esac

    OS_ARCH=$(uname -m)
    case "$OS_ARCH" in
        x86_64)  ARCH=amd64 ;;
        aarch64) ARCH=arm64 ;;
        *)       die "Unsupported architecture: $OS_ARCH" ;;
    esac

    log_info "Detected: $OS_ID $OS_VERSION_ID ($ARCH)"
}

# ── Check if running as root ───────────────────────────
require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo)"
}

# ── Prompts ────────────────────────────────────────────
ask_domain() {
    local result
    if [[ -n "$ARG_DOMAIN" ]]; then
        echo "$ARG_DOMAIN"
        return
    fi
    while [[ -z "$result" ]]; do
        read -rp "Enter your domain (e.g. vpn.example.com): " result
    done
    echo "$result"
}

ask_email() {
    local result
    if [[ -n "$ARG_EMAIL" ]]; then
        echo "$ARG_EMAIL"
        return
    fi
    while [[ -z "$result" ]]; do
        read -rp "Enter admin email (for Let's Encrypt): " result
    done
    echo "$result"
}

# ── Check command exists ───────────────────────────────
has_cmd() { command -v "$1" &>/dev/null; }

# ── Safe systemctl ─────────────────────────────────────
svc_enable() { systemctl enable "$1" &>/dev/null; }
svc_disable() { systemctl disable "$1" &>/dev/null; }
svc_start() { systemctl start "$1" &>/dev/null; }
svc_stop() { systemctl stop "$1" &>/dev/null; }
svc_restart() { systemctl restart "$1" &>/dev/null; }
svc_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

# ── Ensure line in file ────────────────────────────────
ensure_line() {
    local file="$1" line="$2"
    grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

# ── Parse CLI arguments ────────────────────────────────
parse_args() {
    ARG_DOMAIN=""
    ARG_EMAIL=""
    ARG_IP_VERSION="4"
    ARG_WITH_WARP=""
    ARG_NON_INTERACTIVE=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain|-d)      ARG_DOMAIN="$2"; shift 2 ;;
            --email|-e)       ARG_EMAIL="$2"; shift 2 ;;
            --ip-version)     ARG_IP_VERSION="$2"; shift 2 ;;
            --with-warp)      ARG_WITH_WARP=1; shift ;;
            --yes|-y)         ARG_NON_INTERACTIVE=1; shift ;;
            --help|-h)
                echo "Usage: ./install.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -d, --domain DOMAIN      Domain name (e.g. vpn.example.com)"
                echo "  -e, --email EMAIL        Admin email for Let's Encrypt"
                echo "  --ip-version 4|6         IPv4 (default) or IPv6 for certificate"
                echo "  --with-warp              Install Cloudflare WARP on WireGuard"
                echo "  -y, --yes                Non-interactive mode"
                echo "  -h, --help               Show this help"
                exit 0
                ;;
            *) die "Unknown option: $1 (use --help)" ;;
        esac
    done

    if [[ -n "$ARG_NON_INTERACTIVE" && ( -z "$ARG_DOMAIN" || -z "$ARG_EMAIL" ) ]]; then
        die "Non-interactive mode requires --domain and --email"
    fi
}

# ── Banner ─────────────────────────────────────────────
show_banner() {
    echo -e "
${CYAN}╔══════════════════════════════════════════════╗
║                                              ║
║   ${WHITE}KUROVPN${CYAN} — Multi-Protocol VPN Installer   ║
║   ${BLUE}https://github.com/imagi-tech/kurovpn${CYAN}     ║
║                                              ║
╚══════════════════════════════════════════════╝${NC}
"
}

# ── Summary after install ──────────────────────────────
show_summary() {
    local domain="$1"
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  KUROVPN Installation Complete${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Domain      : ${GREEN}$domain${NC}"
    echo -e "  Xray Ports  : 443, 80, 855, 2095"
    echo -e "  SSH Ports   : 22, 3303"
    echo -e "  Dropbear    : 109 (WS), 111, 69"
    echo -e "  BadVPN      : UDP 7300"
    echo -e "  WG Port     : 2048"
    echo -e "  NoobZVPNS   : TCP 8080, SSL 9443"
    echo ""
    echo -e "  Run ${YELLOW}menu${NC} to manage accounts."
    echo -e "  Run ${YELLOW}sudo ./uninstall.sh${NC} to remove KUROVPN."
    echo ""
}
