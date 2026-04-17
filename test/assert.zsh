#!/usr/bin/env zsh
# Minimal assertion library for cclm tests.
# Sourced by test files; relies on globals: ASSERTIONS, FAILURES, CURRENT_TEST.

typeset -g ASSERTIONS=0
typeset -g FAILURES=0
typeset -g CURRENT_TEST=""

_fail() {
  local msg="$1"
  FAILURES=$((FAILURES + 1))
  echo "  FAIL [${CURRENT_TEST}]: $msg" >&2
}

assert_eq() {
  local expected="$1" actual="$2" label="${3:-}"
  ASSERTIONS=$((ASSERTIONS + 1))
  if [[ "$expected" != "$actual" ]]; then
    _fail "${label:-assert_eq} — expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  ASSERTIONS=$((ASSERTIONS + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    _fail "${label:-assert_contains} — '$needle' not found in output"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  ASSERTIONS=$((ASSERTIONS + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    _fail "${label:-assert_not_contains} — '$needle' unexpectedly present"
  fi
}

assert_exit() {
  local expected="$1" actual="$2" label="${3:-}"
  ASSERTIONS=$((ASSERTIONS + 1))
  if [[ "$expected" != "$actual" ]]; then
    _fail "${label:-assert_exit} — expected exit $expected, got $actual"
  fi
}

assert_file_exists() {
  local path="$1" label="${2:-}"
  ASSERTIONS=$((ASSERTIONS + 1))
  if [[ ! -f "$path" ]]; then
    _fail "${label:-assert_file_exists} — $path does not exist"
  fi
}

assert_file_match() {
  local actual_path="$1" expected_path="$2" label="${3:-}"
  ASSERTIONS=$((ASSERTIONS + 1))
  if ! diff -q "$expected_path" "$actual_path" >/dev/null 2>&1; then
    _fail "${label:-assert_file_match} — $actual_path differs from $expected_path"
    diff -u "$expected_path" "$actual_path" | head -30 >&2
  fi
}

start_test() { CURRENT_TEST="$1"; }
