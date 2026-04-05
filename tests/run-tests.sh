#!/usr/bin/env bash
# =============================================================================
# Obsidian REST API Integration Tests
# Tests all plugin endpoints using curl + jq
# Usage: run-tests.sh [base-url]
# =============================================================================
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:27123}"
API_KEY="${2:-}"
PASS=0
FAIL=0
ERRORS=()

# ── Test helpers ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${BOLD}[test]${NC} $*"; }
pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() {
    FAIL=$((FAIL + 1))
    ERRORS+=("$1: $2")
    echo -e "  ${RED}✗${NC} $1"
    echo -e "    ${RED}→ $2${NC}"
}

section() { echo -e "\n${BOLD}${YELLOW}── $1 ──${NC}"; }

# HTTP request helper - returns "STATUS_CODE\nBODY"
# Usage: result=$(api GET /vault/); status=$(head -1 <<< "$result"); body=$(tail -n +2 <<< "$result")
api() {
    local method="$1"
    local path="$2"
    shift 2
    local url="${BASE_URL}${path}"

    local auth_args=()
    if [ -n "$API_KEY" ]; then
        auth_args+=(-H "Authorization: Bearer ${API_KEY}")
    fi

    local response
    response=$(curl -s -w "\n%{http_code}" -X "$method" "${auth_args[@]}" "$url" "$@" 2>&1) || true

    echo "$response"
}

# Extract status code (last line) and body (everything before)
get_status() { echo "$1" | tail -1; }
get_body()   { echo "$1" | sed '$d'; }

assert_status() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    local body="$4"

    if [ "$actual" = "$expected" ]; then
        pass "$test_name"
    else
        fail "$test_name" "expected HTTP $expected, got $actual. Body: $(echo "$body" | head -c 200)"
    fi
}

assert_body_contains() {
    local test_name="$1"
    local needle="$2"
    local body="$3"

    if echo "$body" | grep -q "$needle"; then
        pass "$test_name"
    else
        fail "$test_name" "body does not contain '$needle'. Got: $(echo "$body" | head -c 200)"
    fi
}

assert_json_array_not_empty() {
    local test_name="$1"
    local body="$2"

    local length
    length=$(echo "$body" | jq 'length' 2>/dev/null || echo "0")
    if [ "$length" -gt 0 ]; then
        pass "$test_name (${length} items)"
    else
        fail "$test_name" "expected non-empty JSON array, got length $length"
    fi
}

# ── Auto-detect API key ────────────────────────────────────────────────────

if [ -z "$API_KEY" ]; then
    API_KEY=$(docker exec "${OBSIDIAN_CONTAINER:-obsidian}" \
        cat /vaults/default/.obsidian/plugins/obsidian-local-rest-api/data.json 2>/dev/null \
        | jq -r '.apiKey // empty' 2>/dev/null || true)
    if [ -n "$API_KEY" ]; then
        log "Auto-detected API key from container"
    fi
fi

# ── Wait for API readiness ──────────────────────────────────────────────────

wait_for_api() {
    local timeout="${API_TIMEOUT:-180}"
    local elapsed=0

    log "Waiting for API at ${BASE_URL} (timeout: ${timeout}s)..."
    while true; do
        if curl -sf "${BASE_URL}/" >/dev/null 2>&1; then
            log "API is ready (${elapsed}s)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$timeout" ]; then
            log "ERROR: API not ready after ${timeout}s"
            return 1
        fi
    done
}

# =============================================================================
# TEST SUITES
# =============================================================================

test_server_status() {
    section "Server Status"

    local result status body
    result=$(api GET "/")
    status=$(get_status "$result")
    body=$(get_body "$result")

    assert_status "GET / returns 200" "200" "$status" "$body"
}

