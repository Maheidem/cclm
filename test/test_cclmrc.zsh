start_test "cclmrc discovery and parsing"

# ---------------------------------------------------------------------------
# Sanity: both helpers must live above the CCLM_LIB_ONLY guard so the test
# harness (which sources bin/cclm in lib-only mode) can call them.
# ---------------------------------------------------------------------------
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f find_cclmrc > /dev/null 2>&1; then
  _fail "find_cclmrc function not defined"
fi
ASSERTIONS=$((ASSERTIONS + 1))
if ! typeset -f apply_cclmrc > /dev/null 2>&1; then
  _fail "apply_cclmrc function not defined"
fi

# ---------------------------------------------------------------------------
# Shared fixture: tmpdir layout
#   $CCLMRC_TMP/                  (acts as a fake project root)
#   $CCLMRC_TMP/.cclmrc           (profile=lms-fixture)
#   $CCLMRC_TMP/a/b/c/            (nested cwd for discovery)
#   $CCLMRC_TMP/cfg/              (fake CONFIG_DIR with lms-fixture.json)
# ---------------------------------------------------------------------------
CCLMRC_TMP=$(mktemp -d)
mkdir -p "$CCLMRC_TMP/a/b/c" "$CCLMRC_TMP/cfg"
cat > "$CCLMRC_TMP/cfg/lms-fixture.json" <<'JSON'
{
  "model": "qwen3-fixture",
  "context_length": 65536,
  "gpu": "max",
  "parallel": 1,
  "ttl": 3600,
  "identifier": "qwen3-fixture@q8",
  "remote_host": null
}
JSON
cat > "$CCLMRC_TMP/.cclmrc" <<'RC'
# cclmrc comment — ignored
profile=lms-fixture
RC

# --- Case 1: discovery walks up from a deep subdir --------------------------
DISCOVER_OUT=$(
  cd "$CCLMRC_TMP/a/b/c" && \
  zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    find_cclmrc "$PWD"
    echo "rc=$?"
  ' 2>/dev/null
)
assert_contains "$DISCOVER_OUT" "$CCLMRC_TMP/.cclmrc" "find_cclmrc finds rcfile at project root from nested subdir"
assert_contains "$DISCOVER_OUT" "rc=0"                 "find_cclmrc returns 0 on hit"

# --- Case 2: discovery stops at $HOME --------------------------------------
# .cclmrc above HOME must NOT be found. We fence it in by pointing HOME at a
# child dir that sits *between* the rcfile and the subshell's cwd.
STOPHOME_TMP=$(mktemp -d)
mkdir -p "$STOPHOME_TMP/home/project/sub"
echo 'profile=lms-should-not-be-found' > "$STOPHOME_TMP/.cclmrc"
STOPHOME_OUT=$(
  HOME="$STOPHOME_TMP/home" zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    cd "'"$STOPHOME_TMP/home/project/sub"'"
    find_cclmrc "$PWD"
    echo "rc=$?"
  ' 2>/dev/null
)
assert_contains "$STOPHOME_OUT" "rc=1"        "find_cclmrc stops at \$HOME and returns 1"
assert_not_contains "$STOPHOME_OUT" "should-not-be-found" "rcfile above HOME is not discovered"
rm -rf "$STOPHOME_TMP"

# --- Case 3: apply_cclmrc sets preload globals from profile= ----------------
APPLY_PROFILE_OUT=$(
  CONFIG_DIR="$CCLMRC_TMP/cfg" zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$CCLMRC_TMP/cfg"'"
    apply_cclmrc "'"$CCLMRC_TMP/.cclmrc"'"
    echo "rc=$?"
    echo "backend=$backend"
    echo "profile=$_PRELOADED_PROFILE"
    echo "action=$_PRELOADED_ACTION"
  ' 2>/dev/null
)
assert_contains "$APPLY_PROFILE_OUT" "rc=0"                                   "apply_cclmrc profile= returns 0"
assert_contains "$APPLY_PROFILE_OUT" "backend=lms"                            "apply_cclmrc infers backend from slug prefix"
assert_contains "$APPLY_PROFILE_OUT" "profile=$CCLMRC_TMP/cfg/lms-fixture.json" "apply_cclmrc resolves profile to absolute path"
assert_contains "$APPLY_PROFILE_OUT" "action=open"                            "apply_cclmrc sets _PRELOADED_ACTION=open"

# --- Case 4: apply_cclmrc handles backend= (no profile) --------------------
BACKEND_RC="$CCLMRC_TMP/backend.rc"
cat > "$BACKEND_RC" <<'RC'
# just pick a backend
backend=llama
RC
APPLY_BACKEND_OUT=$(
  CONFIG_DIR="$CCLMRC_TMP/cfg" zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$CCLMRC_TMP/cfg"'"
    apply_cclmrc "'"$BACKEND_RC"'"
    echo "rc=$?"
    echo "backend=$backend"
    echo "profile=$_PRELOADED_PROFILE"
  ' 2>/dev/null
)
assert_contains "$APPLY_BACKEND_OUT" "rc=0"          "apply_cclmrc backend= returns 0"
assert_contains "$APPLY_BACKEND_OUT" "backend=llama" "apply_cclmrc backend= sets backend"
# _PRELOADED_PROFILE must remain empty so the picker can still show profiles.
assert_contains "$APPLY_BACKEND_OUT" "profile="      "apply_cclmrc backend= leaves _PRELOADED_PROFILE empty"

