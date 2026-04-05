#!/usr/bin/env bash
set -euo pipefail

VAULT_PATH="${OBSIDIAN_VAULT_PATH:-/vaults/default}"
CONFIG_DIR="/config/obsidian"
VAULT_CONFIG_DIR="${VAULT_PATH}/.obsidian"
DISPLAY="${DISPLAY:-:99}"
REST_API_PORT="${LOCAL_REST_API_PORT:-27124}"

# ── Helpers ──────────────────────────────────────────────────────────────────

log() { echo "[entrypoint] $(date -Iseconds) $*"; }

wait_for_port() {
    local port=$1 timeout=${2:-60} elapsed=0
    while ! curl -sf "http://127.0.0.1:${port}" >/dev/null 2>&1; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge "$timeout" ]; then
            log "WARNING: Port ${port} not available after ${timeout}s"
            return 1
        fi
    done
    log "Port ${port} is ready (${elapsed}s)"
}

# ── Obsidian app config ─────────────────────────────────────────────────────

OBSIDIAN_APP_DIR="${HOME}/.config/obsidian"
mkdir -p "${OBSIDIAN_APP_DIR}"

# Register the vault with Obsidian if not already configured
if [ ! -f "${OBSIDIAN_APP_DIR}/obsidian.json" ]; then
    VAULT_ID=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    cat > "${OBSIDIAN_APP_DIR}/obsidian.json" <<APPJSON
{
  "vaults": {
    "${VAULT_ID}": {
      "path": "${VAULT_PATH}",
      "ts": $(date +%s)000,
      "open": true
    }
  }
}
APPJSON
    # Create vault-specific config to disable restricted mode (enable community plugins)
    cat > "${OBSIDIAN_APP_DIR}/${VAULT_ID}.json" <<VAULTJSON
{
  "communityPluginCount": 5,
  "livePreview": true,
  "focusNewTab": true,
  "promptDelete": false,
  "readableLineLength": true
}
VAULTJSON
    log "Created obsidian.json and vault config (community plugins enabled)"
fi

# ── Vault initialization ────────────────────────────────────────────────────

log "Initializing vault at ${VAULT_PATH}"
mkdir -p "${VAULT_CONFIG_DIR}/plugins"

# Copy default community plugin list if not present
if [ ! -f "${VAULT_CONFIG_DIR}/community-plugins.json" ]; then
    cp /config/defaults/community-plugins.json "${VAULT_CONFIG_DIR}/community-plugins.json"
    log "Installed default community-plugins.json"
fi

# Copy pre-installed plugins into vault if not already there
if [ -d "${CONFIG_DIR}/plugins" ]; then
    for plugin_dir in "${CONFIG_DIR}/plugins"/*/; do
        plugin_name=$(basename "$plugin_dir")
        if [ ! -d "${VAULT_CONFIG_DIR}/plugins/${plugin_name}" ]; then
            cp -r "$plugin_dir" "${VAULT_CONFIG_DIR}/plugins/${plugin_name}"
            log "Installed plugin: ${plugin_name}"
        fi
    done
fi

# Ensure plugins are enabled in community-plugins.json
log "Vault config ready at ${VAULT_CONFIG_DIR}"

# ── Start Xvfb ──────────────────────────────────────────────────────────────

# Create X11 socket directory (Xvfb can't create it as non-root)
mkdir -p /tmp/.X11-unix 2>/dev/null || true

log "Starting Xvfb on ${DISPLAY}"
Xvfb "${DISPLAY}" -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 1

if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    log "ERROR: Xvfb failed to start"
    exit 1
fi
log "Xvfb running (PID: ${XVFB_PID})"

# ── Start dbus ──────────────────────────────────────────────────────────────

# Start system dbus if socket doesn't exist (Electron needs it)
if [ ! -S /run/dbus/system_bus_socket ] && [ -x /usr/bin/dbus-daemon ]; then
    mkdir -p /run/dbus 2>/dev/null || true
    dbus-daemon --system --nofork --nopidfile 2>/dev/null &
    sleep 0.5
    log "D-Bus system bus started"
fi

# Start session dbus
if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)" || true
    log "D-Bus session started"
fi

# ── Start Obsidian ───────────────────────────────────────────────────────────

log "Starting Obsidian with vault: ${VAULT_PATH}"

/opt/obsidian/obsidian \
    --no-sandbox \
    --disable-gpu \
    --disable-software-rasterizer \
    --disable-dev-shm-usage \
    --remote-debugging-port=9222 \
    "obsidian://open?path=${VAULT_PATH}" 2>&1 &
OBSIDIAN_PID=$!
sleep 3
if ! kill -0 "$OBSIDIAN_PID" 2>/dev/null; then
    log "ERROR: Obsidian process died immediately (PID: ${OBSIDIAN_PID})"
    wait "$OBSIDIAN_PID" 2>/dev/null || true
fi

# Wait for Obsidian to start and auto-update.
# Obsidian downloads a new .asar file and hot-reloads, which resets plugins.
# We wait for the update to finish before enabling plugins.
sleep 8
OBSIDIAN_CFG_DIR="${HOME}/.config/obsidian"
UPDATE_TIMEOUT=30
log "Waiting for Obsidian auto-update..."
for i in $(seq 1 "$UPDATE_TIMEOUT"); do
    # Check if an updated asar was downloaded
    if ls "${OBSIDIAN_CFG_DIR}"/obsidian-*.asar >/dev/null 2>&1; then
        log "Auto-update detected, waiting for hot-reload..."
        sleep 8  # Give Obsidian time to hot-reload the new asar
        break
    fi
    sleep 1
done

log "Enabling community plugins via Chrome DevTools Protocol..."
python3 /usr/local/bin/enable-plugins.py 2>&1 && \
    log "Community plugins activated" || \
    log "WARNING: CDP plugin activation failed"

# ── Health check: wait for REST API ─────────────────────────────────────────

INSECURE_PORT="${LOCAL_REST_API_INSECURE_PORT:-27123}"
log "Waiting for Local REST API on port ${INSECURE_PORT}..."
if wait_for_port "${INSECURE_PORT}" 120; then
    log "Obsidian REST API is ready"
else
    log "WARNING: REST API may not be available. Obsidian is still running."
fi

# ── Signal handling ──────────────────────────────────────────────────────────

cleanup() {
    log "Shutting down..."
    kill "$OBSIDIAN_PID" 2>/dev/null || true
    kill "$XVFB_PID" 2>/dev/null || true
    wait
    log "Shutdown complete"
}
trap cleanup SIGTERM SIGINT

# ── Keep alive ───────────────────────────────────────────────────────────────

log "Container ready. PID: ${OBSIDIAN_PID}"
wait "$OBSIDIAN_PID"
