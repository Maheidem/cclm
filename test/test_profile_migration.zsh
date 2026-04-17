start_test "profile_migration"

# Simulate migration logic (extracted from bin/cclm lines ~232-243)
MIG_DIR=$(mktemp -d)

# Old bare-slug profile (must contain a dash to be migrated)
echo '{"context_length":65536}' > "$MIG_DIR/some-old-model.json"

# Already-prefixed profile (should be left alone)
echo '{"context_length":131072}' > "$MIG_DIR/lms-qwen3-27b.json"

# Hidden dotfile (should not be touched)
echo '{}' > "$MIG_DIR/.last_session"

# No-dash bare name (should be skipped)
echo '{}' > "$MIG_DIR/nodashes.json"

# Run the migration loop directly
for f in "$MIG_DIR"/*.json(N); do
  _base="${f:t}"
  [[ "$_base" == .* ]] && continue
  [[ "$_base" == lms-* || "$_base" == llama-* || "$_base" == zai-* || "$_base" == remote-* ]] && continue
  [[ "$_base" != *-* ]] && continue
  mv "$f" "$MIG_DIR/lms-${_base}"
done

assert_file_exists "$MIG_DIR/lms-some-old-model.json" "bare dashed profile renamed"
assert_file_exists "$MIG_DIR/lms-qwen3-27b.json" "already-prefixed untouched"
assert_file_exists "$MIG_DIR/.last_session" "dotfile untouched"
assert_file_exists "$MIG_DIR/nodashes.json" "no-dash name untouched"

rm -rf "$MIG_DIR"
