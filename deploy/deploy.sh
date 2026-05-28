#!/bin/bash
set -euo pipefail

# =============================================================================
# Chator — bare-metal deployment for Debian 13 (trixie)
# Run: sudo bash deploy/deploy.sh
# Tested on: 1 vCPU, 1 GB RAM, 10+ GB SSD
# =============================================================================

CHATOR_USER="${CHATOR_USER:-chator}"
CHATOR_HOME="/opt/chator"
CHATOR_DATA="/var/lib/chator"
CHATOR_CONF="/etc/chator"
CHATOR_LOG="/var/log/chator"
CHATOR_SECRETS="/etc/chator/secrets"
REUSE_EXISTING="${REUSE_EXISTING:-1}"  # set to 0 to force re-download

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1"; exit 1; }

# Use wget.la mirror for GitHub releases (much faster from Russia)
# Falls back to direct GitHub if mirror fails.
GH_MIRROR="https://wget.la/"
github_curl() {
    local url="$1"
    shift
    curl -fSL --connect-timeout 30 --max-time 300 "${GH_MIRROR}${url}" "$@" 2>/dev/null \
        || curl -fSL --connect-timeout 30 --max-time 300 "$url" "$@"
}

[[ $EUID -eq 0 ]] || error "Must run as root"

SYNAPSE_CONFIG_PATH="/etc/matrix-synapse/homeserver.yaml"

# ============================================================================
# 1. System packages
# ============================================================================
info "Updating apt..."
apt-get update -qq

info "Installing system packages..."
apt-get install -y -qq --no-install-recommends \
    python3 python3-pip python3-venv python3-dev \
    nginx coturn \
    build-essential pkg-config libssl-dev libpq-dev \
    gnupg curl wget git jq \
    openssl ca-certificates \
    iptables ipset kmod \
    nodejs npm \
    libjpeg62-turbo libwebp7 xmlsec1 libjemalloc2 libnice10 \
    sqlite3

# ============================================================================
# 2. Python venv with Synapse (isolated from Debian packages)
# ============================================================================
info "Creating Python venv..."
python3 -m venv /opt/chator/venv
source /opt/chator/venv/bin/activate

info "Installing Synapse into venv..."
/opt/chator/venv/bin/pip install --no-cache-dir matrix-synapse[postgres] psycopg2-binary 2>&1 | tail -5

# Aliases for scripts
VENV_PYTHON="/opt/chator/venv/bin/python"
VENV_PIP="/opt/chator/venv/bin/pip"

# ============================================================================
# 3. Create chator user and directories
# ============================================================================
info "Creating directories..."
id -u ${CHATOR_USER} &>/dev/null || useradd -r -s /bin/bash -d ${CHATOR_HOME} ${CHATOR_USER}
mkdir -p ${CHATOR_HOME} ${CHATOR_DATA} ${CHATOR_CONF} ${CHATOR_LOG}
mkdir -p ${CHATOR_DATA}/media ${CHATOR_DATA}/uploads ${CHATOR_DATA}/appservices
mkdir -p ${CHATOR_SECRETS}
mkdir -p /usr/share/element-web /usr/share/element-call
mkdir -p /var/log/supervisor /var/log/livekit /var/log/localtunnel
mkdir -p /var/log/nginx

# Stop stock nginx, we manage via supervisor
systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true

# ============================================================================
# 4. Download LiveKit
# ============================================================================
LIVEKIT_VERSION="${LIVEKIT_VERSION:-1.12.0}"
if [[ ! -f /usr/local/bin/livekit-server ]] || [[ "${REUSE_EXISTING}" != "1" ]]; then
    info "Downloading LiveKit v${LIVEKIT_VERSION}..."
    github_curl "https://github.com/livekit/livekit/releases/download/v${LIVEKIT_VERSION}/livekit_${LIVEKIT_VERSION}_linux_amd64.tar.gz" \
        | tar -xz -C /usr/local/bin/ livekit-server
    chmod +x /usr/local/bin/livekit-server
else
    info "LiveKit already present, skipping"
fi

# ============================================================================
# 5. Download lk-jwt-service
# ============================================================================
LKJWT_VERSION="${LKJWT_VERSION:-0.4.4}"
if [[ ! -f /usr/local/bin/lk-jwt-service ]] || [[ "${REUSE_EXISTING}" != "1" ]]; then
    info "Downloading lk-jwt-service v${LKJWT_VERSION}..."
    github_curl "https://github.com/element-hq/lk-jwt-service/releases/download/v${LKJWT_VERSION}/lk-jwt-service_linux_amd64" \
        -o /usr/local/bin/lk-jwt-service
    chmod +x /usr/local/bin/lk-jwt-service
