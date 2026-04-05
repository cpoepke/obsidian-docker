#!/usr/bin/env bash
# =============================================================================
# Seed the Obsidian vault with test content
# Usage: seed-vault.sh [vault-path]
#
# Can run either:
#   - On the host against a Docker volume (via docker cp)
#   - Inside the container directly
# =============================================================================
set -euo pipefail

CONTAINER="${OBSIDIAN_CONTAINER:-obsidian}"

log() { echo "[seed-vault] $*"; }

# Write a file into the running container's vault
write_file() {
    local path="$1"
    local content="$2"
    local dir
    dir=$(dirname "/vaults/default/${path}")

    docker exec "$CONTAINER" sh -c "mkdir -p '${dir}'"
    echo "$content" | docker exec -i "$CONTAINER" sh -c "cat > '/vaults/default/${path}'"
    log "Created ${path}"
}

log "Seeding test vault in container: ${CONTAINER}"

# ── Test documents ───────────────────────────────────────────────────────────

write_file "notes/test-document.md" "---
title: Test Document
tags: [test, seed, documentation]
created: 2026-04-04
---

# Test Document

This is a test document for validating the Obsidian REST API.

## Section One

Some content in the first section with a [[linked-note]] reference.

## Section Two

More content here with a reference to [[tagged-note]].

- Item one
- Item two
- Item three
"

write_file "notes/linked-note.md" "---
title: Linked Note
tags: [test, links]
created: 2026-04-04
---

# Linked Note

This note is linked from [[test-document]].

## Connections

It also references [[tagged-note]] to form a small graph.
"

write_file "notes/tagged-note.md" "---
title: Tagged Note
tags: [test, important, search-target]
created: 2026-04-04
---

# Tagged Note

This note has specific tags for search testing.

## Searchable Content

The quick brown fox jumps over the lazy dog.
This sentence contains a unique phrase: quantum-entanglement-test-marker.
"

write_file "daily/2026-04-04.md" "---
title: Daily Note
tags: [daily]
---

# 2026-04-04

## Tasks
- [x] Set up Obsidian Docker infrastructure
- [ ] Run API integration tests

## Notes
Today we're testing the [[notes/test-document|test document]] setup.
"

log "Vault seeded with 4 test files"
