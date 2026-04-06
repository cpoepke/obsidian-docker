# =============================================================================
# Obsidian Docker Image with X11 (Xvfb) on Ubuntu
# Provides REST API access for agent/MCP integration
# =============================================================================
ARG OBSIDIAN_VERSION=1.12.7
ARG TARGETARCH

# ---------------------------------------------------------------------------
# Stage 1: Extract Obsidian AppImage
# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS extractor

ARG OBSIDIAN_VERSION
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates squashfs-tools libfuse2 \
    && rm -rf /var/lib/apt/lists/*

# Download and extract Obsidian AppImage.
# On amd64: execute the AppImage directly (native binary).
# On arm64: use unsquashfs since the arm64 AppImage can't run on amd64 builders.
RUN ARCH_SUFFIX="" && \
    if [ "$TARGETARCH" = "arm64" ]; then ARCH_SUFFIX="-arm64"; fi && \
    curl -fSL -o /tmp/Obsidian.AppImage \
      "https://github.com/obsidianmd/obsidian-releases/releases/download/v${OBSIDIAN_VERSION}/Obsidian-${OBSIDIAN_VERSION}${ARCH_SUFFIX}.AppImage" && \
    chmod +x /tmp/Obsidian.AppImage && \
    cd /tmp && \
    if [ "$TARGETARCH" = "arm64" ]; then \
      offset=$(LC_ALL=C grep -aob 'hsqs' Obsidian.AppImage | head -1 | cut -d: -f1) && \
      unsquashfs -d /opt/obsidian -offset "$offset" Obsidian.AppImage; \
    else \
      ./Obsidian.AppImage --appimage-extract && \
      mv squashfs-root /opt/obsidian; \
    fi

# ---------------------------------------------------------------------------
# Stage 2: Ubuntu runtime (glibc required for Electron/Chromium)
# ---------------------------------------------------------------------------
FROM ubuntu:24.04

LABEL org.opencontainers.image.title="obsidian-docker"
LABEL org.opencontainers.image.description="Headless Obsidian with REST API plugins for agent integration"
LABEL org.opencontainers.image.source="https://github.com/cpoepke/obsidian-docker"

# Install X11, Electron/Chromium deps, and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
        # X11 virtual framebuffer
        xvfb \
        xauth \
        # D-Bus
        dbus \
        dbus-x11 \
        # Mesa / OpenGL
        libgl1-mesa-dri \
        libgl1 \
        libegl1 \
        # GTK and UI dependencies required by Electron
        libgtk-3-0 \
        libx11-6 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxrandr2 \
        libxrender1 \
        libxtst6 \
        libxshmfence1 \
        libxi6 \
        libxkbcommon0 \
        # Chromium / Electron runtime deps
        libnss3 \
        libnspr4 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libatspi2.0-0 \
        libcups2 \
        libdrm2 \
        libpango-1.0-0 \
        libcairo2 \
        libasound2t64 \
        libgbm1 \
        # Networking & utilities
        ca-certificates \
        curl \
        git \
        inotify-tools \
        jq \
        openssl \
        python3 \
        python3-pip \
        # Fonts
        fonts-noto-core \
        fontconfig \
    && rm -rf /var/lib/apt/lists/* \
    && fc-cache -f \
    && pip3 install --no-cache-dir --break-system-packages websockets

# Create non-root user with home directory (Electron needs userData path)
RUN groupadd --system obsidian && useradd --system -g obsidian -m obsidian

# Copy extracted Obsidian from builder stage
COPY --from=extractor /opt/obsidian /opt/obsidian

# Ensure all Obsidian files are readable and binary is executable
RUN chmod -R a+rX /opt/obsidian && \
    chmod +x /opt/obsidian/obsidian && \
    # Electron needs the sandbox disabled in containers or suid helper
    chmod 4755 /opt/obsidian/chrome-sandbox || true

# Create vault and config directories, X11 socket dir, and dbus run dir
RUN mkdir -p /vaults/default /config/obsidian /config/defaults /tmp/.X11-unix /run/dbus && \
    chmod 1777 /tmp/.X11-unix && \
    chown obsidian:obsidian /run/dbus

# Copy plugin installer, entrypoint, and helper scripts
COPY install-plugins.sh /usr/local/bin/install-plugins.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY enable-plugins.py /usr/local/bin/enable-plugins.py
COPY git-sync.sh /usr/local/bin/git-sync.sh
COPY git-pull-server.py /usr/local/bin/git-pull-server.py
RUN chmod +x /usr/local/bin/install-plugins.sh /usr/local/bin/entrypoint.sh /usr/local/bin/git-sync.sh /usr/local/bin/git-pull-server.py

# Copy default plugin configuration
COPY config/community-plugins.json /config/defaults/community-plugins.json

# Install plugins at build time to a non-volume path so they survive PVC mounts
RUN /usr/local/bin/install-plugins.sh /opt/obsidian-plugins && \
    chown -R obsidian:obsidian /vaults /config /opt/obsidian-plugins

# Ports:
#   27124 - Local REST API (HTTPS)
#   27123 - Local REST API (HTTP, optional)
#   27125 - Git pull server (internal, on-demand sync)
EXPOSE 27124 27123 27125

# Volumes for vault data and Obsidian config persistence
VOLUME ["/vaults", "/config/obsidian"]

ENV DISPLAY=:99
ENV OBSIDIAN_VAULT_PATH=/vaults/default
ENV LOCAL_REST_API_PORT=27124
ENV ELECTRON_DISABLE_GPU=1
ENV OBSIDIAN_DISABLE_UPDATE_CHECK=1

HEALTHCHECK --interval=10s --timeout=5s --retries=15 --start-period=60s \
    CMD curl -sf http://127.0.0.1:27123/ || exit 1

USER obsidian
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
