#!/usr/bin/env zsh
# cclm test harness entry point.
# Sources helper functions from bin/cclm in lib-only mode, runs all test files.

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/.." && pwd)"

export CCLM_LIB_ONLY=1
# NOTE: bin/cclm resets CONFIG_DIR to $HOME/.config/cclm on source — never
# rm our sandbox path through $CONFIG_DIR after sourcing, or user profiles die.
MY_TMP_DIR="$(mktemp -d)"
export CONFIG_DIR="$MY_TMP_DIR"
trap 'rm -rf "$MY_TMP_DIR"' EXIT

source "$TEST_DIR/assert.zsh"
source "$REPO_DIR/bin/cclm"
set +euo pipefail  # bin/cclm sets strict mode; we want lenient behavior for tests

echo "Running cclm test suite..."
echo ""

for t in "$TEST_DIR"/test_*.zsh; do
  source "$t"
done

echo ""
echo "Ran ${ASSERTIONS} assertions, ${FAILURES} failures."
(( FAILURES == 0 )) || exit 1
echo "OK"
