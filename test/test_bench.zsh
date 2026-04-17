start_test "cmd_bench"

# cmd_bench must be defined above the CCLM_LIB_ONLY guard so we can source it.
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f cmd_bench > /dev/null 2>&1; then
  _fail "cmd_bench function not defined"
fi

ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f _cclm_bench_resolve > /dev/null 2>&1; then
  _fail "_cclm_bench_resolve helper not defined"
fi

ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f _cclm_bench_one_iter > /dev/null 2>&1; then
  _fail "_cclm_bench_one_iter helper not defined"
fi

# --- sandbox: fake CONFIG_DIR with three fixture profiles ----------------
BENCH_TMP=$(mktemp -d)
cat > "$BENCH_TMP/lms-bench.json" <<'JSON'
{
  "model": "qwen3-bench",
  "context_length": 65536,
  "gpu": "max",
  "parallel": 1,
  "ttl": 3600,
  "identifier": "qwen3-bench@q8",
  "remote_host": null
}
JSON
cat > "$BENCH_TMP/ollama-bench.json" <<'JSON'
{
  "host": "localhost",
  "port": "11434",
  "model": "llama3.2-bench",
  "context_length": "128000"
}
JSON
# zai profile MUST be skipped with a warning (Anthropic-native protocol).
cat > "$BENCH_TMP/zai-bench.json" <<'JSON'
{
  "base_url": "https://api.z.ai/api/anthropic",
  "opus_model": "glm-4.6",
  "sonnet_model": "glm-4.6",
  "haiku_model": "glm-4.5-air",
  "context_length": 200000,
  "api_timeout_ms": 3000000
}
JSON

# --- curl PATH shim: returns a canned OpenAI chat completion body ---------
BENCH_STUB_DIR=$(mktemp -d)
cat > "$BENCH_STUB_DIR/curl" <<'EOF'
#!/usr/bin/env zsh
# Stub curl: ignore all args, emit a deterministic chat completion response.
# Sleep briefly so the wallclock is > 0 (EPOCHREALTIME is float seconds).
sleep 0.05
cat <<JSON
{
  "id": "chatcmpl-stub",
  "object": "chat.completion",
  "choices": [{"index": 0, "message": {"role":"assistant","content":"canned"}, "finish_reason":"stop"}],
  "usage": {"prompt_tokens": 12, "completion_tokens": 42, "total_tokens": 54}
}
JSON
EOF
chmod +x "$BENCH_STUB_DIR/curl"

# --- smoke: --help exits 0, prints usage ---------------------------------
HELP_OUT=$(cmd_bench --help 2>&1)
HELP_RC=$?
assert_exit 0 "$HELP_RC" "bench --help exits 0"
assert_contains "$HELP_OUT" "Usage: cclm bench" "help text visible"
assert_contains "$HELP_OUT" "--iterations" "help mentions --iterations"

# --- dry-run: prints curl commands, no network calls required ------------
DRY_OUT=$(CONFIG_DIR="$BENCH_TMP" cmd_bench --dry-run 2>/dev/null)
DRY_RC=$?
assert_exit 0 "$DRY_RC" "bench --dry-run exits 0"
assert_contains "$DRY_OUT" "/v1/chat/completions" "dry-run prints chat-completions path"
assert_contains "$DRY_OUT" "lms-bench"             "dry-run shows lms-bench slug label"
assert_contains "$DRY_OUT" "ollama-bench"          "dry-run shows ollama-bench slug label"
assert_not_contains "$DRY_OUT" "zai-bench"         "dry-run skips zai profile"

