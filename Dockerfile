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
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables ipset curl git kmod \
    && rm -rf /var/lib/apt/lists/*

# Clone and build zapret
RUN git clone --depth 1 --branch master https://github.com/bol-van/zapret.git /opt/zapret && \
    cd /opt/zapret && \
    # Create user if not exists
    useradd -m -s /bin/false zapret 2>/dev/null || true

# Copy custom domain list
COPY ./zapret/lists/list-general-user.txt /opt/zapret/list/list-general-user.txt

# Copy strategy configs
COPY ./zapret/config/strategy_fake_tls_auto.conf /opt/zapret/config/strategy_fake_tls_auto.conf
COPY ./zapret/config/strategy_fake_tls_auto_alt.conf /opt/zapret/config/strategy_fake_tls_auto_alt.conf
COPY ./zapret/config/strategy_simple_fake.conf /opt/zapret/config/strategy_simple_fake.conf
COPY ./zapret/config/strategy_alt.conf /opt/zapret/config/strategy_alt.conf

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

ENV LIVEKIT_VERSION=1.11.0
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
#  docker run -d --name coturn -p 3478:3478/tcp -p 3478:3478/udp \
#    -v /path/to/turnserver.conf:/etc/turnserver.conf coturn/coturn
###############################################################################

###############################################################################
# Install Element Call (Node.js for Matrix calls)
###############################################################################
RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Build Element Call from source
RUN git clone --depth 1 --branch v1.0.0-alpha.12 https://github.com/element-hq/element-call.git /tmp/element-call && \
    cd /tmp/element-call && \
    npm ci && \
    npm run build && \
    mkdir -p /usr/share/element-call && \
    cp -r dist/* /usr/share/element-call/ && \
    cp -r public/* /usr/share/element-call/ 2>/dev/null || true

# ============ Install Node.js for localtunnel ============
# Node.js already installed above, reusing

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

# ============ Copy entrypoint ============
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# ============ Install Sydent (after all COPY, so it persists) ============
RUN git clone --depth 1 --branch v2.6.1 https://github.com/element-hq/sydent.git /tmp/sydent && \
    cd /tmp/sydent && \
    python3 -m pip install --no-cache-dir . && \
    rm -rf /tmp/sydent

# ============ Expose ports ============
# 8008: Synapse Client API  
# 8448: Synapse Federation API
# 3478: Coturn TURN
# 3479: Coturn TURN over TLS
# 5556: Coturn TURN alt
# 5557: Coturn TURN alt TLS
# 8081: Element Call
# 8082: Element Call (HTTPS)
EXPOSE 8008/tcp 8448/tcp 3478/tcp 3479/tcp 5556/tcp 5557/tcp 8081/tcp 8090/tcp

HEALTHCHECK --start-period=30s --interval=15s --timeout=5s \
    CMD curl -fSs http://localhost:8008/health || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]