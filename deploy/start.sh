#!/bin/bash
set -euo pipefail

# =============================================================================
# Chator — runtime startup script
# Runs at boot via systemd. Wired to supervisor for process management.
# =============================================================================

# === Config (override via env or /etc/chator/env) ===
SYNAPSE_SERVER_NAME="${SYNAPSE_SERVER_NAME:-localhost}"
SYNAPSE_REPORT_STATS="${SYNAPSE_REPORT_STATS:-no}"
SYNAPSE_PUBLIC_URL="${SYNAPSE_PUBLIC_URL:-http://localhost:8008}"
SYNAPSE_ENABLE_REGISTRATION="${SYNAPSE_ENABLE_REGISTRATION:-true}"

CHATOR_CONF="/etc/chator"
CHATOR_DATA="/var/lib/chator"
CHATOR_LOG="/var/log/chator"
SYNAPSE_CONFIG="/etc/matrix-synapse/homeserver.yaml"

# Export DB credentials for supabase_db.py
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-do4ePaNXnyiD7xkX}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_DB="${POSTGRES_DB:-postgres}"

# Optional: set these to override default Supabase endpoints
# export SUPABASE_HOST="db.ukymrxkunsylwiagdowy.supabase.co"
# export SUPABASE_PORT="5432"
# export SUPABASE_POOLER_HOST="aws-1-eu-central-1.pooler.supabase.com"
# export SUPABASE_POOLER_PORT="6543"

# Optional: public IP for LiveKit external IP detection
PUBLIC_IP="${PUBLIC_IP:-}"

# Preload jemalloc
JEMALLOC_PATH="${JEMALLOC_PATH:-/usr/lib/x86_64-linux-gnu/libjemalloc.so.2}"
if [[ -f "${JEMALLOC_PATH}" ]]; then
    export LD_PRELOAD="${JEMALLOC_PATH}"
fi

# ============================================================================
# 1. Source env file if present
# ============================================================================
if [[ -f /etc/chator/env ]]; then
    set -a
    source /etc/chator/env
    set +a
fi

# ============================================================================
# 2. Pre-flight directories
# ============================================================================
mkdir -p "${CHATOR_DATA}/media" "${CHATOR_DATA}/uploads" "${CHATOR_DATA}/appservices"
mkdir -p "${CHATOR_LOG}" /var/log/supervisor /var/log/livekit /var/log/localtunnel

# ============================================================================
# 3. Supabase DB auto-detect
# ============================================================================
echo "=== Chator startup ==="
python3 /usr/local/bin/supabase_db.py "${SYNAPSE_CONFIG}" 2>&1

# ============================================================================
# 4. Patch homeserver.yaml with runtime settings
# ============================================================================

# -- Server name --
sed -i "s/^server_name:.*/server_name: \"${SYNAPSE_SERVER_NAME}\"/" "${SYNAPSE_CONFIG}"

# -- Secrets --
REG_SECRET=$(cat /etc/chator/secrets/registration_shared_secret 2>/dev/null || openssl rand -hex 32)
MAC_SECRET=$(cat /etc/chator/secrets/macaroon_secret 2>/dev/null || openssl rand -hex 32)
FORM_SECRET=$(cat /etc/chator/secrets/form_secret 2>/dev/null || openssl rand -hex 32)

python3 -c "
import re
with open('${SYNAPSE_CONFIG}') as f:
    c = f.read()
c = re.sub(r'registration_shared_secret:.*', 'registration_shared_secret: \"${REG_SECRET}\"', c)
c = re.sub(r'macaroon_secret_key:.*', 'macaroon_secret_key: \"${MAC_SECRET}\"', c)
c = re.sub(r'form_secret:.*', 'form_secret: \"${FORM_SECRET}\"', c)
c = re.sub(r'report_stats:.*', 'report_stats: ${SYNAPSE_REPORT_STATS}', c)
with open('${SYNAPSE_CONFIG}', 'w') as f:
    f.write(c)
"

# -- Registration --
if [[ "${SYNAPSE_ENABLE_REGISTRATION}" = "true" ]]; then
    python3 -c "
with open('${SYNAPSE_CONFIG}') as f:
    c = f.read()
