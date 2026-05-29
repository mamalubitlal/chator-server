#!/bin/bash
set -euo pipefail

# =============================================================================
# Chator — MAS (Matrix Authentication Service) install + migration
# Prerequisites: deploy.sh has already been run
# Usage:
#   bash deploy/install-mas.sh              # install only
#   bash deploy/install-mas.sh --migrate    # install + user migration
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1"; exit 1; }

[[ $EUID -eq 0 ]] || error "Must run as root"

DO_MIGRATE=0
for arg in "$@"; do
  [[ "$arg" == "--migrate" ]] && DO_MIGRATE=1
done

# ---- Config ----
MAS_VERSION="${MAS_VERSION:-1.17.0}"
MAS_HOME="/opt/chator/mas"
MAS_CONFIG="/etc/chator/mas.yaml"
MAS_DATA="/var/lib/mas"
MAS_LOG="/var/log/mas"
SYNAPSE_CONFIG="/etc/matrix-synapse/homeserver.yaml"
SUPERVISOR_CONFIG="/etc/supervisor/supervisord.conf"
NGINX_SITE="/etc/nginx/sites-available/chator"
NGINX_ENABLED="/etc/nginx/sites-enabled/chator"
SITE_URL="https://chator.duckdns.org"

# Local PostgreSQL for MAS (isolated from Synapse's shared Supabase database)
# This avoids schema conflicts with Synapse's public.users table.
MAS_DB_USER="${MAS_DB_USER:-mas}"
MAS_DB_PASS="${MAS_DB_PASS:-$(openssl rand -hex 16)}"
MAS_DB_NAME="${MAS_DB_NAME:-mas}"
MAS_DB_HOST="${MAS_DB_HOST:-localhost}"
MAS_DB_PORT="${MAS_DB_PORT:-5432}"
MAS_DB_URI="postgres://${MAS_DB_USER}:${MAS_DB_PASS}@${MAS_DB_HOST}:${MAS_DB_PORT}/${MAS_DB_NAME}"
export MAS_DB_URI  # For Python inline scripts
echo "${MAS_DB_PASS}" > /etc/chator/mas_db_password 2>/dev/null || true
chmod 600 /etc/chator/mas_db_password 2>/dev/null || true
info "MAS database: ${MAS_DB_USER}@${MAS_DB_HOST}:${MAS_DB_PORT}/${MAS_DB_NAME}"

# GitHub mirror (faster from RU)
GH_MIRROR="https://wget.la/"
github_curl() {
    local url="$1"; shift
    curl -fSL --connect-timeout 30 --max-time 120 "${GH_MIRROR}${url}" "$@" 2>/dev/null \
        || curl -fSL --connect-timeout 30 --max-time 120 "$url" "$@"
}

# ==========================================================================
# 1. Download MAS binary
# ==========================================================================
info "Downloading MAS v${MAS_VERSION}..."
mkdir -p "${MAS_HOME}"
if [[ ! -f "${MAS_HOME}/mas-cli" ]]; then
    github_curl "https://github.com/element-hq/matrix-authentication-service/releases/download/v${MAS_VERSION}/mas-cli-x86_64-linux.tar.gz" \
        | tar -xz -C "${MAS_HOME}"
    chmod +x "${MAS_HOME}/mas-cli"
    info "  Extracted to ${MAS_HOME}"
else
    info "  Already present"
fi
export PATH="${MAS_HOME}:${PATH}"

# ==========================================================================
# 2. Generate MAS config
# ==========================================================================
info "Generating MAS config..."
mkdir -p "$(dirname "${MAS_CONFIG}")" "${MAS_DATA}" "${MAS_LOG}"

if [[ ! -f "${MAS_CONFIG}" ]]; then
    "${MAS_HOME}/mas-cli" config generate > "${MAS_CONFIG}" 2>/dev/null || {
        warn "  config generate failed — creating minimal config"
        cat > "${MAS_CONFIG}" << 'MINIMAL'
http:
  listeners:
    - port: 8777
      address: "127.0.0.1"
MINIMAL
    }
    info "  Base config generated"
fi

# Patch config with our values (Python is more reliable than sed for YAML)
info "Patching config..."
python3 << 'PYPATCH'
import os, re

path = "/etc/chator/mas.yaml"
site_url = "https://chator.duckdns.org"
db_uri = os.environ["MAS_DB_URI"]

with open(path) as f:
    c = f.read()

# Ensure HTTP listener is correct
listener_block = '''http:
  listeners:
    - address: "127.0.0.1"
      port: 8777'''

if "http:" in c:
    c = re.sub(r'^http:.*?(?=^\S|\Z)', listener_block, c, flags=re.MULTILINE|re.DOTALL)
