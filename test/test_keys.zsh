start_test "cclm_keys"

# ---------------------------------------------------------------------------
# Verify the `cclm keys` surface:
#   - _cclm_get_key resolution order: keychain -> env var -> file -> empty
#   - cmd_keys add/get/list/remove round-trip via a stubbed `security` shim
# The shim fakes macOS Keychain by reading/writing a local JSONL-ish file, so
# this test is deterministic on Linux/CI too.
# ---------------------------------------------------------------------------

# All key functions must be defined above the CCLM_LIB_ONLY guard.
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f cmd_keys > /dev/null 2>&1; then
  _fail "cmd_keys function not defined"
fi

ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f _cclm_get_key > /dev/null 2>&1; then
  _fail "_cclm_get_key helper not defined"
fi

ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f _cclm_keys_backend > /dev/null 2>&1; then
  _fail "_cclm_keys_backend helper not defined"
fi

# --- Sandbox -------------------------------------------------------------
# Per-test CONFIG_DIR so file-fallback writes don't touch the user's store,
# and PATH shim so `security` is our stub (not the real macOS binary).
KEYS_TMP=$(mktemp -d)
KEYS_SHIM_DIR="$KEYS_TMP/bin"
KEYS_STORE="$KEYS_TMP/keychain.tsv"
mkdir -p "$KEYS_SHIM_DIR"
: > "$KEYS_STORE"

# Save originals so we can restore at teardown.
_ORIG_CONFIG_DIR="$CONFIG_DIR"
_ORIG_PATH="$PATH"
_ORIG_ZAI_API_KEY="${ZAI_API_KEY:-__UNSET__}"
# Start clean — backend should prefer the keychain, not an inherited env var.
unset ZAI_API_KEY 2>/dev/null || true
CONFIG_DIR="$KEYS_TMP/config"
mkdir -p "$CONFIG_DIR"

# Stub for macOS `security`. Implements the three subcommands we call:
#   add-generic-password -a $USER -s cclm-<name> -w <secret> -U
#   find-generic-password -a $USER -s cclm-<name> -w
#   delete-generic-password -a $USER -s cclm-<name>
# Storage is a TSV: service<TAB>secret, one per line. -U replaces the row.
cat > "$KEYS_SHIM_DIR/security" <<'STUB'
#!/usr/bin/env zsh
set -u
store="${KEYS_STORE:?KEYS_STORE must be set by test}"
sub="$1"; shift
svc="" pw=""
while (( $# )); do
  case "$1" in
    -s) svc="$2"; shift 2 ;;
    -w) if [[ "$sub" == "add-generic-password" ]]; then pw="$2"; shift 2; else shift 1; fi ;;
    -a|-U) shift ;;
    *)  shift ;;
  esac
done
case "$sub" in
  add-generic-password)
    # Replace existing row (simulates -U upsert).
    tmp=$(mktemp)
    grep -v "^${svc}	" "$store" > "$tmp" 2>/dev/null || true
    printf '%s\t%s\n' "$svc" "$pw" >> "$tmp"
    mv "$tmp" "$store"
    exit 0
    ;;
  find-generic-password)
    row=$(grep "^${svc}	" "$store" 2>/dev/null | head -1)
    [[ -z "$row" ]] && exit 1
    printf '%s' "${row#*	}"
    exit 0
    ;;
  delete-generic-password)
    grep -q "^${svc}	" "$store" 2>/dev/null || exit 1
    tmp=$(mktemp)
    grep -v "^${svc}	" "$store" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$store"
    exit 0
    ;;
  dump-keychain)
    # Emit svce lines in the exact format _cclm_keys_list greps for.
    while IFS=$'\t' read -r s _; do
      [[ -z "$s" ]] && continue
      printf '    "svce"<blob>="%s"\n' "$s"
    done < "$store"
    exit 0
    ;;
esac
exit 0
STUB
chmod +x "$KEYS_SHIM_DIR/security"
export KEYS_STORE
# Ensure secret-tool is NOT picked up (shim dir first; remove from real PATH).
# We build a minimal PATH: shim + coreutils needed by cclm (grep, sed, awk, jq,
# mktemp, mv, rm, chmod, cat, mkdir, ls). Rather than enumerate, prepend shim
# and mask `secret-tool` via an empty-exit stub that advertises absence.
cat > "$KEYS_SHIM_DIR/secret-tool" <<'STUB'
#!/usr/bin/env zsh
# Stub that simulates secret-tool absence by returning non-zero without side
# effects. We only need this because the shim dir is PREPENDED; capability
# detection (command -v) would still find a real secret-tool further down.
exit 127
STUB
# Do NOT chmod +x the secret-tool stub — we want `command -v secret-tool` to
# miss it when the stub dir is earlier than a real install. Easiest way: make
# it non-executable so zsh's $+commands hash won't include it.
chmod -x "$KEYS_SHIM_DIR/secret-tool" 2>/dev/null || rm -f "$KEYS_SHIM_DIR/secret-tool"

PATH="$KEYS_SHIM_DIR:$PATH"
# Rehash so zsh picks up the `security` stub ahead of the system one.
rehash

