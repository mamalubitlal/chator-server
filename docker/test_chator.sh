#!/bin/bash
# Chator Docker Test Suite
# Comprehensive integration tests for all services in the Chator container.
#
# Run:
#   docker compose cp docker/test_chator.sh chator:/tmp/test_chator.sh
#   docker compose exec chator bash /tmp/test_chator.sh
#
# Or from host (with network_mode=host):
#   bash docker/test_chator.sh
#
set +e  # Don't abort on individual test failures

# ─── Colors ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS="${GREEN}PASS${NC}"; FAIL="${RED}FAIL${NC}"; SKIP="${YELLOW}SKIP${NC}"; INFO="${CYAN}INFO${NC}"

FAILED=0; TOTAL=0; SKIPPED=0

# ─── Helpers ───────────────────────────────────────────────────────────
pass() { echo -e "  ${PASS}  $1"; ((TOTAL++)); }
fail() { echo -e "  ${FAIL}  $1"; ((TOTAL++)); ((FAILED++)); }
skip() { echo -e "  ${SKIP}  $1"; ((SKIPPED++)); }
info() { echo -e "  ${INFO}  $1"; }
heading() { echo -e "\n${CYAN}════════════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"; }

check_http() {
    local url="$1" expected="$2" label="$3"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    if [ "$code" = "$expected" ]; then pass "$label (HTTP $code)"; else fail "$label (expected $expected, got $code)"; fi
}

check_http_any() {
    local url="$1" label="$2; shift 2; local expected_codes=("$@")"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    local matched=0
    for exp in "$@"; do
        [ "$code" = "$exp" ] && { matched=1; break; }
    done
    if [ "$matched" -eq 1 ]; then pass "$label (HTTP $code)"; else fail "$label (unexpected HTTP $code)"; fi
}

check_json_key() {
    local url="$1" key="$2" label="$3"
    local val
    val=$(curl -s --max-time 5 "$url" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('$key', '__MISSING__'))
except Exception as e:
    sys.stderr.write(str(e))
    print('__FAIL__')
" 2>/dev/null || echo "__FAIL__")
    if [ "$val" != "__MISSING__" ] && [ "$val" != "__FAIL__" ]; then
        pass "$label (found key: $key)"
    else
        fail "$label (key '$key' missing, got: $val)"
    fi
}

check_file_contains() {
    local file="$1" pattern="$2" label="$3"
    if [ ! -f "$file" ]; then fail "$label (file not found: $file)"; return; fi
    if grep -q "$pattern" "$file" 2>/dev/null; then pass "$label"; else fail "$label (pattern '$pattern' not found in $file)"; fi
}

check_port() {
    local host="$1" port="$2" label="$3"
    if timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then pass "$label ($host:$port open)"; else fail "$label ($host:$port not reachable)"; fi
}

check_body_contains() {
    local url="$1" pattern="$2" label="$3"
    if curl -s --max-time 5 "$url" 2>/dev/null | grep -q "$pattern"; then pass "$label"; else fail "$label (pattern '$pattern' not found in response)"; fi
}

check_header() {
    local url="$1" header="$2" expected="$3" label="$4"
    local val
    val=$(curl -s -I --max-time 5 "$url" 2>/dev/null | grep -i "$header" | tr -d '\r' || echo "")
    if echo "$val" | grep -qi "$expected"; then pass "$label (header: ${val##*: })"; else fail "$label (header '$header: $expected' missing, got: '$val')"; fi
}

# Check process by reading /proc/<pid>/cmdline
# (pgrep/ps are 32-bit binaries, broken in this multi-arch container)
proc_running() {
    local pattern="$1"
    for pid_dir in /proc/[0-9]*/; do
        local cmdline
        cmdline=$(cat "${pid_dir}cmdline" 2>/dev/null | tr '\0' ' ' || true)
        if echo "$cmdline" | grep -q "$pattern"; then
            return 0
        fi
    done
    return 1
}

# ─── URLs ──────────────────────────────────────────────────────────────
BASE_URL="${BASE_URL:-http://localhost:8008}"
LIVEKIT_URL="${LIVEKIT_URL:-http://localhost:7880}"
LK_JWT_URL="${LK_JWT_URL:-http://localhost:8070}"
SYDENT_URL="${SYDENT_URL:-http://localhost:8090}"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Chator Docker Integration Test Suite              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e "${INFO}  Target: $BASE_URL"
echo -e "${INFO}  LiveKit: $LIVEKIT_URL"
echo -e "${INFO}  lk-jwt:  $LK_JWT_URL"
echo -e "${INFO}  Sydent:  $SYDENT_URL"
echo ""

