#!/usr/bin/env bash
# =============================================================================
# Download and install Obsidian community plugins at Docker build time
# Usage: install-plugins.sh <config-dir>
# =============================================================================
set -euo pipefail

CONFIG_DIR="${1:-/config/obsidian}"
PLUGINS_DIR="${CONFIG_DIR}/plugins"

mkdir -p "$PLUGINS_DIR"

log() { echo "[install-plugins] $*"; }

# Install a plugin from its GitHub release
# Args: owner/repo  plugin-id  version
install_plugin() {
    local repo="$1"
    local plugin_id="$2"
    local version="$3"
    local dest="${PLUGINS_DIR}/${plugin_id}"

    if [ -d "$dest" ]; then
        log "Plugin ${plugin_id} already installed, skipping"
        return 0
    fi

    mkdir -p "$dest"

    local base_url="https://github.com/${repo}/releases/download/${version}"

    log "Installing ${plugin_id} from ${repo} (${version})..."

    # Every Obsidian plugin release contains manifest.json, main.js, and optionally styles.css
    for file in manifest.json main.js styles.css; do
        if curl -fsSL -o "${dest}/${file}" "${base_url}/${file}" 2>/dev/null; then
            log "  Downloaded ${file}"
        else
            # styles.css is optional
            if [ "$file" != "styles.css" ]; then
                log "  WARNING: Failed to download ${file}"
            fi
            rm -f "${dest}/${file}"
        fi
    done

    # Create placeholder data.json for REST API plugin (key injected at runtime by entrypoint)
    if [ "$plugin_id" = "obsidian-local-rest-api" ]; then
        cat > "${dest}/data.json" <<'RESTCFG'
{
  "port": 27124,
  "enableInsecureServer": true,
  "insecurePort": 27123,
  "bindingHost": "0.0.0.0",
  "apiKey": "",
  "enableAuthentication": true
}
RESTCFG
        log "  Created REST API default config (key injected at runtime)"
    fi

    log "Installed ${plugin_id}"
}

# =============================================================================
# Plugin registry — pinned versions for reproducible builds
# =============================================================================

# Local REST API - Core plugin for all REST access to the vault
install_plugin "coddingtonbear/obsidian-local-rest-api" "obsidian-local-rest-api" "3.5.0"

# Omnisearch - Full-text search across notes, PDFs, images
install_plugin "scambier/obsidian-omnisearch" "omnisearch" "1.28.2"

# Smart Connections - AI-powered semantic/vector search
install_plugin "brianpetro/obsidian-smart-connections" "smart-connections" "4.3.0"

# Dataview - Query engine for vault metadata and structured data
install_plugin "blacksmithgu/obsidian-dataview" "dataview" "0.5.70"

log "All plugins installed to ${PLUGINS_DIR}"
ls -la "$PLUGINS_DIR"
