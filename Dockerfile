# syntax=docker/dockerfile:1
# Combined Dockerfile for Chator: Synapse + Dex (OIDC) + Coturn
#
# This image includes:
# - Synapse (Matrix homeserver)
# - Dex (OpenID Connect provider)  
# - Coturn (TURN server for voice/video calls)
#
# Build: DOCKER_BUILDKIT=1 docker build -f C:/chtor-server/chator/matrix/Dockerfile -t chator .
# Run with env vars passed in

ARG DEBIAN_VERSION=trixie
ARG PYTHON_VERSION=3.13
ARG POETRY_VERSION=2.2.1
ARG TARGETARCH

###############################################################################
# Stage 0: Generate requirements.txt (Synapse)
###############################################################################
FROM --platform=$BUILDPLATFORM ghcr.io/astral-sh/uv:python${PYTHON_VERSION}-${DEBIAN_VERSION} AS synapse-requirements

WORKDIR /synapse
COPY pyproject.toml poetry.lock /synapse/

ARG TEST_ONLY_IGNORE_POETRY_LOCKFILE
ENV UV_LINK_MODE=copy
ARG POETRY_VERSION

RUN --mount=type=cache,target=/root/.cache/uv \
    if [ -z "$TEST_ONLY_IGNORE_POETRY_LOCKFILE" ]; then \
        uvx --with poetry-plugin-export==1.9.0 \
            poetry@${POETRY_VERSION} export --extras all -o /synapse/requirements.txt; \
    else \
        touch /synapse/requirements.txt; \
    fi

###############################################################################
# Stage 1: Builder (Synapse)
###############################################################################
FROM ghcr.io/astral-sh/uv:python${PYTHON_VERSION}-${DEBIAN_VERSION} AS synapse-builder

ENV UV_LINK_MODE=copy
ENV RUSTUP_HOME=/rust
ENV CARGO_HOME=/cargo
ENV PATH=/cargo/bin:/rust/bin:$PATH
RUN mkdir /rust /cargo

RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable --profile minimal

ARG CARGO_NET_GIT_FETCH_WITH_CLI=false
ENV CARGO_NET_GIT_FETCH_WITH_CLI=$CARGO_NET_GIT_FETCH_WITH_CLI

COPY --from=synapse-requirements /synapse/requirements.txt /synapse/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --prefix="/install" --no-deps -r /synapse/requirements.txt

COPY synapse /synapse/synapse/
COPY rust /synapse/rust/
COPY pyproject.toml README.rst build_rust.py Cargo.toml Cargo.lock /synapse/

ARG TEST_ONLY_IGNORE_POETRY_LOCKFILE
RUN \
    --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/synapse/target,sharing=locked \
    --mount=type=cache,target=${CARGO_HOME}/registry,sharing=locked \
    if [ -z "$TEST_ONLY_IGNORE_POETRY_LOCKFILE" ]; then \
        uv pip install --prefix="/install" --no-deps /synapse[all]; \
    else \
        uv pip install --prefix="/install" /synapse[all]; \
    fi

###############################################################################
# Stage 2: Runtime dependencies
###############################################################################
FROM --platform=$BUILDPLATFORM docker.io/library/debian:${DEBIAN_VERSION} AS runtime-deps

RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Add both target architectures (separate commands needed)
RUN dpkg --add-architecture arm64
RUN dpkg --add-architecture amd64

RUN \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances --no-pre-depends \
        curl gosu libjpeg62-turbo libpq5 libwebp7 xmlsec1 libjemalloc2 libnice10 \
    | grep '^\w' > /tmp/pkg-list && \
    for arch in arm64 amd64; do \
        mkdir -p /tmp/debs-${arch} && \
        chown _apt:root /tmp/debs-${arch} && \
        cd /tmp/debs-${arch} && \
        apt-get -o APT::Architecture="${arch}" download $(cat /tmp/pkg-list); \
    done

