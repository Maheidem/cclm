start_test "cmd_status"

# cmd_status must be defined above the CCLM_LIB_ONLY guard
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f cmd_status > /dev/null 2>&1; then
  _fail "cmd_status function not defined"
fi

# _cclm_probe helper must be present (exercised indirectly by cmd_status)
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f _cclm_probe > /dev/null 2>&1; then
  _fail "_cclm_probe helper not defined"
fi

# Build a scratch CONFIG_DIR with two fixture profiles. We override CONFIG_DIR
# in a subshell only — the harness-level tmpdir is left intact.
STATUS_TMP=$(mktemp -d)
cat > "$STATUS_TMP/lms-qwen3-status.json" <<'JSON'
{
  "model": "qwen3-status",
  "context_length": 65536,
  "gpu": "max",
  "parallel": 1,
  "ttl": 3600,
  "identifier": "qwen3-status@q8",
  "remote_host": null
}
JSON
cat > "$STATUS_TMP/ollama-llama32-status.json" <<'JSON'
{
  "host": "localhost",
  "port": "11434",
  "model": "llama3.2-status",
  "context_length": 128000
}
JSON

# Run cmd_status in a subshell with the scratch CONFIG_DIR. Merge stderr into
# stdout so we can assert on both section headers (stderr) and data (stdout).
# Short per-probe timeout means this completes in ~1s even when everything is
# DOWN.
STATUS_OUT=$(CONFIG_DIR="$STATUS_TMP" cmd_status 2>&1)

# Section headers
assert_contains "$STATUS_OUT" "Last session"                          "Last session header"
assert_contains "$STATUS_OUT" "Saved profiles (grouped by backend):"  "Saved profiles header"
assert_contains "$STATUS_OUT" "Backend reachability:"                 "Backend reachability header"

# Backend grouping tags
assert_contains "$STATUS_OUT" "[lms]"    "lms backend group tag"
assert_contains "$STATUS_OUT" "[ollama]" "ollama backend group tag"

# Profile slugs from our fixtures (prefix stripped, .json stripped)
assert_contains "$STATUS_OUT" "qwen3-status"        "lms profile slug visible"
assert_contains "$STATUS_OUT" "llama32-status"      "ollama profile slug visible"

# Context values surface in the per-profile summary line
assert_contains "$STATUS_OUT" "ctx:65536"   "lms ctx rendered"
assert_contains "$STATUS_OUT" "ctx:128000"  "ollama ctx rendered"

# UP/DOWN marker appears at least once (we never hard-fail on probe failure).
ASSERTIONS=$((ASSERTIONS + 1))
if [[ "$STATUS_OUT" != *"UP"* && "$STATUS_OUT" != *"DOWN"* ]]; then
  _fail "no UP/DOWN marker in cmd_status output"
fi

# Localhost defaults must always be probed even with no profiles referencing them.
assert_contains "$STATUS_OUT" "localhost:1234"  "LM Studio default endpoint probed"
assert_contains "$STATUS_OUT" "localhost:8081"  "llama.cpp default endpoint probed"
assert_contains "$STATUS_OUT" "localhost:11434" "Ollama default endpoint probed"

# cmd_status must exit 0 even when every backend is down.
ASSERTIONS=$((ASSERTIONS + 1))
(CONFIG_DIR="$STATUS_TMP" cmd_status >/dev/null 2>&1)
if (( $? != 0 )); then
  _fail "cmd_status returned non-zero when backends are down"
fi

# Stderr/stdout split: with stderr discarded, data rows (profile slugs) must
# remain on stdout so `cclm status | grep` is useful.
STATUS_STDOUT=$(CONFIG_DIR="$STATUS_TMP" cmd_status 2>/dev/null)
assert_contains "$STATUS_STDOUT" "qwen3-status"   "profile slug on stdout (pipe-safe)"
assert_contains "$STATUS_STDOUT" "llama32-status" "ollama slug on stdout (pipe-safe)"

rm -rf "$STATUS_TMP"
