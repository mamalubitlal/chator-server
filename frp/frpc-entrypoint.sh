#!/bin/sh
set -e

FRP_SERVER=${FRP_SERVER:-chator-frp.onrender.com}
AUTH_TOKEN=${AUTH_TOKEN:-chator-frp-secret}

mkdir -p /etc/frp

# Render LB redirects port 80→443. frpc connects via TLS WebSocket to 443.
# Render terminates TLS, forwards WebSocket upgrade to frps.
cat > /etc/frp/frpc.toml <<EOF
serverAddr = "$FRP_SERVER"
serverPort = 443
auth.token = "$AUTH_TOKEN"
transport.tls.enable = true
transport.protocol = "websocket"
loginFailExit = false

[[proxies]]
name = "web"
type = "http"
localIP = "caddy"
localPort = 80
customDomains = ["$FRP_SERVER"]
EOF

exec frpc -c /etc/frp/frpc.toml
