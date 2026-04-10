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

# --- Test: add command ---
test_add_profile_with_existing_key() {
  setup_test_home
  touch "$TEST_HOME/.ssh/git_profile_myprof"
  touch "$TEST_HOME/.ssh/git_profile_myprof.pub"
  echo "fake-pub-key" > "$TEST_HOME/.ssh/git_profile_myprof.pub"

  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    "$GIT_PROFILE" _add_profile "myprof" "My User" "my@email.com" "github.com" "$TEST_HOME/.ssh/git_profile_myprof"

  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "add creates profile section" "[myprof]" "$content"
  assert_contains "add writes name" "name = My User" "$content"
  assert_contains "add writes email" "email = my@email.com" "$content"
  assert_contains "add writes host" "host = github.com" "$content"
  teardown_test_home
}

test_add_profile_generates_key() {
  setup_test_home
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    "$GIT_PROFILE" _add_profile_with_keygen "newprof" "New User" "new@email.com" "gitlab.com" "ed25519"

  if [[ -f "$TEST_HOME/.ssh/git_profile_newprof" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: SSH key file not generated"
  fi

  if [[ "$(stat -f '%Lp' "$TEST_HOME/.ssh/git_profile_newprof" 2>/dev/null || stat -c '%a' "$TEST_HOME/.ssh/git_profile_newprof" 2>/dev/null)" == "600" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: SSH key permissions not 600"
  fi

  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "keygen add writes profile" "[newprof]" "$content"
  teardown_test_home
}

test_add_same_host_writes_ssh_alias() {
  setup_test_home
  touch "$TEST_HOME/.ssh/git_profile_first"
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    "$GIT_PROFILE" _add_profile "first" "First" "first@mail.com" "github.com" "$TEST_HOME/.ssh/git_profile_first"

  touch "$TEST_HOME/.ssh/git_profile_second"
  touch "$TEST_HOME/.ssh/config"
  GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    "$GIT_PROFILE" _add_profile "second" "Second" "second@mail.com" "github.com" "$TEST_HOME/.ssh/git_profile_second"

  local ssh_config
  ssh_config="$(cat "$TEST_HOME/.ssh/config")"
  assert_contains "SSH alias Host written" "Host github.com-second" "$ssh_config"
  assert_contains "SSH alias has HostName" "HostName github.com" "$ssh_config"
  assert_contains "SSH alias has IdentityFile" "IdentityFile" "$ssh_config"
  assert_contains "SSH alias has git-profile marker" "# git-profile: second" "$ssh_config"
  teardown_test_home
}

test_add_single_account_no_ssh_config() {
  setup_test_home
  touch "$TEST_HOME/.ssh/git_profile_only"
  touch "$TEST_HOME/.ssh/config"
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    "$GIT_PROFILE" _add_profile "only" "Only" "only@mail.com" "github.com" "$TEST_HOME/.ssh/git_profile_only"

  local ssh_config
  ssh_config="$(cat "$TEST_HOME/.ssh/config")"
  if [[ -z "$ssh_config" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: single account should not write to ssh config, got: $ssh_config"
  fi
  teardown_test_home
}

test_add_profile_with_existing_key
test_add_profile_generates_key
test_add_same_host_writes_ssh_alias
test_add_single_account_no_ssh_config

# --- Test: use command ---
test_use_applies_config() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = gitlab.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)

  local got_name got_email got_ssh got_profile
  got_name="$(cd "$repo" && git config --local user.name)"
  got_email="$(cd "$repo" && git config --local user.email)"
  got_ssh="$(cd "$repo" && git config --local core.sshCommand)"
  got_profile="$(cd "$repo" && git config --local gitProfile.name)"

  assert_eq "use sets user.name" "Work User" "$got_name"
  assert_eq "use sets user.email" "work@company.com" "$got_email"
  assert_contains "use sets sshCommand with key" "git_profile_work" "$got_ssh"
  assert_contains "use sets sshCommand with IdentitiesOnly" "IdentitiesOnly=yes" "$got_ssh"
  assert_eq "use sets gitProfile.name" "work" "$got_profile"
  teardown_test_home
}

test_use_backup_and_clear() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"
  (cd "$repo" && git config user.name "Original User")
  (cd "$repo" && git config user.email "original@mail.com")

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = gitlab.com
ssh_key = $TEST_HOME/.ssh/git_profile_work

[personal]
name = Personal User
email = personal@mail.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_personal
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"
  touch "$TEST_HOME/.ssh/git_profile_personal"

  # First use: should backup original
  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)
  local backup_name
  backup_name="$(cd "$repo" && git config --local gitProfile.backup.userName 2>/dev/null || echo "")"
  assert_eq "backup saves original user.name" "Original User" "$backup_name"

  # Second use: should NOT overwrite backup
  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use personal)
  backup_name="$(cd "$repo" && git config --local gitProfile.backup.userName 2>/dev/null || echo "")"
  assert_eq "backup preserved after second use" "Original User" "$backup_name"

  # Current name should be personal
  local current_name
  current_name="$(cd "$repo" && git config --local user.name)"
  assert_eq "second use updates name" "Personal User" "$current_name"

  # Clear: should restore original
  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use --clear)
  local restored_name
  restored_name="$(cd "$repo" && git config --local user.name)"
  assert_eq "clear restores original user.name" "Original User" "$restored_name"

  # gitProfile section should be gone
  local profile_marker
  profile_marker="$(cd "$repo" && git config --local gitProfile.name 2>/dev/null || echo "GONE")"
  assert_eq "clear removes gitProfile.name" "GONE" "$profile_marker"
  teardown_test_home
}