RUN \
    for arch in arm64 amd64; do \
        mkdir -p /install-${arch}/var/lib/dpkg/status.d/ && \
        for deb in /tmp/debs-${arch}/*.deb; do \
            package_name=$(dpkg-deb -I ${deb} | awk '/^ Package: .*$/ {print $2}'); \
            dpkg --ctrl-tarfile $deb | tar -Ox ./control > /install-${arch}/var/lib/dpkg/status.d/${package_name}; \
            dpkg --extract $deb /install-${arch}; \
        done; \
    done

###############################################################################
# Stage 3: Runtime
###############################################################################
FROM docker.io/library/python:${PYTHON_VERSION}-slim-${DEBIAN_VERSION}

ARG TARGETARCH
ARG SYNAPSE_VERSION_STRING
ENV SYNAPSE_VERSION_STRING=${SYNAPSE_VERSION_STRING}

LABEL maintainer="Chator"
LABEL description="Combined Synapse + Dex + Coturn for Chator"

# Copy runtime deps and Synapse
COPY --from=runtime-deps /install-${TARGETARCH}/etc /etc
COPY --from=runtime-deps /install-${TARGETARCH}/usr /usr
COPY --from=synapse-builder --exclude=.lock /install /usr/local

###############################################################################
# Install Zapret DPI Bypass (for Russia)
###############################################################################
# Reinstall passwd after multi-arch copy to fix useradd binary
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables ipset curl git kmod passwd \
    && rm -rf /var/lib/apt/lists/*

# Clone and build zapret
RUN git clone --depth 1 --branch master https://github.com/bol-van/zapret.git /opt/zapret && \
    cd /opt/zapret && \
    # Create user if not exists
    useradd -m -s /bin/false zapret 2>/dev/null || true

# Copy zapret config
COPY ./zapret/lists/list-general-user.txt /opt/zapret/list/list-general-user.txt
COPY ./zapret/config/strategy_fake_tls_auto.conf /opt/zapret/config/strategy_fake_tls_auto.conf
COPY ./zapret/config/strategy_fake_tls_auto_alt.conf /opt/zapret/config/strategy_fake_tls_auto_alt.conf
COPY ./zapret/config/strategy_simple_fake.conf /opt/zapret/config/strategy_simple_fake.conf
COPY ./zapret/config/strategy_alt.conf /opt/zapret/config/strategy_alt.conf
COPY ./zapret/detect_blocked_domains.sh /usr/local/bin/detect-blocked.sh

# Set default strategy
RUN echo "FAKE_TLS_AUTO" > /opt/zapret/config/strategy && \
    cp /opt/zapret/config/strategy_fake_tls_auto.conf /opt/zapret/config/strategy.conf

# Create zapret control script
RUN echo '#!/bin/bash\n\
ZAPRET_STRATEGY=${ZAPRET_STRATEGY:-FAKE_TLS_AUTO}\n\
echo "Starting zapret with strategy: $ZAPRET_STRATEGY"\n\
case "$ZAPRET_STRATEGY" in\n\
  FAKE_TLS_AUTO) cp /opt/zapret/config/strategy_fake_tls_auto.conf /opt/zapret/config/strategy.conf ;;\n\
  FAKE_TLS_AUTO_ALT) cp /opt/zapret/config/strategy_fake_tls_auto_alt.conf /opt/zapret/config/strategy.conf ;;\n\
  SIMPLE_FAKE) cp /opt/zapret/config/strategy_simple_fake.conf /opt/zapret/config/strategy.conf ;;\n\
  ALT) cp /opt/zapret/config/strategy_alt.conf /opt/zapret/config/strategy.conf ;;\n\
  *) cp /opt/zapret/config/strategy_fake_tls_auto.conf /opt/zapret/config/strategy.conf ;;\n\
esac\n\
/opt/zapret/init.d/sysv/zapret "$1"\n' > /usr/local/bin/zapret-ctl && \
    chmod +x /usr/local/bin/zapret-ctl

# Enable IP forwarding for zapret
RUN echo 1 > /proc/sys/net/ipv4/ip_forward || true

###############################################################################
# MAS (Matrix Authentication Service) - configured in homeserver.yaml
# No local installation needed - runs as separate container or embedded
###############################################################################

###############################################################################
# Install LiveKit server
###############################################################################
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    && rm -rf /var/lib/apt/lists/*

ENV LIVEKIT_VERSION=1.12.0
# Using wget.la - fast GitHub mirror
RUN for i in 1 2 3 4 5; do \
    wget --timeout=120 -q "https://wget.la/https://github.com/livekit/livekit/releases/download/v${LIVEKIT_VERSION}/livekit_${LIVEKIT_VERSION}_linux_amd64.tar.gz" -O /tmp/livekit.tar.gz && break || sleep 10; done && \
    tar -xzf /tmp/livekit.tar.gz -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/livekit-server && \
    rm /tmp/livekit.tar.gz

###############################################################################
# Install LiveKit JWT Service (Element Call auth) - precompiled binary
###############################################################################
RUN for i in 1 2 3 4 5; do \
    wget --timeout=120 -q "https://wget.la/https://github.com/element-hq/lk-jwt-service/releases/download/v0.4.4/lk-jwt-service_linux_${TARGETARCH}" -O /usr/local/bin/lk-jwt-service && break || sleep 10; done && \
    chmod +x /usr/local/bin/lk-jwt-service

###############################################################################
# Coturn Note: Install separately or use Docker image
#  docker run -d --name coturn -p 3478:3478 -p 3478:3478/udp \
#    -v /path/to/turnserver.conf:/etc/turnserver.conf coturn/coturn
###############################################################################

###############################################################################
# Install Element Web (self-hosted Matrix client for Russia)
# Users in Russia may not reach element.io — bundle our own
###############################################################################
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    && rm -rf /var/lib/apt/lists/*

ENV ELEMENT_WEB_VERSION=1.11.70
RUN for i in 1 2 3 4 5; do \
    wget --timeout=120 -q "https://wget.la/https://github.com/vector-im/element-web/releases/download/v${ELEMENT_WEB_VERSION}/element-v${ELEMENT_WEB_VERSION}.tar.gz" -O /tmp/element-web.tar.gz && break || sleep 10; done && \
    tar -xzf /tmp/element-web.tar.gz -C /tmp/ && \
    mkdir -p /usr/share/element-web && \
    cp -r /tmp/element-v${ELEMENT_WEB_VERSION}/* /usr/share/element-web/ && \
    rm /tmp/element-web.tar.gz && \
    rm -rf /tmp/element-v${ELEMENT_WEB_VERSION}

# Configure Element Web to use local Synapse (updated at runtime for Render)
RUN echo '{"default_server_config":{"m.homeserver":{"base_url":"http://localhost:8008","server_name":"localhost"}},"default_theme":"light","brand":"Чатор"}' > /usr/share/element-web/config.json

# Chator theming: config, logo, background, and CSS overrides
COPY element-theme/gen-config.py /tmp/gen-config.py
RUN python3 /tmp/gen-config.py && rm /tmp/gen-config.py
COPY element-theme/chator-logo.png /usr/share/element-web/themes/element/img/logos/chator-logo.png
COPY element-theme/chator-bg.png /usr/share/element-web/themes/element/img/backgrounds/chator-bg.png
COPY element-theme/chator-theme.css /usr/share/element-web/chator-theme.css
# Inject custom CSS (with cache-busting) + theme override into index.html
# Use build timestamp to prevent stale CSS caching
# MutationObserver permanently forces light theme (survives Element theme detection)
RUN BUILD_TS=$(date +%s) && sed -i "s|</head>|<link rel=\"stylesheet\" href=\"chator-theme.css?v=${BUILD_TS}\">\n<script>!function(){function r(){if(document.body){document.body.className='cpd-theme-light';new MutationObserver(function(){if(document.body.className!='cpd-theme-light'){document.body.className='cpd-theme-light'}}).observe(document.body,{attributes:true,attributeFilter:['class']})}else requestAnimationFrame(r)}r()}()<\/script>\n</head>|" /usr/share/element-web/index.html

# Configure nginx to serve everything on one port (8008):
#   / → Element Web, /call/ → Element Call
#   /_matrix, /_synapse, /health → proxy to Synapse (internal port 8009)
RUN echo 'server {\
    listen 8008;\
    server_name _;\
    root /usr/share/element-web;\
    index index.html;\
    # Security headers\
    add_header X-Frame-Options "SAMEORIGIN" always;\
    add_header X-Content-Type-Options "nosniff" always;\
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;\
    # GZIP for better perf under throttling\
    gzip on;\
    gzip_vary on;\
    gzip_proxied any;\
    gzip_comp_level 6;\
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;\
    # Synapse API proxy (must be before static file locations)\
    location /_matrix {\
        proxy_pass http://localhost:8009;\
        proxy_set_header X-Forwarded-For $remote_addr;\
        proxy_set_header X-Forwarded-Proto $scheme;\
        proxy_set_header Host $host;\
    }\
    location /_synapse {\
        proxy_pass http://localhost:8009;\
        proxy_set_header X-Forwarded-For $remote_addr;\
        proxy_set_header X-Forwarded-Proto $scheme;\
        proxy_set_header Host $host;\
    }\
    location /health {\
        proxy_pass http://localhost:8009/health;\
    }\
    # Element Call\
    location /call/ {\
        alias /usr/share/element-call/;\
        try_files $uri $uri/ /call/index.html;\
    }\
    # LiveKit JWT service proxy (Element Call uses this for call tokens)\
    location /livekit/jwt/ {\
        proxy_pass http://localhost:8070/;\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto $scheme;\
    }\
    # .well-known for Matrix client configuration (incl. Element Call discovery)\
    location /.well-known/ {\
        root /usr/share/element-web;\
        add_header Access-Control-Allow-Origin "*" always;\
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;\
        add_header Access-Control-Allow-Headers "X-Requested-With, Content-Type, Authorization" always;\
        try_files $uri =404;\
    }\
    # Cache Element Web static assets\
    location /themes/ {\
        expires 7d;\
        add_header Cache-Control "public, immutable";\
    }\
    location /assets/ {\
        expires 7d;\
        add_header Cache-Control "public, immutable";\
    }\
    # Catch-all: Element Web SPA\
    location / {\
        try_files $uri $uri/ /index.html;\
    }\
}' > /etc/nginx/sites-available/chator && \
    ln -sf /etc/nginx/sites-available/chator /etc/nginx/sites-enabled/ && \
    rm -f /etc/nginx/sites-enabled/default && \
    echo "daemon off;" >> /etc/nginx/nginx.conf

###############################################################################
# Install cloudflared for DNS-over-HTTPS (Russia DPI bypass for DNS)
###############################################################################
ENV CLOUDFLARED_VERSION=2025.11.0
RUN for i in 1 2 3 4 5; do \
    wget --timeout=120 "https://wget.la/https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64" -O /usr/local/bin/cloudflared && break || sleep 10; done && \
    chmod +x /usr/local/bin/cloudflared

###############################################################################
# Install Element Call (pre-built release tarball)
###############################################################################
# Using pre-built release instead of building from source (avoids npm/pnpm deps)
RUN set -eux; \
    ELEMENT_CALL_VERSION="0.19.3"; \
    wget --timeout=120 -q "https://github.com/element-hq/element-call/releases/download/v${ELEMENT_CALL_VERSION}/element-call-${ELEMENT_CALL_VERSION}.tar.gz" -O /tmp/element-call.tar.gz && \
    mkdir -p /usr/share/element-call && \
    tar -xzf /tmp/element-call.tar.gz -C /usr/share/element-call --strip-components=1 && \
    rm -rf /tmp/element-call.tar.gz

# Configure Element Call to use local services
RUN echo '{"default_server_config":{"m.homeserver":{"base_url":"http://localhost:8008","server_name":"localhost"}},"livekit_jwt_service_url":"http://localhost:8008/livekit/jwt"}' > /usr/share/element-call/config.json

# Fix absolute asset paths for sub-path hosting (/call/)
# Element Call is served under /call/ to coexist with Element Web at root.
# The Vite build generates absolute paths (/assets/..., /config.json) that
# conflict with Element Web's assets at the same paths. Rewrite them to
# use the /call/ prefix so they resolve correctly via the nginx alias.
RUN find /usr/share/element-call -type f \( -name "*.html" -o -name "*.js" -o -name "*.css" \) \
    -exec sed -i 's|/assets/|/call/assets/|g' {} + \
    -exec sed -i 's|/config.json|/call/config.json|g' {} +

# ============ Install Node.js for localtunnel ============
RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Limit Node.js memory to prevent OOM during builds
ENV NODE_OPTIONS="--max-old-space-size=512"
ENV NPM_CONFIG_CACHE=/tmp/npm-cache

# Install localtunnel globally to avoid npx caching issues
RUN npm install -g localtunnel

# ============ Supervisor for process management ============
RUN pip install --no-cache-dir supervisor asyncpg

# ============ Memory optimization env vars ============
ENV PYTHONOPTIMIZE=2
ENV PYTHONDONTWRITEBYTECODE=1
ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

# ============ Copy config files ============
COPY ./docker/start.py /start.py
COPY ./docker/start-localtunnels.sh /start-localtunnels.sh
COPY ./docker/conf /conf
COPY turnserver.conf /etc/turnserver.conf
COPY supervisord.conf /supervisord.conf
COPY debug_synapse.py /debug_synapse.py
COPY ./docker/livekit.conf /etc/livekit.conf

# ============ Create directories ============
RUN mkdir -p /data /var/lib/element-call /var/log/supervisor /var/log/localtunnel /var/log/livekit

# Make localtunnel script executable
RUN chmod +x /start-localtunnels.sh

# ============ Environment variables with defaults ============
ENV SYNAPSE_SERVER_NAME=${SYNAPSE_SERVER_NAME:-chator-server.onrender.com}
ENV SYNAPSE_REPORT_STATS=${SYNAPSE_REPORT_STATS:-no}
ENV POSTGRES_HOST=${POSTGRES_HOST:-db}
ENV POSTGRES_PORT=${POSTGRES_PORT:-5432}
ENV POSTGRES_USER=${POSTGRES_USER:-synapse}
ENV POSTGRES_DB=${POSTGRES_DB:-synapse}

# Dex configuration defaults
ENV DEX_ISSUER=${DEX_ISSUER:-https://chator-auth.onrender.com}

# Zapret DPI bypass configuration
ENV ZAPRET_ENABLED=${ZAPRET_ENABLED:-false}
ENV ZAPRET_STRATEGY=${ZAPRET_STRATEGY:-FAKE_TLS_AUTO}

# Enable registration by default
ENV SYNAPSE_ENABLE_REGISTRATION=true

# Local Coturn server (runs alongside in docker-compose)
ENV COTURN_ENABLED=${COTURN_ENABLED:-true}

# Public URL for Element Web config (set to https://your-app.onrender.com on Render)
ENV SYNAPSE_PUBLIC_URL=${SYNAPSE_PUBLIC_URL:-http://localhost:8008}

# ============ Copy entrypoint ============
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# ============ Install Sydent (after all COPY, so it persists) ============
RUN git clone --depth 1 --branch v2.6.1 https://github.com/element-hq/sydent.git /tmp/sydent && \
    cd /tmp/sydent && \
    python3 -m pip install --no-cache-dir . && \
    rm -rf /tmp/sydent

# ============ Expose ports ============
# 8008: Main entry point (nginx → Element Web + Element Call + Synapse proxy)
# 7880: LiveKit SFU (WebRTC calls)
# 8070: LiveKit JWT token service
# 8090: Sydent Matrix Identity Server
EXPOSE 8008/tcp 7880/tcp 8070/tcp 8090/tcp

HEALTHCHECK --start-period=30s --interval=15s --timeout=10s \
    CMD curl -fSs http://localhost:8008/health || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]