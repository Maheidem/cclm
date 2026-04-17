start_test "dry_run"
# Exercise the --dry-run path via launch_claude in a subshell (exit 0 there
# terminates only the subshell). DRY_RUN=true mimics the arg parser having
# seen --dry-run or --print-env.
OUTPUT=$(DRY_RUN=true launch_claude exec "test-model" "localhost" "1234" "200000" --resume 2>/dev/null)
EXIT=$?
assert_exit 0 "$EXIT" "dry-run exits 0"
assert_contains "$OUTPUT" "ANTHROPIC_BASE_URL=" "stdout has ANTHROPIC_BASE_URL"
assert_contains "$OUTPUT" "claude" "stdout has would-be claude command"

start_test "dry_run_print_env_alias"
# --print-env is an alias; the DRY_RUN flag is what launch_claude sees, so
# sanity-check the same path works when toggled directly.
OUTPUT2=$(DRY_RUN=true launch_claude exec "test-model" "http://remote.example:8080" "" "131072" 2>/dev/null)
EXIT2=$?
assert_exit 0 "$EXIT2" "dry-run (remote url) exits 0"
assert_contains "$OUTPUT2" "CLAUDE_CODE_MAX_CONTEXT_TOKENS=131072" "context env var printed"
assert_contains "$OUTPUT2" "claude --model" "would-be exec line includes --model"

start_test "dry_run_disabled_falls_through"
# When DRY_RUN is unset/false, launch_claude must NOT print the env dump to
# stdout. We don't actually want to exec claude in the test, so stub it out.
claude() { echo "STUB_CLAUDE_CALLED"; }
OUTPUT3=$(DRY_RUN=false launch_claude fg "test-model" "localhost" "1234" "200000" 2>/dev/null)
assert_not_contains "$OUTPUT3" "ANTHROPIC_BASE_URL=" "no env dump when DRY_RUN=false"
assert_contains "$OUTPUT3" "STUB_CLAUDE_CALLED" "falls through to claude invocation"
unfunction claude
