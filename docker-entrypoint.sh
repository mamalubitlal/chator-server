#!/bin/bash
set -e

echo "Starting Chator services..."

# ============ Generate Synapse config if not exists ============
if [ ! -f /data/homeserver.yaml ]; then
    echo "Generating Synapse configuration..."
    python /start.py generate
fi

# ============ Add STUN/TURN servers to config ============
if ! grep -q "turn_uris:" /data/homeserver.yaml; then
    echo "
# TURN/STUN servers (free public TURN from various sources)
turn_uris:
  - \"stun:stun.l.google.com:19302\"
  - \"stun:stun1.l.google.com:19302\"
  - \"stun:stun2.l.google.com:19302\"
  - \"stun:stun3.l.google.com:19302\"
  - \"stun:stun4.l.google.com:19302\"
  - \"turn:numb.viagenie.ca:3478\"
  - \"turn:192.158.29.39:3478?transport=udp\"
  - \"turn:192.158.29.39:3478?transport=tcp\"
  - \"turn:turn.bistri.com:80\"
  - \"turn:turn.anyfirewall.com:443?transport=tcp\"
turn_user_lifetime: \"1h\"
turn_allow_guests: True" >> /data/homeserver.yaml
fi

# Add local Coturn TURN server if not already present
if [ -n "$COTURN_ENABLED" ] && [ "$COTURN_ENABLED" = "true" ]; then
    python3 -c "
with open('/data/homeserver.yaml', 'r') as f:
    content = f.read()
# Add local TURN server if not present
if 'turn:localhost:3478' not in content:
    content = content.replace(
        'turn_uris:',
        'turn_uris:\n  - \"turn:localhost:3478\"'
    )
# Add turn_shared_secret matching coturn's static-auth-secret
if 'turn_shared_secret' not in content:
    content += '\nturn_shared_secret: \"chator-test-secret\"\n'
with open('/data/homeserver.yaml', 'w') as f:
    f.write(content)
print('Local TURN server + shared secret configured')
" 2>&1 || true
fi

# ============ Fix database config if Postgres is configured but unreachable ============
# Switch Postgres config to SQLite (no postgres container) and clean invalid options
python3 -c "
with open('/data/homeserver.yaml', 'r') as f:
    lines = f.readlines()

new_lines = []
in_db_section = False
db_replaced = False

for line in lines:
    if line.startswith('database:'):
        in_db_section = True
        db_replaced = False
        new_lines.append('database:\n')
        new_lines.append('  name: sqlite3\n')
        new_lines.append('  args:\n')
        new_lines.append('    database: /data/homeserver.db\n')
    elif in_db_section:
        # Check if we've left the database section (next top-level key)
        if line.strip() and not line[0].isspace():
            in_db_section = False
            new_lines.append(line)
        # Skip all lines inside the database section
    else:
        new_lines.append(line)

with open('/data/homeserver.yaml', 'w') as f:
    f.writelines(new_lines)
print('Database config switched to SQLite')
" 2>&1

# ============ Enable user registration ============
if [ "$SYNAPSE_ENABLE_REGISTRATION" = "true" ]; then
    echo "Enabling user registration..."
    # Set in homeserver.yaml if not already set
    if grep -q "^enable_registration:" /data/homeserver.yaml; then
        sed -i 's/^enable_registration:.*/enable_registration: true/' /data/homeserver.yaml
    else
        echo "enable_registration: true" >> /data/homeserver.yaml
    fi
    # Disable verification requirement so registration works without email/captcha
    if grep -q "^enable_registration_without_verification:" /data/homeserver.yaml; then
        sed -i 's/^enable_registration_without_verification:.*/enable_registration_without_verification: true/' /data/homeserver.yaml
    else
        echo "enable_registration_without_verification: true" >> /data/homeserver.yaml
    fi
fi

# ============ Enable Element Call experimental features ============
if ! grep -q "msc4140_enabled:" /data/homeserver.yaml; then
    echo "
# Experimental features for Element Call (MatrixRTC)
experimental_features:
  msc4140_enabled: true
  msc4140_max_event_delay_duration: 24h
  msc3266_enabled: true
  msc4222_enabled: true" >> /data/homeserver.yaml
fi

# ============ Element Call livekit_service_url ============
echo "Configuring Element Call (LiveKit JWT) in homeserver.yaml..."
if ! grep -q "element_call:" /data/homeserver.yaml; then
    echo "
# Element Call / MatrixRTC LiveKit backend
element_call:
  livekit_service_url: http://localhost:8008/livekit/jwt" >> /data/homeserver.yaml
fi

# ============ MAS Configuration (Matrix Authentication Service) ============
# Disable MAS when local registration is enabled (they conflict)
if [ "$SYNAPSE_ENABLE_REGISTRATION" = "true" ]; then
    echo "Disabling MAS for local registration compatibility..."
    python3 -c "
