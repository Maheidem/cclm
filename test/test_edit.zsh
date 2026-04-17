start_test "cmd_edit"

# cmd_edit must be defined above the CCLM_LIB_ONLY guard.
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f cmd_edit > /dev/null 2>&1; then
  _fail "cmd_edit function not defined"
fi

# ---- sandbox: scratch CONFIG_DIR populated with fixture profiles ---------
EDIT_TMP=$(mktemp -d)
cat > "$EDIT_TMP/ollama-edit-test.json" <<'JSON'
{
  "host": "localhost",
  "port": "11434",
  "model": "llama3.2",
  "context_length": 128000
}
JSON

cat > "$EDIT_TMP/llama-edit-test.json" <<'JSON'
{
  "model": "Qwen3-7B",
  "model_path": "/models/qwen.gguf",
  "ctx_len": "131072",
  "gpu_layers": "99",
  "flash_attn": "on",
  "cache_type_k": "q8_0",
  "cache_type_v": "q8_0",
  "swa_full": "true",
  "batch_size": "4096",
  "ubatch_size": "1024",
  "temperature": "0.6",
  "top_p": "0.95",
  "top_k": "20",
  "min_p": "0.00",
  "repeat_penalty": "1.0",
  "port": "8081",
  "parallel_slots": "1",
  "slot_save_path": null
}
JSON

# --- Direct-mode edit: by jq-key, pipe the new value on stdin -------------
# `ask` reads from stdin; the " " default fallback is irrelevant because we
# pass a non-empty value. Capture stderr so we can assert on status messages.
CONFIG_DIR="$EDIT_TMP" cmd_edit ollama-edit-test model <<< "llama3.3" >/dev/null 2>&1
EXIT=$?
assert_exit 0 "$EXIT" "direct-mode edit exits 0"

NEW_MODEL=$(jq -r '.model' "$EDIT_TMP/ollama-edit-test.json")
assert_eq "llama3.3" "$NEW_MODEL" "model field updated to new value"

# Other fields preserved exactly (incl. numeric ctx stays a number).
UNCHANGED_HOST=$(jq -r '.host' "$EDIT_TMP/ollama-edit-test.json")
assert_eq "localhost" "$UNCHANGED_HOST" "host field preserved"

UNCHANGED_PORT=$(jq -r '.port' "$EDIT_TMP/ollama-edit-test.json")
assert_eq "11434" "$UNCHANGED_PORT" "port field preserved"

# jq reports "number" for integers — verifies we used --argjson, not --arg,
# so the original numeric type survived the merge even though we only edited
# a different (string) field.
CTX_TYPE=$(jq -r '.context_length | type' "$EDIT_TMP/ollama-edit-test.json")
assert_eq "number" "$CTX_TYPE" "numeric context_length type preserved"

# --- Direct-mode edit: numeric field, type-preserved via --argjson --------
CONFIG_DIR="$EDIT_TMP" cmd_edit ollama-edit-test context_length <<< "65536" >/dev/null 2>&1
EXIT=$?
assert_exit 0 "$EXIT" "edit of numeric field exits 0"
NEW_CTX=$(jq -r '.context_length' "$EDIT_TMP/ollama-edit-test.json")
assert_eq "65536" "$NEW_CTX" "context_length updated"
NEW_CTX_TYPE=$(jq -r '.context_length | type' "$EDIT_TMP/ollama-edit-test.json")
assert_eq "number" "$NEW_CTX_TYPE" "numeric type preserved across direct edit"

# --- Label-substring match ("Host" label matches "host" key too — unique) -
CONFIG_DIR="$EDIT_TMP" cmd_edit ollama-edit-test Host <<< "192.168.1.50" >/dev/null 2>&1
EXIT=$?
assert_exit 0 "$EXIT" "label-substring match resolves to unique field"
NEW_HOST=$(jq -r '.host' "$EDIT_TMP/ollama-edit-test.json")
assert_eq "192.168.1.50" "$NEW_HOST" "host updated via label match"

# --- Error: missing profile -> exit 1 -------------------------------------
OUTPUT=$(CONFIG_DIR="$EDIT_TMP" cmd_edit ollama-does-not-exist model <<< "x" 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "missing profile exits 1"
assert_contains "$OUTPUT" "profile not found" "missing-profile error message"

# --- Error: unknown backend prefix ----------------------------------------
OUTPUT=$(CONFIG_DIR="$EDIT_TMP" cmd_edit bogus-thing model <<< "x" 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "unknown prefix exits 1"
assert_contains "$OUTPUT" "unknown backend prefix" "unknown-prefix error message"

# --- Error: ambiguous field -----------------------------------------------
# llama schema has both `cache_type_k` and `cache_type_v` — substring
# "cache_type" is a shared substring and no exact key matches, so it must
# be rejected as ambiguous.
OUTPUT=$(CONFIG_DIR="$EDIT_TMP" cmd_edit llama-edit-test cache_type <<< "x" 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "ambiguous field exits 1"
assert_contains "$OUTPUT" "ambiguous" "ambiguity error message"
assert_contains "$OUTPUT" "cache_type_k" "candidate cache_type_k listed"
assert_contains "$OUTPUT" "cache_type_v" "candidate cache_type_v listed"

# --- Error: no-match field ------------------------------------------------
OUTPUT=$(CONFIG_DIR="$EDIT_TMP" cmd_edit ollama-edit-test nonexistentfield <<< "x" 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "no-match field exits 1"
assert_contains "$OUTPUT" "no field matches" "no-match error message"

# --- Null-field preservation: empty input keeps null ----------------------
# llama fixture has slot_save_path=null. Edit with empty input → stays null.
CONFIG_DIR="$EDIT_TMP" cmd_edit llama-edit-test slot_save_path <<< "" >/dev/null 2>&1
EXIT=$?
assert_exit 0 "$EXIT" "edit null field with empty input exits 0"
NULL_TYPE=$(jq -r '.slot_save_path | type' "$EDIT_TMP/llama-edit-test.json")
assert_eq "null" "$NULL_TYPE" "null field stays null when new input is empty"

# --- Cleanup --------------------------------------------------------------
rm -rf "$EDIT_TMP"
unset EDIT_TMP NEW_MODEL UNCHANGED_HOST UNCHANGED_PORT CTX_TYPE NEW_CTX \
      NEW_CTX_TYPE NEW_HOST NULL_TYPE OUTPUT EXIT
