start_test "vllm_backend"

# Schema array is declared and populated
assert_eq 4 ${#VLLM_PROFILE_SCHEMA[@]} "VLLM_PROFILE_SCHEMA has 4 field specs"
ASSERTIONS=$((ASSERTIONS + 1))
if [[ -z "${VLLM_PROFILE_SCHEMA[1]:-}" ]]; then
  _fail "VLLM_PROFILE_SCHEMA first entry unexpectedly empty"
fi

# run_vllm function must be sourced
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f run_vllm > /dev/null 2>&1; then
  _fail "run_vllm function not defined"
fi

# schema_display against fixture — verify all four fields appear with values
PROFILE="$TEST_DIR/fixtures/vllm-test.json"
OUTPUT=$(echo n | schema_display "$PROFILE" "${VLLM_PROFILE_SCHEMA[@]}" 2>&1)
assert_contains "$OUTPUT" "Host:" "Host label rendered"
assert_contains "$OUTPUT" "localhost" "Host value (localhost) rendered"
assert_contains "$OUTPUT" "Port:" "Port label rendered"
assert_contains "$OUTPUT" "8000" "Port value (8000) rendered"
assert_contains "$OUTPUT" "Model:" "Model label rendered"
assert_contains "$OUTPUT" "Llama-3.1-8B-Instruct" "Model value rendered"
assert_contains "$OUTPUT" "Context length:" "Context length label rendered"
assert_contains "$OUTPUT" "131072" "Context length value rendered"