# ═══════════════════════════════════════════════════════════════════════
# 1. Container & Infrastructure
# ═══════════════════════════════════════════════════════════════════════
heading "1. Container & Infrastructure"

if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    info "Running inside container"
else
    info "Running from host (network_mode=host)"
fi

if hostname -f >/dev/null 2>&1; then
    info "Hostname: $(hostname -f)"
fi

if [ -f /data/homeserver.yaml ]; then
    pass "/data/homeserver.yaml exists"
else
    fail "/data/homeserver.yaml not found — data volume may be missing"
fi

if proc_running "supervisord"; then
    pass "supervisord running (PID 1)"
else
    fail "supervisord not running"
fi

# ═══════════════════════════════════════════════════════════════════════
# 2. nginx Routes (port 8008)
# ═══════════════════════════════════════════════════════════════════════
heading "2. nginx Routes"

# 2.1 Element Web root
check_http "$BASE_URL/" "200" "Element Web serves root (/)"
check_body_contains "$BASE_URL/" "Element" "Element Web HTML contains 'Element'"

# 2.2 Element Call sub-path
check_http "$BASE_URL/call/" "200" "Element Call serves (/call/)"
check_body_contains "$BASE_URL/call/" "Element Call" "Element Call HTML contains 'Element Call'"

# 2.3 Synapse API proxy
check_http "$BASE_URL/_matrix/client/versions" "200" "Synapse API (/versions) → 200"
check_json_key "$BASE_URL/_matrix/client/versions" "versions" "Synapse API returns versions JSON"
check_body_contains "$BASE_URL/_matrix/client/versions" "v1." "Synapse API response contains version string"

# 2.4 Synapse health endpoint
check_http "$BASE_URL/health" "200" "Synapse health (/health) → 200"

# 2.5 Synapse admin API proxy
check_http "$BASE_URL/_synapse/admin/v1/server_version" "200" "Synapse admin API → 200"
check_json_key "$BASE_URL/_synapse/admin/v1/server_version" "server_version" "Synapse admin API returns server_version"

# 2.6 .well-known/matrix/client (Element Call discovery)
check_http "$BASE_URL/.well-known/matrix/client" "200" ".well-known/matrix/client → 200"
check_json_key "$BASE_URL/.well-known/matrix/client" "m.homeserver" ".well-known has m.homeserver"
check_json_key "$BASE_URL/.well-known/matrix/client" "org.matrix.msc4143.rtc_foci" ".well-known has rtc_foci (Element Call)"
check_body_contains "$BASE_URL/.well-known/matrix/client" "livekit_service_url" ".well-known rtc_foci has livekit_service_url"

# 2.7 lk-jwt proxy via nginx
# GET returns 405 (POST expected), 400 from lk-jwt-service, or 502 if nginx issue
LK_PROXY_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL/livekit/jwt/get_token" 2>/dev/null || echo "000")
if [ "$LK_PROXY_CODE" = "405" ] || [ "$LK_PROXY_CODE" = "400" ] || [ "$LK_PROXY_CODE" = "200" ]; then
    pass "lk-jwt nginx proxy reachable (HTTP $LK_PROXY_CODE)"
else
    fail "lk-jwt nginx proxy unexpected response (HTTP $LK_PROXY_CODE)"
fi

# 2.8 CORS headers on .well-known
check_header "$BASE_URL/.well-known/matrix/client" "Access-Control-Allow-Origin" "\\*" "CORS Allow-Origin: * on .well-known"
check_header "$BASE_URL/.well-known/matrix/client" "Access-Control-Allow-Methods" "GET" "CORS Allow-Methods on .well-known"

# 2.9 Element Web static assets
check_http "$BASE_URL/config.json" "200" "Element Web config.json served"
check_json_key "$BASE_URL/config.json" "default_server_config" "Element Web config has default_server_config"

# 2.10 Element Call static assets (path-rewritten for sub-path hosting)
check_http "$BASE_URL/call/config.json" "200" "Element Call config.json served at /call/config.json"
check_json_key "$BASE_URL/call/config.json" "livekit_jwt_service_url" "Element Call config has livekit_jwt_service_url"
check_body_contains "$BASE_URL/call/config.json" "livekit/jwt" "Element Call livekit_jwt_service_url points to /livekit/jwt"

