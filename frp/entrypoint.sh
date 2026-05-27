#!/bin/sh
set -e

PORT=${PORT:-10000}
AUTH_TOKEN=${AUTH_TOKEN:-chator-frp-secret}
FRPS_CONTROL_PORT=${FRPS_CONTROL_PORT:-7001}
FRPS_VHOST_PORT=${FRPS_VHOST_PORT:-8080}

mkdir -p /etc/frp
cat > /etc/frp/frps.toml <<EOF
bindPort = $FRPS_CONTROL_PORT
vhostHTTPPort = $FRPS_VHOST_PORT
auth.token = "$AUTH_TOKEN"
log.to = "console"
log.level = "info"
detailedErrorsToClient = true
EOF

# Start frps in background
frps -c /etc/frp/frps.toml &

# Start demux on $PORT in foreground (keeps container alive)
exec demux
