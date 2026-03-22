#!/bin/sh
# Dex entrypoint - substitute environment variables in config

set -e

echo "Starting Dex OIDC..."

# Substitute environment variables in config template
envsubst '${DEX_ISSUER} ${DEX_CLIENT_SECRET} ${SYNAPSE_URL} ${DEX_STATIC_PASSWORD_HASH} ${DEX_STATIC_PASSWORD_EMAIL} ${DEX_STATIC_PASSWORD_USERNAME}' \
  < /etc/dex/config.yaml.template \
  > /etc/dex/config.yaml

echo "Config generated:"
cat /etc/dex/config.yaml

echo ""
echo "Starting Dex..."
exec "$@"
