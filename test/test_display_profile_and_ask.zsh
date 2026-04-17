start_test "display_profile_and_ask"

PROFILE="$TEST_DIR/fixtures/llama-test.json"

# accept on "y"
OUTPUT=$(echo y | display_profile_and_ask "$PROFILE" \
  "Context length|.ctx_len|Loading" \
  "GPU layers|.gpu_layers|Loading" \
  "Temperature|.temperature|Sampling" 2>&1)
assert_exit 0 $? "returns 0 on y"
assert_contains "$OUTPUT" "Loading:" "emits Loading group"
assert_contains "$OUTPUT" "Sampling:" "emits Sampling group"
assert_contains "$OUTPUT" "131072" "emits ctx_len value"
assert_contains "$OUTPUT" "0.7" "emits temperature value"
assert_not_contains "$OUTPUT" "Loading::" "no double-colon artifact from old bug"

# reject on "n"
RC=0
echo n | display_profile_and_ask "$PROFILE" "Context length|.ctx_len|Loading" > /dev/null 2>&1 || RC=$?
assert_exit 1 $RC "returns 1 on n"

# missing file
RC=0
display_profile_and_ask "/nonexistent/profile.json" "Context length|.ctx_len" > /dev/null 2>&1 || RC=$?
assert_exit 1 $RC "returns 1 on missing file"

# edit mode skips
RC=0
EDIT_MODE=true display_profile_and_ask "$PROFILE" "Context length|.ctx_len" > /dev/null 2>&1 || RC=$?
assert_exit 1 $RC "returns 1 in EDIT_MODE"
