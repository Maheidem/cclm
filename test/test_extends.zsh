start_test "profile_extends"

# _cclm_profile_resolve must be defined above the CCLM_LIB_ONLY guard.
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f _cclm_profile_resolve > /dev/null 2>&1; then
  _fail "_cclm_profile_resolve function not defined"
fi

ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f _cclm_read_profile > /dev/null 2>&1; then
  _fail "_cclm_read_profile function not defined"
fi

# ---- sandbox: fixtures for extends behaviour -----------------------------
EXT_TMP=$(mktemp -d)

# Base profile: host + ctx=65536 (plus a parent-only field we expect to
# survive the merge).
cat > "$EXT_TMP/ollama-base.json" <<'JSON'
{
  "host": "localhost",
  "port": "11434",
  "model": "base-model",
  "context_length": 65536,
  "parent_only": "keep-me"
}
JSON

# Child profile: extends base, overrides ctx, adds a child-only field.
cat > "$EXT_TMP/ollama-big.json" <<'JSON'
{
  "extends": "ollama-base",
  "context_length": 262144,
  "child_only": "present"
}
JSON

# --- Happy path: merge applies, child overrides parent --------------------
RESOLVED=$(CONFIG_DIR="$EXT_TMP" _cclm_profile_resolve ollama-big 2>&1)
EXIT=$?
assert_exit 0 "$EXIT" "resolve happy path exits 0"

# Context length must be the child's (262144), not the parent's (65536).
CTX=$(echo "$RESOLVED" | jq -r '.context_length')
assert_eq "262144" "$CTX" "child context_length overrides parent"

# Host inherited from parent.
HOST=$(echo "$RESOLVED" | jq -r '.host')
assert_eq "localhost" "$HOST" "host inherited from parent"

# Parent-only field is preserved.
PO=$(echo "$RESOLVED" | jq -r '.parent_only')
assert_eq "keep-me" "$PO" "parent-only field preserved after merge"

# Child-only field is present.
CO=$(echo "$RESOLVED" | jq -r '.child_only')
assert_eq "present" "$CO" "child-only field preserved after merge"

# `extends` is stripped from the resolved output.
EXT=$(echo "$RESOLVED" | jq -r '.extends // "absent"')
assert_eq "absent" "$EXT" "extends field stripped from resolved JSON"

# --- _cclm_read_profile wrapper accepts both slug and abs path ------------
BY_SLUG=$(CONFIG_DIR="$EXT_TMP" _cclm_read_profile ollama-big)
BY_PATH=$(CONFIG_DIR="$EXT_TMP" _cclm_read_profile "$EXT_TMP/ollama-big.json")
ASSERTIONS=$((ASSERTIONS + 1))
if [[ "$BY_SLUG" != "$BY_PATH" ]]; then
  _fail "_cclm_read_profile slug vs path form disagree"
fi

# --- Missing base: extends points to a nonexistent slug -------------------
cat > "$EXT_TMP/ollama-orphan.json" <<'JSON'
{
  "extends": "ollama-ghost",
  "context_length": 1024
}
JSON
OUTPUT=$(CONFIG_DIR="$EXT_TMP" _cclm_profile_resolve ollama-orphan 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "missing base exits 1"
assert_contains "$OUTPUT" "not found" "missing-base error mentions not found"

# --- Cycle: two profiles that extend each other ---------------------------
cat > "$EXT_TMP/ollama-cyc-a.json" <<'JSON'
{ "extends": "ollama-cyc-b", "model": "a" }
JSON
cat > "$EXT_TMP/ollama-cyc-b.json" <<'JSON'
{ "extends": "ollama-cyc-a", "model": "b" }
JSON
OUTPUT=$(CONFIG_DIR="$EXT_TMP" _cclm_profile_resolve ollama-cyc-a 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "cycle exits 1"
assert_contains "$OUTPUT" "cycle" "cycle error mentions cycle"

# --- Cross-backend extends: forbidden -------------------------------------
cat > "$EXT_TMP/ollama-xback.json" <<'JSON'
{ "extends": "lms-something", "model": "x" }
JSON
OUTPUT=$(CONFIG_DIR="$EXT_TMP" _cclm_profile_resolve ollama-xback 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "cross-backend extends exits 1"
assert_contains "$OUTPUT" "cross-backend" "cross-backend error message"

# --- No extends: resolve returns the file JSON verbatim (extends-stripped)
cat > "$EXT_TMP/ollama-plain.json" <<'JSON'
{ "host": "localhost", "port": "11434", "model": "p", "context_length": 1024 }
JSON
PLAIN=$(CONFIG_DIR="$EXT_TMP" _cclm_profile_resolve ollama-plain)
PLAIN_MODEL=$(echo "$PLAIN" | jq -r '.model')
assert_eq "p" "$PLAIN_MODEL" "no-extends profile resolves to itself"

# --- cmd_profile resolve subcommand: prints resolved JSON on stdout -------
RSUB=$(CONFIG_DIR="$EXT_TMP" cmd_profile resolve ollama-big)
EXIT=$?
assert_exit 0 "$EXIT" "cmd_profile resolve exits 0"
RSUB_CTX=$(echo "$RSUB" | jq -r '.context_length')
assert_eq "262144" "$RSUB_CTX" "cmd_profile resolve emits merged JSON"

# --- cmd_profile resolve with bad prefix exits 1 --------------------------
OUTPUT=$(CONFIG_DIR="$EXT_TMP" cmd_profile resolve bogus-slug 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "cmd_profile resolve rejects bad prefix"

# --- Cleanup --------------------------------------------------------------
rm -rf "$EXT_TMP"
unset EXT_TMP RESOLVED EXIT CTX HOST PO CO EXT BY_SLUG BY_PATH OUTPUT PLAIN PLAIN_MODEL RSUB RSUB_CTX
