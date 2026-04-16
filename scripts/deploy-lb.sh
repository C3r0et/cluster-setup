#!/bin/bash
# ==============================================================================
# deploy-lb.sh
# Script Deploy Nginx Load Balancer & Monitoring Dashboard
# ==============================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

if [ "$EUID" -ne 0 ]; then log_error "Jalankan sebagai root."; fi

# --- Konfigurasi IP Cluster ---
WA_NODES=("192.168.56.11" "192.168.56.12" "192.168.56.13" "192.168.56.14" "192.168.56.15")
AUTOCALL_NODES=("192.168.56.21" "192.168.56.22" "192.168.56.23" "192.168.56.24" "192.168.56.25")
RCS_NODES=("192.168.56.31" "192.168.56.32" "192.168.56.33" "192.168.56.34" "192.168.56.35")

DASHBOARD_REPO="https://github.com/C3r0et/load_balance.git"
DASH_DIR="/opt/monitor-dashboard"
NGINX_CONF="/etc/nginx/sites-available/ak_loadbalancer"
NGINX_ENABLED="/etc/nginx/sites-enabled/ak_loadbalancer"
CURRENT_IP=$(hostname -I | awk '{print $1}')

log_section "Deploy Nginx Load Balancer"

# -- TAHAP 1: Nginx --
log_section "TAHAP 1: Install & Config Nginx"
if ! command -v nginx &>/dev/null; then
    apt-get update -y && apt-get install -y nginx
fi

# Build Upstreams
WA_UP=""; for ip in "${WA_NODES[@]}"; do WA_UP+="    server ${ip}:3002 max_fails=3 fail_timeout=30s;\n"; done
AC_UP=""; for ip in "${AUTOCALL_NODES[@]}"; do AC_UP+="    server ${ip}:3003 max_fails=3 fail_timeout=30s;\n"; done
RC_UP=""; for ip in "${RCS_NODES[@]}"; do RC_UP+="    server ${ip}:3000 max_fails=3 fail_timeout=30s;\n"; done

cat > "$NGINX_CONF" << EOF
# 1. Cluster Upstreams
upstream wa_gateway_cluster { least_conn; $(printf "$WA_UP") keepalive 32; }
upstream autocall_cluster { least_conn; $(printf "$AC_UP") keepalive 16; }
upstream rcs_message_cluster { least_conn; $(printf "$RC_UP") keepalive 16; }

# 2. Main Server Block
server {
    listen 80;
    server_name _;
    add_header X-LB-Node "$CURRENT_IP" always;

    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    location /wa {
        rewrite ^/wa/(.*)$ /\$1 break;
        proxy_pass http://wa_gateway_cluster;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }

    location /rcs {
        rewrite ^/rcs/(.*)$ /\$1 break;
        proxy_pass http://rcs_message_cluster;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /autocall {
        rewrite ^/autocall/(.*)$ /\$1 break;
        proxy_pass http://autocall_cluster;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /health { return 200 '{"status":"ok","lb":"$CURRENT_IP"}'; add_header Content-Type application/json; }
    
    location / {
        return 200 '<html><body style="font-family:sans-serif;background:#1a1a2e;color:#eee;padding:40px">
        <h1>Sahabat Sakinah - Cluster Status</h1>
        <p>LB IP: $CURRENT_IP</p>
        <p>Status: ONLINE</p>
        </body></html>';
        add_header Content-Type text/html;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf "$NGINX_CONF" "$NGINX_ENABLED"
systemctl restart nginx

# -- TAHAP 2: Dashboard --
log_section "TAHAP 2: Monitoring Dashboard"
if [ -d "$DASH_DIR/.git" ]; then
    cd "$DASH_DIR"
    git pull origin main
else
    git clone --depth 1 --filter=blob:none --sparse "$DASHBOARD_REPO" "$DASH_DIR"
    cd "$DASH_DIR"
    git sparse-checkout set dashboard
fi

cd "$DASH_DIR/dashboard"
[ ! -d "node_modules" ] && npm install --omit=dev
pm2 delete "monitor-dashboard" 2>/dev/null || true
pm2 start server.js --name "monitor-dashboard"
pm2 save

log_section "✅ Load Balancer Deploy SELESAI"
