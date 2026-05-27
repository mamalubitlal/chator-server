#!/bin/sh
set -e

FRP_SERVER=${FRP_SERVER:-chator-frp.onrender.com}
AUTH_TOKEN=${AUTH_TOKEN:-chator-frp-secret}

# Generate frpc config
cat > /etc/frp/frpc.toml <<EOF
serverAddr = "$FRP_SERVER"
serverPort = 443
auth.token = "$AUTH_TOKEN"
transport.tls.enable = true
transport.protocol = "websocket"
loginFailExit = false

[[proxies]]
name = "web"
type = "tcp"
localIP = "caddy"
localPort = 80
remotePort = 8080
EOF

exec frpc -c /etc/frp/frpc.toml
