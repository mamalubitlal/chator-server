#!/bin/bash
# =============================================================================
# Chator — finalize: fix MAS config, validate, restart, verify
# Run: sudo bash deploy/finalize.sh
# Idempotent — safe to run multiple times.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1"; exit 1; }

[[ $EUID -eq 0 ]] || error "Must run as root"

SITE_URL="${SITE_URL:-https://chator.duckdns.org}"
MAS_CONFIG="${MAS_CONFIG:-/etc/chator/mas.yaml}"
MAS_BIN="${MAS_BIN:-/opt/chator/mas/mas-cli}"
SYNAPSE_CONFIG="${SYNAPSE_CONFIG:-/etc/matrix-synapse/homeserver.yaml}"
NGINX_SITE="${NGINX_SITE:-/etc/nginx/sites-available/chator}"

# =============================================================================
# 0. Fix Synapse DB schema (refresh_tokens table must exist for Synapse to start)
# =============================================================================
FIX_SCRIPT="$(dirname "$0")/fix-refresh-tokens.py"
if [[ -f "${FIX_SCRIPT}" ]]; then
    info "Checking Synapse DB schema..."
    python3 "${FIX_SCRIPT}" 2>&1 || warn "  refresh_tokens fix had warnings — inspect output above"
else
    warn "  fix-refresh-tokens.py not found at ${FIX_SCRIPT} — skipping"
    warn "  If Synapse fails to start, run: sudo python3 deploy/fix-refresh-tokens.py"
fi

# =============================================================================
# 1. Fix MAS config
# =============================================================================
info "Patching MAS config..."

python3 << 'PYEOF'
import re

path = "/etc/chator/mas.yaml"

with open(path) as f:
    c = f.read()

changes = []

# 1a. Web listener → 127.0.0.1:8777
# The generated config has various formats, handle them all
for pattern, replacement in [
    ("address: '127.0.0.1:8777'", None),  # already correct
    ("address: '[::]:8080'", "address: '127.0.0.1'\n      port: 8777"),
    ("address: '0.0.0.0:8080'", "address: '127.0.0.1'\n      port: 8777"),
    ("address: '[::]'\n      port: 8080", "address: '127.0.0.1'\n      port: 8777"),
    ("address: '0.0.0.0'\n      port: 8080", "address: '127.0.0.1'\n      port: 8777"),
]:
    if replacement is None:
        changes.append("  Listener already correct")
        break
    if pattern in c:
        c = c.replace(pattern, replacement)
        changes.append(f"  Listener: {pattern} → 127.0.0.1:8777")
        break
else:
    changes.append("  Listener: no known pattern found (check manually)")

# 1b. public_base and issuer
for key in ["public_base", "issuer"]:
    pattern = f"  {key}: http://[::]:8080/"
    if pattern in c:
        c = c.replace(pattern, f"  {key}: https://chator.duckdns.org/")
        changes.append(f"  {key}: fixed")
    # Also catch other http:// values pointing to wrong URL
    for wrong in ["http://localhost:8080", "http://127.0.0.1:8080", "http://0.0.0.0:8080"]:
        wrong_pat = f"  {key}: {wrong}/"
        if wrong_pat in c:
            c = c.replace(wrong_pat, f"  {key}: https://chator.duckdns.org/")
            changes.append(f"  {key}: fixed from {wrong}")

# 1c. Matrix homeserver (server_name in Synapse, not a URL)
for old in [
    "  homeserver: localhost:8008",
    "  homeserver_url: http://localhost:8008/",
    "  homeserver_url: http://localhost:8008",
    "  homeserver: localhost",
]:
    if old in c:
        c = c.replace(old, "  homeserver: chator.duckdns.org")
        changes.append(f"  matrix homeserver: fixed to chator.duckdns.org")
        break

# 1d. Matrix endpoint (actual URL to reach Synapse)
for old in [
    "  endpoint: http://localhost:8008/",
    "  endpoint: http://localhost:8008",
    "  endpoint: http://[::]:8080/",
    "  endpoint: http://localhost:8009/",  # already correct
    "  endpoint: http://localhost:8009",
    "  endpoint: https://chator.duckdns.org/",
]:
    if old in c and "8009" not in old:
        c = c.replace(old, "  endpoint: http://localhost:8009/")
        changes.append(f"  matrix endpoint: fixed to localhost:8009")
        break

# 1e. Add Element Web OAuth client if missing
client_block = '''
clients:
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
      - "admin@chator.duckdns.org"
'''

if "clients:" not in c:
    c += client_block
    changes.append("  OAuth client: element-web added")
else:
    # Check existing client has correct redirect_uri
    if "element-web" in c and "chator.duckdns.org" not in c:
        changes.append("  OAuth client: exists but may need redirect_uri check")
    else:
        changes.append("  OAuth client: already present")