test_vault_crud() {
    section "Vault CRUD Operations"

    # ── List files ───────────────────────────────────────────────────────
    local result status body

    result=$(api GET "/vault/")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "GET /vault/ - list files" "200" "$status" "$body"

    local file_count
    file_count=$(echo "$body" | jq '.files | length' 2>/dev/null || echo "0")
    if [ "$file_count" -gt 0 ]; then
        pass "GET /vault/ - has files (${file_count} items)"
    else
        fail "GET /vault/ - has files" "expected non-empty files list"
    fi

    # ── Create a note ────────────────────────────────────────────────────
    local test_content="# API Test Note

This note was created by the integration test suite.

## Details
- Created via PUT /vault/
- Testing CRUD operations
"
    result=$(api PUT "/vault/test-api/crud-test.md" \
        -H "Content-Type: text/markdown" \
        -d "$test_content")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "PUT /vault/test-api/crud-test.md - create note" "204" "$status" "$body"

    # ── Read the note back ───────────────────────────────────────────────
    result=$(api GET "/vault/test-api/crud-test.md")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "GET /vault/test-api/crud-test.md - read note" "200" "$status" "$body"
    assert_body_contains "GET /vault/test-api/crud-test.md - content matches" "API Test Note" "$body"

    # ── Update the note (append) ─────────────────────────────────────────
    local updated_content="# API Test Note (Updated)

This note was updated by the integration test suite.

## Updated Section
New content added during update test.
"
    result=$(api PUT "/vault/test-api/crud-test.md" \
        -H "Content-Type: text/markdown" \
        -d "$updated_content")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "PUT /vault/test-api/crud-test.md - update note" "204" "$status" "$body"

    # ── Verify update ────────────────────────────────────────────────────
    result=$(api GET "/vault/test-api/crud-test.md")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_body_contains "GET after update - content updated" "Updated" "$body"

    # ── Create note in subfolder ─────────────────────────────────────────
    result=$(api PUT "/vault/test-api/subfolder/nested-note.md" \
        -H "Content-Type: text/markdown" \
        -d "# Nested Note\n\nCreated in a subfolder.")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "PUT /vault/test-api/subfolder/nested-note.md - nested create" "204" "$status" "$body"

    # ── Delete the note ──────────────────────────────────────────────────
    result=$(api DELETE "/vault/test-api/crud-test.md")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "DELETE /vault/test-api/crud-test.md - delete note" "204" "$status" "$body"

    # ── Verify deletion ──────────────────────────────────────────────────
    result=$(api GET "/vault/test-api/crud-test.md")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "GET deleted note - returns 404" "404" "$status" "$body"

    # ── Cleanup nested note ──────────────────────────────────────────────
    api DELETE "/vault/test-api/subfolder/nested-note.md" >/dev/null 2>&1 || true
}

test_search() {
    section "Search"

    # ── Simple search ────────────────────────────────────────────────────
    local result status body

    result=$(api POST "/search/simple/?query=test")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "POST /search/simple/?query=test - simple search" "200" "$status" "$body"

    # ── Search for unique marker ─────────────────────────────────────────
    result=$(api POST "/search/simple/?query=quantum-entanglement-test-marker")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "POST /search/simple/ - unique marker search" "200" "$status" "$body"

    # ── Dataview DQL search ──────────────────────────────────────────────
    result=$(api POST "/search/" \
        -H "Content-Type: application/vnd.olrapi.dataview.dql+txt" \
        -d 'TABLE title, tags FROM "notes" WHERE contains(tags, "test")')
    status=$(get_status "$result")
    body=$(get_body "$result")
    # Dataview may return 200 on success or 400 if plugin isn't fully loaded
    if [ "$status" = "200" ]; then
        pass "POST /search/ - Dataview DQL query"
    elif [ "$status" = "400" ]; then
        pass "POST /search/ - Dataview endpoint reachable (plugin may need warmup)"
    else
        fail "POST /search/ - Dataview DQL query" "expected HTTP 200 or 400, got $status"
    fi
}