import re
with open('/data/homeserver.yaml', 'r') as f:
    content = f.read()
# Disable MAS (conflicts with enable_registration)
content = re.sub(r'(matrix_authentication_service:\n\s+enabled:) true', r'\1 false', content)
with open('/data/homeserver.yaml', 'w') as f:
    f.write(content)
" 2>&1 && echo '  -> MAS disabled' || echo '  -> WARNING: Could not disable MAS'
else
    echo 'MAS configured via homeserver.yaml'
fi

# ============ Fix Synapse listener port (move to 8009, nginx handles public port 8008) ============
python3 -c "
with open('/data/homeserver.yaml', 'r') as f:
    content = f.read()
# Change Synapse listener from 8008 to 8009
import re
content = re.sub(r'(\s+port:)\s*8008\b', r'\1 8009', content)
with open('/data/homeserver.yaml', 'w') as f:
    f.write(content)
print('Synapse port changed to 8009')
" 2>&1

# ============ Update Element Web config.json for public URL ============
if [ -n "$SYNAPSE_PUBLIC_URL" ]; then
    echo "Setting Element Web public URL to: $SYNAPSE_PUBLIC_URL"
    python3 -c "
import json
with open('/usr/share/element-web/config.json', 'r') as f:
    config = json.load(f)
config['default_server_config']['m.homeserver']['base_url'] = '$SYNAPSE_PUBLIC_URL'
if '$SYNAPSE_SERVER_NAME':
    config['default_server_config']['m.homeserver']['server_name'] = '$SYNAPSE_SERVER_NAME'
with open('/usr/share/element-web/config.json', 'w') as f:
    json.dump(config, f)
print('config.json updated')
" 2>&1 || echo '  -> WARNING: Could not update config.json'
fi

# ============ Create .well-known/matrix/client for Element Call discovery ============
mkdir -p /usr/share/element-web/.well-known/matrix
WELL_KNOWN_CLIENT="/usr/share/element-web/.well-known/matrix/client"
# Also update the data dir copy for persistence
mkdir -p /data/.well-known/matrix

PUBLIC_URL="${SYNAPSE_PUBLIC_URL:-http://localhost:8008}"
JWT_SERVICE_URL="${PUBLIC_URL}/livekit/jwt"

cat > "$WELL_KNOWN_CLIENT" << EOF
{
    "m.homeserver": {
        "base_url": "${PUBLIC_URL}"
    },
    "m.identity_server": {
        "base_url": "${PUBLIC_URL}"
    },
    "org.matrix.msc4143.rtc_foci": [
        {
            "type": "livekit",
            "livekit_service_url": "${JWT_SERVICE_URL}"
        }
    ]
}
EOF
cp "$WELL_KNOWN_CLIENT" /data/.well-known/matrix/client
echo ".well-known/matrix/client created with rtc_foci for Element Call"

# ============ Setup Supervisor ============
echo "Setting up supervisor..."
mkdir -p /etc/supervisor/conf.d
cp /supervisord.conf /etc/supervisor/supervisord.conf

# ============ Start DNS-over-HTTPS proxy for Russia ============
# Bypasses DNS DPI blocking — critical for Russian ISPs
echo "Starting DNS-over-HTTPS proxy (cloudflared on port 5053)..."
mkdir -p /var/log/supervisor

# Configure system DNS to use DoH proxy
if [ ! -f /etc/systemd/resolved.conf.d/goodbyedpi.conf ]; then
    mkdir -p /etc/systemd/resolved.conf.d
    echo "[Resolve]" > /tmp/goodbyedpi.conf
    echo "DNS=127.0.0.1:5053" >> /tmp/goodbyedpi.conf
    echo "DNSOverTLS=yes" >> /tmp/goodbyedpi.conf
    # Note: Don't override /etc/resolv.conf directly in container
fi

# ============ Pre-flight check: Test blocked domains ============
if [ "$ZAPRET_ENABLED" = "true" ]; then
    echo "Checking connectivity to blocked Matrix domains..."
    FAILED_DOMAINS=""
    for domain in "matrix.org" "matrix-client.matrix.org" "element.io" "github.com"; do
        if ! curl -s --max-time 5 --connect-timeout 3 -o /dev/null "https://$domain" 2>/dev/null; then
            echo "  WARNING: Cannot reach $domain — may be blocked by DPI"
            FAILED_DOMAINS="$FAILED_DOMAINS $domain"
        else
            echo "  OK: $domain"
        fi
    done
    if [ -n "$FAILED_DOMAINS" ]; then
        echo "Failed domains:$FAILED_DOMAINS"
        echo "Ensure ZAPRET_ENABLED=true or use VPN to download clients"
    fi