# 1f. Ensure templates/assets paths exist (from install-mas.sh)
MAS_ROOT = "/opt/chator/mas"
tpl_lines = f'''templates:
  path: "{MAS_ROOT}/share/templates"
assets:
  path: "{MAS_ROOT}/share/assets"
  manifest: "{MAS_ROOT}/share/manifest.json"
policy:
  wasm_file: "{MAS_ROOT}/share/policy.wasm"'''

if "templates:" not in c:
    c += "\n" + tpl_lines + "\n"
    changes.append("  templates/assets paths: added")
elif MAS_ROOT not in c:
    changes.append("  templates/assets: exist but paths may need verification")

with open(path, "w") as f:
    f.write(c)

for ch in changes:
    print(ch)
PYEOF

# =============================================================================
# 2. Validate MAS config
# =============================================================================
info "Validating MAS config..."
if [[ -x "${MAS_BIN}" ]]; then
    "${MAS_BIN}" config check "${MAS_CONFIG}" 2>&1 | head -10 && echo "" || {
        warn "  mas-cli config check failed — inspect ${MAS_CONFIG}"
    }
else
    warn "  MAS binary not found at ${MAS_BIN}, skipping validation"
fi

# =============================================================================
# 3. Validate Synapse config
# =============================================================================
info "Validating Synapse config..."
if [[ -f "${SYNAPSE_CONFIG}" ]]; then
    python3 -c "
import yaml
with open('${SYNAPSE_CONFIG}') as f:
    data = yaml.safe_load(f)
print(f'  OK: {len(data)} top-level keys')
print(f'  server_name: {data.get(\"server_name\", \"MISSING\")}')
print(f'  listeners: {len(data.get(\"listeners\", []))}')
print(f'  experimental_features: {data.get(\"experimental_features\", {})}')
print(f'  matrix_authentication_service: {\"present\" if data.get(\"matrix_authentication_service\") else \"MISSING\"}')
" 2>&1 || warn "  Synapse config validation failed"
else
    warn "  Synapse config not found at ${SYNAPSE_CONFIG}"
fi

# =============================================================================
# 4. Validate nginx config
# =============================================================================
info "Validating nginx config..."
nginx -t 2>&1 && info "  nginx config OK" || warn "  nginx config has errors"

# =============================================================================
# 5. Restart services
# =============================================================================
info "Restarting services..."

# Reload supervisor if running
if supervisorctl status &>/dev/null; then
    # Restart MAS
    if supervisorctl status mas &>/dev/null; then
        supervisorctl restart mas 2>&1 || true
        info "  MAS restarted"
    else
        warn "  MAS not in supervisor"
    fi
    
    # Reload nginx
    if supervisorctl status nginx &>/dev/null; then
        supervisorctl restart nginx 2>&1 || true
        info "  nginx restarted"
    fi
    
    # Restart Synapse
    if supervisorctl status synapse &>/dev/null; then
        supervisorctl restart synapse 2>&1 || true
        info "  Synapse restarted"
    fi
else
    warn "  Supervisor not running — start with: supervisord -c /etc/supervisor/supervisord.conf"
fi

# =============================================================================
# 6. Verify
# =============================================================================
echo ""
info "=== VERIFICATION ==="
echo ""

# Check processes
for proc in mas synapse nginx; do
    if pgrep -x "$proc" &>/dev/null || pgrep -f "mas-cli" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $proc running"
    else
        echo -e "  ${RED}✗${NC} $proc NOT running"
    fi
done

# Check ports
for port in 8777 8009 8008 443; do
    if ss -tlnp | grep -q ":$port "; then
        echo -e "  ${GREEN}✓${NC} Port $port listening"
    else
        echo -e "  ${YELLOW}~${NC} Port $port not listening (may be expected)"
    fi
done

# DNS check
echo ""
info "DNS:"
if host chator.duckdns.org &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} chator.duckdns.org resolves"
else
    echo -e "  ${YELLOW}~${NC} chator.duckdns.org DNS check failed (dig not installed?)"
fi

# HTTP check
echo ""
info "HTTP endpoints:"
for ep in \
    "https://chator.duckdns.org/ | Element Web" \
    "https://chator.duckdns.org/.well-known/openid-configuration | MAS OIDC" \
    "https://chator.duckdns.org/_matrix/client/versions | Synapse API"; do
    url="${ep%%|*}"
    desc="${ep##*|}"
    url="$(echo "$url" | xargs)"
    desc="$(echo "$desc" | xargs)"
    if curl -sfL --connect-timeout 5 "$url" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $desc — $url"
    else
        echo -e "  ${RED}✗${NC} $desc — $url"
    fi
done

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Finalization complete!                  ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Visit: https://chator.duckdns.org       ║${NC}"
echo -e "${GREEN}║  Check: supervisorctl status             ║${NC}"
echo -e "${GREEN}║  Logs:  tail -f /var/log/mas/mas.log     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
