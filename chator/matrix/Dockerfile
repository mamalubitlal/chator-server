# Matrix Synapse Dockerfile for Render + Supabase
FROM matrixdotorg/synapse:latest

# Install envsubst for template processing (Debian-based, not Alpine!)
RUN apt-get update && apt-get install -y --no-install-recommends curl gettext && rm -rf /var/lib/apt/lists/*

# Copy configuration files
COPY homeserver.yaml.template /data/homeserver.yaml.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose the default Synapse port
EXPOSE 8008

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8008/_matrix/client/versions || exit 1

# Use custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Run Synapse
CMD ["run"]
