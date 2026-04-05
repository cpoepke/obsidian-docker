# obsidian-docker

Headless [Obsidian](https://obsidian.md) Docker image with REST API plugins for agent and automation integration.

Runs Obsidian in a virtual X11 framebuffer (Xvfb) with community plugins pre-installed, exposing the vault via HTTP REST API.

## Quick Start

```bash
# Generate an API key
export LOCAL_REST_API_KEY=$(openssl rand -hex 32)

# Run with Docker Compose
LOCAL_REST_API_KEY=$LOCAL_REST_API_KEY docker compose up -d

# Or run standalone
docker run -d \
  --name obsidian \
  --shm-size=256m \
  -p 27123:27123 \
  -p 27124:27124 \
  -e LOCAL_REST_API_KEY=$LOCAL_REST_API_KEY \
  -v ./my-vault:/vaults/default \
  ghcr.io/cpoepke/obsidian-docker:latest
```

The container takes ~60 seconds to start (Obsidian boot + plugin activation). The REST API is ready when the health check passes:

```bash
curl -sf -H "Authorization: Bearer $LOCAL_REST_API_KEY" http://localhost:27123/
```

## REST API Usage

All endpoints require the `Authorization: Bearer <key>` header.

```bash
# List all files
curl -s -H "Authorization: Bearer $LOCAL_REST_API_KEY" http://localhost:27123/vault/

# Create a note
curl -s -X PUT http://localhost:27123/vault/notes/my-note.md \
  -H "Authorization: Bearer $LOCAL_REST_API_KEY" \
  -H "Content-Type: text/markdown" \
  -d "# My Note\n\nContent here"

# Read a note
curl -s -H "Authorization: Bearer $LOCAL_REST_API_KEY" http://localhost:27123/vault/notes/my-note.md

# Search
curl -s -X POST "http://localhost:27123/search/simple/?query=my+search" \
  -H "Authorization: Bearer $LOCAL_REST_API_KEY"

# Dataview DQL query
curl -s -X POST http://localhost:27123/search/ \
  -H "Authorization: Bearer $LOCAL_REST_API_KEY" \
  -H "Content-Type: application/vnd.olrapi.dataview.dql+txt" \
  -d 'TABLE file.ctime FROM "notes" SORT file.ctime DESC'
```

## Pre-installed Plugins

| Plugin | Version | Purpose | API Surface |
|--------|---------|---------|-------------|
| **[Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api)** | 3.5.0 | Core REST interface | CRUD notes, search, commands, tags |
| **[Omnisearch](https://github.com/scambier/obsidian-omnisearch)** | 1.28.2 | Full-text search | Intelligent search across all content |
| **[Smart Connections](https://github.com/brianpetro/obsidian-smart-connections)** | 4.3.0 | Semantic/vector search | AI-powered note similarity & connections |
| **[Dataview](https://github.com/blacksmithgu/obsidian-dataview)** | 0.5.70 | Structured queries | DQL queries over vault metadata |

### Custom Plugins

The image ships with all 4 plugins above baked in. To use your own plugin set, mount a volume over the plugin directory:

```bash
docker run -d \
  --name obsidian \
  --shm-size=256m \
  -p 27123:27123 \
  -e LOCAL_REST_API_KEY=$LOCAL_REST_API_KEY \
  -v ./my-vault:/vaults/default \
  -v ./my-plugins:/config/obsidian/plugins \
  ghcr.io/cpoepke/obsidian-docker:latest
```

Place each plugin in its own subdirectory (e.g., `my-plugins/obsidian-local-rest-api/manifest.json`). The entrypoint copies them into the vault's `.obsidian/plugins/` on startup and activates them via Chrome DevTools Protocol.

You must also provide a matching `community-plugins.json` in your vault's `.obsidian/` directory listing the plugin IDs to enable.

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `LOCAL_REST_API_KEY` | *(required)* | API key for authenticating REST API requests |
| `OBSIDIAN_VAULT_PATH` | `/vaults/default` | Path to the vault inside the container |
| `LOCAL_REST_API_PORT` | `27124` | HTTPS port for the REST API |
| `LOCAL_REST_API_INSECURE_PORT` | `27123` | HTTP port for the REST API |
| `DISPLAY` | `:99` | X11 display number |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 27123 | HTTP | Local REST API (insecure, no TLS) |
| 27124 | HTTPS | Local REST API (self-signed TLS) |

## Volumes

| Path | Purpose |
|------|---------|
| `/vaults` | Vault data (notes, attachments) |
| `/config/obsidian` | Plugin binaries and configuration |

## Security

- **Authentication required**: The `LOCAL_REST_API_KEY` environment variable is mandatory. The container will refuse to start without it.
- **No sandbox**: Obsidian runs with `--no-sandbox` (required for Electron in containers). Run in an isolated network.
- **Plugin versions pinned**: All plugins are downloaded at specific versions during the Docker build for reproducibility.

## Sister Project

**[obsidian-mcp](https://github.com/cpoepke/obsidian-mcp)** — MCP (Model Context Protocol) server that exposes this image's REST API as MCP tools. Use it to connect Obsidian to AI agents like Claude Desktop, enabling note creation, search, and vault management through the MCP protocol.

## License

MIT