else:
    c += "\n" + listener_block + "\n"

# Database
db_block = f'''database:
  uri: "{db_uri}"
  min_connections: 1
  max_connections: 5
  connect_timeout: 10
  max_lifetime: 30m'''

if "database:" in c:
    c = re.sub(r'^database:.*?(?=^\S|\Z)', db_block, c, flags=re.MULTILINE|re.DOTALL)
else:
    c += "\n" + db_block + "\n"

# Matrix
matrix_block = f'''matrix:
  kind: synapse
  homeserver: "chator.duckdns.org"
  endpoint: "http://localhost:8009"
  # secret will be set during migration step'''

if "matrix:" in c:
    c = re.sub(r'^matrix:.*?(?=^\S|\Z)', matrix_block, c, flags=re.MULTILINE|re.DOTALL)
else:
    c += "\n" + matrix_block + "\n"

# Clients — Element Web OAuth client
clients_block = '''clients:
  - client_id: "element-web"
    client_name: "Element Web"
    client_uri: "https://chator.duckdns.org"
    redirect_uris:
      - "https://chator.duckdns.org"
    grant_types:
      - "authorization_code"
    response_types:
      - "code"
    token_endpoint_auth_method: "none"
    application_type: "web"
    contacts:
      - "admin@chator.duckdns.org"'''

if "clients:" in c:
    c = re.sub(r'^clients:.*?(?=^\S|\Z)', clients_block, c, flags=re.MULTILINE|re.DOTALL)
else:
    c += "\n" + clients_block + "\n"

# Templates/assets paths — point to extracted share/
MAS_ROOT = "/opt/chator/mas"
tpl_block = f'''templates:
  path: "{MAS_ROOT}/share/templates"
assets:
  path: "{MAS_ROOT}/share/assets"
  manifest: "{MAS_ROOT}/share/manifest.json"
policy:
  wasm_file: "{MAS_ROOT}/share/policy.wasm"'''

for section in ["templates:", "assets:", "policy:"]:
    if section in c:
        c = re.sub(r'^' + section + r':.*?(?=^\S|\Z)', '', c, flags=re.MULTILINE|re.DOTALL)
c += "\n" + tpl_block + "\n"

with open(path, "w") as f:
    f.write(c)
print("  Config patched")

# Show what we ended up with (sensitive lines redacted)
for line in c.split("\n"):
    stripped = line.strip()
    if any(k in stripped.lower() for k in ["secret", "password", "key", "token"]):
        print(f"    {stripped.split(':')[0]}: <redacted>")
    elif stripped:
        print(f"    {stripped}")
PYPATCH

# ==========================================================================
# 3. Install & configure local PostgreSQL (if not using existing)
# ==========================================================================
if ! command -v psql &>/dev/null; then
    info "Installing PostgreSQL..."
    apt-get update -qq && apt-get install -y -qq postgresql postgresql-client
fi

info "Starting PostgreSQL if not already running..."
pg_lsclusters 2>/dev/null | grep -q "online" || pg_ctlcluster $(pg_lsclusters -h 2>/dev/null | head -1 | awk '{print $1, $2}') start 2>/dev/null || \
    service postgresql start 2>/dev/null || true

# Wait for PG to be ready
for i in $(seq 1 10); do
    if su - postgres -c "psql -c 'SELECT 1'" &>/dev/null; then
        break
    fi
    sleep 1
done

info "Creating MAS database and user (idempotent)..."
su - postgres -c "psql -c \"SELECT 1 FROM pg_roles WHERE rolname='${MAS_DB_USER}'\"" 2>/dev/null | grep -q 1 || \
    su - postgres -c "psql -c \"CREATE USER ${MAS_DB_USER} WITH PASSWORD '${MAS_DB_PASS}'\"" 

su - postgres -c "psql -c \"SELECT 1 FROM pg_database WHERE datname='${MAS_DB_NAME}'\"" 2>/dev/null | grep -q 1 || \
    su - postgres -c "psql -c \"CREATE DATABASE ${MAS_DB_NAME} OWNER ${MAS_DB_USER}\""

su - postgres -c "psql -d ${MAS_DB_NAME} -c \"GRANT ALL PRIVILEGES ON SCHEMA public TO ${MAS_DB_USER}\"" 2>/dev/null || true

