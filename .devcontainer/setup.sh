#!/bin/bash
# Chator Codespace setup script
# Detects Codespace environment and configures .env dynamically

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Create .env if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating .env from .env.example..."
    cp "$SCRIPT_DIR/../.env.example" "$ENV_FILE"
fi

# Detect Codespace
if [ -n "$CODESPACE_NAME" ] && [ -n "$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" ]; then
    PUBLIC_URL="https://${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
    echo "Codespace detected. Public URL: $PUBLIC_URL"

    # Update .env with Codespace-specific values
    if grep -q "^CHATOR_PUBLIC_URL=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^CHATOR_PUBLIC_URL=.*|CHATOR_PUBLIC_URL=$PUBLIC_URL|" "$ENV_FILE"
    else
        echo "CHATOR_PUBLIC_URL=$PUBLIC_URL" >> "$ENV_FILE"
    fi

    # TURN: leave empty — coturn auto-detects
    if grep -q "^TURN_EXTERNAL_IP=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^TURN_EXTERNAL_IP=.*|TURN_EXTERNAL_IP=|" "$ENV_FILE"
    fi

    echo ".env configured for Codespaces."
else
    echo "Not in Codespace. Using .env as-is."
fi

# Build and start the stack
echo "Building Chator..."
docker compose build

echo "Starting services (caddy, chator, coturn)..."
docker compose up -d caddy chator coturn
