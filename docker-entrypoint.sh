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

# ============ MAS Configuration (Matrix Authentication Service) ============
# MAS is configured in homeserver.yaml - no separate config needed
echo "MAS configured via homeserver.yaml"

# ============ Setup Supervisor ============
echo "Setting up supervisor..."
mkdir -p /etc/supervisor/conf.d
cp /supervisord.conf /etc/supervisor/supervisord.conf

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
            /opt/zapret/init.d/sysv/zapret start
            sleep 3

            # Test connectivity to blocked sites
            SCORE=0
            for test_url in "https://matrix.org" "https://element.io" "https://google.com"; do
                if curl -s --max-time 5 -o /dev/null "$test_url" 2>/dev/null; then
                    ((SCORE++))
                fi
            done

            echo "  Strategy $strategy score: $SCORE/3"

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

    /opt/zapret/init.d/sysv/zapret start

    # Wait and check if running
    sleep 3
    if pgrep -x "nfqws" > /dev/null || pgrep -x "tpws" > /dev/null; then
        echo "Zapret is running with strategy: $BEST_STRATEGY"
    else
        echo "Warning: Zapret may not have started properly, trying fallback..."
        # Fallback to SIMPLE_FAKE if main strategy fails
        cp /opt/zapret/config/strategy_simple_fake.conf /opt/zapret/config/strategy.conf
        /opt/zapret/init.d/sysv/zapret restart
    fi
else
    echo "Zapret disabled (set ZAPRET_ENABLED=true to enable)"
fi

# ============ Start Supervisor ============
echo "Starting supervisor..."
exec /usr/local/bin/supervisord -c /etc/supervisor/supervisord.conf