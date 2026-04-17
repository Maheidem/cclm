start_test "golden_schema"

NEW_DIR=$(mktemp -d)
FIX="$TEST_DIR/fixtures"
GOLDEN="$TEST_DIR/golden"

compare_schema() {
  local name="$1" profile="$2" schema_var="$3"
  local actual="$NEW_DIR/${name}.txt"
  local schema_val=("${(@P)schema_var}")
  echo n | schema_display "$profile" "${schema_val[@]}" > /dev/null 2> "$actual"
  if diff -q "$GOLDEN/${name}.txt" "$actual" >/dev/null 2>&1; then
    ASSERTIONS=$((ASSERTIONS + 1))
  else
    FAILURES=$((FAILURES + 1))
    ASSERTIONS=$((ASSERTIONS + 1))
    echo "  FAIL [golden_schema]: $name differs from golden" >&2
    diff -u "$GOLDEN/${name}.txt" "$actual" | head -10 >&2
  fi
}

compare_schema "lms_inner"   "$FIX/lms-test.json"   LMS_PROFILE_SCHEMA_BRIEF
compare_schema "lms_outer"   "$FIX/lms-test.json"   LMS_PROFILE_SCHEMA
compare_schema "llama_inner" "$FIX/llama-test.json" LLAMA_PROFILE_SCHEMA_WITH_PATH
compare_schema "llama_outer" "$FIX/llama-test.json" LLAMA_PROFILE_SCHEMA
compare_schema "zai"         "$FIX/zai-test.json"   ZAI_PROFILE_SCHEMA

rm -rf "$NEW_DIR"