# Sanity: $+commands[security] should resolve to our stub.
ASSERTIONS=$((ASSERTIONS + 1))
if [[ "$(command -v security 2>/dev/null)" != "$KEYS_SHIM_DIR/security" ]]; then
  _fail "stub 'security' not first on PATH (got '$(command -v security 2>/dev/null)')"
fi

# --- 1. Backend detection picks keychain ----------------------------------
ASSERTIONS=$((ASSERTIONS + 1))
_b="$(_cclm_keys_backend)"
if [[ "$_b" != "security" ]]; then
  _fail "backend picker should return 'security' when stub is on PATH (got '$_b')"
fi

# --- 2. add -> get round-trip via Keychain --------------------------------
# Drive cmd_keys add with stdin providing the secret (read -rs consumes it).
OUTPUT=$(printf 'supersecret123\n' | cmd_keys add zai 2>&1)
EXIT=$?
assert_exit 0 "$EXIT" "cmd_keys add zai exits 0"
assert_contains "$OUTPUT" "Stored 'zai' in macOS Keychain" "add prints success (stderr)"
assert_not_contains "$OUTPUT" "supersecret123" "add never echoes secret"

# Store file must now contain the row with the secret.
assert_contains "$(cat $KEYS_STORE)" "cclm-zai	supersecret123" "keychain store row persisted"

# get should print the secret on stdout.
OUTPUT=$(cmd_keys get zai 2>/dev/null)
assert_eq "supersecret123" "$OUTPUT" "cmd_keys get zai returns stored secret"

# _cclm_get_key (the internal helper used by run_zai) must agree.
assert_eq "supersecret123" "$(_cclm_get_key zai)" "_cclm_get_key zai matches stored secret"

# --- 3. list shows name only, never the value -----------------------------
OUTPUT=$(cmd_keys list 2>&1)
assert_contains "$OUTPUT" "zai" "list includes stored key name"
assert_not_contains "$OUTPUT" "supersecret123" "list NEVER shows secret value"

# --- 4. remove deletes from the keychain ----------------------------------
OUTPUT=$(cmd_keys remove zai 2>&1)
assert_exit 0 "$?" "cmd_keys remove zai exits 0"
assert_contains "$OUTPUT" "Removed 'zai'" "remove announces deletion"
assert_eq "" "$(_cclm_get_key zai)" "_cclm_get_key empty after remove"

# --- 5. Env-var fallback when keychain is empty ---------------------------
# With no keychain entry, _cclm_get_key must fall back to $ZAI_API_KEY.
export ZAI_API_KEY="env-fallback-key"
assert_eq "env-fallback-key" "$(_cclm_get_key zai)" "env-var fallback hit when keychain empty"
unset ZAI_API_KEY

# --- 6. File fallback when no credential store is available ---------------
# Force the "file" backend by overriding the picker. Snapshot the real body
# via `functions` so we can restore it in teardown (prevents subtle breakage
# if a later test is added that relies on the real helper).
_REAL_KEYS_BACKEND_BODY="$(typeset -f _cclm_keys_backend)"
_cclm_keys_backend() { echo file; }
ASSERTIONS=$((ASSERTIONS + 1))
_b2="$(_cclm_keys_backend)"
if [[ "$_b2" != "file" ]]; then
  _fail "backend picker override should return 'file' (got '$_b2')"
fi

# Write the key via add (file backend path) and verify perms + retrieval.
OUTPUT=$(printf 'file-only-key\n' | cmd_keys add zai 2>&1)
assert_exit 0 "$?" "file-backend add exits 0"
assert_contains "$OUTPUT" "no system credential store" "file-backend warns user"
assert_not_contains "$OUTPUT" "file-only-key" "file-backend never echoes secret"

FILE_PATH="$CONFIG_DIR/keys/zai"
assert_file_exists "$FILE_PATH" "file fallback wrote $FILE_PATH"

# Mode must be 600 (owner rw, nothing else). stat format differs BSD vs GNU.
FILE_MODE=$(stat -f '%A' "$FILE_PATH" 2>/dev/null || stat -c '%a' "$FILE_PATH" 2>/dev/null)
assert_eq "600" "$FILE_MODE" "file fallback permissions are 600"

assert_eq "file-only-key" "$(_cclm_get_key zai)" "_cclm_get_key reads file fallback"

# --- Cleanup --------------------------------------------------------------
PATH="$_ORIG_PATH"
rehash
rm -rf "$KEYS_TMP"
CONFIG_DIR="$_ORIG_CONFIG_DIR"
if [[ "$_ORIG_ZAI_API_KEY" == "__UNSET__" ]]; then
  unset ZAI_API_KEY 2>/dev/null || true
else
  export ZAI_API_KEY="$_ORIG_ZAI_API_KEY"
fi
# Restore the real _cclm_keys_backend body so later tests (or future additions)
# see the production helper, not our file-forcing override.
if [[ -n "$_REAL_KEYS_BACKEND_BODY" ]]; then
  eval "$_REAL_KEYS_BACKEND_BODY"
fi
unset KEYS_TMP KEYS_SHIM_DIR KEYS_STORE _ORIG_CONFIG_DIR _ORIG_PATH _ORIG_ZAI_API_KEY _REAL_KEYS_BACKEND_BODY _b _b2 OUTPUT EXIT FILE_PATH FILE_MODE
