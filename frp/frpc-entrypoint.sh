#!/bin/sh
set -e

FRP_SERVER=${FRP_SERVER:-chator-frp.onrender.com}
AUTH_TOKEN=${AUTH_TOKEN:-chator-frp-secret}
WSPROXY_PORT=${WSPROXY_PORT:-7002}

# Generate frpc config (TCP transport → local wsproxy)
cat > /etc/frp/frpc.toml <<EOF
serverAddr = "127.0.0.1"
serverPort = $WSPROXY_PORT
auth.token = "$AUTH_TOKEN"
transport.tls.enable = false
transport.protocol = "tcp"
loginFailExit = false

[[proxies]]
name = "web"
type = "tcp"
localIP = "caddy"
localPort = 80
remotePort = 8080
EOF

# Start wsproxy (TCP→WebSocket bridge with Origin header)
/usr/local/bin/wsproxy \
  -listen ":$WSPROXY_PORT" \
  -target "wss://${FRP_SERVER}/frpws" \
  -origin "https://${FRP_SERVER}" &

sleep 1

exec frpc -c /etc/frp/frpc.toml
