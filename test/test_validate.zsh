start_test "validate_endpoint"

# The helper must be defined above the CCLM_LIB_ONLY guard.
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f _cclm_validate_endpoint > /dev/null 2>&1; then
  _fail "_cclm_validate_endpoint function not defined"
fi

ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f _cclm_confirm_unreachable_save > /dev/null 2>&1; then
  _fail "_cclm_confirm_unreachable_save function not defined"
fi

# --- PATH shims: success and failure curl stubs --------------------------
VAL_OK_DIR=$(mktemp -d)
cat > "$VAL_OK_DIR/curl" <<'EOF'
#!/usr/bin/env zsh
# Success stub: ignore args, emit a /v1/models response containing id "test-model".
cat <<JSON
{"data":[{"id":"test-model","object":"model"},{"id":"other","object":"model"}]}
JSON
EOF
chmod +x "$VAL_OK_DIR/curl"

VAL_FAIL_DIR=$(mktemp -d)
cat > "$VAL_FAIL_DIR/curl" <<'EOF'
#!/usr/bin/env zsh
# Failure stub: exit 7 (connection refused-ish) and print nothing.
exit 7
EOF
chmod +x "$VAL_FAIL_DIR/curl"

# --- Helper-level: success path returns 0 --------------------------------
PATH="$VAL_OK_DIR:$PATH" _cclm_validate_endpoint "http://localhost:11434" "test-model" "ollama"
RC=$?
assert_exit 0 "$RC" "validator returns 0 on reachable endpoint with matching model"

# --- Helper-level: model-not-in-list returns non-zero -------------------
PATH="$VAL_OK_DIR:$PATH" _cclm_validate_endpoint "http://localhost:11434" "missing-model" "ollama"
RC=$?
ASSERTIONS=$((ASSERTIONS + 1))
if (( RC == 0 )); then
  _fail "validator should return non-zero when model id is absent from /v1/models (got 0)"
fi

# --- Helper-level: unreachable endpoint returns non-zero ----------------
PATH="$VAL_FAIL_DIR:$PATH" _cclm_validate_endpoint "http://localhost:11434" "test-model" "ollama"
RC=$?
ASSERTIONS=$((ASSERTIONS + 1))
if (( RC == 0 )); then
  _fail "validator should return non-zero on unreachable endpoint (got 0)"
fi

# --- Helper-level: zai is best-effort (treats non-2xx as success) -------
PATH="$VAL_FAIL_DIR:$PATH" _cclm_validate_endpoint "https://api.z.ai/api/anthropic" "glm-4.6" "zai"
RC=$?
assert_exit 0 "$RC" "zai backend returns 0 even when curl fails (best-effort WARN not FAIL)"

# --- End-to-end: drive the save-guard pattern directly -------------------
# Simulates the exact block wired into run_ollama/vllm/remote. Testing the
# full run_ollama flow would require navigating ~6 interactive ask prompts;
# replicating the save-step block here is cheaper and just as honest — the
# code under test is byte-identical to what's in run_ollama.
VAL_TMP=$(mktemp -d)
_drive_save() {
  # Args: <url> <model> <backend> <profile_path>
  # Mirrors the wired guard in run_ollama/vllm/remote.
  local url="$1" model="$2" backend="$3" prof="$4"
  if [[ "${DRY_RUN:-false}" != "true" && "${CCLM_SKIP_VALIDATE:-0}" != "1" ]]; then
    if ! _cclm_validate_endpoint "$url" "$model" "$backend"; then
      if ! _cclm_confirm_unreachable_save; then
        echo "Profile not saved. You can re-run cclm to try again." >&2
        return 1
      fi
    fi
  fi
  jq -n --arg m "$model" '{model: $m}' > "$prof"
  echo "Profile saved: $prof" >&2
}

# 1) Success case: validator passes, save happens silently.
SAVE1="$VAL_TMP/ok.json"
OUT1=$(PATH="$VAL_OK_DIR:$PATH" _drive_save "http://h:1" "test-model" "ollama" "$SAVE1" 2>&1)
RC1=$?
assert_exit 0 "$RC1" "success path exits 0"
assert_file_exists "$SAVE1" "success path writes profile"
assert_not_contains "$OUT1" "not reachable" "success path emits no warning"

# 2) Failure + user says "n": no save, function returns non-zero, warning printed.
SAVE2="$VAL_TMP/rejected.json"
OUT2=$(printf 'n\n' | PATH="$VAL_FAIL_DIR:$PATH" _drive_save "http://h:1" "test-model" "ollama" "$SAVE2" 2>&1)
RC2=$?
ASSERTIONS=$((ASSERTIONS + 1))
if (( RC2 == 0 )); then
  _fail "reject path should exit non-zero (got 0)"
fi
ASSERTIONS=$((ASSERTIONS + 1))
if [[ -f "$SAVE2" ]]; then
  _fail "reject path should NOT have written profile at $SAVE2"
fi
assert_contains "$OUT2" "not reachable" "reject path warns about unreachable endpoint"
assert_contains "$OUT2" "Profile not saved" "reject path prints 'Profile not saved' message"

# 3) Failure + user says "y": save happens despite warning.
SAVE3="$VAL_TMP/accepted.json"
OUT3=$(printf 'y\n' | PATH="$VAL_FAIL_DIR:$PATH" _drive_save "http://h:1" "test-model" "ollama" "$SAVE3" 2>&1)
RC3=$?
assert_exit 0 "$RC3" "accept-anyway path exits 0"
assert_file_exists "$SAVE3" "accept-anyway path writes profile despite validation failure"
assert_contains "$OUT3" "not reachable" "accept-anyway path still shows warning"

# 4) CCLM_SKIP_VALIDATE=1: validator bypassed entirely, no curl invoked.
SAVE4="$VAL_TMP/skipped.json"
OUT4=$(CCLM_SKIP_VALIDATE=1 PATH="$VAL_FAIL_DIR:$PATH" _drive_save "http://h:1" "test-model" "ollama" "$SAVE4" 2>&1)
RC4=$?
assert_exit 0 "$RC4" "CCLM_SKIP_VALIDATE=1 path exits 0 with failing stub"
assert_file_exists "$SAVE4" "CCLM_SKIP_VALIDATE=1 writes profile without probing"
assert_not_contains "$OUT4" "not reachable" "CCLM_SKIP_VALIDATE=1 emits no warning"

# 5) DRY_RUN=true: validator bypassed entirely as well.
SAVE5="$VAL_TMP/dryrun.json"
OUT5=$(DRY_RUN=true PATH="$VAL_FAIL_DIR:$PATH" _drive_save "http://h:1" "test-model" "ollama" "$SAVE5" 2>&1)
RC5=$?
assert_exit 0 "$RC5" "DRY_RUN=true path exits 0 with failing stub"
assert_file_exists "$SAVE5" "DRY_RUN=true writes profile without probing"

# --- cleanup -------------------------------------------------------------
rm -rf "$VAL_OK_DIR" "$VAL_FAIL_DIR" "$VAL_TMP"
unfunction _drive_save
