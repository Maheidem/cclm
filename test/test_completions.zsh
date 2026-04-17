start_test "completions"

# Resolve the repo root from this test file's location ($0 in zsh points to
# the sourced file under `source`).
_completions_test_dir="${0:A:h}"
_completions_file="${_completions_test_dir}/../completions/_cclm"
_completions_bash="${_completions_test_dir}/../completions/cclm.bash"

# File exists
assert_file_exists "$_completions_file" "zsh completion file present"
assert_file_exists "$_completions_bash" "bash completion file present"

# Syntactic sanity: zsh -n must pass on the completion file.
zsh -n "$_completions_file" 2>/dev/null
assert_exit 0 $? "zsh -n on _cclm"

# Sourcing must define the _cclm function without invoking completion builtins.
# Run in a subshell so we don't pollute the parent test harness' function
# table, then propagate the status via assert_exit.
zsh -c "source '$_completions_file' && (( \$+functions[_cclm] ))"
assert_exit 0 $? "_cclm function defined after source"

# Helper functions should also be defined.
zsh -c "source '$_completions_file' && (( \$+functions[_cclm_profiles] ))"
assert_exit 0 $? "_cclm_profiles helper defined"

zsh -c "source '$_completions_file' && (( \$+functions[_cclm_hosts] ))"
assert_exit 0 $? "_cclm_hosts helper defined"

unset _completions_test_dir _completions_file _completions_bash
