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

# Delete old signing key to force regeneration (fixes "seed must be 32 bytes" error)
SIGNING_KEY_FILE="$CONFIG_DIR/chator.signing.key"
if [ -f "$SIGNING_KEY_FILE" ]; then
    echo "🗑️  Deleting old signing key (will regenerate)..."
    rm "$SIGNING_KEY_FILE"
fi

# Generate signing key if missing (32 bytes, base64 encoded for Synapse)
if [ ! -f "$SIGNING_KEY_FILE" ]; then
    echo "Generating signing key..."
    # Generate 32 random bytes and format as Synapse signing key
    openssl rand -base64 32 | tr -d '\n' > "$SIGNING_KEY_FILE"
fi
# Read the signing key and export for template
SIGNING_KEY=$(cat "$SIGNING_KEY_FILE")
export SIGNING_KEY

# Check if homeserver.yaml already exists
if [ ! -f "$OUTPUT" ]; then
    echo "Generating homeserver.yaml from template..."
    
    # Substitute environment variables
    envsubst '${SYNAPSE_SERVER_NAME} ${SYNAPSE_REPORT_STATS} ${SYNAPSE_CONFIG_DIR} ${SYNAPSE_DATA_DIR} ${SUPABASE_DB_HOST} ${SUPABASE_DB_USER} ${SUPABASE_DB_PASSWORD} ${SUPABASE_DB_NAME} ${MACAROON_SECRET} ${SIGNING_KEY}' < "$TEMPLATE" > "$OUTPUT"
    
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