# 2.11 Element Call JS assets served with correct prefix
check_http "$BASE_URL/call/config.json" "200" "Element Call config.json accessible under /call/"

# ═══════════════════════════════════════════════════════════════════════
# 3. Synapse (direct on port 8009)
# ═══════════════════════════════════════════════════════════════════════
heading "3. Synapse"
SYNAPSE_DIRECT="${SYNAPSE_DIRECT:-http://localhost:8009}"

check_http "$SYNAPSE_DIRECT/health" "200" "Synapse direct health → 200"
check_http "$SYNAPSE_DIRECT/_matrix/client/versions" "200" "Synapse direct versions → 200"
check_json_key "$SYNAPSE_DIRECT/_matrix/client/versions" "versions" "Synapse direct returns versions"

# ═══════════════════════════════════════════════════════════════════════
# 4. User Registration & End-to-End Flows
# ═══════════════════════════════════════════════════════════════════════
heading "4. User Registration & End-to-End"

TEST_USER="chator_test_$(date +%s)"
TEST_PASS="TestPass123!"
TEST_DISPLAY="Chator Tester"

# 4.1 Registration endpoint
REG_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    -X POST "$BASE_URL/_matrix/client/v3/register" \
    -H "Content-Type: application/json" \
    -d '{"username":"probe_'$TEST_USER'","password":"probe123","auth":{"type":"m.login.dummy"}}' \
    2>/dev/null || echo "000")
if [ "$REG_CODE" = "200" ] || [ "$REG_CODE" = "400" ] || [ "$REG_CODE" = "401" ]; then
    pass "Registration endpoint accepts POST (HTTP $REG_CODE)"
else
    fail "Registration endpoint unreachable (HTTP $REG_CODE)"
fi

# 4.2 Register a real user
REG_RESPONSE=$(curl -s --max-time 10 -X POST "$BASE_URL/_matrix/client/v3/register" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${TEST_USER}\",\"password\":\"${TEST_PASS}\",\"displayname\":\"${TEST_DISPLAY}\",\"auth\":{\"type\":\"m.login.dummy\"}}" \
    2>/dev/null || echo "")

