start_test "try_shortcut_dispatch"

# try_shortcut_dispatch must be defined above the CCLM_LIB_ONLY guard so
# tests can invoke it without running the main script body.
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f try_shortcut_dispatch > /dev/null 2>&1; then
  _fail "try_shortcut_dispatch function not defined"
fi

# --- Scratch CONFIG_DIR with a fixture profile and a last-session record -----
# bin/cclm hardcodes CONFIG_DIR="$HOME/.config/cclm" on source, so we override
# it (and STATE_FILE) per-invocation via a subshell env. The fixture profile
# is a realistic lms profile; the .last_session file points at it.
SHORTCUT_TMP=$(mktemp -d)
cat > "$SHORTCUT_TMP/lms-fixture.json" <<'JSON'
{
  "model": "qwen3-fixture",
  "context_length": 65536,
  "gpu": "max",
  "parallel": 1,
  "ttl": 3600,
  "identifier": "qwen3-fixture@q8",
  "remote_host": "192.168.1.50"
}
JSON
cat > "$SHORTCUT_TMP/.last_session" <<'JSON'
{
  "backend": "lms",
  "profile": "lms-fixture.json",
  "remote_host": "192.168.1.50",
  "model": "qwen3-fixture"
}
JSON

# --- Case 1: `resume` with a populated .last_session ------------------------
# Run in a subshell so helper-set globals don't leak into sibling test cases.
# Emit the resulting globals as k=v lines, parse them back here.
RESUME_OUT=$(
  CONFIG_DIR="$SHORTCUT_TMP" STATE_FILE="$SHORTCUT_TMP/.last_session" \
  zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$SHORTCUT_TMP"'"
    STATE_FILE="'"$SHORTCUT_TMP/.last_session"'"
    try_shortcut_dispatch resume
    echo "rc=$?"
    echo "backend=$backend"
    echo "profile=$_PRELOADED_PROFILE"
    echo "action=$_PRELOADED_ACTION"
    echo "remote=$remote_host"
  ' 2>/dev/null
)
assert_contains "$RESUME_OUT" "rc=0"                                   "resume returns 0 when state exists"
assert_contains "$RESUME_OUT" "backend=lms"                            "resume sets backend=lms"
assert_contains "$RESUME_OUT" "profile=$SHORTCUT_TMP/lms-fixture.json" "resume sets absolute _PRELOADED_PROFILE"
assert_contains "$RESUME_OUT" "action=open"                            "resume sets _PRELOADED_ACTION=open"
assert_contains "$RESUME_OUT" "remote=192.168.1.50"                    "resume propagates last_remote"

# --- Case 2: `resume` with NO last-session state → rc=2 ---------------------
NO_STATE_TMP=$(mktemp -d)
NO_STATE_OUT=$(
  zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$NO_STATE_TMP"'"
    STATE_FILE="'"$NO_STATE_TMP/.last_session"'"
    try_shortcut_dispatch resume
    echo "rc=$?"
  ' 2>/dev/null
)
assert_contains "$NO_STATE_OUT" "rc=2" "resume with no state returns 2"
rm -rf "$NO_STATE_TMP"

# --- Case 3: `<slug>` matching a profile file -------------------------------
SLUG_OUT=$(
  zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$SHORTCUT_TMP"'"
    try_shortcut_dispatch lms-fixture
    echo "rc=$?"
    echo "backend=$backend"
    echo "profile=$_PRELOADED_PROFILE"
    echo "action=$_PRELOADED_ACTION"
  ' 2>/dev/null
)
assert_contains "$SLUG_OUT" "rc=0"                                   "known slug returns 0"
assert_contains "$SLUG_OUT" "backend=lms"                            "slug prefix drives backend inference"
assert_contains "$SLUG_OUT" "profile=$SHORTCUT_TMP/lms-fixture.json" "slug resolves to absolute profile path"
assert_contains "$SLUG_OUT" "action=open"                            "slug sets _PRELOADED_ACTION=open"

# --- Case 4: unknown slug → rc=1 (fall-through, no globals set) -------------
UNKNOWN_OUT=$(
  zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$SHORTCUT_TMP"'"
    try_shortcut_dispatch lms-nonexistent
    echo "rc=$?"
    echo "backend=$backend"
    echo "profile=$_PRELOADED_PROFILE"
  ' 2>/dev/null
)
assert_contains "$UNKNOWN_OUT" "rc=1"         "unknown slug returns 1 (fall-through)"
assert_contains "$UNKNOWN_OUT" "backend="     "unknown slug leaves backend empty"
assert_contains "$UNKNOWN_OUT" "profile="     "unknown slug leaves _PRELOADED_PROFILE empty"

# --- Case 5: non-prefix garbage (e.g. a stray arg) → rc=1 -------------------
GARBAGE_OUT=$(
  zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$SHORTCUT_TMP"'"
    try_shortcut_dispatch random-word
    echo "rc=$?"
  ' 2>/dev/null
)
assert_contains "$GARBAGE_OUT" "rc=1" "arg without known backend prefix returns 1"

# --- Case 6: flag-like arg must never be treated as a shortcut --------------
FLAG_OUT=$(
  zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$SHORTCUT_TMP"'"
    try_shortcut_dispatch --lms
    echo "rc=$?"
  ' 2>/dev/null
)
assert_contains "$FLAG_OUT" "rc=1" "flag-like arg (--lms) returns 1"

rm -rf "$SHORTCUT_TMP"