# Enable trust auth for local Unix socket (MAS connects via TCP with password)
info "Configuring PostgreSQL auth..."
PG_HBA=$(su - postgres -c "psql -t -c 'SHOW hba_file'" 2>/dev/null | tr -d ' ')
if [[ -n "${PG_HBA}" ]] && [[ -f "${PG_HBA}" ]]; then
    # Ensure md5/scram-sha-256 for TCP on localhost
    if ! grep -q "^host.*${MAS_DB_NAME}.*${MAS_DB_USER}.*127.0.0.1/32" "${PG_HBA}" 2>/dev/null; then
        echo "host ${MAS_DB_NAME} ${MAS_DB_USER} 127.0.0.1/32 scram-sha-256" >> "${PG_HBA}"
        pg_ctlcluster $(pg_lsclusters -h 2>/dev/null | head -1 | awk '{print $1, $2}') reload 2>/dev/null || true
    fi
fi

# ==========================================================================
# 4. Verify database connection
# ==========================================================================
info "Verifying MAS database connection..."
python3 << 'PYDBCHECK'
import psycopg2, sys, os

db_uri = os.environ["MAS_DB_URI"]
try:
    conn = psycopg2.connect(db_uri)
    cur = conn.cursor()
    cur.execute("SELECT current_database(), current_user, version()")
    row = cur.fetchone()
    print(f"   Connected to: {row[0]} as {row[1]}")
    cur.close()
    conn.close()
    print("   Database connection OK")
except Exception as e:
    print(f"   WARN: {e}", file=sys.stderr)
    print("   DB setup non-fatal for install step", file=sys.stderr)
PYDBCHECK

info "Running MAS database migrations..."
set +e
"${MAS_HOME}/mas-cli" --config "${MAS_CONFIG}" database migrate 2>&1
MIGRATE_EXIT=$?
set -e

if [[ $MIGRATE_EXIT -ne 0 ]]; then
    warn "  Database migration exit code: $MIGRATE_EXIT"
    warn "  Check that PostgreSQL is running and reachable at localhost:5432"
    warn "  Try: su - postgres -c 'psql -d ${MAS_DB_NAME} -c \"SELECT 1\"'"
fi

# ==========================================================================
# 6. Add MAS to Supervisor
# ==========================================================================
info "Configuring supervisor..."
MAS_PROGRAM="

[program:mas]
command=${MAS_HOME}/mas-cli server --config ${MAS_CONFIG}
user=root
directory=${MAS_HOME}
autostart=false
autorestart=true
startretries=3
stdout_logfile=${MAS_LOG}/mas.log
stderr_logfile=${MAS_LOG}/mas-error.log
environment=MAS_CONFIG=\"${MAS_CONFIG}\""

if grep -q "\[program:mas\]" "${SUPERVISOR_CONFIG}" 2>/dev/null; then
    info "  MAS already in supervisor"
else
    echo "${MAS_PROGRAM}" >> "${SUPERVISOR_CONFIG}"
    info "  MAS added (autostart=false)"
fi

# ==========================================================================
# 7. Add nginx proxy locations
# ==========================================================================
info "Configuring nginx..."
python3 << 'PYNGX'
config_path = "/etc/nginx/sites-available/chator"

with open(config_path) as f:
    c = f.read()

mas_block = '''
    # MAS (Matrix Authentication Service) — OIDC / OAuth 2.0
    location /.well-known/openid-configuration {
        proxy_pass http://127.0.0.1:8777/.well-known/openid-configuration;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location /.well-known/oauth-authorization-server {
        proxy_pass http://127.0.0.1:8777/.well-known/oauth-authorization-server;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location /oauth/ {
        proxy_pass http://127.0.0.1:8777;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location /mas/ {
        proxy_pass http://127.0.0.1:8777/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
'''

if "# MAS " in c:
    print("  MAS nginx locations already exist")
else:
    # Insert before the SPA catch-all (last "location / {" block)
    # Find the LAST occurrence of "    # Element Web SPA" or the last "location / {"
    insert_before = "    # Element Web SPA"
    if insert_before in c:
        idx = c.rfind(insert_before)
        c = c[:idx] + mas_block + "\n" + c[idx:]
    else:
        # Fallback: insert before the final }
        idx = c.rstrip().rfind("}")
        c = c[:idx] + mas_block + "\n" + c[idx:]

    with open(config_path, "w") as f:
        f.write(c)
    print("  MAS nginx locations added")
PYNGX

# ==========================================================================
# 8. Update Synapse config
# ==========================================================================
info "Updating Synapse config..."
python3 << 'PYSYN'
config_path = "/etc/matrix-synapse/homeserver.yaml"

with open(config_path) as f:
    c = f.read()

mas_block = '''
# MAS (Matrix Authentication Service) — OAuth 2.0 delegation
experimental_features:
  msc3861_enabled: false

matrix_authentication_service:
  enabled: false
  url: "http://127.0.0.1:8777"
  issuer: "https://chator.duckdns.org"
'''

if "matrix_authentication_service" in c:
    print("  Synapse MAS config already present")
