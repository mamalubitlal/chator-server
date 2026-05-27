#!/bin/sh
set -e

PORT=${PORT:-10000}
TUNNEL_SERVER_PORT=${TUNNEL_SERVER_PORT:-9999}
REVERSE_PORT=${REVERSE_PORT:-8080}

# Start wstunnel server in background
# Accepts client tunnel connections via WebSocket upgrade on /tunnel path
wstunnel server \
    --restrict-http-upgrade-path-prefix /tunnel \
    --log-lvl info \
    ws://0.0.0.0:${TUNNEL_SERVER_PORT} &

echo "entrypoint: wstunnel started on :${TUNNEL_SERVER_PORT}, reverse tunnel on :${REVERSE_PORT}"

# Start demux on $PORT in foreground (keeps container alive)
# Routes: /tunnel -> wstunnel, / -> health check 200, rest -> reverse tunnel :8080
exec demux