test_use_clear_unsets_when_no_backup() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = gitlab.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)
  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use --clear)

  local local_name
  local_name="$(cd "$repo" && git config --local user.name 2>/dev/null || echo "UNSET")"
  assert_eq "clear unsets when no backup" "UNSET" "$local_name"
  teardown_test_home
}

test_use_not_git_repo() {
  setup_test_home
  local exit_code=0
  (cd "$TEST_HOME" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work 2>/dev/null) || exit_code=$?
  assert_eq "use in non-git dir exits 1" "1" "$exit_code"
  teardown_test_home
}

test_use_applies_config
test_use_backup_and_clear
test_use_clear_unsets_when_no_backup
test_use_not_git_repo

# --- Test: current command ---
test_current_shows_use_profile() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = gitlab.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"
  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)

  local output
  output="$(cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" current 2>&1)"
  assert_contains "current shows profile name" "work" "$output"
  assert_contains "current shows user name" "Work User" "$output"
  assert_contains "current shows email" "work@company.com" "$output"
  assert_contains "current shows source" "project config" "$output"
  teardown_test_home
}

test_current_no_profile() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"
  echo "" > "$TEST_HOME/.git-profiles.conf"

  local output
  output="$(cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" current 2>&1)"
  assert_contains "current with no profile" "not set" "$(echo "$output" | tr '[:upper:]' '[:lower:]')"
  teardown_test_home
}