else:
    c += mas_block
    with open(config_path, "w") as f:
        f.write(c)
    print("  Synapse MAS config added (disabled)")
PYSYN

# ==========================================================================
# 9. Reload nginx
# ==========================================================================
info "Reloading nginx..."
nginx -t 2>&1 && supervisorctl restart nginx 2>/dev/null || {
    warn "  nginx reload failed — check config manually"
    nginx -t 2>&1 || true
}

# ==========================================================================
# 10. Migration step (--migrate flag)
# ==========================================================================
if [[ "$DO_MIGRATE" == "1" ]]; then
    echo ""
    info "=== STARTING syn2mas MIGRATION ==="
    echo ""
    warn "This will STOP synapse and START mas to migrate users."
    warn "Make sure no users are actively using the server."
    echo ""

    # Fix Synapse DB schema before migration (refresh_tokens required for startup)
    FIX_SCRIPT="$(dirname "$0")/fix-refresh-tokens.py"
    if [[ -f "${FIX_SCRIPT}" ]]; then
        info "Fixing Synapse DB schema..."
        python3 "${FIX_SCRIPT}" 2>&1 || warn "  refresh_tokens fix had warnings"
    else
        warn "  fix-refresh-tokens.py not found — skipping DB fix"
    fi

    # Stop Synapse
    info "Stopping Synapse..."
    supervisorctl stop synapse 2>/dev/null || systemctl stop synapse 2>/dev/null || true

    # Generate shared secret and update configs
    info "Generating MAS shared secret..."
    SHARED_SECRET=$(openssl rand -hex 32)
    ADMIN_TOKEN=$(openssl rand -hex 32)

    # Update MAS config with shared secret
    python3 -c "
import re
with open('/etc/chator/mas.yaml') as f:
    c = f.read()
c = re.sub(
    r'# secret will be set during migration step',
    'secret: \"$SHARED_SECRET\"',
    c
)
with open('/etc/chator/mas.yaml', 'w') as f:
    f.write(c)
print('  MAS secret set')
"

    # Update Synapse config
    python3 -c "
with open('/etc/matrix-synapse/homeserver.yaml') as f:
    c = f.read()
c = c.replace('msc3861_enabled: false', 'msc3861_enabled: true')
c = c.replace('  enabled: false', '  enabled: true')
c = c.replace('#  admin_token: \"\"', '  admin_token: \"$ADMIN_TOKEN\"')
with open('/etc/matrix-synapse/homeserver.yaml', 'w') as f:
    f.write(c)
print('  Synapse config updated (enabled=true)')
"

    # Start MAS (needs to be running for migration)
    info "Starting MAS for migration..."
    supervisorctl start mas 2>/dev/null || "${MAS_HOME}/mas-cli" server --config "${MAS_CONFIG}" &
    MAS_PID=$!
    sleep 3

    # Run syn2mas migration
    info "Running syn2mas migrate..."
    "${MAS_HOME}/mas-cli" syn2mas migrate \
        --synapse-config "${SYNAPSE_CONFIG}" \
        --mas-config "${MAS_CONFIG}" 2>&1 | tail -20 || {
        error "Migration failed — check logs above"
    }
    info "Migration completed"

    # Restart MAS under supervisor
    info "Restarting MAS..."
    supervisorctl restart mas 2>/dev/null || true

    # Start Synapse
    info "Starting Synapse..."
    supervisorctl start synapse 2>/dev/null || systemctl start synapse 2>/dev/null || true

    echo ""
    info "=== MIGRATION COMPLETE ==="
    echo ""
    info "Users migrated. Login is now handled by MAS."
    info "Access your account at: ${SITE_URL}"
    echo ""
fi

# ==========================================================================
# Summary
# ==========================================================================
echo ""
echo -e "${GREEN}╔═════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  MAS v${MAS_VERSION} installation complete                     ${NC}"
echo -e "${GREEN}╠═════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Binary:  ${MAS_HOME}/mas-cli             ${NC}"
echo -e "${GREEN}║  Config:  ${MAS_CONFIG}                   ${NC}"
echo -e "${GREEN}║  MAS URL: http://127.0.0.1:8777                        ${NC}"
echo -e "${GREEN}║                                                         ${NC}"
echo -e "${GREEN}║  Synapse MAS integration: DISABLED                      ${NC}"
echo -e "${GREEN}║  To enable: set msc3861_enabled: true + restart         ${NC}"
echo -e "${GREEN}║                                                         ${NC}"
echo -e "${GREEN}║  Run with --migrate to migrate users + enable:          ${NC}"
echo -e "${GREEN}║    bash deploy/install-mas.sh --migrate                 ${NC}"
echo -e "${GREEN}╚═════════════════════════════════════════════════════════════╝${NC}"