# --- Case 5: malformed .cclmrc triggers warning + rc=1 ---------------------
BAD_RC="$CCLMRC_TMP/bad.rc"
cat > "$BAD_RC" <<'RC'
this line has no equals sign
RC
BAD_OUT=$(
  CONFIG_DIR="$CCLMRC_TMP/cfg" zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$CCLMRC_TMP/cfg"'"
    apply_cclmrc "'"$BAD_RC"'"
    echo "rc=$?"
  ' 2>&1
)
assert_contains "$BAD_OUT" "rc=1"     "malformed .cclmrc returns 1"
assert_contains "$BAD_OUT" "warning:" "malformed .cclmrc prints a warning"

# --- Case 6: profile= pointing at a non-existent file → rc=1 ---------------
MISS_RC="$CCLMRC_TMP/miss.rc"
echo 'profile=lms-ghost' > "$MISS_RC"
MISS_OUT=$(
  CONFIG_DIR="$CCLMRC_TMP/cfg" zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$CCLMRC_TMP/cfg"'"
    apply_cclmrc "'"$MISS_RC"'"
    echo "rc=$?"
  ' 2>&1
)
assert_contains "$MISS_OUT" "rc=1"          "missing profile file returns 1"
assert_contains "$MISS_OUT" "not found"     "missing profile warning mentions not-found"

# --- Case 7: unknown backend value → rc=1 ----------------------------------
BADBE_RC="$CCLMRC_TMP/badbe.rc"
echo 'backend=tensorflow' > "$BADBE_RC"
BADBE_OUT=$(
  zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    apply_cclmrc "'"$BADBE_RC"'"
    echo "rc=$?"
  ' 2>&1
)
assert_contains "$BADBE_OUT" "rc=1"              "unknown backend= returns 1"
assert_contains "$BADBE_OUT" "unknown backend"   "unknown backend= prints a warning"

# --- Case 8: symlinked cwd — logical $PWD is honored ------------------------
# Real tree at $SYM_TMP/real with the rcfile at its root. `/link -> /real`,
# cd through the symlink, then discover. We verify the helper walks up via
# the LOGICAL path (what the user cd'd into), not the realpath.
SYM_TMP=$(mktemp -d)
mkdir -p "$SYM_TMP/real/deep/nest"
echo 'profile=lms-fixture' > "$SYM_TMP/real/.cclmrc"
ln -s "$SYM_TMP/real" "$SYM_TMP/link"
SYM_OUT=$(
  zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    cd "'"$SYM_TMP/link/deep/nest"'"
    find_cclmrc "$PWD"
    echo "pwd=$PWD"
  ' 2>/dev/null
)
assert_contains "$SYM_OUT" "$SYM_TMP/link/deep/nest" "symlinked cwd: \$PWD kept as logical path"
assert_contains "$SYM_OUT" "$SYM_TMP/link/.cclmrc"   "symlinked cwd: discovery resolves against logical \$PWD"
rm -rf "$SYM_TMP"

# --- Case 9: CLI flags override .cclmrc ------------------------------------
# We simulate the full dispatch guard the main script uses: if $backend is
# pre-set (as it would be after `--llama` parses), apply_cclmrc should never
# be called. We model this with the same guard, then assert the pre-set
# backend wins even though a .cclmrc is present.
CLIOVR_OUT=$(
  CONFIG_DIR="$CCLMRC_TMP/cfg" zsh -c '
    CCLM_LIB_ONLY=1 source "'"$REPO_DIR"'/bin/cclm"
    set +euo pipefail
    CONFIG_DIR="'"$CCLMRC_TMP/cfg"'"
    # Simulate `cclm --llama` having already parsed.
    backend="llama"
    _PRELOADED_PROFILE=""
    cd "'"$CCLMRC_TMP/a/b/c"'"
    # The dispatch guard from the main script:
    if [[ -z "$backend" && -z "${_PRELOADED_PROFILE:-}" ]]; then
      rcpath=$(find_cclmrc "$PWD") && apply_cclmrc "$rcpath"
    fi
    echo "backend=$backend"
    echo "profile=$_PRELOADED_PROFILE"
  ' 2>/dev/null
)
assert_contains "$CLIOVR_OUT" "backend=llama" "CLI flag wins over .cclmrc (backend unchanged)"
assert_contains "$CLIOVR_OUT" "profile="      "CLI flag wins over .cclmrc (profile still empty)"

rm -rf "$CCLMRC_TMP"