test_current_not_git_repo() {
  setup_test_home
  local exit_code=0
  (cd "$TEST_HOME" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" current 2>/dev/null) || exit_code=$?
  assert_eq "current in non-git dir exits 1" "1" "$exit_code"
  teardown_test_home
}

test_current_shows_use_profile
test_current_no_profile
test_current_not_git_repo

# ── Task 8 tests ─────────────────────────────────────────────────────────────

test_rule_add_normalizes_path() {
  setup_test_home
  local target_dir="$TEST_HOME/projects/work"
  mkdir -p "$target_dir"
  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = gitlab.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"
  mkdir -p "$TEST_HOME/.gitconfig.d"
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    GITCONFIG_D="$TEST_HOME/.gitconfig.d" \
    GIT_PROFILE_AUTO_CONFIRM=y \
    "$GIT_PROFILE" _rule_add "work-projects" "$target_dir" "work"
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "rule section created" '[rule "work-projects"]' "$content"
  assert_contains "rule dir ends with /" "dir = ${target_dir}/" "$content"
  local fragment
  fragment="$(cat "$TEST_HOME/.gitconfig.d/work")"
  assert_contains "fragment has gitProfile.name" "name = work" "$fragment"
  assert_contains "fragment has user.name" "name = Work User" "$fragment"
  assert_contains "fragment has sshCommand" "IdentitiesOnly=yes" "$fragment"
  teardown_test_home
}

test_rule_add_tilde_expansion() {
  setup_test_home
  mkdir -p "$TEST_HOME/projects"
  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[personal]
name = User
email = u@mail.com
host = github.com
ssh_key = $TEST_HOME/.ssh/key
EOF
  touch "$TEST_HOME/.ssh/key"
  mkdir -p "$TEST_HOME/.gitconfig.d"
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    GITCONFIG_D="$TEST_HOME/.gitconfig.d" \
    GIT_PROFILE_AUTO_CONFIRM=y \
    "$GIT_PROFILE" _rule_add "personal-rule" "~/projects" "personal"
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "tilde expanded" "dir = ${TEST_HOME}/projects/" "$content"
  teardown_test_home
}

test_rule_add_normalizes_path
test_rule_add_tilde_expansion

# ── Task 9 tests ─────────────────────────────────────────────────────────────

test_rule_remove() {
  setup_test_home
  mkdir -p "$TEST_HOME/projects"
  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = gitlab.com
ssh_key = $TEST_HOME/.ssh/git_profile_work

[rule "work-rule"]
dir = $TEST_HOME/projects/
profile = work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"
  mkdir -p "$TEST_HOME/.gitconfig.d"
  echo "[user] name=test" > "$TEST_HOME/.gitconfig.d/work"
  git config --global includeIf."gitdir:$TEST_HOME/projects/".path "$TEST_HOME/.gitconfig.d/work"
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    GITCONFIG_D="$TEST_HOME/.gitconfig.d" \
    GIT_PROFILE_AUTO_CONFIRM=y \
    "$GIT_PROFILE" _rule_remove "work-rule"
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  if [[ "$content" == *'[rule "work-rule"]'* ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: rule section should be removed"
  else
    PASS=$((PASS + 1))
  fi
  assert_contains "profile preserved after rule remove" "[work]" "$content"
  teardown_test_home
}

test_rule_remove

# ── Task 10 tests ────────────────────────────────────────────────────────────

test_edit_updates_profile_and_fragment() {
  setup_test_home
  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Old Name
email = old@mail.com
host = gitlab.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"
  mkdir -p "$TEST_HOME/.gitconfig.d"
  cat > "$TEST_HOME/.gitconfig.d/work" <<EOF
[gitProfile]
  name = work
[user]
  name = Old Name
  email = old@mail.com
[core]
  sshCommand = ssh -i $TEST_HOME/.ssh/git_profile_work -o IdentitiesOnly=yes
EOF
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    GITCONFIG_D="$TEST_HOME/.gitconfig.d" \
    "$GIT_PROFILE" _edit_profile "work" "New Name" "new@mail.com" "" ""
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "edit updates name in config" "name = New Name" "$content"
  assert_contains "edit updates email in config" "email = new@mail.com" "$content"
  assert_contains "edit preserves host" "host = gitlab.com" "$content"
  local fragment
  fragment="$(cat "$TEST_HOME/.gitconfig.d/work")"
  assert_contains "fragment updated with new name" "name = New Name" "$fragment"
  assert_contains "fragment updated with new email" "email = new@mail.com" "$fragment"
  teardown_test_home
}

test_edit_updates_profile_and_fragment

# ── Task 11 tests ────────────────────────────────────────────────────────────

test_remove_profile() {
  setup_test_home
  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[keep]
name = Keep
email = keep@mail.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_keep

[delete-target]
name = Delete
email = del@mail.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_delete
EOF
  touch "$TEST_HOME/.ssh/git_profile_keep"
  touch "$TEST_HOME/.ssh/git_profile_delete"
  touch "$TEST_HOME/.ssh/git_profile_delete.pub"
  GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    "$GIT_PROFILE" _remove_profile "delete-target"
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "keep profile still exists" "[keep]" "$content"
  if [[ "$content" == *"[delete-target]"* ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: delete-target should be removed"
  else
    PASS=$((PASS + 1))
  fi
  teardown_test_home
}

test_remove_with_rules_cascade() {
  setup_test_home
  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work
email = work@mail.com
host = gitlab.com
ssh_key = $TEST_HOME/.ssh/git_profile_work

[rule "work-rule"]
dir = $TEST_HOME/projects/
profile = work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"
  mkdir -p "$TEST_HOME/.gitconfig.d"
  echo "fragment" > "$TEST_HOME/.gitconfig.d/work"
  GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    GITCONFIG_D="$TEST_HOME/.gitconfig.d" \
    "$GIT_PROFILE" _remove_profile "work"
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  if [[ "$content" == *"[work]"* ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: work profile should be removed"
  else
    PASS=$((PASS + 1))
  fi
  if [[ "$content" == *'[rule "work-rule"]'* ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: work-rule should be cascade-removed"
  else
    PASS=$((PASS + 1))
  fi
  teardown_test_home
}

test_remove_profile
test_remove_with_rules_cascade

# ── URL conversion tests ──────────────────────────────────────────────────────

test_https_to_ssh_basic() {
  local output
  output="$("$GIT_PROFILE" _url_https_to_ssh "https://github.com/user/repo.git" "github.com")"
  assert_eq "https→ssh basic" "git@github.com:user/repo.git" "$output"
}

test_https_to_ssh_no_git_suffix() {
  local output
  output="$("$GIT_PROFILE" _url_https_to_ssh "https://github.com/user/repo" "github.com")"
  assert_eq "https→ssh auto-append .git" "git@github.com:user/repo.git" "$output"
}

test_https_to_ssh_alias_host() {
  local output
  output="$("$GIT_PROFILE" _url_https_to_ssh "https://github.com/user/repo.git" "github.com-work")"
  assert_eq "https→ssh alias host" "git@github.com-work:user/repo.git" "$output"
}

test_ssh_to_https_basic() {
  local output
  output="$("$GIT_PROFILE" _url_ssh_to_https "git@github.com:user/repo.git" "github.com")"
  assert_eq "ssh→https basic" "https://github.com/user/repo.git" "$output"
}

test_ssh_to_https_alias_host() {
  local output
  output="$("$GIT_PROFILE" _url_ssh_to_https "git@github.com-work:user/repo.git" "github.com")"
  assert_eq "ssh→https alias host" "https://github.com/user/repo.git" "$output"
}

test_profile_ssh_host_single() {
  setup_test_home
  cat > "$TEST_HOME/.git-profiles.conf" <<'EOF'
[personal]
name = User
email = user@mail.com
host = github.com
ssh_key = ~/.ssh/key
EOF
  local output
  output="$(CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" _profile_ssh_host "personal")"
  assert_eq "profile_ssh_host single account returns raw host" "github.com" "$output"
  teardown_test_home
}

test_profile_ssh_host_multi_with_alias() {
  setup_test_home
  cat > "$TEST_HOME/.git-profiles.conf" <<'EOF'
[personal]
name = User
email = user@mail.com
host = github.com
ssh_key = ~/.ssh/key_personal

[work]
name = Work
email = work@mail.com
host = github.com
ssh_key = ~/.ssh/key_work
EOF
  # Create SSH config with alias
  cat > "$TEST_HOME/.ssh/config" <<'EOF'
# git-profile: work
Host github.com-work
  HostName github.com
  IdentityFile ~/.ssh/key_work
  IdentitiesOnly yes
EOF
  local output
  output="$(CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" _profile_ssh_host "work")"
  assert_eq "profile_ssh_host multi with alias returns alias" "github.com-work" "$output"
  teardown_test_home
}

test_https_to_ssh_basic
test_https_to_ssh_no_git_suffix
test_https_to_ssh_alias_host
test_ssh_to_https_basic
test_ssh_to_https_alias_host
test_profile_ssh_host_single
test_profile_ssh_host_multi_with_alias

# ── Remote command integration tests ─────────────────────────────────────────

test_remote_set_ssh() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && git remote add origin "https://github.com/user/repo.git")
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=n CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" remote set-ssh)

  local new_url
  new_url="$(cd "$repo" && git remote get-url origin)"
  assert_eq "remote set-ssh converts URL" "git@github.com:user/repo.git" "$new_url"
  teardown_test_home
}

test_remote_set_default_origin() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"
  (cd "$repo" && git remote add origin "https://github.com/user/repo.git")

  local output exit_code=0
  output="$(cd "$repo" && "$GIT_PROFILE" remote set "git@gitlab.com:team/new.git" 2>&1)" || exit_code=$?

  local new_url
  new_url="$(cd "$repo" && git remote get-url origin)"
  assert_exit_code "remote set default origin exits zero" "0" "$exit_code"
  assert_eq "remote set defaults to origin" "git@gitlab.com:team/new.git" "$new_url"
  teardown_test_home
}

test_remote_set_specific_remote() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"
  (cd "$repo" && git remote add origin "https://github.com/user/repo.git")
  (cd "$repo" && git remote add upstream "https://github.com/org/repo.git")

  local output exit_code=0
  output="$(cd "$repo" && "$GIT_PROFILE" remote set upstream "git@gitlab.com:team/upstream.git" 2>&1)" || exit_code=$?

  local origin_url upstream_url
  origin_url="$(cd "$repo" && git remote get-url origin)"
  upstream_url="$(cd "$repo" && git remote get-url upstream)"
  assert_exit_code "remote set specific remote exits zero" "0" "$exit_code"
  assert_eq "remote set keeps origin unchanged" "https://github.com/user/repo.git" "$origin_url"
  assert_eq "remote set updates target remote" "git@gitlab.com:team/upstream.git" "$upstream_url"
  teardown_test_home
}

test_remote_set_missing_remote() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"
  (cd "$repo" && git remote add origin "https://github.com/user/repo.git")

  local output exit_code=0
  output="$(cd "$repo" && "$GIT_PROFILE" remote set upstream "git@gitlab.com:team/upstream.git" 2>&1)" || exit_code=$?

  assert_exit_code "remote set missing remote exits non-zero" "1" "$exit_code"
  assert_contains "remote set missing remote shows clear error" "remote 'upstream' not found" "$output"
  teardown_test_home
}

test_remote_set_missing_url() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"
  (cd "$repo" && git remote add origin "https://github.com/user/repo.git")

  local output exit_code=0
  output="$(cd "$repo" && "$GIT_PROFILE" remote set 2>&1)" || exit_code=$?

  assert_exit_code "remote set missing URL exits non-zero" "1" "$exit_code"
  assert_contains "remote set missing URL shows usage" "git-profile remote set [remote-name] <url>" "$output"
  teardown_test_home
}

test_remote_set_https() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && git remote add origin "git@github.com:user/repo.git")
  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" remote set-https)

  local new_url
  new_url="$(cd "$repo" && git remote get-url origin)"
  assert_eq "remote set-https converts URL" "https://github.com/user/repo.git" "$new_url"
  teardown_test_home
}

