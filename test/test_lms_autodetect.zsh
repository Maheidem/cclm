start_test "lms_autodetect_detect_loaded_empty"
# When `lms ps` returns empty (nothing loaded), both extracted values are
# empty strings — callers treat this as "no model loaded" and behave as
# before. Stub `lms` so the helper sees "[]" via stdout.
lms() { echo "[]"; }

_OUT=$(_cclm_lms_detect_loaded)
_MK="${_OUT%%$'\t'*}"
_KEY="${_OUT##*$'\t'}"
_KEY="${_KEY%$'\n'}"

assert_eq "" "$_MK" "modelKey empty when lms ps returns []"
assert_eq "" "$_KEY" "identifier-preferred empty when lms ps returns []"

unfunction lms

start_test "lms_autodetect_detect_loaded_identifier_preferred"
# When `lms ps` reports both modelKey and a non-null identifier, the
# identifier-preferred key equals the identifier; modelKey stays for list
# matching. This mirrors the api_id resolution further down in run_lms.
lms() {
  echo '[{"modelKey":"meta/llama-3.1-8b","identifier":"my-custom-id"}]'
}
_OUT2=$(_cclm_lms_detect_loaded)
_MK2="${_OUT2%%$'\t'*}"
_KEY2="${_OUT2##*$'\t'}"
_KEY2="${_KEY2%$'\n'}"

assert_eq "meta/llama-3.1-8b" "$_MK2" "modelKey preserved as-is (with /)"
assert_eq "my-custom-id" "$_KEY2" "identifier preferred over modelKey"

unfunction lms

start_test "lms_autodetect_detect_loaded_null_identifier"
# identifier == null → fall back to modelKey for the key field.
lms() { echo '[{"modelKey":"qwen/qwen3-coder-30b","identifier":null}]'; }
_OUT3=$(_cclm_lms_detect_loaded)
_KEY3="${_OUT3##*$'\t'}"
_KEY3="${_KEY3%$'\n'}"

assert_eq "qwen/qwen3-coder-30b" "$_KEY3" "null identifier falls back to modelKey (slash preserved)"

unfunction lms

# -- Picker rendering tests -------------------------------------------------
#
# Sandbox CONFIG_DIR so profile-lookup side effects (the " *" saved tag and
# the default_idx branch) don't leak into/from the real user config. Restore
# afterward.
_AUTODETECT_TMP=$(mktemp -d)
_AUTODETECT_OLD_CONFIG="$CONFIG_DIR"
export CONFIG_DIR="$_AUTODETECT_TMP"

_MODELS_JSON='[
  {"modelKey":"qwen/qwen3-coder-30b","displayName":"Qwen3 Coder 30B","paramsString":"30B","maxContextLength":131072,"trainedForToolUse":true},
  {"modelKey":"meta/llama-3.1-8b","displayName":"Llama 3.1 8B","paramsString":"8B","maxContextLength":32768,"trainedForToolUse":false}
]'

start_test "lms_autodetect_picker_synthetic_when_no_profile"
# Loaded model has no saved profile → synthetic "0)" prepended; prompt
# range is 0-N; default_idx returned as 0 (no Enter-picks-default hint).
OUTPUT1=$(_cclm_lms_render_model_picker "$_MODELS_JSON" "qwen/qwen3-coder-30b" "qwen/qwen3-coder-30b" 2>&1 >/dev/null)
STDOUT1=$(_cclm_lms_render_model_picker "$_MODELS_JSON" "qwen/qwen3-coder-30b" "qwen/qwen3-coder-30b" 2>/dev/null)

assert_contains "$OUTPUT1" "0) Use currently-loaded model: qwen/qwen3-coder-30b" "synthetic option uses loaded_key verbatim, slashes preserved"
assert_contains "$OUTPUT1" "[LOADED]" "existing [LOADED] marker still rendered against matching list entry"
assert_contains "$OUTPUT1" "Select model (0-2)" "prompt range includes synthetic option"
assert_contains "$OUTPUT1" "Qwen3 Coder 30B" "list entry rendered"
# stdout side-channel: "default_idx\tshow_synthetic\tcount"
assert_eq "0	true	2" "${STDOUT1%$'\n'}" "picker stdout: no default, synthetic shown, 2 entries"

start_test "lms_autodetect_picker_default_when_profile_exists"
# Loaded model HAS a saved profile → no synthetic, but default_idx points
# at the matching list entry and prompt shows "[N]" hint.
echo '{"model":"qwen/qwen3-coder-30b","context_length":"65536","gpu":"max","parallel":"1","ttl":null,"identifier":null,"remote_host":null}' \
  > "$CONFIG_DIR/lms-qwen_qwen3-coder-30b.json"

OUTPUT2=$(_cclm_lms_render_model_picker "$_MODELS_JSON" "qwen/qwen3-coder-30b" "qwen/qwen3-coder-30b" 2>&1 >/dev/null)
STDOUT2=$(_cclm_lms_render_model_picker "$_MODELS_JSON" "qwen/qwen3-coder-30b" "qwen/qwen3-coder-30b" 2>/dev/null)

assert_contains "$OUTPUT2" "[LOADED]" "loaded marker present"
assert_contains "$OUTPUT2" "Select model (1-2) [1]:" "default index hint shown — Enter picks the loaded model"
assert_not_contains "$OUTPUT2" "0) Use currently-loaded model:" "synthetic suppressed when profile exists"
assert_eq "1	false	2" "${STDOUT2%$'\n'}" "picker stdout: default_idx=1, no synthetic, 2 entries"

rm -f "$CONFIG_DIR/lms-qwen_qwen3-coder-30b.json"

start_test "lms_autodetect_picker_no_loaded_model_unchanged"
# Nothing loaded (both args empty) → prompt unchanged, no synthetic, no hint.
# Exactly matches the pre-change picker UX.
OUTPUT3=$(_cclm_lms_render_model_picker "$_MODELS_JSON" "" "" 2>&1 >/dev/null)
STDOUT3=$(_cclm_lms_render_model_picker "$_MODELS_JSON" "" "" 2>/dev/null)

assert_not_contains "$OUTPUT3" "0) Use currently-loaded model:" "no synthetic when nothing loaded"
assert_not_contains "$OUTPUT3" "[LOADED]" "no loaded marker when nothing loaded"
assert_contains "$OUTPUT3" "Select model (1-2):" "prompt unchanged (no hint, range 1-N)"
assert_eq "0	false	2" "${STDOUT3%$'\n'}" "picker stdout: no default, no synthetic"

# Teardown
export CONFIG_DIR="$_AUTODETECT_OLD_CONFIG"
rm -rf "$_AUTODETECT_TMP"
unset _AUTODETECT_TMP _AUTODETECT_OLD_CONFIG _MODELS_JSON \
      _OUT _OUT2 _OUT3 _MK _MK2 _KEY _KEY2 _KEY3 \
      OUTPUT1 OUTPUT2 OUTPUT3 STDOUT1 STDOUT2 STDOUT3