else
    info "lk-jwt-service already present, skipping"
fi

# ============================================================================
# 6. Download cloudflared
# ============================================================================
CLOUDFLARED_VERSION="${CLOUDFLARED_VERSION:-2025.11.0}"
if [[ ! -f /usr/local/bin/cloudflared ]] || [[ "${REUSE_EXISTING}" != "1" ]]; then
    info "Downloading cloudflared v${CLOUDFLARED_VERSION}..."
    github_curl "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64" \
        -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
else
    info "cloudflared already present, skipping"
fi

# ============================================================================
# 7. Download and install Element Web
# ============================================================================
ELEMENT_WEB_VERSION="${ELEMENT_WEB_VERSION:-1.11.70}"
if [[ ! -f /usr/share/element-web/index.html ]] || [[ "${REUSE_EXISTING}" != "1" ]]; then
    info "Downloading Element Web v${ELEMENT_WEB_VERSION}..."
    TMP_EW=$(mktemp -d)
    github_curl "https://github.com/vector-im/element-web/releases/download/v${ELEMENT_WEB_VERSION}/element-v${ELEMENT_WEB_VERSION}.tar.gz" \
        | tar -xz -C "${TMP_EW}" --strip-components=1
    cp -r "${TMP_EW}"/* /usr/share/element-web/
    rm -rf "${TMP_EW}"
else
    info "Element Web already present, skipping"
fi

# ============================================================================
# 8. Download and install Element Call
# ============================================================================
ELEMENT_CALL_VERSION="${ELEMENT_CALL_VERSION:-0.19.3}"
if [[ ! -f /usr/share/element-call/index.html ]] || [[ "${REUSE_EXISTING}" != "1" ]]; then
    info "Downloading Element Call v${ELEMENT_CALL_VERSION}..."
    TMP_EC=$(mktemp -d)
    github_curl "https://github.com/element-hq/element-call/releases/download/v${ELEMENT_CALL_VERSION}/element-call-${ELEMENT_CALL_VERSION}.tar.gz" \
        | tar -xz -C "${TMP_EC}" --strip-components=1
    cp -r "${TMP_EC}"/* /usr/share/element-call/
    rm -rf "${TMP_EC}"
else
    info "Element Call already present, skipping"
fi

# ============================================================================
# 9. Configure Element Web with Chator theme
# ============================================================================
info "Configuring Element Web..."
python3 "${REPO_DIR}/element-theme/gen-config.py" 2>/dev/null || {
    # fallback: write config.json directly
    cat > /usr/share/element-web/config.json << 'EWCONFIG'
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "http://localhost:8008",
            "server_name": "localhost"
        }
    },
    "default_theme": "light",
    "brand": "Чатор",
    "setting_defaults": {
        "custom_themes": [
            {
                "name": "Chator Blue",
                "is_dark": false,
                "colors": {
                    "accent-color": "#389cff",
                    "primary-color": "#6cb8ff",
                    "warning-color": "#ff4b55",
                    "sidebar-color": "#1a2332",
                    "roomlist-background-color": "#f0f6ff",
                    "roomlist-text-color": "#2e2f32",
                    "roomlist-text-secondary-color": "#389cff",
                    "roomlist-highlights-color": "#ffffff",
                    "roomlist-separator-color": "#d4e4ff",
                    "timeline-background-color": "#ffffff",
                    "timeline-text-color": "#2e2f32",
                    "timeline-text-secondary-color": "#61708b",
                    "timeline-highlights-color": "#f0f6ff",
                    "username-colors": ["#389cff", "#6cb8ff", "#1a7ae0", "#4da6ff", "#80c0ff"],
                    "avatar-background-colors": ["#389cff", "#6cb8ff", "#1a7ae0", "#4da6ff", "#80c0ff"]
                }
            }
        ]
    }
}
EWCONFIG
}
cp "${REPO_DIR}/element-theme/chator-logo.png" /usr/share/element-web/themes/element/img/logos/chator-logo.png 2>/dev/null || true
cp "${REPO_DIR}/element-theme/chator-bg.png" /usr/share/element-web/themes/element/img/backgrounds/chator-bg.png 2>/dev/null || true
cp "${REPO_DIR}/element-theme/chator-theme.css" /usr/share/element-web/chator-theme.css 2>/dev/null || true

# Inject custom CSS + theme override into index.html
BUILD_TS=$(date +%s)
sed -i "s|script-src 'self' 'wasm-unsafe-eval'|script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'|" /usr/share/element-web/index.html 2>/dev/null || true
if ! grep -q "chator-theme.css" /usr/share/element-web/index.html 2>/dev/null; then
    sed -i "s|</head>|<link rel=\"stylesheet\" href=\"chator-theme.css?v=${BUILD_TS}\">\n<script>!function(){function r(){if(document.body){var c=document.body.className;if(c.indexOf('cpd-theme-light')===-1\&\&c.indexOf('cpd-theme-dark')===-1)document.body.className='cpd-theme-light';new MutationObserver(function(){var c=document.body.className;if(c.indexOf('cpd-theme-light')===-1\&\&c.indexOf('cpd-theme-dark')===-1)document.body.className='cpd-theme-light'}).observe(document.body,{attributes:true,attributeFilter:['class']})}else requestAnimationFrame(r)}r()}()<\/script>\n</head>|" /usr/share/element-web/index.html
fi

# Fix Element Call asset paths for sub-path hosting (/call/)
# First revert any existing prefix (idempotent — safe to run multiple times)
find /usr/share/element-call -type f \( -name "*.html" -o -name "*.js" -o -name "*.css" \) \
    -exec sed -i 's|/call/assets/|/assets/|g' {} + 2>/dev/null || true
# Then apply exactly once
find /usr/share/element-call -type f \( -name "*.html" -o -name "*.js" -o -name "*.css" \) \
    -exec sed -i 's|/assets/|/call/assets/|g' {} + 2>/dev/null || true
cat > /usr/share/element-call/config.json << 'ECCALL'
{"default_server_config":{"m.homeserver":{"base_url":"http://localhost:8008","server_name":"localhost"}},"livekit_jwt_service_url":"/livekit/jwt"}
ECCALL

# ============================================================================
# 10. Install Sydent (Matrix Identity Server)
# ============================================================================
info "Installing Sydent..."
/opt/chator/venv/bin/pip install --no-cache-dir matrix-sydent 2>/dev/null || {
    warn "Sydent pip install failed — installing from git..."
    TMP_SYD=$(mktemp -d)
    git clone --depth 1 --branch v2.6.1 https://github.com/element-hq/sydent.git "${TMP_SYD}"
    /opt/chator/venv/bin/pip install --no-cache-dir "${TMP_SYD}"
    rm -rf "${TMP_SYD}"
}

# ============================================================================
# 11. Install supervisor + asyncpg
# ============================================================================
info "Installing supervisor..."
/opt/chator/venv/bin/pip install --no-cache-dir supervisor asyncpg

# ============================================================================
# 12. Copy config files
# ============================================================================
info "Copying config files..."

# -- nginx --
cp "${REPO_DIR}/deploy/conf/nginx-chator.conf" /etc/nginx/sites-available/chator
ln -sf /etc/nginx/sites-available/chator /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
# Supervisor manages nginx — set daemon off
if ! grep -q "daemon off;" /etc/nginx/nginx.conf; then
    echo "daemon off;" >> /etc/nginx/nginx.conf
fi

# Generate self-signed TLS cert for federation (needed by lk-jwt-service OpenID)
if [[ ! -f /etc/nginx/certs/chator.key ]]; then
    mkdir -p /etc/nginx/certs
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/certs/chator.key -out /etc/nginx/certs/chator.crt \
        -subj "/CN=chator.local" \
        -addext "subjectAltName=DNS:chator.local,DNS:localhost,IP:127.0.0.1"
    cat /etc/nginx/certs/chator.crt >> /etc/ssl/certs/ca-certificates.crt || true
fi

# -- LiveKit config --
cp "${REPO_DIR}/docker/livekit.conf" /etc/livekit.conf
sed -i 's|use_external_ip: true|use_external_ip: false|' /etc/livekit.conf  # will be set by start.sh if needed

# -- Coturn config --
cp "${REPO_DIR}/turnserver.conf" /etc/turnserver.conf

# -- Supervisor --
mkdir -p /etc/supervisor/conf.d
cp "${REPO_DIR}/deploy/conf/supervisord.conf" /etc/supervisor/supervisord.conf

# -- Synapse config (generated) --
info "Generating Synapse config..."
# Ensure /etc/matrix-synapse exists (created by package)
mkdir -p /etc/matrix-synapse/conf.d

# Copy our base config
cp "${REPO_DIR}/deploy/conf/homeserver.yaml" "${SYNAPSE_CONFIG_PATH}"

# Generate secrets if missing
if [[ ! -f /etc/chator/secrets/registration_shared_secret ]]; then
    openssl rand -hex 32 > /etc/chator/secrets/registration_shared_secret
    chmod 600 /etc/chator/secrets/registration_shared_secret
fi
if [[ ! -f /etc/chator/secrets/macaroon_secret ]]; then
    openssl rand -hex 32 > /etc/chator/secrets/macaroon_secret
    chmod 600 /etc/chator/secrets/macaroon_secret
fi
if [[ ! -f /etc/chator/secrets/form_secret ]]; then
    openssl rand -hex 32 > /etc/chator/secrets/form_secret
    chmod 600 /etc/chator/secrets/form_secret
fi

# Generate signing key if missing
SIGNING_KEY_PATH="/etc/matrix-synapse/${SYNAPSE_SERVER_NAME:-homeserver}.signing.key"
if [[ ! -f "${SIGNING_KEY_PATH}" ]]; then
    /opt/chator/venv/bin/python -m synapse.app.homeserver \
        --config-path "${SYNAPSE_CONFIG_PATH}" \
        --generate-keys \
        --keys-directory /etc/matrix-synapse \
        2>/dev/null || true
fi

# -- supabase_db.py --
cp "${REPO_DIR}/docker/supabase_db.py" /usr/local/bin/supabase_db.py
chmod +x /usr/local/bin/supabase_db.py

# -- log.config --
cp "${REPO_DIR}/deploy/conf/log.config" /etc/chator/log.config

# ============================================================================
# 13. Create swap (critical for 1 GB RAM)
# ============================================================================
if ! swapon --show | grep -q /swapfile; then
    info "Creating 1 GB swapfile..."
    fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q /swapfile /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    info "Swap created"
else
    info "Swap already active"
fi

# ============================================================================
# 14. Create systemd service for Chator startup
# ============================================================================
info "Creating systemd service..."
cat > /etc/systemd/system/chator.service << 'SERVICE'
[Unit]
Description=Chator — Matrix homeserver + VoIP
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/chator/start.sh
Restart=on-failure
RestartSec=10
User=root
Environment=SYNAPSE_SERVER_NAME=localhost
Environment=SYNAPSE_REPORT_STATS=no
Environment=JEMALLOC_PATH=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
Environment=LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE

# Copy start script
cat "${REPO_DIR}/deploy/start.sh" > /opt/chator/start.sh
chmod +x /opt/chator/start.sh

# ============================================================================
# 15. Install localtunnel (for identity server tunnel)
# ============================================================================
info "Installing localtunnel..."
npm install -g localtunnel 2>/dev/null || warn "localtunnel install failed (non-critical)"

# ============================================================================
# 16. Set permissions
# ============================================================================
info "Setting permissions..."
mkdir -p /var/lib/matrix-synapse/media /var/lib/matrix-synapse/uploads
chown -R matrix-synapse:matrix-synapse /etc/matrix-synapse /var/lib/matrix-synapse /var/log/chator
chown -R ${CHATOR_USER}:${CHATOR_USER} ${CHATOR_HOME} ${CHATOR_CONF} /etc/chator
# ${CHATOR_DATA} owned by matrix-synapse (that's the Synapse runtime user)
chown -R matrix-synapse:matrix-synapse ${CHATOR_DATA}
chmod 755 /opt/chator /var/lib/chator /etc/chator /etc/matrix-synapse

# ============================================================================
# 17. Enable and start
# ============================================================================
info "Enabling chator service..."
systemctl daemon-reload
systemctl enable chator.service

# ============================================================================
# Done
# ============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Chator deployed!                                      ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Before starting:                                       ║${NC}"
echo -e "${GREEN}║  1. Edit /etc/chator/secrets/                          ║${NC}"
echo -e "${GREEN}║  2. Start: systemctl start chator                      ║${NC}"
echo -e "${GREEN}║  3. Check: journalctl -u chator -f                     ║${NC}"
echo -e "${GREEN}║  4. Register user:                                     ║${NC}"
echo -e "${GREEN}║     /opt/chator/venv/bin/register_new_matrix_user      ║${NC}"
echo -e "${GREEN}║      -u admin -p <pass> -c /etc/matrix-synapse/homeserver.yaml  ║${NC}"
echo -e "${GREEN}║                                                        ║${NC}"
echo -e "${GREEN}║  Chator runs on: http://$(hostname -I | awk '{print $1}'):8008  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