# --- single iteration: stubbed curl returns canned JSON ------------------
BENCH_OUT=$(PATH="$BENCH_STUB_DIR:$PATH" CONFIG_DIR="$BENCH_TMP" cmd_bench 2>/dev/null)
BENCH_RC=$?
assert_exit 0 "$BENCH_RC" "bench exits 0 when profiles succeed"
assert_contains "$BENCH_OUT" "lms-bench"    "table row for lms-bench"
assert_contains "$BENCH_OUT" "ollama-bench" "table row for ollama-bench"
assert_contains "$BENCH_OUT" "12 |"         "prompt_tokens 12 surfaces in table"
assert_contains "$BENCH_OUT" "42 |"         "completion_tokens 42 surfaces in table"
assert_contains "$BENCH_OUT" "profile"      "markdown header row visible"

# Stderr warning fires for zai profile being skipped.
BENCH_STDERR=$(PATH="$BENCH_STUB_DIR:$PATH" CONFIG_DIR="$BENCH_TMP" cmd_bench 2>&1 >/dev/null)
assert_contains "$BENCH_STDERR" "Anthropic-native" "zai skip warning mentions Anthropic-native"
assert_contains "$BENCH_STDERR" "zai-bench"        "zai skip warning names the profile"

# --- --profiles filter: only the selected slug shows up ------------------
FILTERED_OUT=$(PATH="$BENCH_STUB_DIR:$PATH" CONFIG_DIR="$BENCH_TMP" cmd_bench --profiles lms-bench 2>/dev/null)
assert_contains "$FILTERED_OUT"     "lms-bench"    "--profiles filter includes lms-bench"
assert_not_contains "$FILTERED_OUT" "ollama-bench" "--profiles filter excludes ollama-bench"

# --- iterations > 1: per-iter rows plus a mean row -----------------------
ITER_OUT=$(PATH="$BENCH_STUB_DIR:$PATH" CONFIG_DIR="$BENCH_TMP" cmd_bench --profiles lms-bench --iterations 2 2>/dev/null)
ITER_RC=$?
assert_exit 0 "$ITER_RC" "bench --iterations=2 exits 0"
assert_contains "$ITER_OUT" "mean"  "mean row present when iterations > 1"
assert_contains "$ITER_OUT" "iter"  "per-iteration header present when iterations > 1"

# --- unreachable backend: curl stub returns non-zero -> single failure ---
# Bench must NOT hard-exit; it should log a warning and, if this is the only
# profile, return non-zero overall.
BENCH_FAIL_STUB=$(mktemp -d)
cat > "$BENCH_FAIL_STUB/curl" <<'EOF'
#!/usr/bin/env zsh
exit 7
EOF
chmod +x "$BENCH_FAIL_STUB/curl"

FAIL_OUT=$(PATH="$BENCH_FAIL_STUB:$PATH" CONFIG_DIR="$BENCH_TMP" cmd_bench --profiles lms-bench 2>&1)
FAIL_RC=$?
ASSERTIONS=$((ASSERTIONS + 1))
if (( FAIL_RC == 0 )); then
  _fail "bench should exit non-zero when all profiles fail"
fi
assert_contains "$FAIL_OUT" "curl failed" "failure warning surfaces on stderr"

# --- custom --prompt-file overrides the embedded default -----------------
PROMPT_FILE="$BENCH_TMP/custom-prompt.txt"
echo "ping" > "$PROMPT_FILE"
PROMPT_OUT=$(CONFIG_DIR="$BENCH_TMP" cmd_bench --profiles lms-bench --prompt-file "$PROMPT_FILE" --dry-run 2>/dev/null)
assert_contains "$PROMPT_OUT" "ping" "custom prompt-file contents appear in dry-run curl body"

# Nonexistent prompt-file -> non-zero, no noisy trace.
(CONFIG_DIR="$BENCH_TMP" cmd_bench --prompt-file /nope/not/here.txt --dry-run >/dev/null 2>&1)
NOPE_RC=$?
ASSERTIONS=$((ASSERTIONS + 1))
if (( NOPE_RC == 0 )); then
  _fail "bench should exit non-zero when --prompt-file is missing"
fi

# --- cleanup -------------------------------------------------------------
rm -rf "$BENCH_TMP" "$BENCH_STUB_DIR" "$BENCH_FAIL_STUB"
