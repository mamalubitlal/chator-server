#!/bin/sh
set -e

FRP_SERVER=${FRP_SERVER:-chator-frp.onrender.com}
TUNNEL_PATH=${TUNNEL_PATH:-/tunnel}
REVERSE_PORT=${REVERSE_PORT:-8080}

# Wait for caddy to be ready
echo "tunnel: waiting for caddy..."
until wget -q -O /dev/null http://caddy:80/ 2>/dev/null; do
    sleep 1
done
echo "tunnel: caddy is ready"

# Wstunnel client reverse tunnel:
# Connects to Render wstunnel server via WebSocket through Cloudflare
# Server listens on :REVERSE_PORT, forwards traffic through tunnel to local caddy:80
exec wstunnel client \
    --http-upgrade-path-prefix "$TUNNEL_PATH" \
    --tls-verify-certificate \
    -R "tcp://${REVERSE_PORT}:caddy:80" \
    wss://$FRP_SERVER
