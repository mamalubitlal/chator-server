#!/bin/sh
set -e

PORT=${PORT:-10000}
AUTH_TOKEN=${AUTH_TOKEN:-chator-frp-secret}

cat > /etc/frp/frps.toml <<EOF
bindPort = $PORT
vhostHTTPPort = $PORT
auth.token = "$AUTH_TOKEN"
log.to = "console"
log.level = "info"
detailedErrorsToClient = true
EOF

exec frps -c /etc/frp/frps.toml
