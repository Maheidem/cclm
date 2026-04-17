start_test "mcp_compose_merge_into_claude_json"
# Verify apply_mcp_servers merges a profile's .mcp_servers into ~/.claude.json's
# .mcpServers, creates a backup, and is restore-safe. All paths overridable via
# CCLM_CLAUDE_CONFIG / CCLM_CLAUDE_BACKUP so we never touch the real file.
#
# Note: apply_mcp_servers sets _CCLM_MCP_ARMED=1 so the shell-level EXIT hook
# knows to restore. In CCLM_LIB_ONLY mode (tests) the hook is NOT installed —
# see bin/cclm below the CCLM_LIB_ONLY return — so we can inspect merged state
# without interference.

MCP_TMP=$(mktemp -d)
export CCLM_CLAUDE_CONFIG="$MCP_TMP/claude.json"
export CCLM_CLAUDE_BACKUP="$MCP_TMP/claude.json.cclm-backup"

# Seed a pre-existing claude.json with an unrelated top-level field and one
# pre-existing MCP server so we can assert merge semantics (original+new both
# survive, and same-name override wins).
cat > "$CCLM_CLAUDE_CONFIG" <<'EOF'
{
  "theme": "dark",
  "mcpServers": {
    "existing": {"command": "existing-bin", "args": []}
  }
}
EOF

# Profile carries a new server AND overrides "existing" — profile must win.
PROFILE="$MCP_TMP/lms-test.json"
cat > "$PROFILE" <<'EOF'
{
  "model": "test-model",
  "context_length": 200000,
  "mcp_servers": {
    "fs":       {"command": "npx", "args": ["-y", "fs-mcp"]},
    "existing": {"command": "overridden-bin", "args": ["v2"]}
  }
}
EOF

DRY_RUN=false apply_mcp_servers "$PROFILE" >/dev/null 2>&1
RC=$?
assert_exit 0 "$RC" "apply_mcp_servers returns 0 on success"

# Unrelated top-level fields preserved.
THEME=$(jq -r '.theme' "$CCLM_CLAUDE_CONFIG")
assert_eq "dark" "$THEME" "unrelated .theme preserved after merge"

# New server merged under .mcpServers.
FS_CMD=$(jq -r '.mcpServers.fs.command' "$CCLM_CLAUDE_CONFIG")
assert_eq "npx" "$FS_CMD" "new server 'fs' merged into mcpServers"

# Profile overrides existing same-name server (RHS wins on jq + operator).
OVERRIDDEN=$(jq -r '.mcpServers.existing.command' "$CCLM_CLAUDE_CONFIG")
assert_eq "overridden-bin" "$OVERRIDDEN" "profile overrides existing same-name server"

# Backup file created with the pre-merge contents.
assert_file_exists "$CCLM_CLAUDE_BACKUP" "backup file created"
BACKUP_EXISTING_CMD=$(jq -r '.mcpServers.existing.command' "$CCLM_CLAUDE_BACKUP")
assert_eq "existing-bin" "$BACKUP_EXISTING_CMD" "backup captures pre-merge state"

start_test "mcp_compose_restore_from_backup"
# restore_claude_config must roll claude.json back to the backup and remove
# the backup file.
restore_claude_config
RESTORED_CMD=$(jq -r '.mcpServers.existing.command' "$CCLM_CLAUDE_CONFIG" 2>/dev/null)
assert_eq "existing-bin" "$RESTORED_CMD" "claude.json restored from backup"

ASSERTIONS=$((ASSERTIONS + 1))
if [[ -f "$CCLM_CLAUDE_BACKUP" ]]; then
  _fail "restore must remove the backup file after restoring"
fi

# No .mcp_servers field present → no-op, no backup created.
start_test "mcp_compose_no_mcp_field_is_noop"
cp "$CCLM_CLAUDE_CONFIG" "$MCP_TMP/before.json"
PLAIN_PROFILE="$MCP_TMP/plain.json"
echo '{"model":"x","context_length":200000}' > "$PLAIN_PROFILE"
apply_mcp_servers "$PLAIN_PROFILE"
RC2=$?
assert_exit 0 "$RC2" "apply_mcp_servers on profile without mcp_servers returns 0"

ASSERTIONS=$((ASSERTIONS + 1))
if [[ -f "$CCLM_CLAUDE_BACKUP" ]]; then
  _fail "no backup created when profile lacks mcp_servers"
fi
assert_file_match "$CCLM_CLAUDE_CONFIG" "$MCP_TMP/before.json" "claude.json untouched"

# claude.json doesn't exist at merge time → zero-byte marker backup; restore
# deletes the created file.
start_test "mcp_compose_no_preexisting_claude_json"
rm -f "$CCLM_CLAUDE_CONFIG" "$CCLM_CLAUDE_BACKUP"
apply_mcp_servers "$PROFILE"
assert_file_exists "$CCLM_CLAUDE_CONFIG" "claude.json created when absent"
assert_file_exists "$CCLM_CLAUDE_BACKUP"  "zero-byte marker backup created"
FS_AFTER=$(jq -r '.mcpServers.fs.command' "$CCLM_CLAUDE_CONFIG")
assert_eq "npx" "$FS_AFTER" "new server present when claude.json was absent"

restore_claude_config
ASSERTIONS=$((ASSERTIONS + 1))
if [[ -f "$CCLM_CLAUDE_CONFIG" ]]; then
  _fail "restore deletes the claude.json we created when backup was zero-byte marker"
fi

# Dry-run path: prints merged JSON to stdout, skips writes, no backup.
start_test "mcp_compose_dry_run_skips_writes"
rm -f "$CCLM_CLAUDE_CONFIG" "$CCLM_CLAUDE_BACKUP"
echo '{"mcpServers":{"existing":{"command":"existing-bin"}}}' > "$CCLM_CLAUDE_CONFIG"
cp "$CCLM_CLAUDE_CONFIG" "$MCP_TMP/pre-dryrun.json"
DRY_OUT=$(DRY_RUN=true apply_mcp_servers "$PROFILE" 2>/dev/null)
assert_contains "$DRY_OUT" '"fs"' "dry-run stdout contains new server name"
assert_file_match "$CCLM_CLAUDE_CONFIG" "$MCP_TMP/pre-dryrun.json" "claude.json unchanged in dry-run"
ASSERTIONS=$((ASSERTIONS + 1))
if [[ -f "$CCLM_CLAUDE_BACKUP" ]]; then
  _fail "no backup file in dry-run"
fi

# Corrupt JSON → abort cleanly, no write, no backup overwrite.
start_test "mcp_compose_corrupt_claude_json_aborts"
rm -f "$CCLM_CLAUDE_BACKUP"
echo 'this is not json {' > "$CCLM_CLAUDE_CONFIG"
cp "$CCLM_CLAUDE_CONFIG" "$MCP_TMP/pre-corrupt.json"
apply_mcp_servers "$PROFILE" >/dev/null 2>&1
BAD_RC=$?
ASSERTIONS=$((ASSERTIONS + 1))
if (( BAD_RC == 0 )); then
  _fail "apply_mcp_servers must fail when claude.json is not valid JSON"
fi
assert_file_match "$CCLM_CLAUDE_CONFIG" "$MCP_TMP/pre-corrupt.json" "corrupt claude.json left untouched"

rm -rf "$MCP_TMP"
unset CCLM_CLAUDE_CONFIG CCLM_CLAUDE_BACKUP _CCLM_MCP_ARMED
