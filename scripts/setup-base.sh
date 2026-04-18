#!/bin/bash
# ==============================================================================
# setup-base.sh
# Script Setup Dasar untuk Semua Mini PC (Debian 13 Headless)
# ==============================================================================

set -e

# --- Warna Output ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

if [ "$EUID" -ne 0 ]; then log_error "Jalankan sebagai root."; fi

# -- TAHAP 1: Repo & Update --
log_section "TAHAP 1: Konfigurasi Repo & Update Sistem"
if ! grep -q "trixie" /etc/apt/sources.list; then
    cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF
    apt-get update -y
else
    log_warn "Repository Debian 13 sudah terkonfigurasi. Lewati."
fi

apt-get install -y curl git ffmpeg build-essential ca-certificates gnupg lsb-release \
    net-tools htop zram-tools openssh-server procps psmisc unzip wget >/dev/null

# -- TAHAP 2: Disable Unused Services --
log_section "TAHAP 2: Disable Service Tidak Diperlukan"
SERVICES=("bluetooth" "ModemManager" "avahi-daemon" "wpa_supplicant")
for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        systemctl stop "$svc" && systemctl disable "$svc"
    fi
done

# -- TAHAP 3: Optimasi Kernel --
log_section "TAHAP 3: Optimasi Kernel"
if [ ! -f /etc/sysctl.d/99-minipc-optimize.conf ]; then
    cat > /etc/sysctl.d/99-minipc-optimize.conf << 'EOF'
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
fs.file-max = 65535
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
EOF
    sysctl -p /etc/sysctl.d/99-minipc-optimize.conf
fi

# -- TAHAP 4: ZRAM & tmpfs --
log_section "TAHAP 4: RAM Optimization (ZRAM & tmpfs)"
if ! systemctl is-active --quiet zramswap; then
    apt-get install -y zram-tools
    echo -e "ALGO=lzo-rle\nPERCENT=75" > /etc/default/zramswap
    systemctl enable zramswap && systemctl restart zramswap
    log_info "ZRAM aktif."
fi

if ! grep -q "tmpfs /tmp" /etc/fstab; then
    echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,size=256m 0 0" >> /etc/fstab
    mount -o remount,exec /tmp 2>/dev/null || true
    log_info "tmpfs /tmp terkonfigurasi."
fi

# -- TAHAP 5: Node.js 20 LTS --
log_section "TAHAP 5: Install Node.js 20 LTS"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    log_info "Node.js terinstall: $(node -v)"
fi

# -- TAHAP 6: PM2 & Logrotate --
log_section "TAHAP 6: PM2 & Logrotate"
TARGET_USER="sss"
if ! id "$TARGET_USER" &>/dev/null; then
    TARGET_USER="root"
    log_warn "User 'sss' tidak ditemukan. Menggunakan root."
fi

if ! command -v pm2 &>/dev/null; then
    npm install -g pm2
    
    # Hapus PM2 root jika ada
    pm2 kill 2>/dev/null || true
    systemctl stop pm2-root 2>/dev/null || true
    systemctl disable pm2-root 2>/dev/null || true
    
    # Setup startup untuk target user
    sudo -u "$TARGET_USER" pm2 startup systemd -u "$TARGET_USER" --hp "/home/$TARGET_USER" | bash
    systemctl enable "pm2-$TARGET_USER"
    
    sudo -u "$TARGET_USER" pm2 install pm2-logrotate
    sudo -u "$TARGET_USER" pm2 set pm2-logrotate:max_size 50M
    sudo -u "$TARGET_USER" pm2 set pm2-logrotate:retain 5
fi

# Ensure /opt is accessible
mkdir -p /opt
chown -R "$TARGET_USER:$TARGET_USER" /opt

log_section "✅ Setup Dasar SELESAI"