test_remote_set_ssh_single_remote() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && git remote add origin "https://github.com/user/repo.git")
  (cd "$repo" && git remote add upstream "https://github.com/org/repo.git")
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=n CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" remote set-ssh upstream)

  local origin_url upstream_url
  origin_url="$(cd "$repo" && git remote get-url origin)"
  upstream_url="$(cd "$repo" && git remote get-url upstream)"
  assert_eq "remote set-ssh single keeps origin unchanged" "https://github.com/user/repo.git" "$origin_url"
  assert_eq "remote set-ssh single converts target" "git@github.com:org/repo.git" "$upstream_url"
  teardown_test_home
}

test_remote_set_ssh_missing_remote() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && git remote add origin "https://github.com/user/repo.git")
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=n CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)

  local output exit_code=0
  output="$(cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" remote set-ssh upstream 2>&1)" || exit_code=$?

  assert_exit_code "remote set-ssh missing remote exits non-zero" "1" "$exit_code"
  assert_contains "remote set-ssh missing remote shows clear error" "remote 'upstream' not found" "$output"
  teardown_test_home
}

test_remote_set_ssh_multi_remotes() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && git remote add origin "https://github.com/user/repo.git")
  (cd "$repo" && git remote add upstream "https://github.com/org/repo.git")
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=n CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" remote set-ssh)

  local url_origin url_upstream
  url_origin="$(cd "$repo" && git remote get-url origin)"
  url_upstream="$(cd "$repo" && git remote get-url upstream)"
  assert_eq "multi remote: origin converted" "git@github.com:user/repo.git" "$url_origin"
  assert_eq "multi remote: upstream converted" "git@github.com:org/repo.git" "$url_upstream"
  teardown_test_home
}