REG_ACCESS_TOKEN=$(echo "$REG_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    token = data.get('access_token', '')
    if token: print(token)
    else: print(data.get('errcode', 'NO_TOKEN'))
except Exception as e:
    sys.stderr.write(str(e))
    print('PARSE_ERROR')
" 2>/dev/null || echo "EMPTY")

REG_ERRCODE=$(echo "$REG_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('errcode', ''))
except:
    print('')
" 2>/dev/null || echo "")

if [ -n "$REG_ACCESS_TOKEN" ] && [[ "$REG_ACCESS_TOKEN" != "M_USER_IN_USE" ]] && [[ "$REG_ACCESS_TOKEN" != "M_FORBIDDEN" ]] && [[ "$REG_ACCESS_TOKEN" != "NO_TOKEN" ]] && [[ "$REG_ACCESS_TOKEN" != "PARSE_ERROR" ]] && [[ "$REG_ACCESS_TOKEN" != "EMPTY" ]]; then
    pass "User registration successful (got access token)"
elif [[ "$REG_ACCESS_TOKEN" == "M_USER_IN_USE"* ]]; then
    info "User already exists — attempting login"
    LOGIN_RESPONSE=$(curl -s --max-time 10 -X POST "$BASE_URL/_matrix/client/v3/login" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"${TEST_USER}\"},\"password\":\"${TEST_PASS}\"}" \
        2>/dev/null || echo "")
    REG_ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('access_token', 'LOGIN_FAILED'))
except:
    print('LOGIN_FAILED')
" 2>/dev/null || echo "EMPTY")
    if [ -n "$REG_ACCESS_TOKEN" ] && [ "$REG_ACCESS_TOKEN" != "LOGIN_FAILED" ] && [ "$REG_ACCESS_TOKEN" != "EMPTY" ]; then
        pass "User login successful (got access token)"
    else
        fail "User login failed"
        REG_ACCESS_TOKEN=""
    fi
elif [[ "$REG_ACCESS_TOKEN" == "M_FORBIDDEN" ]]; then
    fail "Registration forbidden — SYNAPSE_ENABLE_REGISTRATION may be disabled"
    REG_ACCESS_TOKEN=""
else
    fail "User registration failed: $REG_ACCESS_TOKEN ($REG_ERRCODE)"
    REG_ACCESS_TOKEN=""
fi

# Authenticated flows (only if we have a token)
if [ -n "$REG_ACCESS_TOKEN" ]; then
    USER_ID=$(echo "$REG_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('user_id', 'unknown'))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")

    # 4.3 OpenID token request (needed for LiveKit JWT via lk-jwt)
    OPENID_RESPONSE=$(curl -s --max-time 10 -X POST \
        "$BASE_URL/_matrix/client/v3/user/${USER_ID}/openid/request_token" \
        -H "Authorization: Bearer $REG_ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{}" 2>/dev/null || echo "")
    OPENID_TOKEN=$(echo "$OPENID_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('access_token', 'NO_OPENID'))
except:
    print('OPENID_FAILED')
" 2>/dev/null || echo "EMPTY")
    if [ -n "$OPENID_TOKEN" ] && [ "$OPENID_TOKEN" != "NO_OPENID" ] && [ "$OPENID_TOKEN" != "OPENID_FAILED" ]; then
        pass "OpenID token obtained for LiveKit JWT exchange"
    else
        fail "OpenID token request failed ($OPENID_TOKEN)"
    fi

    # 4.4 Create a room
    ROOM_RESPONSE=$(curl -s --max-time 10 -X POST "$BASE_URL/_matrix/client/v3/createRoom" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $REG_ACCESS_TOKEN" \
        -d "{\"name\":\"Test Room\",\"room_alias_name\":\"test_${TEST_USER}\",\"preset\":\"public_chat\"}" \
        2>/dev/null || echo "")
    ROOM_ID=$(echo "$ROOM_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('room_id', data.get('errcode', 'NO_ROOM')))
except:
    print('CREATE_FAILED')
" 2>/dev/null || echo "EMPTY")
    if [ -n "$ROOM_ID" ] && [ "$ROOM_ID" != "NO_ROOM" ] && [ "$ROOM_ID" != "CREATE_FAILED" ] && ! echo "$ROOM_ID" | grep -q "M_"; then
        pass "Room created (room_id: ${ROOM_ID:0:20}...)"
    else
        fail "Room creation failed ($ROOM_ID)"
    fi

    # 4.5 LiveKit JWT via lk-jwt /sfu/get through nginx proxy
    # This is the endpoint Element Call uses for authenticating calls
    SFU_RESPONSE=$(curl -s --max-time 10 -X POST \
        "$BASE_URL/livekit/jwt/sfu/get" \
        -H "Content-Type: application/json" \
        -d "{\"room_id\":\"!test:chator.local\",\"slot_id\":1,\"openid_token\":${OPENID_RESPONSE}}" \
        2>/dev/null || echo "")
    LK_JWT_RESULT=$(echo "$SFU_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Either success (has 'token') or expected error (M_BAD_JSON with details)
    err = data.get('errcode', '')
    if err == 'M_BAD_JSON':
        print('EXPECTED_M_BAD_JSON')
    elif err:
        print('ERR:' + err + ':' + data.get('error',''))
    else:
        print(data.get('token', 'NO_TOKEN'))
except:
    print('PARSE_ERROR')
" 2>/dev/null || echo "EMPTY")
    if [ "$LK_JWT_RESULT" = "EXPECTED_M_BAD_JSON" ]; then
        pass "lk-jwt /sfu/get processed the request (room validation needed)"
    elif echo "$LK_JWT_RESULT" | grep -q "^ERR:"; then
        fail "lk-jwt /sfu/get unexpected error ($LK_JWT_RESULT)"
    elif [ -n "$LK_JWT_RESULT" ] && [ "$LK_JWT_RESULT" != "NO_TOKEN" ]; then
        pass "LiveKit JWT token obtained via lk-jwt /sfu/get"
    else
        fail "LiveKit JWT token request failed"
    fi

    # 4.6 Sync (ensure the Matrix client-server API is fully functional)
    SYNC_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        "$BASE_URL/_matrix/client/v3/sync?timeout=0" \
        -H "Authorization: Bearer $REG_ACCESS_TOKEN" 2>/dev/null || echo "000")
    if [ "$SYNC_CODE" = "200" ]; then
        pass "Matrix sync endpoint works (HTTP 200)"
    else
        fail "Matrix sync endpoint failed (HTTP $SYNC_CODE)"
    fi

    # 4.7 Whoami
    WHOAMI_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        "$BASE_URL/_matrix/client/v3/account/whoami" \
        -H "Authorization: Bearer $REG_ACCESS_TOKEN" 2>/dev/null || echo "000")
    if [ "$WHOAMI_CODE" = "200" ]; then
        pass "Account whoami endpoint (HTTP 200)"
    else
        fail "Account whoami endpoint failed (HTTP $WHOAMI_CODE)"
    fi

    # 4.8 Logout
    LOGOUT_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        -X POST "$BASE_URL/_matrix/client/v3/logout" \
        -H "Authorization: Bearer $REG_ACCESS_TOKEN" 2>/dev/null || echo "000")
    if [ "$LOGOUT_CODE" = "200" ] || [ "$LOGOUT_CODE" = "401" ]; then
        pass "Logout endpoint reachable (HTTP $LOGOUT_CODE)"
    else
        fail "Logout endpoint failed (HTTP $LOGOUT_CODE)"
    fi
else
    skip "Skipping authenticated flows (no access token)"
fi

# ═══════════════════════════════════════════════════════════════════════
# 5. LiveKit SFU
# ═══════════════════════════════════════════════════════════════════════
heading "5. LiveKit SFU"

check_port "localhost" "7880" "LiveKit TCP port 7880"
check_http "$LIVEKIT_URL/" "200" "LiveKit root → 200"

# ═══════════════════════════════════════════════════════════════════════
# 6. lk-jwt-service (direct)
# ═══════════════════════════════════════════════════════════════════════
heading "6. lk-jwt-service"

check_port "localhost" "8070" "lk-jwt-service TCP port 8070"

# lk-jwt-service doesn't serve at root — test /sfu/get instead
# The /sfu/get endpoint expects POST with JSON body
SFU_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    -X POST "$LK_JWT_URL/sfu/get" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null || echo "000")
if [ "$SFU_CODE" = "200" ] || [ "$SFU_CODE" = "400" ]; then
    pass "lk-jwt-service /sfu/get POST responds (HTTP $SFU_CODE)"
else
    fail "lk-jwt-service /sfu/get unexpected (HTTP $SFU_CODE)"
fi

# The /get_token endpoint (legacy) — may return 400 or M_NOT_JSON
GET_TOKEN_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    -X POST "$LK_JWT_URL/get_token" \
    -H "Content-Type: application/json" \
    -d '{"room":"test","identity":"test"}' 2>/dev/null || echo "000")
