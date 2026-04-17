start_test "cmd_log_basics"

# Sandbox: override SESSION_LOG_DIR/FILE for the whole test (cmd_log reads
# these globals). Preserve the real values so the user's log isn't touched.
_ORIG_LOG_DIR="${SESSION_LOG_DIR:-}"
_ORIG_LOG_FILE="${SESSION_LOG_FILE:-}"
_LOG_TMP="$(mktemp -d)"
SESSION_LOG_DIR="$_LOG_TMP"
SESSION_LOG_FILE="$_LOG_TMP/sessions.log"

# --- Empty-log behavior ---------------------------------------------------
# No file yet — cmd_log must print the friendly message and exit 0.
OUTPUT=$(cmd_log 2>&1)
EXIT=$?
assert_exit 0 "$EXIT" "empty-log exits 0"
assert_contains "$OUTPUT" "No sessions logged yet." "empty-log prints friendly message"

# --- Fixture: 5 entries across two profiles, spanning ~40 days ------------
# Write JSONL directly so the test doesn't depend on launch_claude internals.
# Dates are ISO-8601 UTC (the same format log_session writes).
# We use old dates for most and a fresh "today" for the last one so --last
# filtering has something to exercise.
TODAY_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$SESSION_LOG_FILE" <<EOF
{"ts_start":"2026-03-01T09:00:00Z","backend":"llama","profile_basename":"llama-qwen3.json","host":"localhost","model":"qwen3","pid":111}
{"ts_start":"2026-03-15T10:00:00Z","backend":"lms","profile_basename":"lms-gemma.json","host":"localhost","model":"gemma","pid":222}
{"ts_start":"2026-04-01T11:00:00Z","backend":"zai","profile_basename":"zai-glm46.json","host":"https://api.z.ai","model":"glm-4.6","pid":333}
{"ts_start":"2026-04-10T12:00:00Z","backend":"llama","profile_basename":"llama-qwen3.json","host":"192.168.1.50","model":"qwen3","pid":444}
{"ts_start":"${TODAY_ISO}","backend":"remote","profile_basename":"remote-anthropic.json","host":"10.0.0.5","model":"claude-sonnet","pid":555}
EOF

# --- Default table output -------------------------------------------------
OUTPUT=$(cmd_log 2>&1)
assert_contains "$OUTPUT" "TIMESTAMP" "default output has header row"
assert_contains "$OUTPUT" "llama-qwen3.json" "default output includes first profile"
assert_contains "$OUTPUT" "zai-glm46.json" "default output includes zai profile"
assert_contains "$OUTPUT" "remote-anthropic.json" "default output includes today's entry"
assert_contains "$OUTPUT" "glm-4.6" "default output includes model name"

# --- --profile filter narrows to matching basenames -----------------------
OUTPUT=$(cmd_log --profile qwen3 2>&1)
assert_contains "$OUTPUT" "llama-qwen3.json" "profile filter keeps matching entries"
assert_not_contains "$OUTPUT" "lms-gemma.json" "profile filter drops non-matching entries"
assert_not_contains "$OUTPUT" "zai-glm46.json" "profile filter drops zai entry"

# --- --json dumps raw JSONL (filtered by --profile) -----------------------
OUTPUT=$(cmd_log --profile gemma --json 2>&1)
assert_contains "$OUTPUT" "\"profile_basename\":\"lms-gemma.json\"" "--json dumps raw JSONL with matching profile"
assert_not_contains "$OUTPUT" "qwen3" "--json + --profile filters out non-matches"

# --- --last Nd filter narrows by date -------------------------------------
# Our fixture's oldest entry is 2026-03-01; today's entry is TODAY.
# --last 1d must include today's entry and drop the 2026-03-01 entry.
OUTPUT=$(cmd_log --last 1d 2>&1)
assert_contains "$OUTPUT" "remote-anthropic.json" "--last 1d keeps today's entry"
assert_not_contains "$OUTPUT" "2026-03-01" "--last 1d drops old entry"

# --- Bad --last format is rejected ----------------------------------------
OUTPUT=$(cmd_log --last bogus 2>&1)
EXIT=$?
ASSERTIONS=$((ASSERTIONS + 1))
if (( EXIT == 0 )); then
  _fail "cmd_log --last bogus should exit non-zero"
fi
assert_contains "$OUTPUT" "--last must look like" "bad --last prints usage hint"

# --- Cleanup --------------------------------------------------------------
rm -rf "$_LOG_TMP"
SESSION_LOG_DIR="$_ORIG_LOG_DIR"
SESSION_LOG_FILE="$_ORIG_LOG_FILE"
unset _ORIG_LOG_DIR _ORIG_LOG_FILE _LOG_TMP TODAY_ISO
