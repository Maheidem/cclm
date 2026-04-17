#!/usr/bin/env zsh
# Verify post-refactor schema_display output is byte-identical to captured
# golden files. Must be run AFTER bin/cclm refactor.

set +xeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GOLDEN_DIR="$SCRIPT_DIR/golden"
NEW_DIR="$(mktemp -d)"
DIFFS=0

export CCLM_LIB_ONLY=1
MY_TMP_DIR="$(mktemp -d)"
export CONFIG_DIR="$MY_TMP_DIR"
source "$REPO_DIR/bin/cclm"
set +xeuo pipefail

compare() {
  local name="$1" profile="$2" schema_var="$3"
  local actual="$NEW_DIR/${name}.txt"
  local schema_val=("${(@P)schema_var}")
  echo n | schema_display "$profile" "${schema_val[@]}" > /dev/null 2> "$actual"
  if diff -q "$GOLDEN_DIR/${name}.txt" "$actual" >/dev/null 2>&1; then
    echo "  OK:   $name"
  else
    echo "  DIFF: $name"
    diff -u "$GOLDEN_DIR/${name}.txt" "$actual" | head -20
    DIFFS=$((DIFFS + 1))
  fi
}

compare "lms_inner"   "$SCRIPT_DIR/fixtures/lms-test.json"   LMS_PROFILE_SCHEMA_BRIEF
compare "lms_outer"   "$SCRIPT_DIR/fixtures/lms-test.json"   LMS_PROFILE_SCHEMA
compare "llama_inner" "$SCRIPT_DIR/fixtures/llama-test.json" LLAMA_PROFILE_SCHEMA_WITH_PATH
compare "llama_outer" "$SCRIPT_DIR/fixtures/llama-test.json" LLAMA_PROFILE_SCHEMA
compare "zai"         "$SCRIPT_DIR/fixtures/zai-test.json"   ZAI_PROFILE_SCHEMA

rm -rf "$NEW_DIR" "$MY_TMP_DIR"
if (( DIFFS == 0 )); then
  echo ""
  echo "All golden files match."
  exit 0
else
  echo ""
  echo "$DIFFS golden file(s) differ."
  exit 1
fi