test_remote_show_output() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && git remote add origin "https://github.com/user/repo.git")
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=n CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)

  local output
  output="$(cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" remote show 2>&1)"
  assert_contains "remote show lists origin" "origin" "$output"
  assert_contains "remote show shows URL" "https://github.com/user/repo.git" "$output"
  assert_contains "remote show shows HTTPS label" "[HTTPS]" "$output"
  teardown_test_home
}

test_remote_set_ssh_already_ssh() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && git remote add origin "git@github.com:user/repo.git")
  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)

  local output
  output="$(cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" remote set-ssh 2>&1)"
  assert_contains "already SSH shows message" "already using SSH" "$output"
  teardown_test_home
}

test_remote_set_https_single_remote() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && git remote add origin "git@github.com:user/repo.git")
  (cd "$repo" && git remote add upstream "git@github.com:org/repo.git")
  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)
  (cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" remote set-https upstream)

  local origin_url upstream_url
  origin_url="$(cd "$repo" && git remote get-url origin)"
  upstream_url="$(cd "$repo" && git remote get-url upstream)"
  assert_eq "remote set-https single keeps origin unchanged" "git@github.com:user/repo.git" "$origin_url"
  assert_eq "remote set-https single converts target" "https://github.com/org/repo.git" "$upstream_url"
  teardown_test_home
}

