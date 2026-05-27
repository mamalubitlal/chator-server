#!/bin/sh
set -e

FRP_SERVER=${FRP_SERVER:-chator-frp.onrender.com}
AUTH_TOKEN=${AUTH_TOKEN:-chator-frp-secret}

mkdir -p /etc/frp

# Render LB terminates TLS. frpc connects via plain WebSocket to port 80.
# Render forwards WebSocket upgrade to frps, tunnel established.
cat > /etc/frp/frpc.toml <<EOF
serverAddr = "$FRP_SERVER"
serverPort = 80
auth.token = "$AUTH_TOKEN"
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
