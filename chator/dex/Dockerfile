# Dex OIDC Server for чатор
# Based on: https://dexidp.io/docs/

FROM ghcr.io/dexidp/dex:latest

# Create config directory
RUN mkdir -p /etc/dex

# Copy configuration
COPY config.yaml /etc/dex/config.yaml

# Create data directory for SQLite
RUN mkdir -p /var/dex && chown -R 1001:1001 /var/dex

# Expose Dex port
EXPOSE 5556

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:5556/healthz || exit 1

# Run Dex
CMD ["dex", "serve", "/etc/dex/config.yaml"]
