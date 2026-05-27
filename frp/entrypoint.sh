#!/bin/sh
set -e

PORT=${PORT:-10000}

# Patch PORT into nginx config
sed -i "s/listen PORT;/listen ${PORT};/" /etc/nginx/http.d/default.conf

# Start frps in background
frps -c /etc/frp/frps.toml &

# Start nginx in foreground (keeps container alive)
exec nginx -g 'daemon off;'
