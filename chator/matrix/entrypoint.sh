#!/bin/bash
set -e

# Configuration directory
CONFIG_DIR="/data"
TEMPLATE="$CONFIG_DIR/homeserver.yaml.template"
OUTPUT="$CONFIG_DIR/homeserver.yaml"

# Generate macaroon secret key if missing
MACAROON_KEY_FILE="$CONFIG_DIR/chator.macaroon.secret"
if [ ! -f "$MACAROON_KEY_FILE" ]; then
    echo "Generating macaroon secret key..."
    openssl rand -hex 32 > "$MACAROON_KEY_FILE"
fi
MACAROON_SECRET=$(cat "$MACAROON_KEY_FILE")
export MACAROON_SECRET

# Delete old signing key to force regeneration (fixes format errors)
SIGNING_KEY_FILE="$CONFIG_DIR/chator.signing.key"
if [ -f "$SIGNING_KEY_FILE" ]; then
    echo "🗑️  Deleting old signing key (will regenerate)..."
    rm "$SIGNING_KEY_FILE"
fi

# Generate signing key if missing (Synapse format: ed25519 <key_id> <base64>)
if [ ! -f "$SIGNING_KEY_FILE" ]; then
    echo "Generating signing key..."
    # Use Python to generate proper 32-byte ed25519 key (guaranteed correct format)
    python3 -c "
import secrets
import base64
key_bytes = secrets.token_bytes(32)
key_b64 = base64.b64encode(key_bytes).decode('ascii')
key_id = base64.b64encode(secrets.token_bytes(3)).decode('ascii')[:4]
print(f'ed25519 {key_id} {key_b64}')
" > "$SIGNING_KEY_FILE"
fi
# Read the signing key and export for template
SIGNING_KEY=$(cat "$SIGNING_KEY_FILE")
export SIGNING_KEY

# Check if homeserver.yaml already exists
if [ ! -f "$OUTPUT" ]; then
    echo "Generating homeserver.yaml from template..."
    
    # Substitute ALL environment variables (no list = substitutes everything it finds)
    envsubst < "$TEMPLATE" > "$OUTPUT"
    
    echo "Configuration generated successfully"
else
    echo "Using existing homeserver.yaml"
fi

# Generate log config if missing
if [ ! -f "$CONFIG_DIR/chator.log.config" ]; then
    cat > "$CONFIG_DIR/chator.log.config" << 'EOF'
version: 1
formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'
handlers:
  console:
    class: logging.StreamHandler
    formatter: precise
loggers:
  synapse.storage.SQL:
    level: WARNING
root:
  level: INFO
  handlers: [console]
disable_existing_loggers: false
EOF
    echo "Log config generated"
fi

# Run Synapse with config file
exec python -m synapse.app.homeserver -c "$OUTPUT"
