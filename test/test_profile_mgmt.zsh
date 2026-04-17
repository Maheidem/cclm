start_test "cmd_profile"

# cmd_profile must be defined above the CCLM_LIB_ONLY guard.
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f cmd_profile > /dev/null 2>&1; then
  _fail "cmd_profile function not defined"
fi

# ---- sandbox: scratch CONFIG_DIR populated with fixture profiles ---------
PM_TMP=$(mktemp -d)
cat > "$PM_TMP/lms-pm-src.json" <<'JSON'
{
  "model": "pm-source",
  "context_length": 65536,
  "gpu": "max",
  "parallel": 1,
  "ttl": 3600,
  "identifier": "pm-source@q8",
  "remote_host": null
}
JSON
cat > "$PM_TMP/ollama-pm-src.json" <<'JSON'
{
  "host": "localhost",
  "port": "11434",
  "model": "pm-ollama",
  "context_length": 128000
}
JSON

# --- list: both slugs visible, grouped by backend -------------------------
LIST_OUT=$(CONFIG_DIR="$PM_TMP" cmd_profile list 2>&1)
assert_contains "$LIST_OUT" "lms-pm-src"    "list shows lms profile"
assert_contains "$LIST_OUT" "ollama-pm-src" "list shows ollama profile"
assert_contains "$LIST_OUT" "[lms]"         "list groups by backend"

# --- clone: produces byte-identical copy at new slug ----------------------
CONFIG_DIR="$PM_TMP" cmd_profile clone lms-pm-src lms-pm-clone >/dev/null 2>&1
EXIT=$?
assert_exit 0 "$EXIT" "clone exits 0 on success"
assert_file_exists "$PM_TMP/lms-pm-clone.json" "clone dst file exists"
ASSERTIONS=$((ASSERTIONS + 1))
if ! diff -q "$PM_TMP/lms-pm-src.json" "$PM_TMP/lms-pm-clone.json" >/dev/null 2>&1; then
  _fail "clone contents differ from source"
fi
# Source must survive the clone.
assert_file_exists "$PM_TMP/lms-pm-src.json" "clone leaves source intact"

# --- clone: refuses existing destination ---------------------------------
OUTPUT=$(CONFIG_DIR="$PM_TMP" cmd_profile clone lms-pm-src lms-pm-clone 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "clone refuses overwrite"
assert_contains "$OUTPUT" "already exists" "clone-overwrite error message"

# --- clone: rejects missing source (exit 1) ------------------------------
OUTPUT=$(CONFIG_DIR="$PM_TMP" cmd_profile clone lms-nope lms-pm-clone2 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "clone with missing source exits 1"
assert_contains "$OUTPUT" "source profile not found" "clone missing-source message"

# --- clone: rejects invalid dst prefix (exit 1) --------------------------
OUTPUT=$(CONFIG_DIR="$PM_TMP" cmd_profile clone lms-pm-src bogus-thing 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "clone with invalid dst prefix exits 1"
assert_contains "$OUTPUT" "unknown backend prefix" "clone invalid-prefix message"

# --- clone: rejects cross-backend clone (exit 1) -------------------------
OUTPUT=$(CONFIG_DIR="$PM_TMP" cmd_profile clone lms-pm-src ollama-pm-xbackend 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "cross-backend clone exits 1"
assert_contains "$OUTPUT" "prefix mismatch" "clone cross-backend error"

# --- rename: old gone, new present, contents preserved -------------------
CONFIG_DIR="$PM_TMP" cmd_profile rename lms-pm-clone lms-pm-renamed >/dev/null 2>&1
EXIT=$?
assert_exit 0 "$EXIT" "rename exits 0 on success"
assert_file_exists "$PM_TMP/lms-pm-renamed.json" "rename dst file exists"
ASSERTIONS=$((ASSERTIONS + 1))
if [[ -f "$PM_TMP/lms-pm-clone.json" ]]; then
  _fail "rename did not remove old file"
fi

# --- rename: rejects missing source --------------------------------------
OUTPUT=$(CONFIG_DIR="$PM_TMP" cmd_profile rename lms-nope lms-pm-foo 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "rename with missing source exits 1"
assert_contains "$OUTPUT" "source profile not found" "rename missing-source message"

# --- delete with FORCE=1: no prompt, file gone ---------------------------
FORCE=1 CONFIG_DIR="$PM_TMP" cmd_profile delete lms-pm-renamed >/dev/null 2>&1
EXIT=$?
assert_exit 0 "$EXIT" "delete with FORCE=1 exits 0"
ASSERTIONS=$((ASSERTIONS + 1))
if [[ -f "$PM_TMP/lms-pm-renamed.json" ]]; then
  _fail "delete with FORCE=1 did not remove file"
fi

# --- delete: declined prompt keeps file, returns 0 -----------------------
OUTPUT=$(CONFIG_DIR="$PM_TMP" cmd_profile delete lms-pm-src <<< "n" 2>&1)
EXIT=$?
assert_exit 0 "$EXIT" "delete declined prompt is not a failure (exit 0)"
assert_contains "$OUTPUT" "Cancelled" "delete declined prints Cancelled"
assert_file_exists "$PM_TMP/lms-pm-src.json" "declined delete preserves file"

# --- delete: missing slug exits 1 ----------------------------------------
OUTPUT=$(FORCE=1 CONFIG_DIR="$PM_TMP" cmd_profile delete lms-nope 2>&1)
EXIT=$?
assert_exit 1 "$EXIT" "delete of missing profile exits 1"
assert_contains "$OUTPUT" "profile not found" "delete missing profile message"

# --- unknown subcommand returns 2 ----------------------------------------
OUTPUT=$(CONFIG_DIR="$PM_TMP" cmd_profile frobnicate foo 2>&1)
EXIT=$?
assert_exit 2 "$EXIT" "unknown subcommand exits 2"
assert_contains "$OUTPUT" "unknown subcommand" "unknown-subcommand message"

# --- Cleanup --------------------------------------------------------------
rm -rf "$PM_TMP"
unset PM_TMP LIST_OUT OUTPUT EXIT
