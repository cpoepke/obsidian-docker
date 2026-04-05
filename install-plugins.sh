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
# Args: owner/repo  plugin-id  [version]
install_plugin() {
    local repo="$1"
    local plugin_id="$2"
    local version="${3:-latest}"
    local dest="${PLUGINS_DIR}/${plugin_id}"

    if [ -d "$dest" ]; then
        log "Plugin ${plugin_id} already installed, skipping"
        return 0
    fi

    mkdir -p "$dest"

    local base_url
    if [ "$version" = "latest" ]; then
        base_url="https://github.com/${repo}/releases/latest/download"
    else
        base_url="https://github.com/${repo}/releases/download/${version}"
    fi

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

    # Create default data.json if the plugin needs configuration
    if [ "$plugin_id" = "obsidian-local-rest-api" ]; then
        cat > "${dest}/data.json" <<'RESTCFG'
{
  "port": 27124,
  "enableInsecureServer": true,
  "insecurePort": 27123,
  "bindingHost": "0.0.0.0",
  "apiKey": "",
  "enableAuthentication": false
}
RESTCFG
        log "  Created REST API default config (auth disabled for local use)"
    fi

    log "Installed ${plugin_id}"
}

# =============================================================================
# Plugin registry - add or remove plugins here
# =============================================================================

# Local REST API - Core plugin for all REST access to the vault
# Provides: CRUD operations, search, command execution, periodic notes
install_plugin "coddingtonbear/obsidian-local-rest-api" "obsidian-local-rest-api"

# Omnisearch - Full-text search across notes, PDFs, images
# Provides: Intelligent search with HTTP API via Local REST API
install_plugin "scambier/obsidian-omnisearch" "omnisearch"

# Smart Connections - AI-powered semantic/vector search
# Provides: Semantic search, note connections, local embeddings
install_plugin "brianpetro/obsidian-smart-connections" "smart-connections"

# Dataview - Query engine for vault metadata and structured data
# Provides: DQL queries accessible via Local REST API
install_plugin "blacksmithgu/obsidian-dataview" "dataview"

# Graph Analysis - Advanced graph traversal and analysis
# Provides: Betweenness centrality, closeness, PageRank, community detection
install_plugin "SkepticMystic/graph-analysis" "graph-analysis"

log "All plugins installed to ${PLUGINS_DIR}"
ls -la "$PLUGINS_DIR"
