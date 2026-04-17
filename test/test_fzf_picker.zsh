start_test "fzf_picker"

# ---------------------------------------------------------------------------
# pick_profile()'s fzf branch uses an external `fzf` binary to render a fuzzy
# picker. We drive it in tests by defining a shell FUNCTION named `fzf` that
# shadows any real binary on PATH and emits a canned 2-line fzf response
# (line 1 = key, line 2 = selected input line).
#
# CCLM_FZF_FORCE=1 bypasses the `[[ -t 0 ]]` TTY gate inside pick_profile so
# the fzf branch runs even though our test stdin is a pipe. CCLM_NO_FZF=1 is
# the documented user-facing escape hatch that should route back to the
# numbered fallback regardless of whether fzf is installed.
#
# The stub runs inside the pipeline RHS (a subshell), so captures into plain
# shell variables would not survive back to the test. Persist via files.
# The advisor specifically called the sentinel-file approach out as the most
# robust way to assert (non-)invocation without stdout diffing.
# ---------------------------------------------------------------------------

# bin/cclm unconditionally sets CONFIG_DIR="$HOME/.config/cclm" on source, so
# the export from run.sh is clobbered. Use a local scratch dir and point
# pick_profile at it via per-invocation CONFIG_DIR overrides — same pattern
# as test_status.zsh / test_resume_and_slug.zsh.
FZF_TMP="$(mktemp -d)"
FZF_SENTINEL="$(mktemp -t cclm_fzf_sentinel.XXXXXX)"
FZF_FEED_FILE="$(mktemp -t cclm_fzf_feed.XXXXXX)"
: > "$FZF_SENTINEL"
: > "$FZF_FEED_FILE"
FZF_CANNED="" # 2-line payload the stub returns (set per-case below)

fzf() {
  echo "called" >> "$FZF_SENTINEL"
  cat > "$FZF_FEED_FILE"
  printf '%s' "$FZF_CANNED"
}

# Seed three profiles into the scratch CONFIG_DIR so pick_profile has input.
cp "$TEST_DIR/fixtures/lms-test.json"    "$FZF_TMP/lms-alpha.json"
cp "$TEST_DIR/fixtures/llama-test.json"  "$FZF_TMP/llama-beta.json"
cp "$TEST_DIR/fixtures/zai-test.json"    "$FZF_TMP/zai-gamma.json"

# ---- Case 1: fzf branch runs, Enter selects llama-beta → action "open" -----
: > "$FZF_SENTINEL"; : > "$FZF_FEED_FILE"
FZF_CANNED=$'\n'"$FZF_TMP/llama-beta.json"$'\t'"[llama] some-model        local                 ctx:131072"$'\n'
_PRELOADED_PROFILE=""; _PRELOADED_ACTION=""; backend=""
unset CCLM_NO_FZF
CONFIG_DIR="$FZF_TMP" CCLM_FZF_FORCE=1 pick_profile </dev/null >/dev/null 2>&1
RC=$?
assert_exit 0 "$RC" "fzf Enter returns 0"
assert_eq "$FZF_TMP/llama-beta.json" "$_PRELOADED_PROFILE" "fzf Enter sets _PRELOADED_PROFILE"
assert_eq "open" "$_PRELOADED_ACTION" "fzf Enter sets action=open"
assert_eq "llama" "$backend" "fzf Enter sets backend=llama"
assert_contains "$(cat "$FZF_SENTINEL")" "called" "fzf stub was invoked"
# The feed fzf saw must contain all three profile paths as first-column entries.
FEED_CONTENT="$(cat "$FZF_FEED_FILE")"
assert_contains "$FEED_CONTENT" "$FZF_TMP/lms-alpha.json" "feed carries lms path"
assert_contains "$FEED_CONTENT" "$FZF_TMP/llama-beta.json" "feed carries llama path"
assert_contains "$FEED_CONTENT" "$FZF_TMP/zai-gamma.json" "feed carries zai path"

# ---- Case 2: Ctrl-E → action "edit" ----------------------------------------
: > "$FZF_SENTINEL"; : > "$FZF_FEED_FILE"
FZF_CANNED="ctrl-e"$'\n'"$FZF_TMP/zai-gamma.json"$'\t'"[zai] sonnet  z.ai ctx:200000"$'\n'
_PRELOADED_PROFILE=""; _PRELOADED_ACTION=""; backend=""
unset CCLM_NO_FZF
CONFIG_DIR="$FZF_TMP" CCLM_FZF_FORCE=1 pick_profile </dev/null >/dev/null 2>&1
RC=$?
assert_exit 0 "$RC" "fzf Ctrl-E returns 0"
assert_eq "edit" "$_PRELOADED_ACTION" "Ctrl-E sets action=edit"
assert_eq "zai" "$backend" "Ctrl-E sets backend=zai"
assert_eq "$FZF_TMP/zai-gamma.json" "$_PRELOADED_PROFILE" "Ctrl-E picks the right profile path"

# ---- Case 3: CCLM_NO_FZF=1 bypasses fzf entirely (stub untouched) ----------
# "n" at the numbered menu returns 1 (new session) — safe to pipe without
# triggering `exit 0` from the `q` branch that would kill the test process.
: > "$FZF_SENTINEL"; : > "$FZF_FEED_FILE"
FZF_CANNED="SHOULD_NOT_BE_READ"
_PRELOADED_PROFILE=""; _PRELOADED_ACTION=""; backend=""
CONFIG_DIR="$FZF_TMP" CCLM_NO_FZF=1 pick_profile <<<"n" >/dev/null 2>&1
RC=$?
assert_exit 1 "$RC" "CCLM_NO_FZF=1 + 'n' returns 1 (falls through to backend picker)"
# Sentinel must be EMPTY — stub was never called.
assert_eq "" "$(cat "$FZF_SENTINEL")" "CCLM_NO_FZF=1 bypasses fzf stub"
assert_eq "" "$_PRELOADED_PROFILE" "numbered fallback + 'n' leaves _PRELOADED_PROFILE empty"

# ---- Case 4: numbered fallback can still pick a profile by index -----------
# Feed "1\no\n" → select first profile (alphabetical: llama-beta), action=open.
: > "$FZF_SENTINEL"; : > "$FZF_FEED_FILE"
_PRELOADED_PROFILE=""; _PRELOADED_ACTION=""; backend=""
CONFIG_DIR="$FZF_TMP" CCLM_NO_FZF=1 pick_profile <<EOF >/dev/null 2>&1
1
o
EOF
RC=$?
assert_exit 0 "$RC" "numbered picker returns 0 on valid selection"
assert_eq "open" "$_PRELOADED_ACTION" "numbered picker sets action=open"
assert_eq "$FZF_TMP/llama-beta.json" "$_PRELOADED_PROFILE" "numbered picker selected index 1 = llama-beta"
assert_eq "" "$(cat "$FZF_SENTINEL")" "numbered picker path never calls fzf"

# Cleanup
unset -f fzf
rm -rf "$FZF_TMP"
rm -f "$FZF_SENTINEL" "$FZF_FEED_FILE"
unset CCLM_FZF_FORCE CCLM_NO_FZF FZF_TMP FZF_SENTINEL FZF_FEED_FILE FZF_CANNED FEED_CONTENT RC
