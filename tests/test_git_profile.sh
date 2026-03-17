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

# ── Task 2 tests ────────────────────────────────────────────────────────────

test_parse_profiles() {
  setup_test_home
  cat > "$TEST_HOME/.git-profiles.conf" <<'EOF'
# comment line
[personal]
name = kgfan
email = test@example.com
host = github.com
ssh_key = ~/.ssh/git_profile_personal

[work]
name = Chen Jinfan
email = work@company.com
host = gitlab.company.com
ssh_key = ~/.ssh/git_profile_work
EOF
  local output
  output="$(CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" list 2>&1)"
  assert_contains "list shows personal" "personal" "$output"
  assert_contains "list shows work" "work" "$output"
  teardown_test_home
}

test_parse_rules() {
  setup_test_home
  cat > "$TEST_HOME/.git-profiles.conf" <<'EOF'
[personal]
name = kgfan
email = test@example.com
host = github.com
ssh_key = ~/.ssh/key

[rule "my-rule"]
dir = /tmp/projects/
profile = personal
EOF
  local output
  output="$(CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" rule list 2>&1)"
  assert_contains "rule list shows rule name" "my-rule" "$output"
  assert_contains "rule list shows directory" "/tmp/projects/" "$output"
  assert_contains "rule list shows profile" "personal" "$output"
  teardown_test_home
}

test_parse_empty_config() {
  setup_test_home
  echo "" > "$TEST_HOME/.git-profiles.conf"
  local output
  output="$(CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" list 2>&1)"
  assert_contains "empty config shows no profiles" "No profiles" "$output"
  teardown_test_home
}

test_parse_profiles
test_parse_rules
test_parse_empty_config

# ── Task 3 tests ────────────────────────────────────────────────────────────

test_write_profile_section() {
  setup_test_home
  echo "" > "$TEST_HOME/.git-profiles.conf"
  CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" _write_profile test-prof "Test User" "test@mail.com" "github.com" "~/.ssh/key_test"
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "written profile has section header" "[test-prof]" "$content"
  assert_contains "written profile has name" "name = Test User" "$content"
  assert_contains "written profile has email" "email = test@mail.com" "$content"
  teardown_test_home
}

test_delete_profile_section() {
  setup_test_home
  cat > "$TEST_HOME/.git-profiles.conf" <<'EOF'
[keep-me]
name = Keep
email = keep@test.com
host = github.com
ssh_key = ~/.ssh/keep

[delete-me]
name = Delete
email = del@test.com
host = github.com
ssh_key = ~/.ssh/del

[also-keep]
name = Also
email = also@test.com
host = github.com
ssh_key = ~/.ssh/also
EOF
  CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" _delete_section "delete-me"
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "kept section still exists" "[keep-me]" "$content"
  assert_contains "also-keep still exists" "[also-keep]" "$content"
  if [[ "$content" == *"[delete-me]"* ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: delete-me should be removed but still exists"
  else
    PASS=$((PASS + 1))
  fi
  teardown_test_home
}

test_write_rule_section() {
  setup_test_home
  echo "" > "$TEST_HOME/.git-profiles.conf"
  CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" _write_rule "my-rule" "/home/user/projects/" "personal"
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "rule section header" '[rule "my-rule"]' "$content"
  assert_contains "rule has dir" "dir = /home/user/projects/" "$content"
  assert_contains "rule has profile" "profile = personal" "$content"
  teardown_test_home
}

test_write_profile_section
test_delete_profile_section
test_write_rule_section

report