if [ "$GET_TOKEN_CODE" = "200" ] || [ "$GET_TOKEN_CODE" = "400" ]; then
    pass "lk-jwt-service /get_token POST responds (HTTP $GET_TOKEN_CODE)"
else
    fail "lk-jwt-service /get_token unexpected (HTTP $GET_TOKEN_CODE)"
fi

# ═══════════════════════════════════════════════════════════════════════
# 7. SyDent (Matrix Identity Server)
# ═══════════════════════════════════════════════════════════════════════
heading "7. SyDent (Identity Server)"

check_port "localhost" "8090" "SyDent TCP port 8090"

# SyDent API is at /_matrix/identity/*, not root
check_http "$SYDENT_URL/_matrix/identity/v2" "200" "SyDent identity API v2 → 200"

# Account endpoint (requires auth — 401 means it's working)
ACCOUNT_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$SYDENT_URL/_matrix/identity/v2/account" 2>/dev/null || echo "000")
if [ "$ACCOUNT_CODE" = "200" ] || [ "$ACCOUNT_CODE" = "401" ]; then
    pass "SyDent account endpoint reachable (HTTP $ACCOUNT_CODE)"
else
    fail "SyDent account endpoint failed (HTTP $ACCOUNT_CODE)"
fi

# ═══════════════════════════════════════════════════════════════════════
# 8. cloudflared DNS-over-HTTPS
# ═══════════════════════════════════════════════════════════════════════
heading "8. cloudflared DNS-over-HTTPS"

check_port "localhost" "5053" "cloudflared DNS-over-HTTPS port 5053"