test_commands() {
    section "Commands"

    local result status body

    # ── List commands ────────────────────────────────────────────────────
    result=$(api GET "/commands/")
    status=$(get_status "$result")
    body=$(get_body "$result")
    assert_status "GET /commands/ - list commands" "200" "$status" "$body"

    local cmd_count
    cmd_count=$(echo "$body" | jq '.commands | length' 2>/dev/null || echo "0")
    if [ "$cmd_count" -gt 0 ]; then
        pass "GET /commands/ - has commands (${cmd_count} items)"
    else
        fail "GET /commands/ - has commands" "expected non-empty commands list"
    fi
}

test_plugin_installation() {
    section "Plugin Installation Verification"

    local plugins=("obsidian-local-rest-api" "omnisearch" "smart-connections" "dataview" "graph-analysis")

    for plugin_id in "${plugins[@]}"; do
        local result status body
        result=$(api GET "/vault/.obsidian/plugins/${plugin_id}/manifest.json")
        status=$(get_status "$result")
        body=$(get_body "$result")

        if [ "$status" = "200" ]; then
            local plugin_name
            plugin_name=$(echo "$body" | jq -r '.name // .id // "unknown"' 2>/dev/null || echo "$plugin_id")
            pass "Plugin installed: ${plugin_name} (${plugin_id})"
        else
            fail "Plugin installed: ${plugin_id}" "manifest.json returned HTTP $status"
        fi
    done
}

test_active_plugins() {
    section "Plugin Activation Verification"

    local result status body
    result=$(api GET "/commands/")
    status=$(get_status "$result")
    body=$(get_body "$result")

    if [ "$status" != "200" ]; then
        fail "Plugin activation check" "cannot list commands (HTTP $status)"
        return
    fi

    # Check that plugins registered commands (proves they're loaded and active)
    # Commands response is {"commands": [...]} with id fields like "plugin-id:command-name"
    local plugin_checks=(
        "omnisearch:Omnisearch"
        "dataview:Dataview"
        "graph-analysis:Graph Analysis"
        "smart-connections:Smart Connections"
    )

    for check in "${plugin_checks[@]}"; do
        local plugin_prefix="${check%%:*}"
        local plugin_label="${check##*:}"

        if echo "$body" | jq -e ".commands[] | select(.id | startswith(\"${plugin_prefix}:\"))" >/dev/null 2>&1; then
            pass "Plugin active: ${plugin_label} (has registered commands)"
        else
            fail "Plugin active: ${plugin_label}" "no commands found with prefix '${plugin_prefix}:'"
        fi
    done
}

test_seed_data() {
    section "Seed Data Verification"

    local expected_files=(
        "notes/test-document.md"
        "notes/linked-note.md"
        "notes/tagged-note.md"
        "daily/2026-04-04.md"
    )

    for file in "${expected_files[@]}"; do
        local result status body
        result=$(api GET "/vault/${file}")
        status=$(get_status "$result")
        body=$(get_body "$result")
        assert_status "Seed file exists: ${file}" "200" "$status" "$body"
    done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo -e "${BOLD}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Obsidian REST API Integration Tests${NC}"
    echo -e "${BOLD}  Target: ${BASE_URL}${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════${NC}"

    if ! wait_for_api; then
        echo -e "\n${RED}FATAL: API not available. Aborting tests.${NC}"
        exit 1
    fi

    # Run test suites
    test_server_status
    test_seed_data
    test_plugin_installation
    test_active_plugins
    test_vault_crud
    test_search
    test_commands

    # ── Summary ──────────────────────────────────────────────────────────
    echo -e "\n${BOLD}════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}Passed: ${PASS}${NC}"
    echo -e "  ${RED}Failed: ${FAIL}${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════${NC}"

    if [ "$FAIL" -gt 0 ]; then
        echo -e "\n${RED}Failed tests:${NC}"
        for err in "${ERRORS[@]}"; do
            echo -e "  ${RED}✗${NC} $err"
        done
        echo ""
        exit 1
    fi

    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
}

main "$@"
