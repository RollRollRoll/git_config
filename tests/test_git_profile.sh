#!/usr/bin/env bash
# tests/test_git_profile.sh — integration tests for git-profile
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GIT_PROFILE="$SCRIPT_DIR/git-profile"
PASS=0; FAIL=0; ERRORS=""

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: ${desc}\n  expected: ${expected}\n  actual:   ${actual}"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: ${desc}\n  expected to contain: ${needle}\n  actual: ${haystack}"
  fi
}

assert_exit_code() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: ${desc}\n  expected exit code: ${expected}\n  actual: ${actual}"
  fi
}

setup_test_home() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig"
  mkdir -p "$TEST_HOME/.ssh"
  mkdir -p "$TEST_HOME/.gitconfig.d"
  touch "$TEST_HOME/.git-profiles.conf"
  touch "$TEST_HOME/.gitconfig"
}

teardown_test_home() {
  rm -rf "$TEST_HOME"
}

report() {
  echo ""
  echo "================================"
  echo "Results: $PASS passed, $FAIL failed"
  if [[ $FAIL -gt 0 ]]; then
    echo -e "$ERRORS"
    exit 1
  fi
  echo "All tests passed."
  exit 0
}

# ── Task 1 tests ────────────────────────────────────────────────────────────

test_version_flag() {
  local output
  output="$("$GIT_PROFILE" --version 2>&1)"
  assert_contains "--version outputs version" "git-profile" "$output"
}

test_help_flag() {
  local output
  output="$("$GIT_PROFILE" --help 2>&1)"
  assert_contains "--help shows usage" "usage" "$(echo "$output" | tr '[:upper:]' '[:lower:]')"
}

test_unknown_subcommand() {
  local exit_code=0
  "$GIT_PROFILE" nonexistent 2>/dev/null || exit_code=$?
  assert_eq "unknown subcommand exits non-zero" "1" "$exit_code"
}

test_version_flag
test_help_flag
test_unknown_subcommand

report
