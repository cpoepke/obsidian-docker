# obsidian-docker

Headless Obsidian Docker image with REST API plugins for agent integration.

## Architecture

- **Base**: Ubuntu 24.04 (glibc required for Electron/Chromium)
- **Obsidian**: Extracted from AppImage, runs in Xvfb (virtual X11 framebuffer)
- **Plugins**: Downloaded at build time (pinned versions), activated at runtime via Chrome DevTools Protocol (CDP)
- **User**: Runs as non-root `obsidian` user

### Startup flow (entrypoint.sh)

1. Validate `LOCAL_REST_API_KEY` env var (required, exits if missing)
2. Register vault with Obsidian (`~/.config/obsidian/obsidian.json`)
3. Copy plugins from `/config/obsidian/plugins/` → vault's `.obsidian/plugins/`
4. Inject API key into REST API plugin's `data.json` (via `jq`)
5. Start Xvfb → dbus → Obsidian
6. Wait for auto-update (`.asar` hot-reload)
7. Enable plugins via CDP (`enable-plugins.py`)
8. Wait for REST API health check on port 27123

### Plugin activation (enable-plugins.py)

Connects to Obsidian's remote debugging port (9222) via WebSocket, executes JavaScript to:
- Dismiss modals
- Disable restricted mode (`app.plugins.setEnable(true)`)
- Load and initialize all plugins

## Pre-installed plugins (pinned versions)

| Plugin | Version | ID |
|--------|---------|-----|
| Local REST API | 3.5.0 | `obsidian-local-rest-api` |
| Omnisearch | 1.28.2 | `omnisearch` |
| Smart Connections | 4.3.0 | `smart-connections` |
| Dataview | 0.5.70 | `dataview` |

## Required environment variables

- `LOCAL_REST_API_KEY` — API key for REST API authentication (container refuses to start without it)

## Build and test

```bash
docker compose build

# Run (key is required)
LOCAL_REST_API_KEY=$(openssl rand -hex 32) docker compose up -d

# Wait for healthy, then seed + test
./tests/seed-vault.sh
./tests/run-tests.sh http://127.0.0.1:27123 <your-key>

# Tear down
LOCAL_REST_API_KEY=x docker compose down -v
```

## Key files

- `Dockerfile` — Multi-stage build (extractor + runtime), supports amd64 and arm64
- `entrypoint.sh` — Container startup, plugin setup, API key injection
- `install-plugins.sh` — Downloads plugins at build time from GitHub releases
- `enable-plugins.py` — CDP WebSocket client for runtime plugin activation
- `config/community-plugins.json` — Plugin IDs to enable
- `tests/run-tests.sh` — 27 integration tests for REST API endpoints
- `tests/seed-vault.sh` — Creates test documents in the vault

## Sister repo

[obsidian-mcp](https://github.com/cpoepke/obsidian-mcp) — MCP server that exposes this image's REST API as MCP tools.
