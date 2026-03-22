# Dex OIDC Server for чатор
# Based on: https://dexidp.io/docs/

FROM ghcr.io/dexidp/dex:latest

# Install envsubst for variable substitution
USER root
RUN apk add --no-cache gettext

# Create config directory
RUN mkdir -p /etc/dex

# Copy template configuration
COPY config.yaml /etc/dex/config.yaml.template

# Create data directory for SQLite
RUN mkdir -p /var/dex && chown -R 1001:1001 /var/dex

# Copy and set up entrypoint script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Switch back to non-root user (Dex default)
USER 1001:1001

# Expose Dex port
EXPOSE 5556

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:5556/healthz || exit 1

# Run Dex
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["dex", "serve", "/etc/dex/config.yaml"]
