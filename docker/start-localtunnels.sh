#!/bin/bash
set -e

kill_localtunnels() {
    echo "Killing any lingering localtunnel processes..."
    pkill -f "localtunnel" 2>/dev/null || true
    pkill -f "lt" 2>/dev/null || true
    sleep 1
}

start_tunnels() {
    local PORT=$1
    local SUBDOMAINS=("chator-server" "chator-dexter" "chator-cal")

    for SUBDOMAIN in "${SUBDOMAINS[@]}"; do
        echo "Starting localtunnel for port ${PORT} with subdomain ${SUBDOMAIN}..."
        nohup lt --port ${PORT} --subdomain ${SUBDOMAIN} > /var/log/localtunnel-${SUBDOMAIN}.log 2>&1 &
        sleep 2
    done
}

kill_localtunnels
sleep 2

start_tunnels 8008

echo "All localtunnels started!"
tail -f /var/log/localtunnel-*.log