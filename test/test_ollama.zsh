start_test "ollama_backend"

# Schema array is declared and populated
assert_eq 4 ${#OLLAMA_PROFILE_SCHEMA[@]} "OLLAMA_PROFILE_SCHEMA has 4 field specs"
ASSERTIONS=$((ASSERTIONS + 1))
if [[ -z "${OLLAMA_PROFILE_SCHEMA[1]:-}" ]]; then
  _fail "OLLAMA_PROFILE_SCHEMA first entry unexpectedly empty"
fi

# run_ollama function must be sourced
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f run_ollama > /dev/null 2>&1; then
  _fail "run_ollama function not defined"
fi

# schema_display against fixture — verify all four fields appear with values
PROFILE="$TEST_DIR/fixtures/ollama-test.json"
OUTPUT=$(echo n | schema_display "$PROFILE" "${OLLAMA_PROFILE_SCHEMA[@]}" 2>&1)
assert_contains "$OUTPUT" "Host:" "Host label rendered"
assert_contains "$OUTPUT" "localhost" "Host value (localhost) rendered"
assert_contains "$OUTPUT" "Port:" "Port label rendered"
assert_contains "$OUTPUT" "11434" "Port value (11434) rendered"
assert_contains "$OUTPUT" "Model:" "Model label rendered"
assert_contains "$OUTPUT" "llama3.2" "Model value (llama3.2) rendered"
assert_contains "$OUTPUT" "Context length:" "Context length label rendered"
assert_contains "$OUTPUT" "128000" "Context length value rendered"
