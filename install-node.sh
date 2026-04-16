#!/bin/bash
# ==============================================================================
# install-node.sh
# Master Deployment Script untuk Cluster AKU
# Digunakan di setiap Mini PC fresh install untuk setup role secara otomatis.
# ==============================================================================

set -e

# --- Konfigurasi ---
BASE_URL="https://raw.githubusercontent.com/C3r0et/cluster-setup/main"

# --- Warna ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# Cek root
if [ "$EUID" -ne 0 ]; then
  log_error "Harus dijalankan sebagai root: sudo bash install-node.sh"
fi

# Fungsi untuk mendownload script jika belum ada locally
ensure_script() {
    local script_name=$1
    if [ ! -f "scripts/$script_name" ]; then
        log_info "Mendownload $script_name dari repository..."
        mkdir -p scripts
        if ! curl -s -f "$BASE_URL/scripts/$script_name" -o "scripts/$script_name"; then
            log_error "Gagal mendownload $script_name dari $BASE_URL/scripts/$script_name"
        fi
        chmod +x "scripts/$script_name"
    fi
}

# Tampilan Selamat Datang
clear
echo -e "${CYAN}"
echo "  ⚡ AKU CLUSTER INFRASTRUCTURE ⚡"
echo "  ==============================="
echo -e "${NC}"
echo "Pilih Role untuk PC ini:"
echo "  1) Load Balancer (Dashboard + Nginx)"
echo "  2) WA Gateway (Baileys Service)"
echo "  3) RCS Message (Playwright Service)"
echo "  4) Autocall (SIP Service)"
echo "  5) Hanya Setup Dasar & Agent (ZRAM, Node, PM2)"
echo ""
read -p "Masukkan pilihan [1-5]: " ROLE_CHOICE

case $ROLE_CHOICE in
  1) ROLE="LB";   SCRIPT="deploy-lb.sh";    AGENT=true ;;
  2) ROLE="WA";   SCRIPT="deploy-wa.sh";    AGENT=true ;;
  3) ROLE="RCS";  SCRIPT="deploy-rcs.sh";   AGENT=true ;;
  4) ROLE="CALL"; SCRIPT="deploy-autocall.sh"; AGENT=true ;;
  5) ROLE="BASE"; SCRIPT="";                AGENT=true ;;
  *) log_error "Pilihan tidak valid." ;;
esac

CURRENT_IP=$(hostname -I | awk '{print $1}')
log_section "MULAI DEPLOYMENT: ROLE [$ROLE]"
log_info "Target IP: $CURRENT_IP"

# --- TAHAP 1: Setup Dasar ---
log_section "TAHAP 1: Setup Dasar (OS & Dependencies)"
ensure_script "setup-base.sh"
bash scripts/setup-base.sh

# --- TAHAP 2: Deploy Role ---
if [ ! -z "$SCRIPT" ]; then
    log_section "TAHAP 2: Deploy Service [$ROLE]"
    ensure_script "$SCRIPT"
    bash "scripts/$SCRIPT"
else
    log_info "Lewati Tahap 2 (Hanya setup dasar)."
fi

# --- TAHAP 3: Deploy Monitor Agent ---
if [ "$AGENT" = true ]; then
    log_section "TAHAP 3: Deploy Monitoring Agent"
    ensure_script "deploy-agent.sh"
    bash scripts/deploy-agent.sh
fi

# --- FINISH ---
log_section "✅ SEMUA TAHAP SELESAI"
echo -e "${GREEN}"
echo "  PC ini telah dikonfigurasi sebagai: $ROLE"
echo "  IP Address: $CURRENT_IP"
echo -e "${NC}"
echo "Layanan yang berjalan:"
pm2 list
echo ""
log_info "Gunakan 'pm2 monit' untuk melihat penggunaan resource secara realtime."
echo ""