test_remote_set_https_missing_remote() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[work]
name = Work User
email = work@company.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_work
EOF
  touch "$TEST_HOME/.ssh/git_profile_work"

  (cd "$repo" && git remote add origin "git@github.com:user/repo.git")
  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use work)

  local output exit_code=0
  output="$(cd "$repo" && GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" remote set-https upstream 2>&1)" || exit_code=$?

  assert_exit_code "remote set-https missing remote exits non-zero" "1" "$exit_code"
  assert_contains "remote set-https missing remote shows clear error" "remote 'upstream' not found" "$output"
  teardown_test_home
}

test_remote_set_default_origin
test_remote_set_specific_remote
test_remote_set_missing_remote
test_remote_set_missing_url
test_remote_set_ssh
test_remote_set_https
test_remote_set_ssh_single_remote
test_remote_set_ssh_missing_remote
test_remote_set_ssh_multi_remotes
test_remote_show_output
test_remote_set_ssh_already_ssh
test_remote_set_https_single_remote
test_remote_set_https_missing_remote

# ── Task: keyless profile ────────────────────────────────────────────────────

test_add_keyless_no_ssh_alias() {
  setup_test_home
  # 先添加有密钥的 profile，占用 github.com
  touch "$TEST_HOME/.ssh/git_profile_first"
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    "$GIT_PROFILE" _add_profile "first" "First" "first@mail.com" "github.com" \
    "$TEST_HOME/.ssh/git_profile_first"

  # 再添加无密钥的 profile，同 host — 不应写 SSH alias
  touch "$TEST_HOME/.ssh/config"
  GIT_PROFILE_AUTO_CONFIRM=y CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    "$GIT_PROFILE" _add_profile "keyless" "Keyless" "keyless@mail.com" "github.com" ""

  local ssh_config
  ssh_config="$(cat "$TEST_HOME/.ssh/config" 2>/dev/null || echo "")"
  if [[ "$ssh_config" == *"keyless"* ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: keyless profile should not write SSH alias, got: $ssh_config"
  else
    PASS=$((PASS + 1))
  fi
  teardown_test_home
}

test_add_keyless_no_ssh_alias

test_add_keyless_interactive() {
  setup_test_home
  # 输入序列：profile名 / 用户名 / 邮箱 / host / 不绑定密钥(n)
  printf "keyless-iact\nKeyless User\nkeyless@mail.com\ngithub.com\nn\n" | \
    CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" add >/dev/null 2>&1 || true

  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "interactive keyless creates section" "[keyless-iact]" "$content"
  assert_contains "interactive keyless writes name" "name = Keyless User" "$content"
  assert_contains "interactive keyless writes email" "email = keyless@mail.com" "$content"
  assert_contains "interactive keyless has ssh_key line" "ssh_key = " "$content"
  teardown_test_home
}

test_add_keyless_interactive

test_use_keyless_no_sshcommand() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"

  cat > "$TEST_HOME/.git-profiles.conf" <<'EOF'
[keyless]
name = Keyless User
email = keyless@mail.com
host = github.com
ssh_key =
EOF

  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use keyless) >/dev/null 2>&1

  local got_ssh
  got_ssh="$(cd "$repo" && git config --local core.sshCommand 2>/dev/null || echo "NOT_SET")"
  assert_eq "keyless use does not write sshCommand" "NOT_SET" "$got_ssh"
  teardown_test_home
}

test_use_keyless_preserves_sshcommand() {
  setup_test_home
  local repo="$TEST_HOME/myrepo"
  git init -q "$repo"
  (cd "$repo" && git config core.sshCommand "ssh -i /existing/key")

  cat > "$TEST_HOME/.git-profiles.conf" <<'EOF'
[keyless]
name = Keyless User
email = keyless@mail.com
host = github.com
ssh_key =
EOF

  (cd "$repo" && CONF_FILE="$TEST_HOME/.git-profiles.conf" "$GIT_PROFILE" use keyless) >/dev/null 2>&1

  local got_ssh
  got_ssh="$(cd "$repo" && git config --local core.sshCommand 2>/dev/null || echo "")"
  assert_eq "keyless use preserves existing sshCommand" "ssh -i /existing/key" "$got_ssh"
  teardown_test_home
}

test_use_keyless_no_sshcommand
test_use_keyless_preserves_sshcommand

report