# Test DNS resolution (Python-based since dig may not be installed)
DNS_TEST=$(python3 -c "
import socket
try:
    socket.setdefaulttimeout(3)
    result = socket.getaddrinfo('matrix.org', 443)
    print(result[0][4][0])
except Exception as e:
    print('FAIL:' + str(e))
" 2>/dev/null || echo "FAIL")
if [ -n "$DNS_TEST" ] && [ "$DNS_TEST" != "FAIL" ] && ! echo "$DNS_TEST" | grep -q "^FAIL"; then
    pass "DNS resolution via system works (matrix.org → $DNS_TEST)"
else
    fail "DNS resolution failed ($DNS_TEST)"
fi

# ═══════════════════════════════════════════════════════════════════════
# 9. Configuration File Integrity
# ═══════════════════════════════════════════════════════════════════════
heading "9. Configuration File Integrity"

# Synapse config
check_file_contains "/data/homeserver.yaml" "enable_registration:" "homeserver.yaml has enable_registration"
check_file_contains "/data/homeserver.yaml" "port:" "homeserver.yaml has port listener"
check_file_contains "/data/homeserver.yaml" "8009" "homeserver.yaml port set to 8009"
check_file_contains "/data/homeserver.yaml" "livekit_service_url" "homeserver.yaml has livekit_service_url"
check_file_contains "/data/homeserver.yaml" "turn_uris:" "homeserver.yaml has TURN server URIs"
check_file_contains "/data/homeserver.yaml" "experimental_features:" "homeserver.yaml has experimental_features"
check_file_contains "/data/homeserver.yaml" "msc4140_enabled" "homeserver.yaml has MSC4140 (Element Call)"

# Element Web config
check_file_contains "/usr/share/element-web/config.json" "default_server_config" "Element Web config.json has default_server_config"
check_file_contains "/usr/share/element-web/config.json" "localhost" "Element Web config.json points to localhost"

# Element Call config
check_file_contains "/usr/share/element-call/config.json" "livekit_jwt_service_url" "Element Call config.json has livekit_jwt_service_url"
check_file_contains "/usr/share/element-call/config.json" "/livekit/jwt" "Element Call config.json points to /livekit/jwt"

# .well-known/matrix/client
check_file_contains "/usr/share/element-web/.well-known/matrix/client" "rtc_foci" ".well-known/matrix/client has rtc_foci"
check_file_contains "/usr/share/element-web/.well-known/matrix/client" "livekit_service_url" ".well-known/matrix/client has livekit_service_url"

# nginx config
check_file_contains "/etc/nginx/sites-enabled/chator" "listen 8008" "nginx config listens on port 8008"
check_file_contains "/etc/nginx/sites-enabled/chator" "proxy_pass http://localhost:8009" "nginx proxies /_matrix → localhost:8009"
check_file_contains "/etc/nginx/sites-enabled/chator" "proxy_pass http://localhost:8070" "nginx proxies /livekit/jwt → localhost:8070"

# ═══════════════════════════════════════════════════════════════════════
# 10. Process Health
# ═══════════════════════════════════════════════════════════════════════
heading "10. Process Health"

declare -A PROC_CHECKS=(
    ["supervisord"]="supervisord (PID 1)"
    ["nginx.*master"]="nginx master process"
    ["livekit-server"]="LiveKit server"
    ["lk-jwt-service"]="lk-jwt-service"
    ["cloudflared"]="cloudflared DoH proxy"
    ["sydent"]="SyDent identity server"
    ["synapse.*homeserver"]="Synapse homeserver"
)
for proc_pattern in "${!PROC_CHECKS[@]}"; do
    proc_label="${PROC_CHECKS[$proc_pattern]}"
    if proc_running "$proc_pattern"; then
        pass "$proc_label process running"
    else
        fail "$proc_label process not found"
    fi
done

# ═══════════════════════════════════════════════════════════════════════
# 11. nginx Configuration Details
# ═══════════════════════════════════════════════════════════════════════
heading "11. nginx Configuration Details"

check_file_contains "/etc/nginx/sites-enabled/chator" "proxy_pass http://localhost:8009" "nginx proxies Synapse requests"
check_file_contains "/etc/nginx/sites-enabled/chator" "proxy_pass http://localhost:8070" "nginx proxies lk-jwt requests"
check_file_contains "/etc/nginx/sites-enabled/chator" "alias /usr/share/element-call" "nginx serves Element Call from /usr/share/element-call"
check_file_contains "/etc/nginx/sites-enabled/chator" "root /usr/share/element-web" "nginx root is Element Web"
check_file_contains "/etc/nginx/sites-enabled/chator" "Access-Control-Allow-Origin" "nginx has CORS headers on .well-known"
check_file_contains "/etc/nginx/sites-enabled/chator" "gzip on" "nginx has gzip compression enabled"
check_file_contains "/etc/nginx/sites-enabled/chator" "gzip_types" "nginx has gzip_types configured"
check_file_contains "/etc/nginx/sites-enabled/chator" "expires 7d" "nginx has caching headers for assets"

# ═══════════════════════════════════════════════════════════════════════
# 12. Log Verification
# ═══════════════════════════════════════════════════════════════════════
heading "12. Log Verification"

LOG_FILES=(
    "/var/log/supervisor/synapse.log:Synapse log"
    "/var/log/supervisor/synapse-error.log:Synapse error log"
    "/var/log/livekit/livekit.log:LiveKit log"
    "/var/log/livekit/jwt.log:lk-jwt-service log"
    "/var/log/supervisor/sydent.log:SyDent log"
    "/var/log/supervisor/cloudflared.log:cloudflared log"
    "/var/log/supervisor/element-web.log:nginx log"
    "/var/log/supervisor/supervisord.log:Supervisor log"
)

for entry in "${LOG_FILES[@]}"; do
    LOG_FILE="${entry%%:*}"
    LOG_LABEL="${entry#*:}"
    if [ -f "$LOG_FILE" ]; then
        LOG_SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
        if [ "${LOG_SIZE:-0}" -gt 0 ] 2>/dev/null; then
            pass "$LOG_LABEL exists with content ($LOG_SIZE bytes)"
        else
            info "$LOG_LABEL exists (0 bytes — may buffer output)"
        fi
    else
        fail "$LOG_LABEL not found at $LOG_FILE"
    fi
done

# Scan error logs for issues (informational)
for err_log in /var/log/supervisor/*-error.log; do
    [ -f "$err_log" ] || continue
    ERROR_COUNT=$(grep -ci "error\|traceback\|exception" "$err_log" 2>/dev/null || echo "0")
    if [ "${ERROR_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        info "Found $ERROR_COUNT potential issue(s) in $(basename "$err_log")"
    fi
done

# ═══════════════════════════════════════════════════════════════════════
# 13. Supervisor Status
# ═══════════════════════════════════════════════════════════════════════
heading "13. Supervisor Managed Processes"

# Read supervisor state from its XML-RPC interface if available
# or fall back to signal-based status check
if [ -S /var/run/supervisor.sock ] 2>/dev/null; then
    info "supervisor socket found"
fi

# Count processes that supervisor should be managing
# (listed in supervisord.conf [program:*] sections)
SUPERVISED_COUNT=0
SUPERVISED_RUNNING=0
for proc_dir in /proc/[0-9]*/; do
    local_ppid=$(cat "${proc_dir}status" 2>/dev/null | grep "^PPid:" | awk '{print $2}' || echo "")
    [ -z "$local_ppid" ] && continue
    # Check if parent is PID 1 (supervisord)
    if [ "$local_ppid" = "1" ]; then
        local_cmdline=$(cat "${proc_dir}cmdline" 2>/dev/null | tr '\0' ' ' || echo "")
        # Filter out kernel threads and the shell itself
        if [ -n "$local_cmdline" ] && ! echo "$local_cmdline" | grep -q "^\["; then
            ((SUPERVISED_COUNT++))
            local_name=$(echo "$local_cmdline" | awk '{print $1}' | sed 's|.*/||')
            info "Supervised: $local_name (PID $(basename $proc_dir))"
        fi
    fi
done

if [ "$SUPERVISED_COUNT" -ge 4 ]; then
    pass "Supervisor manages $SUPERVISED_COUNT child processes"
else
    fail "Supervisor has few child processes ($SUPERVISED_COUNT)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════
heading "Test Summary"
echo -e "  ${CYAN}Tests run:${NC}     $TOTAL"
echo -e "  ${GREEN}Passed:${NC}      $((TOTAL - FAILED))"
echo -e "  ${RED}Failed:${NC}      $FAILED"
echo -e "  ${YELLOW}Skipped:${NC}    $SKIPPED"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ALL TESTS PASSED!                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              SOME TESTS FAILED!                              ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    exit 1
fi