fi

# ============ Start Zapret DPI Bypass if enabled ============
if [ "$ZAPRET_ENABLED" = "true" ]; then
    echo "Starting Zapret DPI bypass..."

    # Force re-detect if ZAPRET_REDETECT=true
    if [ "$ZAPRET_REDETECT" = "true" ]; then
        echo "Forcing re-detect of best strategy..."
        rm -f /data/zapret_best_strategy
    fi

    # Auto-detect best strategy on first run (or if re-detect requested)
    if [ ! -f /data/zapret_best_strategy ]; then
        echo "Running auto-detect for best strategy..."

        # Test each strategy and find the best one
        STRATEGIES="FAKE_TLS_AUTO FAKE_TLS_AUTO_ALT SIMPLE_FAKE ALT"
        BEST_STRATEGY=""
        BEST_SCORE=0

        for strategy in $STRATEGIES; do
            echo "Testing strategy: $strategy"

            # Apply strategy
            case "$strategy" in
                FAKE_TLS_AUTO) cp /opt/zapret/config/strategy_fake_tls_auto.conf /opt/zapret/config/strategy.conf ;;
                FAKE_TLS_AUTO_ALT) cp /opt/zapret/config/strategy_fake_tls_auto_alt.conf /opt/zapret/config/strategy.conf ;;
                SIMPLE_FAKE) cp /opt/zapret/config/strategy_simple_fake.conf /opt/zapret/config/strategy.conf ;;
                ALT) cp /opt/zapret/config/strategy_alt.conf /opt/zapret/config/strategy.conf ;;
            esac

            # Start zapret
            /opt/zapret/init.d/sysv/zapret stop 2>/dev/null || true
            sleep 1
            /opt/zapret/init.d/sysv/zapret start || true
            sleep 3

            # Test connectivity to blocked sites
            SCORE=0
            for test_url in \
                "https://matrix.org/_matrix/federation/v1/version" \
                "https://matrix-client.matrix.org/_matrix/client/versions" \
                "https://element.io" \
                "https://github.com"; do
                if curl -s --max-time 5 -o /dev/null "$test_url" 2>/dev/null; then
                    ((SCORE++))
                fi
            done

            echo "  Strategy $strategy score: $SCORE/4"

            if [ $SCORE -gt $BEST_SCORE ]; then
                BEST_SCORE=$SCORE
                BEST_STRATEGY=$strategy
            fi

            # Stop zapret before testing next
            /opt/zapret/init.d/sysv/zapret stop 2>/dev/null || true
            sleep 1
        done

        if [ -n "$BEST_STRATEGY" ]; then
            echo "Best strategy found: $BEST_STRATEGY (score: $BEST_SCORE/3)"
            echo "$BEST_STRATEGY" > /data/zapret_best_strategy
        else
            echo "Using default strategy: FAKE_TLS_AUTO"
            echo "FAKE_TLS_AUTO" > /data/zapret_best_strategy
            BEST_STRATEGY="FAKE_TLS_AUTO"
        fi
    else
        BEST_STRATEGY=$(cat /data/zapret_best_strategy)
        echo "Using saved best strategy: $BEST_STRATEGY"
    fi

    # Apply best strategy and start
    case "$BEST_STRATEGY" in
        FAKE_TLS_AUTO) cp /opt/zapret/config/strategy_fake_tls_auto.conf /opt/zapret/config/strategy.conf ;;
        FAKE_TLS_AUTO_ALT) cp /opt/zapret/config/strategy_fake_tls_auto_alt.conf /opt/zapret/config/strategy.conf ;;
        SIMPLE_FAKE) cp /opt/zapret/config/strategy_simple_fake.conf /opt/zapret/config/strategy.conf ;;
        ALT) cp /opt/zapret/config/strategy_alt.conf /opt/zapret/config/strategy.conf ;;
    esac

    /opt/zapret/init.d/sysv/zapret start || true

    # Wait and check if running
    sleep 3
    if pgrep -x "nfqws" > /dev/null || pgrep -x "tpws" > /dev/null; then
        echo "Zapret is running with strategy: $BEST_STRATEGY"
    else
        echo "Warning: Zapret may not have started properly, trying fallback..."
        # Fallback to SIMPLE_FAKE if main strategy fails
        cp /opt/zapret/config/strategy_simple_fake.conf /opt/zapret/config/strategy.conf
        /opt/zapret/init.d/sysv/zapret restart || true
    fi
else
    echo "Zapret disabled (set ZAPRET_ENABLED=true to enable)"
fi

# ============ Start Supervisor ============
echo "Starting supervisor..."
exec /usr/local/bin/supervisord -c /etc/supervisor/supervisord.conf