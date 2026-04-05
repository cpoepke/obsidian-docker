#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# GIT-SYNC — clone vault repo and watch for changes via inotifywait
# ============================================================================
# Required env vars:
#   GIT_REPO_URL      — HTTPS repo URL (e.g. https://github.com/user/brain.git)
#   GITHUB_TOKEN      — PAT for HTTPS auth
# Optional env vars:
#   GIT_USER_NAME     — git commit author name  (default: Obsidian Brain)
#   GIT_USER_EMAIL    — git commit author email  (default: obsidian@n8t.dev)
#   GIT_SYNC_DEBOUNCE — seconds to wait after last change before commit (default: 30)
#   GIT_SYNC_INIT_ONLY — if "true", clone/pull then exit without starting watcher
# ============================================================================

VAULT_PATH="${OBSIDIAN_VAULT_PATH:-/vaults/default}"
DEBOUNCE="${GIT_SYNC_DEBOUNCE:-30}"
GIT_USER="${GIT_USER_NAME:-Obsidian Brain}"
GIT_EMAIL="${GIT_USER_EMAIL:-obsidian@n8t.dev}"

log() { echo "[git-sync] $(date -Iseconds) $*"; }

# ── Validate ────────────────────────────────────────────────────────────────

if [ -z "${GIT_REPO_URL:-}" ]; then
    log "GIT_REPO_URL not set — git sync disabled"
    exit 0
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    log "GITHUB_TOKEN not set — git sync disabled"
    exit 0
fi

# Inject token into HTTPS URL: https://TOKEN@github.com/user/repo.git
AUTH_URL=$(echo "${GIT_REPO_URL}" | sed "s|https://|https://${GITHUB_TOKEN}@|")

# ── Git config ──────────────────────────────────────────────────────────────

git config --global user.name "${GIT_USER}"
git config --global user.email "${GIT_EMAIL}"
git config --global init.defaultBranch main
git config --global --add safe.directory "${VAULT_PATH}"

# ── Clone or pull ───────────────────────────────────────────────────────────

if [ ! -d "${VAULT_PATH}/.git" ]; then
    log "Cloning ${GIT_REPO_URL} into ${VAULT_PATH}..."
    TMPDIR=$(mktemp -d)
    git clone --depth 50 "${AUTH_URL}" "${TMPDIR}"
    mv "${TMPDIR}/.git" "${VAULT_PATH}/.git"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --ignore-existing "${TMPDIR}/" "${VAULT_PATH}/"
    else
        cp -rn "${TMPDIR}/"* "${VAULT_PATH}/" 2>/dev/null || true
        cp -rn "${TMPDIR}/".[!.]* "${VAULT_PATH}/" 2>/dev/null || true
    fi
    rm -rf "${TMPDIR}"
    log "Clone complete"
else
    log "Vault already has .git — pulling latest..."
    cd "${VAULT_PATH}"
    git remote set-url origin "${AUTH_URL}"
    git pull --rebase --autostash || log "WARNING: pull failed, continuing with local state"
    log "Pull complete"
fi

# Ensure .gitignore excludes Obsidian workspace/cache files
GITIGNORE="${VAULT_PATH}/.gitignore"
if [ ! -f "${GITIGNORE}" ] || ! grep -q 'workspace.json' "${GITIGNORE}" 2>/dev/null; then
    cat >> "${GITIGNORE}" <<'EOF'

# Obsidian ephemeral files (auto-added by git-sync)
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/cache
.obsidian/.obsidian-git-isomorphic-git/
.trash/
EOF
    log "Updated .gitignore"
fi

# ── Init-only mode ───────────────────────────────────────────────────────────

if [ "${GIT_SYNC_INIT_ONLY:-false}" = "true" ]; then
    log "Init-only mode — exiting after initial sync"
    exit 0
fi

# ── Watcher mode ────────────────────────────────────────────────────────────

cd "${VAULT_PATH}"

commit_and_push() {
    cd "${VAULT_PATH}"
    git add -A
    if git diff --cached --quiet; then
        return 0
    fi
    local msg="vault: auto-sync $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    git commit -m "${msg}" || { log "WARNING: commit failed"; return 1; }
    git push origin HEAD || { log "WARNING: push failed, will retry next cycle"; return 1; }
    log "Synced: ${msg}"
}

# Initial commit of any pre-existing changes
commit_and_push || true

log "Starting inotifywait watcher (debounce=${DEBOUNCE}s)..."

TRIGGER_FILE="/tmp/git-sync-trigger"

# Background sync loop — checks trigger file every 5s
(
    while true; do
        if [ -f "${TRIGGER_FILE}" ]; then
            TRIGGER_TIME=$(cat "${TRIGGER_FILE}" 2>/dev/null || echo "0")
            NOW=$(date +%s)
            ELAPSED=$((NOW - TRIGGER_TIME))
            if [ "${ELAPSED}" -ge "${DEBOUNCE}" ]; then
                rm -f "${TRIGGER_FILE}"
                commit_and_push || true
            fi
        fi
        sleep 5
    done
) &
SYNC_LOOP_PID=$!

# inotifywait writes trigger timestamp on each change
inotifywait -r -m \
    --exclude '(\.git/|\.obsidian/workspace.*\.json|\.obsidian/cache)' \
    -e create -e modify -e delete -e move \
    "${VAULT_PATH}" 2>/dev/null |
while read -r _dir _event _file; do
    date +%s > "${TRIGGER_FILE}"
done

# Clean up sync loop if inotifywait exits
kill "${SYNC_LOOP_PID}" 2>/dev/null || true
