#!/bin/bash
#
#  KUROVPN — shared UI component library
#  https://github.com/imagi-tech/kurovpn
#
#  Sources this in commands/menus to get a consistent look.

# ── Palette ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

UI_W=46   # inner content width (between border chars)

# ── Internal helpers ─────────────────────────────────────
_visible_len() { echo -en "$1" | sed 's/\x1b\[[0-9;]*m//g' | wc -m; }

_repeat() { printf "$1%.0s" $(seq 1 "$2"); }

_box_line() {
    # Left-aligned row inside ║ … ║.  Optionally right-side text.
    local left="$1" right="${2:-}"
    local lv=$(_visible_len "$left")
    local rv=$(_visible_len "$right")
    local pad=$(( UI_W - lv - rv - 2 ))
    (( pad < 0 )) && pad=0
    echo -e "${CYAN}║${NC} ${left}$(printf "%${pad}s")${right} ${CYAN}║${NC}"
}

_card_row() {
    # Same as _box_line but with │ border for card interiors.
    local left="$1" right="${2:-}"
    local lv=$(_visible_len "$left")
    local rv=$(_visible_len "$right")
    local pad=$(( UI_W - lv - rv - 2 ))
    (( pad < 0 )) && pad=0
    echo -e "${CYAN}│${NC} ${left}$(printf "%${pad}s")${right} ${CYAN}│${NC}"
}

# ── Pre-built borders ────────────────────────────────────
_top="${CYAN}╔$(_repeat '═' $UI_W)╗${NC}"
_bot="${CYAN}╚$(_repeat '═' $UI_W)╝${NC}"
_sep="${CYAN}╠$(_repeat '─' $UI_W)╣${NC}"
_card_top="${CYAN}╭$(_repeat '─' $UI_W)╮${NC}"
_card_bot="${CYAN}╰$(_repeat '─' $UI_W)╯${NC}"

# ── Public components ────────────────────────────────────

# ui_header  "Screen Title"  ["Breadcrumb path"]
ui_header() {
    local title="$1" breadcrumb="${2:-}"
    local domain
    domain=$(cat /etc/xray/domain 2>/dev/null || echo "unknown")

    echo -e "$_top"
    _box_line "${WHITE}KUROVPN${NC}" "$domain"
    echo -e "$_sep"
    if [[ -n "$breadcrumb" ]]; then
        _box_line "${YELLOW}› $breadcrumb${NC}"
    else
        _box_line "${YELLOW}$title${NC}"
    fi
    echo -e "$_bot"
    echo ""
}

# ui_footer   — draws "X Back  ·  domain" line
ui_footer() {
    local domain
    domain=$(cat /etc/xray/domain 2>/dev/null || echo "")
    echo -e "  ${RED}X${NC} Back  ${BLUE}· $domain${NC}\n"
}

# ui_item  N  "label"   — numbered option, number in green
ui_item() {
    local num="$1" label="$2"
    printf "   ${GREEN}%2s)${NC}  %s\n" "$num" "$label"
}

# ui_section "Label"   — gold section divider
ui_section() {
    echo -e "\n  ${YELLOW}[ $1 ]${NC}"
}

# ui_card_begin "Title"
ui_card_begin() {
    local title="$1"
    echo -e "$_card_top"
    if [[ -n "$title" ]]; then
        _card_row "${YELLOW}$title${NC}"
        echo -e "${CYAN}│$(printf "%$((UI_W))s")${CYAN}│${NC}"
    fi
}

# ui_card_end
ui_card_end() {
    echo -e "$_card_bot"
    echo ""
}

# ui_kv  "Key"  "Value"
ui_kv() {
    local key="$1" val="${2:-}"
    printf "  ${CYAN}%-18s${NC}: %s\n" "$key" "$val"
}

# ui_pad K V  — same as ui_kv but key is plain (no cyan)
ui_pad() {
    printf "  %-18s : %s\n" "$1" "${2:-}"
}

# ui_badge ok|warn|fail "label"
ui_badge() {
    case "$1" in
        ok|pass)   echo -e "  ${GREEN}[PASS]${NC} $2" ;;
        warn)      echo -e "  ${YELLOW}[WARN]${NC} $2" ;;
        fail|FAIL) echo -e "  ${RED}[FAIL]${NC} $2" ;;
    esac
}

# ui_running  "svc-name"   — green check or red cross
ui_running() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        printf "  ${GREEN}[RUNNING]${NC} %s\n" "$svc"
    else
        printf "  ${RED}[STOPPED]${NC} %s\n" "$svc"
    fi
}

# ui_qr "URI_or_TEXT" ["Title"]
ui_qr() {
    local text="$1" title="${2:-Scan QR Code}"
    if command -v qrencode &>/dev/null && [[ -n "$text" ]]; then
        echo -e "\n  ${YELLOW}[ $title ]${NC}\n"
        qrencode -t ANSIUTF8 -o - "$text" 2>/dev/null | sed 's/^/  /' || true
        echo ""
    elif [[ -n "$text" ]]; then
        echo -e "\n  ${BLUE}[ QR Code: install 'qrencode' to view terminal QR ]${NC}"
    fi
}

# ui_pill "service_name" ["display_label"]
ui_pill() {
    local svc="$1" label="${2:-$svc}"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -en "${GREEN}● ${label}${NC}"
    else
        echo -en "${RED}○ ${label}${NC}"
    fi
}

# ui_gauge percentage [bar_width] [details_text]
ui_gauge() {
    local pct="${1%.*}" width="${2:-15}" detail="${3:-}"
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100
    
    local filled=$(( (pct * width) / 100 ))
    local empty=$(( width - filled ))
    
    local color="$GREEN"
    (( pct >= 70 )) && color="$YELLOW"
    (( pct >= 90 )) && color="$RED"
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    echo -e "${color}[${bar}]${NC} ${WHITE}${pct}%${NC} ${detail}"
}

# ui_wait_key
ui_wait_key() {
    if [[ -t 0 ]]; then
        echo ""
        read -n 1 -s -r -p "  Press any key to continue..."
        echo ""
    fi
}