c = re.sub(r'enable_registration:.*', 'enable_registration: true', c)
if 'enable_registration_without_verification' not in c:
    c += '\nenable_registration_without_verification: true\n'
else:
    c = re.sub(r'enable_registration_without_verification:.*', 'enable_registration_without_verification: true', c)
with open('${SYNAPSE_CONFIG}', 'w') as f:
    f.write(c)
" 2>/dev/null || true
fi

# -- Public URL for well-known --
mkdir -p "${CHATOR_DATA}/.well-known/matrix"
cat > "${CHATOR_DATA}/.well-known/matrix/client" << EOF
{
    "m.homeserver": {
        "base_url": "${SYNAPSE_PUBLIC_URL}"
    },
    "m.identity_server": {
        "base_url": "${SYNAPSE_PUBLIC_URL}"
    }
}
EOF

# -- MatrixRTC / Element Call config (ensures it's present) --
python3 -c "
import re
with open('${SYNAPSE_CONFIG}') as f:
    c = f.read()
if 'msc4143_enabled:' not in c:
    c = re.sub(r'^experimental_features:', 'experimental_features:\n  msc4143_enabled: true', c, flags=re.MULTILINE)
if 'matrix_rtc:' not in c:
    c += '\nmatrix_rtc:\n  transports:\n    - type: livekit\n      livekit_service_url: ${SYNAPSE_PUBLIC_URL}/livekit/jwt\n'
with open('${SYNAPSE_CONFIG}', 'w') as f:
    f.write(c)
"

# -- Synapse listener port 8009 --
python3 -c "
import re
with open('${SYNAPSE_CONFIG}') as f:
    c = f.read()
c = re.sub(r'port:\s*8008\b', 'port: 8009', c)
with open('${SYNAPSE_CONFIG}', 'w') as f:
    f.write(c)
"

# ============================================================================
# 5. Update LiveKit config with public IP if available
# ============================================================================
if [[ -n "${PUBLIC_IP}" ]] && grep -q 'use_external_ip: false' /etc/livekit.conf; then
    sed -i "s/use_external_ip: false/use_external_ip: true/" /etc/livekit.conf
    # Add external IP if not already there
    if ! grep -q "external_ip:" /etc/livekit.conf; then
        sed -i "/use_external_ip: true/a\  external_ip: ${PUBLIC_IP}" /etc/livekit.conf
    fi
fi

# ============================================================================
# 6. Update Element Web config with public URL
# ============================================================================
if [[ -n "${SYNAPSE_PUBLIC_URL}" ]] && [[ "${SYNAPSE_PUBLIC_URL}" != "http://localhost:8008" ]]; then
    python3 -c "
import json
with open('/usr/share/element-web/config.json') as f:
    cfg = json.load(f)
cfg['default_server_config']['m.homeserver']['base_url'] = '${SYNAPSE_PUBLIC_URL}'
cfg['default_server_config']['m.homeserver']['server_name'] = '${SYNAPSE_SERVER_NAME}'
with open('/usr/share/element-web/config.json', 'w') as f:
    json.dump(cfg, f)
" 2>/dev/null || true
fi

# ============================================================================
# 7. Well-known with RTC focus for Element Call
# ============================================================================
mkdir -p /usr/share/element-web/.well-known/matrix
cat > /usr/share/element-web/.well-known/matrix/client << EOF
{
    "m.homeserver": { "base_url": "${SYNAPSE_PUBLIC_URL}" },
    "m.identity_server": { "base_url": "${SYNAPSE_PUBLIC_URL}" },
    "org.matrix.msc4143.rtc_foci": [
        {
            "type": "livekit",
            "livekit_service_url": "${SYNAPSE_PUBLIC_URL}/livekit/jwt"
        }
    ]
}
EOF

mkdir -p "${CHATOR_DATA}/.well-known/matrix"
cp /usr/share/element-web/.well-known/matrix/client "${CHATOR_DATA}/.well-known/matrix/client"

# ============================================================================
# 8. Start supervisor
# ============================================================================
echo "=== Starting supervisor ==="
exec /opt/chator/venv/bin/supervisord -c /etc/supervisor/supervisord.conf
