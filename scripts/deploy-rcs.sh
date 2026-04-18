#!/bin/bash
# ==============================================================================
# deploy-rcs.sh
# Script Deploy RCS Message Gateway
# ==============================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

if [ "$EUID" -ne 0 ]; then log_error "Jalankan sebagai root."; fi

TARGET_USER="sss"
if ! id "$TARGET_USER" &>/dev/null; then TARGET_USER="root"; fi

# --- Konfigurasi ---
GITHUB_REPO="https://github.com/C3r0et/rcs_massage.git"
GITHUB_BRANCH="main"
APP_DIR="/opt/rcs-message"
APP_NAME="rcs-message"
APP_PORT="3000"
JWT_SECRET="S@k1nah@2026"
DB_HOST="10.9.9.110"
DB_USER="userdb"
DB_PASSWORD="sahabat25*"
DB_NAME="rsc_massage"

log_section "Deploy RCS Message Gateway"

# -- TAHAP 1: System Dependencies --
log_section "TAHAP 1: System Dependencies"
if ! command -v Xvfb &>/dev/null; then
    apt-get install -y chromium libatk-bridge2.0-0 libatk1.0-0 libcairo2 libcups2 libdbus-1-3 \
        libdrm2 libgbm1 libglib2.0-0 libnspr4 libnss3 libpango-1.0-0 libx11-6 libx11-xcb1 \
        libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 \
        libxrender1 libxtst6 xvfb fonts-liberation libasound2
else
    log_warn "Dependencies sistem sudah ada. Lewati."
fi

# -- TAHAP 2: Clone/Update --
log_section "TAHAP 2: Clone/Update Repository"
if [ -d "$APP_DIR/.git" ]; then
    cd "$APP_DIR"
    sudo -u "$TARGET_USER" git fetch --all
    sudo -u "$TARGET_USER" git reset --hard origin/"$GITHUB_BRANCH"
else
    git clone --branch "$GITHUB_BRANCH" "$GITHUB_REPO" "$APP_DIR"
    chown -R "$TARGET_USER:$TARGET_USER" "$APP_DIR"
    cd "$APP_DIR"
fi

# -- TAHAP 3: Node Dependencies & Playwright --
log_section "TAHAP 3: Node Dependencies & Playwright"
chown -R "$TARGET_USER:$TARGET_USER" "$APP_DIR"
cd "$APP_DIR"
if [ ! -d "node_modules" ]; then
    sudo -u "$TARGET_USER" npm install --omit=dev
else
    log_warn "node_modules sudah ada. Lewati."
fi

log_info "Memastikan permission playwright..."
mkdir -p /opt/playwright-browsers
chmod -R 755 "$APP_DIR"
if [ -f "node_modules/.bin/playwright" ]; then
    chmod +x node_modules/.bin/playwright
fi

if [ ! -d "/opt/playwright-browsers/chromium-"* ]; then
    log_info "Menginstall Playwright Chromium..."
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers node node_modules/playwright/cli.js install chromium
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers node node_modules/playwright/cli.js install-deps chromium
fi

# -- TAHAP 4: .env & Xvfb --
log_section "TAHAP 4: Konfigurasi Service"
cat > .env << EOF
PORT=$APP_PORT
SERVER_ID=RCS-$(hostname -I | awk '{print $1}' | awk -F'.' '{print $3"-"$4}')
JWT_SECRET=$JWT_SECRET
DB_HOST=$DB_HOST
DB_USER=$DB_USER
DB_PASS=$DB_PASSWORD
DB_NAME=$DB_NAME
PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
EOF

if [ ! -f /etc/systemd/system/xvfb.service ]; then
    cat > /etc/systemd/system/xvfb.service << 'EOF'
[Unit]
Description=X Virtual Framebuffer (Xvfb)
After=network.target
[Service]
ExecStart=/usr/bin/Xvfb :99 -screen 0 1280x800x24
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable xvfb
fi
systemctl start xvfb
export DISPLAY=:99

# -- TAHAP 5: PM2 --
log_section "TAHAP 5: Registrasi PM2"
chown -R "$TARGET_USER:$TARGET_USER" "$APP_DIR"
sudo -u "$TARGET_USER" pm2 delete "$APP_NAME" 2>/dev/null || true
sudo -u "$TARGET_USER" bash -c "cd $APP_DIR && pm2 start server.js --name '$APP_NAME' --max-memory-restart 1G --restart-delay 5000"
sudo -u "$TARGET_USER" pm2 save

log_section "✅ RCS Deploy SELESAI"
