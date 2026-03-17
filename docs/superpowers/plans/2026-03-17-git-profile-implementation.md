# Git Profile Manager Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `git-profile`, a Bash CLI tool for managing multiple Git identities (SSH keys + user/email) per project.

**Architecture:** Single Bash script (`git-profile`) with an INI parser, subcommand dispatcher, and interactive menu. All profile data stored in `~/.git-profiles.conf`. Directory rules leverage git's native `includeIf` with generated gitconfig fragments. An `install.sh` handles deployment. A test suite (`tests/test_git_profile.sh`) validates all commands in isolated temporary environments.

**Tech Stack:** Bash 3.2+, git, ssh-keygen, ssh

---

## File Structure

| File | Responsibility |
|------|----------------|
| `git-profile` | Main script: INI parser, subcommand dispatcher, all commands, interactive menu |
| `install.sh` | Installation: copy script, init config, create dirs, set git alias |
| `tests/test_git_profile.sh` | Integration test suite: each command tested in isolated tmp dirs with mock HOME |

All three files are new. No existing code to modify.

---

## Chunk 1: Script Skeleton, INI Parser, and `list` Command

This chunk builds the foundation: script structure, dependency checks, INI config parser (read/write), and the simplest command (`list`) to prove the parser works end-to-end.

### Task 1: Script skeleton with dependency checks and subcommand dispatcher

**Files:**
- Create: `git-profile`
- Create: `tests/test_git_profile.sh`

- [ ] **Step 1: Write the test for dependency check and version flag**

```bash
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

# --- Test: --version ---
test_version_flag() {
  local output
  output="$("$GIT_PROFILE" --version 2>&1)"
  assert_contains "--version outputs version" "git-profile" "$output"
}

# --- Test: --help ---
test_help_flag() {
  local output
  output="$("$GIT_PROFILE" --help 2>&1)"
  assert_contains "--help shows usage" "usage" "$(echo "$output" | tr '[:upper:]' '[:lower:]')"
}

# --- Test: unknown subcommand ---
test_unknown_subcommand() {
  local exit_code=0
  "$GIT_PROFILE" nonexistent 2>/dev/null || exit_code=$?
  assert_eq "unknown subcommand exits non-zero" "1" "$exit_code"
}

# --- Run tests ---
test_version_flag
test_help_flag
test_unknown_subcommand
report
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: FAIL — `git-profile` does not exist yet

- [ ] **Step 3: Write the script skeleton**

```bash
#!/usr/bin/env bash
# git-profile — manage multiple Git identities
set -euo pipefail

VERSION="0.1.0"

# --- Dependency checks ---
check_dependencies() {
  local missing=""
  for cmd in git ssh-keygen ssh; do
    if ! command -v "$cmd" &>/dev/null; then
      missing="$missing $cmd"
    fi
  done
  if [[ -n "$missing" ]]; then
    echo "Error: missing required tools:$missing" >&2
    echo "Please install them before using git-profile." >&2
    exit 1
  fi
}

# --- realpath fallback ---
resolve_path() {
  local path="$1"
  if command -v realpath &>/dev/null; then
    realpath "$path"
  else
    (cd "$(dirname "$path")" && echo "$(pwd)/$(basename "$path")")
  fi
}

# --- Help ---
show_help() {
  cat <<'HELP'
Usage: git-profile <command> [args]

Commands:
  add                 Add a new profile (interactive)
  edit <name>         Edit an existing profile
  list                List all profiles
  use <name>          Apply a profile to the current project
  use --clear         Remove profile override, restore original config
  current             Show the current project's active profile
  rule add            Add a directory rule
  rule list           List directory rules
  rule remove         Remove a directory rule
  remove <name>       Remove a profile

Options:
  --help              Show this help message
  --version           Show version

Run without arguments for interactive menu.
HELP
}

# --- Config file path ---
CONF_FILE="${HOME}/.git-profiles.conf"
GITCONFIG_D="${HOME}/.gitconfig.d"

# --- Main dispatcher ---
main() {
  check_dependencies

  if [[ $# -eq 0 ]]; then
    interactive_menu
    return
  fi

  case "$1" in
    --version) echo "git-profile $VERSION" ;;
    --help)    show_help ;;
    add)       shift; cmd_add "$@" ;;
    edit)      shift; cmd_edit "$@" ;;
    list)      cmd_list ;;
    use)       shift; cmd_use "$@" ;;
    current)   cmd_current ;;
    rule)      shift; cmd_rule "$@" ;;
    remove)    shift; cmd_remove "$@" ;;
    *)         echo "Error: unknown command '$1'. Run 'git-profile --help' for usage." >&2; exit 1 ;;
  esac
}

# --- Stub commands (to be implemented) ---
interactive_menu() { echo "TODO: interactive menu"; }
cmd_add() { echo "TODO: add"; }
cmd_edit() { echo "TODO: edit"; }
cmd_list() { echo "TODO: list"; }
cmd_use() { echo "TODO: use"; }
cmd_current() { echo "TODO: current"; }
cmd_rule() { echo "TODO: rule"; }
cmd_remove() { echo "TODO: remove"; }

main "$@"
```

- [ ] **Step 4: Make script executable and run tests**

Run: `chmod +x git-profile && bash tests/test_git_profile.sh`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add script skeleton with dispatcher, deps check, and tests"
```

### Task 2: INI config parser (read)

**Files:**
- Modify: `git-profile`
- Modify: `tests/test_git_profile.sh`

The parser must handle two section types: profile sections `[name]` and rule sections `[rule "name"]`. It produces output in a structured format that other functions can grep/awk.

- [ ] **Step 1: Write tests for INI parser**

Append to `tests/test_git_profile.sh` (before `report`):

```bash
# --- Test: INI parser ---
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
  # Source the script to access functions
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: The 3 new tests FAIL (stubs return "TODO")

- [ ] **Step 3: Implement INI parser and list/rule list commands**

Replace the stubs in `git-profile` with:

```bash
# --- INI Parser ---
# Reads CONF_FILE. Outputs structured lines:
#   PROFILE:<name>:<key>=<value>
#   RULE:<rule_name>:<key>=<value>
parse_config() {
  local conf="${CONF_FILE}"
  [[ -f "$conf" ]] || return 0

  local current_section="" section_type=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Trim leading/trailing whitespace
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Rule section: [rule "name"]
    if [[ "$line" =~ ^\[rule\ \"([^\"]+)\"\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      section_type="RULE"
      continue
    fi

    # Profile section: [name]
    if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      section_type="PROFILE"
      continue
    fi

    # Key = value
    if [[ -n "$current_section" && "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\ *=\ *(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      # Trim trailing whitespace from value
      value="$(echo "$value" | sed 's/[[:space:]]*$//')"
      echo "${section_type}:${current_section}:${key}=${value}"
    fi
  done < "$conf"
}

# Get a specific profile field
get_profile_field() {
  local profile_name="$1" field="$2"
  parse_config | grep "^PROFILE:${profile_name}:${field}=" | head -1 | sed "s/^PROFILE:${profile_name}:${field}=//"
}

# List all profile names
list_profile_names() {
  parse_config | grep "^PROFILE:" | sed 's/^PROFILE:\([^:]*\):.*/\1/' | sort -u
}

# List all rule names
list_rule_names() {
  parse_config | grep "^RULE:" | sed 's/^RULE:\([^:]*\):.*/\1/' | sort -u
}

# Get a specific rule field
get_rule_field() {
  local rule_name="$1" field="$2"
  parse_config | grep "^RULE:${rule_name}:${field}=" | head -1 | sed "s/^RULE:${rule_name}:${field}=//"
}

# --- list command ---
cmd_list() {
  local names
  names="$(list_profile_names)"
  if [[ -z "$names" ]]; then
    echo "No profiles configured. Run 'git-profile add' to create one."
    return
  fi
  echo "Configured profiles:"
  echo ""
  while IFS= read -r name; do
    local p_name p_email p_host p_key
    p_name="$(get_profile_field "$name" "name")"
    p_email="$(get_profile_field "$name" "email")"
    p_host="$(get_profile_field "$name" "host")"
    p_key="$(get_profile_field "$name" "ssh_key")"
    echo "  [$name]"
    echo "    Name:  $p_name"
    echo "    Email: $p_email"
    echo "    Host:  $p_host"
    echo "    Key:   $p_key"
    echo ""
  done <<< "$names"
}

# --- rule command dispatcher ---
cmd_rule() {
  if [[ $# -eq 0 ]]; then
    interactive_rule_menu
    return
  fi
  case "$1" in
    add)    shift; cmd_rule_add "$@" ;;
    list)   cmd_rule_list ;;
    remove) shift; cmd_rule_remove "$@" ;;
    *)      echo "Error: unknown rule command '$1'" >&2; exit 1 ;;
  esac
}

cmd_rule_list() {
  local names
  names="$(list_rule_names)"
  if [[ -z "$names" ]]; then
    echo "No directory rules configured. Run 'git-profile rule add' to create one."
    return
  fi
  echo "Directory rules:"
  echo ""
  while IFS= read -r rname; do
    local r_dir r_profile
    r_dir="$(get_rule_field "$rname" "dir")"
    r_profile="$(get_rule_field "$rname" "profile")"
    echo "  [$rname]"
    echo "    Directory: $r_dir"
    echo "    Profile:   $r_profile"
    echo ""
  done <<< "$names"
}

# Stubs for rule subcommands
cmd_rule_add() { echo "TODO: rule add"; }
cmd_rule_remove() { echo "TODO: rule remove"; }
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_git_profile.sh`
Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add INI config parser, list and rule list commands"
```

### Task 3: INI config writer (add/update/delete sections)

**Files:**
- Modify: `git-profile`
- Modify: `tests/test_git_profile.sh`

- [ ] **Step 1: Write tests for config write operations**

Append to `tests/test_git_profile.sh` (before `report`):

```bash
# --- Test: config writer ---
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
  # Should not contain deleted section
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: New tests FAIL

- [ ] **Step 3: Implement config write functions**

Add to `git-profile` (after parser functions, before command implementations):

```bash
# --- Config Writer ---

# Write a profile section to config file.
# Usage: write_profile_section <profile_name> <name> <email> <host> <ssh_key>
write_profile_section() {
  local pname="$1" uname="$2" email="$3" host="$4" ssh_key="$5"
  # Delete existing section first if present
  delete_config_section "$pname"
  cat >> "$CONF_FILE" <<EOF

[$pname]
name = $uname
email = $email
host = $host
ssh_key = $ssh_key
EOF
}

# Write a rule section to config file.
# Usage: write_rule_section <rule_name> <dir> <profile>
write_rule_section() {
  local rname="$1" dir="$2" profile="$3"
  delete_config_section "rule:$rname"
  cat >> "$CONF_FILE" <<EOF

[rule "$rname"]
dir = $dir
profile = $profile
EOF
}

# Delete a section from config file.
# For profiles: delete_config_section "profile_name"
# For rules: delete_config_section "rule:rule_name"
delete_config_section() {
  local target="$1"
  [[ -f "$CONF_FILE" ]] || return 0

  local header_pattern
  if [[ "$target" == rule:* ]]; then
    local rname="${target#rule:}"
    header_pattern="^\[rule \"${rname}\"\]$"
  else
    header_pattern="^\[${target}\]$"
  fi

  local tmpfile
  tmpfile="$(mktemp)"
  local in_target=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    local trimmed
    trimmed="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ "$trimmed" =~ $header_pattern ]]; then
      in_target=true
      continue
    fi
    # New section starts -> stop skipping
    if $in_target && [[ "$trimmed" =~ ^\[.+\]$ ]]; then
      in_target=false
    fi
    if ! $in_target; then
      echo "$line" >> "$tmpfile"
    fi
  done < "$CONF_FILE"
  mv "$tmpfile" "$CONF_FILE"
}

# Validate profile name: only [a-zA-Z0-9_-], not starting with "rule"
validate_profile_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: profile name can only contain letters, numbers, hyphens, and underscores." >&2
    return 1
  fi
  if [[ "$name" =~ ^rule ]]; then
    echo "Error: profile name cannot start with 'rule'." >&2
    return 1
  fi
  return 0
}
```

Also add hidden internal commands to the dispatcher so tests can invoke them:

```bash
# In main() case statement, add:
    _write_profile) shift; write_profile_section "$@" ;;
    _delete_section) shift; delete_config_section "$@" ;;
    _write_rule)     shift; write_rule_section "$@" ;;
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_git_profile.sh`
Expected: All 9 tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add config writer (write/delete profile and rule sections)"
```

---

## Chunk 2: `add` Command and SSH Key Generation

### Task 4: `add` command — non-interactive path for testing

**Files:**
- Modify: `git-profile`
- Modify: `tests/test_git_profile.sh`

The `add` command is interactive in normal use, but we need a non-interactive code path for testing. We implement the core logic first, then wrap it with interactive prompts.

- [ ] **Step 1: Write tests for add**

Append to `tests/test_git_profile.sh` (before `report`):

```bash
# --- Test: add command ---
test_add_profile_with_existing_key() {
  setup_test_home
  # Create a fake key
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

  # Key should exist
  if [[ -f "$TEST_HOME/.ssh/git_profile_newprof" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: SSH key file not generated"
  fi

  # Key permissions should be 600
  if [[ "$(stat -f '%Lp' "$TEST_HOME/.ssh/git_profile_newprof" 2>/dev/null || stat -c '%a' "$TEST_HOME/.ssh/git_profile_newprof" 2>/dev/null)" == "600" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: SSH key permissions not 600"
  fi

  # Profile should be in config
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "keygen add writes profile" "[newprof]" "$content"
  teardown_test_home
}

test_add_same_host_writes_ssh_alias() {
  setup_test_home
  # First profile on github.com
  touch "$TEST_HOME/.ssh/git_profile_first"
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    "$GIT_PROFILE" _add_profile "first" "First" "first@mail.com" "github.com" "$TEST_HOME/.ssh/git_profile_first"

  # Second profile on github.com — should trigger SSH alias
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
  # Should NOT have written anything
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: New tests FAIL

- [ ] **Step 3: Implement add core logic**

Add to `git-profile`:

```bash
# --- SSH config management ---

# Backup ~/.ssh/config with timestamp
backup_ssh_config() {
  local ssh_config="${HOME}/.ssh/config"
  if [[ -f "$ssh_config" ]]; then
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    cp "$ssh_config" "${ssh_config}.bak.${timestamp}"
  fi
}

# Check if a host already has another profile in config
host_has_other_profiles() {
  local host="$1" exclude_profile="$2"
  local names
  names="$(list_profile_names)"
  [[ -z "$names" ]] && return 1
  while IFS= read -r pname; do
    [[ "$pname" == "$exclude_profile" ]] && continue
    local phost
    phost="$(get_profile_field "$pname" "host")"
    if [[ "$phost" == "$host" ]]; then
      return 0
    fi
  done <<< "$names"
  return 1
}

# Write SSH Host alias block
write_ssh_alias() {
  local profile_name="$1" host="$2" key_path="$3"
  local ssh_config="${HOME}/.ssh/config"
  local alias_host="${host}-${profile_name}"

  # Check if alias already exists
  if [[ -f "$ssh_config" ]] && grep -q "# git-profile: ${profile_name}" "$ssh_config"; then
    return 0
  fi

  backup_ssh_config
  cat >> "$ssh_config" <<EOF

# git-profile: ${profile_name}
Host ${alias_host}
  HostName ${host}
  User git
  IdentityFile ${key_path}
  IdentitiesOnly yes
EOF
  echo "SSH alias added: ${alias_host} -> ${host}"
  echo "  Use this in clone URLs: git@${alias_host}:<user>/<repo>.git"
}

# --- Add core logic (non-interactive, for testing) ---

# _add_profile <name> <user> <email> <host> <key_path>
_add_profile() {
  local pname="$1" uname="$2" email="$3" host="$4" key_path="$5"

  validate_profile_name "$pname" || return 1

  write_profile_section "$pname" "$uname" "$email" "$host" "$key_path"

  # Check for same-host multi-account
  if host_has_other_profiles "$host" "$pname"; then
    if [[ "${GIT_PROFILE_AUTO_CONFIRM:-}" == "y" ]]; then
      write_ssh_alias "$pname" "$host" "$key_path"
    else
      echo ""
      echo "Detected another profile using the same host '$host'."
      read -rp "Add SSH Host alias '${host}-${pname}' to ~/.ssh/config? [y/N] " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        write_ssh_alias "$pname" "$host" "$key_path"
      fi
    fi
  fi

  echo "Profile '$pname' added successfully."
}

# _add_profile_with_keygen <name> <user> <email> <host> <algorithm>
_add_profile_with_keygen() {
  local pname="$1" uname="$2" email="$3" host="$4" algo="${5:-ed25519}"
  local key_path="${HOME}/.ssh/git_profile_${pname}"

  validate_profile_name "$pname" || return 1

  if [[ -f "$key_path" ]]; then
    echo "Warning: key file '$key_path' already exists."
    if [[ "${GIT_PROFILE_AUTO_CONFIRM:-}" != "y" ]]; then
      read -rp "Overwrite? [y/N] " confirm
      [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 1
    fi
  fi

  ssh-keygen -t "$algo" -C "${email}" -f "$key_path" -N "" -q
  chmod 600 "$key_path"

  echo ""
  echo "Public key (add this to your Git platform):"
  echo "---"
  cat "${key_path}.pub"
  echo "---"
  echo ""

  _add_profile "$pname" "$uname" "$email" "$host" "$key_path"
}
```

Update the main dispatcher:

```bash
    _add_profile)           shift; _add_profile "$@" ;;
    _add_profile_with_keygen) shift; _add_profile_with_keygen "$@" ;;
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_git_profile.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add profile creation with SSH key generation and host alias detection"
```

### Task 5: `add` command — interactive wrapper

**Files:**
- Modify: `git-profile`

- [ ] **Step 1: Implement interactive `cmd_add`**

Replace the `cmd_add` stub:

```bash
cmd_add() {
  echo "=== Add New Profile ==="
  echo ""

  # Profile name
  local pname=""
  while [[ -z "$pname" ]]; do
    read -rp "Profile name (e.g., personal, work): " pname
    if [[ -z "$pname" ]]; then
      echo "Profile name cannot be empty."
      continue
    fi
    if ! validate_profile_name "$pname"; then
      pname=""
      continue
    fi
    # Check existing
    if list_profile_names | grep -qx "$pname"; then
      read -rp "Profile '$pname' already exists. Overwrite? [y/N] " confirm
      if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        pname=""
      fi
    fi
  done

  # User details
  local uname=""
  read -rp "User name: " uname
  [[ -z "$uname" ]] && { echo "Error: name cannot be empty." >&2; return 1; }

  local email=""
  read -rp "Email: " email
  [[ -z "$email" ]] && { echo "Error: email cannot be empty." >&2; return 1; }

  local host=""
  read -rp "Git platform host (e.g., github.com): " host
  [[ -z "$host" ]] && { echo "Error: host cannot be empty." >&2; return 1; }

  # SSH key
  local gen_key=""
  read -rp "Generate a new SSH key? [Y/n] " gen_key
  if [[ "$gen_key" != "n" && "$gen_key" != "N" ]]; then
    local algo=""
    read -rp "Key algorithm [ed25519/rsa] (default: ed25519): " algo
    algo="${algo:-ed25519}"
    _add_profile_with_keygen "$pname" "$uname" "$email" "$host" "$algo"
  else
    local key_path=""
    read -rp "Path to existing SSH private key: " key_path
    key_path="${key_path/#\~/$HOME}"
    if [[ ! -f "$key_path" ]]; then
      echo "Error: key file '$key_path' not found." >&2
      return 1
    fi
    _add_profile "$pname" "$uname" "$email" "$host" "$key_path"
  fi
}
```

- [ ] **Step 2: Manual smoke test**

Run: `./git-profile add` and walk through the prompts to verify the flow works.

- [ ] **Step 3: Commit**

```bash
git add git-profile
git commit -m "feat: add interactive add command with prompts"
```

---

## Chunk 3: `use`, `use --clear`, and `current` Commands

### Task 6: `use` command with backup/restore

**Files:**
- Modify: `git-profile`
- Modify: `tests/test_git_profile.sh`

- [ ] **Step 1: Write tests for use command**

Append to `tests/test_git_profile.sh` (before `report`):

```bash
# --- Test: use command ---
test_use_applies_config() {
  setup_test_home
  # Create a git repo
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
  # Set original local values
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
  # No original local values

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

  # user.name should be unset from local (no backup existed)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: New tests FAIL

- [ ] **Step 3: Implement `cmd_use`**

Replace the `cmd_use` stub:

```bash
# --- use command ---
cmd_use() {
  # Handle --clear
  if [[ "${1:-}" == "--clear" ]]; then
    cmd_use_clear
    return
  fi

  # Check git repo
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
  fi

  # Determine profile name
  local pname="${1:-}"
  if [[ -z "$pname" ]]; then
    # Interactive: list profiles and let user pick
    local names
    names="$(list_profile_names)"
    if [[ -z "$names" ]]; then
      echo "No profiles configured. Run 'git-profile add' first." >&2
      exit 1
    fi
    echo "Select a profile:"
    local i=1
    local name_arr=()
    while IFS= read -r n; do
      name_arr+=("$n")
      local p_email
      p_email="$(get_profile_field "$n" "email")"
      echo "  $i) $n ($p_email)"
      i=$((i + 1))
    done <<< "$names"
    local choice
    read -rp "Enter number: " choice
    if [[ "$choice" -lt 1 || "$choice" -gt ${#name_arr[@]} ]] 2>/dev/null; then
      echo "Error: invalid choice." >&2
      exit 1
    fi
    pname="${name_arr[$((choice - 1))]}"
  fi

  # Validate profile exists
  local p_name p_email p_host p_key
  p_name="$(get_profile_field "$pname" "name")"
  if [[ -z "$p_name" ]]; then
    echo "Error: profile '$pname' not found." >&2
    exit 1
  fi
  p_email="$(get_profile_field "$pname" "email")"
  p_host="$(get_profile_field "$pname" "host")"
  p_key="$(get_profile_field "$pname" "ssh_key")"
  # Expand ~ in key path
  p_key="${p_key/#\~/$HOME}"

  # Check if in a rule's scope and warn
  local rule_names
  rule_names="$(list_rule_names)"
  if [[ -n "$rule_names" ]]; then
    local effective_profile
    effective_profile="$(git config gitProfile.name 2>/dev/null || echo "")"
    local local_profile
    local_profile="$(git config --local gitProfile.name 2>/dev/null || echo "")"
    if [[ -n "$effective_profile" && -z "$local_profile" ]]; then
      # Profile comes from includeIf, not local
      echo "Note: current directory is matched by a directory rule (profile: $effective_profile)."
      echo "  'use' will override this rule. To undo, run: git-profile use --clear"
      echo ""
    fi
  fi

  # Backup original local values (only on first use)
  local existing_local_profile
  existing_local_profile="$(git config --local gitProfile.name 2>/dev/null || echo "")"
  if [[ -z "$existing_local_profile" ]]; then
    # First use — backup current local values
    local orig_name orig_email orig_ssh
    orig_name="$(git config --local user.name 2>/dev/null || echo "")"
    orig_email="$(git config --local user.email 2>/dev/null || echo "")"
    orig_ssh="$(git config --local core.sshCommand 2>/dev/null || echo "")"
    [[ -n "$orig_name" ]] && git config --local gitProfile.backup.userName "$orig_name"
    [[ -n "$orig_email" ]] && git config --local gitProfile.backup.userEmail "$orig_email"
    [[ -n "$orig_ssh" ]] && git config --local gitProfile.backup.sshCommand "$orig_ssh"
  fi

  # Apply profile
  git config --local gitProfile.name "$pname"
  git config --local user.name "$p_name"
  git config --local user.email "$p_email"
  git config --local core.sshCommand "ssh -i \"$p_key\" -o IdentitiesOnly=yes"

  # Check for HTTPS remotes
  local remotes
  remotes="$(git remote -v 2>/dev/null | grep 'https://' | head -1 || echo "")"
  if [[ -n "$remotes" ]]; then
    echo "Note: some remotes use HTTPS. SSH config won't affect HTTPS remotes."
  fi

  echo "Profile '$pname' applied to current project."
  echo "  Name:  $p_name"
  echo "  Email: $p_email"
  echo "  Key:   $p_key"
}

cmd_use_clear() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
  fi

  local local_profile
  local_profile="$(git config --local gitProfile.name 2>/dev/null || echo "")"
  if [[ -z "$local_profile" ]]; then
    echo "Current project has no profile override to clear."
    return
  fi

  # Restore from backup
  local backup_name backup_email backup_ssh
  backup_name="$(git config --local gitProfile.backup.userName 2>/dev/null || echo "")"
  backup_email="$(git config --local gitProfile.backup.userEmail 2>/dev/null || echo "")"
  backup_ssh="$(git config --local gitProfile.backup.sshCommand 2>/dev/null || echo "")"

  if [[ -n "$backup_name" ]]; then
    git config --local user.name "$backup_name"
  else
    git config --local --unset user.name 2>/dev/null || true
  fi

  if [[ -n "$backup_email" ]]; then
    git config --local user.email "$backup_email"
  else
    git config --local --unset user.email 2>/dev/null || true
  fi

  if [[ -n "$backup_ssh" ]]; then
    git config --local core.sshCommand "$backup_ssh"
  else
    git config --local --unset core.sshCommand 2>/dev/null || true
  fi

  # Remove all gitProfile keys — git stores dotted subsections separately
  # gitProfile.name is under [gitProfile], gitProfile.backup.* is under [gitProfile "backup"]
  git config --local --remove-section gitProfile 2>/dev/null || true
  git config --local --remove-section 'gitProfile "backup"' 2>/dev/null || true

  echo "Profile override cleared. Restored to original state."
  # Show what's effective now
  local eff_name eff_email
  eff_name="$(git config user.name 2>/dev/null || echo "(not set)")"
  eff_email="$(git config user.email 2>/dev/null || echo "(not set)")"
  echo "  Effective name:  $eff_name"
  echo "  Effective email: $eff_email"
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_git_profile.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add use command with backup/restore and --clear"
```

### Task 7: `current` command

**Files:**
- Modify: `git-profile`
- Modify: `tests/test_git_profile.sh`

- [ ] **Step 1: Write tests for current**

Append to `tests/test_git_profile.sh` (before `report`):

```bash
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
  # Should show raw git config values or "not set"
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: New tests FAIL

- [ ] **Step 3: Implement `cmd_current`**

Replace the `cmd_current` stub:

```bash
cmd_current() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
  fi

  local eff_profile local_profile source_label
  eff_profile="$(git config gitProfile.name 2>/dev/null || echo "")"
  local_profile="$(git config --local gitProfile.name 2>/dev/null || echo "")"

  if [[ -n "$local_profile" ]]; then
    # Profile set by 'use' command
    # Check if it overrides a rule
    local rule_profile=""
    # Temporarily check what includeIf would say by reading without local
    # We can detect this by comparing local vs effective when local is set
    source_label="project config"

    # Check rules in our config to see if any match current dir
    local rule_names
    rule_names="$(list_rule_names)"
    if [[ -n "$rule_names" ]]; then
      local cwd
      cwd="$(pwd)"
      while IFS= read -r rname; do
        local r_dir r_prof
        r_dir="$(get_rule_field "$rname" "dir")"
        r_prof="$(get_rule_field "$rname" "profile")"
        # Expand ~ in dir
        r_dir="${r_dir/#\~/$HOME}"
        if [[ "$cwd" == "$r_dir"* ]]; then
          source_label="project config (overrides rule: $rname)"
          break
        fi
      done <<< "$rule_names"
    fi

    # Display from profile config
    local p_name p_email p_host p_key
    p_name="$(get_profile_field "$local_profile" "name")"
    p_email="$(get_profile_field "$local_profile" "email")"
    p_host="$(get_profile_field "$local_profile" "host")"
    p_key="$(get_profile_field "$local_profile" "ssh_key")"

    echo "Current Git Profile: $local_profile"
    echo "  Name:   ${p_name:-$(git config user.name 2>/dev/null || echo '(not set)')}"
    echo "  Email:  ${p_email:-$(git config user.email 2>/dev/null || echo '(not set)')}"
    echo "  Host:   ${p_host:-(not set)}"
    echo "  Key:    ${p_key:-(not set)}"
    echo "  Source: $source_label"

  elif [[ -n "$eff_profile" ]]; then
    # Profile set by includeIf rule
    # Find which rule
    local rule_label="includeIf"
    local rule_names
    rule_names="$(list_rule_names)"
    if [[ -n "$rule_names" ]]; then
      while IFS= read -r rname; do
        local r_prof
        r_prof="$(get_rule_field "$rname" "profile")"
        if [[ "$r_prof" == "$eff_profile" ]]; then
          rule_label="includeIf rule: $rname"
          break
        fi
      done <<< "$rule_names"
    fi

    local p_name p_email p_host p_key
    p_name="$(get_profile_field "$eff_profile" "name")"
    p_email="$(get_profile_field "$eff_profile" "email")"
    p_host="$(get_profile_field "$eff_profile" "host")"
    p_key="$(get_profile_field "$eff_profile" "ssh_key")"

    echo "Current Git Profile: $eff_profile"
    echo "  Name:   ${p_name:-$(git config user.name 2>/dev/null || echo '(not set)')}"
    echo "  Email:  ${p_email:-$(git config user.email 2>/dev/null || echo '(not set)')}"
    echo "  Host:   ${p_host:-(not set)}"
    echo "  Key:    ${p_key:-(not set)}"
    echo "  Source: $rule_label"

  else
    # No git-profile marker — try to infer
    local eff_name eff_email
    eff_name="$(git config user.name 2>/dev/null || echo "")"
    eff_email="$(git config user.email 2>/dev/null || echo "")"

    # Try matching against known profiles
    local matched=""
    local names
    names="$(list_profile_names)"
    if [[ -n "$names" && -n "$eff_name" && -n "$eff_email" ]]; then
      while IFS= read -r pn; do
        local pn_name pn_email
        pn_name="$(get_profile_field "$pn" "name")"
        pn_email="$(get_profile_field "$pn" "email")"
        if [[ "$pn_name" == "$eff_name" && "$pn_email" == "$eff_email" ]]; then
          matched="$pn"
          break
        fi
      done <<< "$names"
    fi

    if [[ -n "$matched" ]]; then
      local p_host p_key
      p_host="$(get_profile_field "$matched" "host")"
      p_key="$(get_profile_field "$matched" "ssh_key")"
      echo "Current Git Profile: $matched (inferred)"
      echo "  Name:   $eff_name"
      echo "  Email:  $eff_email"
      echo "  Host:   ${p_host:-(not set)}"
      echo "  Key:    ${p_key:-(not set)}"
      echo "  Source: $(git config --show-origin user.name 2>/dev/null | cut -f1 || echo 'unknown')"
    else
      echo "Current Git Profile: (not set)"
      echo "  Name:   ${eff_name:-(not set)}"
      echo "  Email:  ${eff_email:-(not set)}"
      echo "  Source: $(git config --show-origin user.name 2>/dev/null | cut -f1 || echo 'unknown')"
    fi
  fi
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_git_profile.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add current command with source detection and fallback inference"
```

---

## Chunk 4: `rule` Commands, `edit`, and `remove`

### Task 8: `rule add` with path normalization

**Files:**
- Modify: `git-profile`
- Modify: `tests/test_git_profile.sh`

- [ ] **Step 1: Write tests for rule add**

Append to `tests/test_git_profile.sh` (before `report`):

```bash
# --- Test: rule add ---
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

  # Use internal command for non-interactive testing
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    GITCONFIG_D="$TEST_HOME/.gitconfig.d" \
    GIT_PROFILE_AUTO_CONFIRM=y \
    "$GIT_PROFILE" _rule_add "work-projects" "$target_dir" "work"

  # Check config file
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  assert_contains "rule section created" '[rule "work-projects"]' "$content"
  # Path should be absolute and end with /
  assert_contains "rule dir ends with /" "dir = ${target_dir}/" "$content"

  # Check gitconfig.d fragment
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
  # Should have expanded ~ to $HOME
  assert_contains "tilde expanded" "dir = ${TEST_HOME}/projects/" "$content"
  teardown_test_home
}

test_rule_add_normalizes_path
test_rule_add_tilde_expansion
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: New tests FAIL

- [ ] **Step 3: Implement rule add**

Add to `git-profile`:

```bash
# --- Path normalization ---
normalize_path() {
  local path="$1"
  # Expand ~
  path="${path/#\~/$HOME}"
  # Make absolute
  if [[ "$path" != /* ]]; then
    path="$(pwd)/$path"
  fi
  # Resolve realpath if directory exists
  if [[ -d "$path" ]]; then
    if command -v realpath &>/dev/null; then
      path="$(realpath "$path")"
    else
      path="$(cd "$path" && pwd)"
    fi
  else
    echo "Warning: directory '$path' does not exist. Cannot resolve symlinks." >&2
    echo "  If the path contains symlinks, the rule may not match." >&2
  fi
  # Ensure trailing /
  [[ "$path" != */ ]] && path="${path}/"
  echo "$path"
}

# --- Generate gitconfig.d fragment ---
write_gitconfig_fragment() {
  local profile_name="$1"
  local p_name p_email p_key
  p_name="$(get_profile_field "$profile_name" "name")"
  p_email="$(get_profile_field "$profile_name" "email")"
  p_key="$(get_profile_field "$profile_name" "ssh_key")"
  p_key="${p_key/#\~/$HOME}"

  local fragment_path="${GITCONFIG_D}/${profile_name}"
  cat > "$fragment_path" <<EOF
[gitProfile]
  name = ${profile_name}
[user]
  name = ${p_name}
  email = ${p_email}
[core]
  sshCommand = ssh -i \"${p_key}\" -o IdentitiesOnly=yes
EOF
  echo "$fragment_path"
}

# Internal non-interactive rule add
# _rule_add <rule_name> <dir> <profile_name>
_rule_add() {
  local rname="$1" dir="$2" profile="$3"

  # Validate profile exists
  local p_name
  p_name="$(get_profile_field "$profile" "name")"
  if [[ -z "$p_name" ]]; then
    echo "Error: profile '$profile' not found." >&2
    return 1
  fi

  # Normalize path
  local normalized
  normalized="$(normalize_path "$dir")"

  echo "Normalized path: $normalized"
  if [[ "${GIT_PROFILE_AUTO_CONFIRM:-}" != "y" ]]; then
    read -rp "Confirm this path? [Y/n] " confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
      echo "Cancelled."
      return 1
    fi
  fi

  # Write rule to config
  write_rule_section "$rname" "$normalized" "$profile"

  # Generate gitconfig.d fragment
  local fragment_path
  fragment_path="$(write_gitconfig_fragment "$profile")"

  # Write includeIf to global gitconfig
  git config --global includeIf."gitdir:${normalized}".path "$fragment_path"

  echo "Rule '$rname' added."
  echo "  Directory: $normalized"
  echo "  Profile:   $profile"
  echo "  Fragment:  $fragment_path"
}

cmd_rule_add() {
  echo "=== Add Directory Rule ==="
  echo ""

  local rname=""
  read -rp "Rule name: " rname
  [[ -z "$rname" ]] && { echo "Error: rule name cannot be empty." >&2; return 1; }

  local dir=""
  read -rp "Directory path: " dir
  [[ -z "$dir" ]] && { echo "Error: directory path cannot be empty." >&2; return 1; }

  echo ""
  echo "Available profiles:"
  local names
  names="$(list_profile_names)"
  if [[ -z "$names" ]]; then
    echo "No profiles configured. Run 'git-profile add' first." >&2
    return 1
  fi
  local i=1 name_arr=()
  while IFS= read -r n; do
    name_arr+=("$n")
    echo "  $i) $n"
    i=$((i + 1))
  done <<< "$names"
  local choice
  read -rp "Select profile number: " choice
  if [[ "$choice" -lt 1 || "$choice" -gt ${#name_arr[@]} ]] 2>/dev/null; then
    echo "Error: invalid choice." >&2
    return 1
  fi
  local profile="${name_arr[$((choice - 1))]}"

  _rule_add "$rname" "$dir" "$profile"
}
```

Update dispatcher:

```bash
    _rule_add) shift; _rule_add "$@" ;;
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_git_profile.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add rule add with path normalization and gitconfig.d fragment generation"
```

### Task 9: `rule remove`

**Files:**
- Modify: `git-profile`
- Modify: `tests/test_git_profile.sh`

- [ ] **Step 1: Write tests for rule remove**

Append to `tests/test_git_profile.sh` (before `report`):

```bash
# --- Test: rule remove ---
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
  # Write a fake includeIf to global config
  git config --global includeIf."gitdir:$TEST_HOME/projects/".path "$TEST_HOME/.gitconfig.d/work"

  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
    GITCONFIG_D="$TEST_HOME/.gitconfig.d" \
    GIT_PROFILE_AUTO_CONFIRM=y \
    "$GIT_PROFILE" _rule_remove "work-rule"

  # Rule should be gone from config
  local content
  content="$(cat "$TEST_HOME/.git-profiles.conf")"
  if [[ "$content" == *'[rule "work-rule"]'* ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: rule section should be removed"
  else
    PASS=$((PASS + 1))
  fi

  # Profile section should still exist
  assert_contains "profile preserved after rule remove" "[work]" "$content"
  teardown_test_home
}

test_rule_remove
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: New test FAILS

- [ ] **Step 3: Implement rule remove**

Add to `git-profile`:

```bash
_rule_remove() {
  local rname="$1"

  local r_dir r_profile
  r_dir="$(get_rule_field "$rname" "dir")"
  r_profile="$(get_rule_field "$rname" "profile")"

  if [[ -z "$r_dir" ]]; then
    echo "Error: rule '$rname' not found." >&2
    return 1
  fi

  # Remove from config file
  delete_config_section "rule:$rname"

  # Remove includeIf from global gitconfig
  git config --global --unset includeIf."gitdir:${r_dir}".path 2>/dev/null || true

  # Check if other rules still use the same profile
  local other_rules=false
  local all_rules
  all_rules="$(list_rule_names)"
  if [[ -n "$all_rules" ]]; then
    while IFS= read -r other; do
      local op
      op="$(get_rule_field "$other" "profile")"
      if [[ "$op" == "$r_profile" ]]; then
        other_rules=true
        break
      fi
    done <<< "$all_rules"
  fi

  if ! $other_rules; then
    local fragment="${GITCONFIG_D}/${r_profile}"
    if [[ -f "$fragment" ]]; then
      if [[ "${GIT_PROFILE_AUTO_CONFIRM:-}" == "y" ]]; then
        rm -f "$fragment"
      else
        read -rp "No other rules use profile '$r_profile'. Delete fragment '$fragment'? [y/N] " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          rm -f "$fragment"
          echo "Fragment removed."
        fi
      fi
    fi
  fi

  echo "Rule '$rname' removed."
}

cmd_rule_remove() {
  local names
  names="$(list_rule_names)"
  if [[ -z "$names" ]]; then
    echo "No rules to remove."
    return
  fi
  echo "Select a rule to remove:"
  local i=1 name_arr=()
  while IFS= read -r n; do
    name_arr+=("$n")
    local r_dir r_prof
    r_dir="$(get_rule_field "$n" "dir")"
    r_prof="$(get_rule_field "$n" "profile")"
    echo "  $i) $n -> $r_dir ($r_prof)"
    i=$((i + 1))
  done <<< "$names"
  local choice
  read -rp "Enter number: " choice
  if [[ "$choice" -lt 1 || "$choice" -gt ${#name_arr[@]} ]] 2>/dev/null; then
    echo "Error: invalid choice." >&2
    return 1
  fi
  _rule_remove "${name_arr[$((choice - 1))]}"
}
```

Update dispatcher:

```bash
    _rule_remove) shift; _rule_remove "$@" ;;
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_git_profile.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add rule remove with includeIf cleanup and fragment management"
```

### Task 10: `edit` command

**Files:**
- Modify: `git-profile`
- Modify: `tests/test_git_profile.sh`

- [ ] **Step 1: Write tests for edit**

Append to `tests/test_git_profile.sh` (before `report`):

```bash
# --- Test: edit command ---
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
  # Create an existing fragment
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

  # Fragment should be updated too
  local fragment
  fragment="$(cat "$TEST_HOME/.gitconfig.d/work")"
  assert_contains "fragment updated with new name" "name = New Name" "$fragment"
  assert_contains "fragment updated with new email" "email = new@mail.com" "$fragment"
  teardown_test_home
}

test_edit_updates_profile_and_fragment
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: New test FAILS

- [ ] **Step 3: Implement edit**

Add to `git-profile`:

```bash
# Internal edit: _edit_profile <name> <new_name> <new_email> <new_host> <new_ssh_key>
# Empty string = keep current value
_edit_profile() {
  local pname="$1"
  local new_uname="$2" new_email="$3" new_host="$4" new_key="$5"

  local cur_uname cur_email cur_host cur_key
  cur_uname="$(get_profile_field "$pname" "name")"
  cur_email="$(get_profile_field "$pname" "email")"
  cur_host="$(get_profile_field "$pname" "host")"
  cur_key="$(get_profile_field "$pname" "ssh_key")"

  if [[ -z "$cur_uname" ]]; then
    echo "Error: profile '$pname' not found." >&2
    return 1
  fi

  # Apply changes (empty = keep)
  [[ -n "$new_uname" ]] && cur_uname="$new_uname"
  [[ -n "$new_email" ]] && cur_email="$new_email"
  [[ -n "$new_host" ]] && cur_host="$new_host"
  [[ -n "$new_key" ]] && cur_key="$new_key"

  # Rewrite profile section
  write_profile_section "$pname" "$cur_uname" "$cur_email" "$cur_host" "$cur_key"

  # Rewrite gitconfig.d fragment if it exists
  local fragment="${GITCONFIG_D}/${pname}"
  if [[ -f "$fragment" ]]; then
    write_gitconfig_fragment "$pname"
  fi

  # Update SSH config alias if host changed and alias exists
  # (This is a best-effort update; complex SSH config editing is deferred)

  echo "Profile '$pname' updated."
}

cmd_edit() {
  local pname="${1:-}"
  if [[ -z "$pname" ]]; then
    local names
    names="$(list_profile_names)"
    if [[ -z "$names" ]]; then
      echo "No profiles to edit." >&2
      return 1
    fi
    echo "Select a profile to edit:"
    local i=1 name_arr=()
    while IFS= read -r n; do
      name_arr+=("$n")
      echo "  $i) $n"
      i=$((i + 1))
    done <<< "$names"
    local choice
    read -rp "Enter number: " choice
    if [[ "$choice" -lt 1 || "$choice" -gt ${#name_arr[@]} ]] 2>/dev/null; then
      echo "Error: invalid choice." >&2; return 1
    fi
    pname="${name_arr[$((choice - 1))]}"
  fi

  local cur_uname cur_email cur_host cur_key
  cur_uname="$(get_profile_field "$pname" "name")"
  cur_email="$(get_profile_field "$pname" "email")"
  cur_host="$(get_profile_field "$pname" "host")"
  cur_key="$(get_profile_field "$pname" "ssh_key")"

  if [[ -z "$cur_uname" ]]; then
    echo "Error: profile '$pname' not found." >&2
    return 1
  fi

  echo "Editing profile '$pname' (press Enter to keep current value):"
  echo ""

  local new_uname new_email new_host new_key
  read -rp "  Name [$cur_uname]: " new_uname
  read -rp "  Email [$cur_email]: " new_email
  read -rp "  Host [$cur_host]: " new_host
  read -rp "  SSH Key [$cur_key]: " new_key

  _edit_profile "$pname" "$new_uname" "$new_email" "$new_host" "$new_key"
}
```

Update dispatcher:

```bash
    _edit_profile) shift; _edit_profile "$@" ;;
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_git_profile.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add edit command with gitconfig.d fragment sync"
```

### Task 11: `remove` command

**Files:**
- Modify: `git-profile`
- Modify: `tests/test_git_profile.sh`

- [ ] **Step 1: Write tests for remove**

Append to `tests/test_git_profile.sh` (before `report`):

```bash
# --- Test: remove command ---
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
  # Both profile and rule should be gone
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_git_profile.sh`
Expected: New tests FAIL

- [ ] **Step 3: Implement remove**

Add to `git-profile`:

```bash
_remove_profile() {
  local pname="$1"
  local p_name
  p_name="$(get_profile_field "$pname" "name")"
  if [[ -z "$p_name" ]]; then
    echo "Error: profile '$pname' not found." >&2
    return 1
  fi

  # Check for rules referencing this profile
  local rule_names
  rule_names="$(list_rule_names)"
  local referencing_rules=()
  if [[ -n "$rule_names" ]]; then
    while IFS= read -r rname; do
      local rprof
      rprof="$(get_rule_field "$rname" "profile")"
      if [[ "$rprof" == "$pname" ]]; then
        referencing_rules+=("$rname")
      fi
    done <<< "$rule_names"
  fi

  if [[ ${#referencing_rules[@]} -gt 0 ]]; then
    echo "Profile '$pname' is referenced by these rules:"
    for r in "${referencing_rules[@]}"; do
      echo "  - $r"
    done
    if [[ "${GIT_PROFILE_AUTO_CONFIRM:-}" != "y" ]]; then
      read -rp "Delete these rules as well? [Y/n] " confirm
      [[ "$confirm" == "n" || "$confirm" == "N" ]] && { echo "Cancelled."; return 1; }
    fi
    # Remove referencing rules
    for r in "${referencing_rules[@]}"; do
      _rule_remove "$r"
    done
  fi

  # Read data BEFORE deleting section
  local p_key
  p_key="$(get_profile_field "$pname" "ssh_key")"
  p_key="${p_key/#\~/$HOME}"

  # Remove profile section
  delete_config_section "$pname"

  if [[ "${GIT_PROFILE_AUTO_CONFIRM:-}" == "y" ]]; then
    # Auto cleanup
    rm -f "$p_key" "${p_key}.pub" 2>/dev/null
    rm -f "${GITCONFIG_D}/${pname}" 2>/dev/null
    # Remove SSH config entries
    _remove_ssh_config_entries "$pname"
  else
    if [[ -f "$p_key" ]]; then
      read -rp "Delete SSH key '$p_key'? [y/N] " confirm
      [[ "$confirm" == "y" || "$confirm" == "Y" ]] && rm -f "$p_key" "${p_key}.pub"
    fi
    if [[ -f "${GITCONFIG_D}/${pname}" ]]; then
      read -rp "Delete gitconfig fragment '${GITCONFIG_D}/${pname}'? [y/N] " confirm
      [[ "$confirm" == "y" || "$confirm" == "Y" ]] && rm -f "${GITCONFIG_D}/${pname}"
    fi
    _remove_ssh_config_entries "$pname"
  fi

  echo "Profile '$pname' removed."
}

_remove_ssh_config_entries() {
  local pname="$1"
  local ssh_config="${HOME}/.ssh/config"
  [[ -f "$ssh_config" ]] || return 0

  if ! grep -q "# git-profile: ${pname}" "$ssh_config"; then
    return 0
  fi

  backup_ssh_config
  local tmpfile
  tmpfile="$(mktemp)"
  local skip=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == *"# git-profile: ${pname}"* ]]; then
      skip=true
      continue
    fi
    if $skip; then
      # Skip until next empty line or new Host block
      if [[ -z "$line" || "$line" =~ ^[^[:space:]] ]]; then
        skip=false
        [[ -n "$line" ]] && echo "$line" >> "$tmpfile"
      fi
      continue
    fi
    echo "$line" >> "$tmpfile"
  done < "$ssh_config"
  mv "$tmpfile" "$ssh_config"
}

cmd_remove() {
  local pname="${1:-}"
  if [[ -z "$pname" ]]; then
    local names
    names="$(list_profile_names)"
    if [[ -z "$names" ]]; then
      echo "No profiles to remove." >&2
      return 1
    fi
    echo "Select a profile to remove:"
    local i=1 name_arr=()
    while IFS= read -r n; do
      name_arr+=("$n")
      echo "  $i) $n"
      i=$((i + 1))
    done <<< "$names"
    local choice
    read -rp "Enter number: " choice
    if [[ "$choice" -lt 1 || "$choice" -gt ${#name_arr[@]} ]] 2>/dev/null; then
      echo "Error: invalid choice." >&2; return 1
    fi
    pname="${name_arr[$((choice - 1))]}"
  fi
  _remove_profile "$pname"
}
```

Update dispatcher:

```bash
    _remove_profile) shift; _remove_profile "$@" ;;
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_git_profile.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add remove command with cascade rule deletion and file cleanup"
```

---

## Chunk 5: Interactive Menu and Install Script

### Task 12: Interactive menu

**Files:**
- Modify: `git-profile`

- [ ] **Step 1: Implement interactive menu**

Replace the `interactive_menu` stub:

```bash
interactive_menu() {
  while true; do
    echo ""
    echo "Git Profile Manager"
    echo "━━━━━━━━━━━━━━━━━━━━━"
    echo "1) 添加新身份"
    echo "2) 修改身份"
    echo "3) 查看所有身份"
    echo "4) 切换当前项目身份"
    echo "5) 撤销身份覆盖（恢复原始配置）"
    echo "6) 管理目录规则"
    echo "7) 查看当前身份"
    echo "8) 删除身份"
    echo "0) 退出"
    echo ""
    read -rp "请选择: " choice

    case "$choice" in
      1) cmd_add ;;
      2) cmd_edit ;;
      3) cmd_list ;;
      4) cmd_use ;;
      5) cmd_use --clear ;;
      6) interactive_rule_menu ;;
      7) cmd_current ;;
      8) cmd_remove ;;
      0) echo "Bye."; return ;;
      *) echo "Invalid choice." ;;
    esac
  done
}

interactive_rule_menu() {
  echo ""
  echo "Directory Rules"
  echo "━━━━━━━━━━━━━━━━"
  echo "1) 添加规则"
  echo "2) 查看规则"
  echo "3) 删除规则"
  echo "0) 返回"
  echo ""
  read -rp "请选择: " choice
  case "$choice" in
    1) cmd_rule_add ;;
    2) cmd_rule_list ;;
    3) cmd_rule_remove ;;
    0) return ;;
    *) echo "Invalid choice." ;;
  esac
}
```

- [ ] **Step 2: Manual smoke test**

Run: `./git-profile` and navigate through the menu options.

- [ ] **Step 3: Commit**

```bash
git add git-profile
git commit -m "feat: add interactive menu with rule submenu"
```

### Task 13: Install script

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write install.sh**

```bash
#!/usr/bin/env bash
# install.sh — install git-profile to local bin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${SCRIPT_DIR}/git-profile"
DEFAULT_DEST="${HOME}/.local/bin"

echo "=== Git Profile Installer ==="
echo ""

# Determine install destination
DEST="${1:-$DEFAULT_DEST}"
read -rp "Install to [$DEST]: " user_dest
DEST="${user_dest:-$DEST}"

# Create destination if needed
mkdir -p "$DEST"

# Copy script
cp "$SOURCE" "$DEST/git-profile"
chmod +x "$DEST/git-profile"
echo "Installed: $DEST/git-profile"

# Init config file
if [[ ! -f "${HOME}/.git-profiles.conf" ]]; then
  touch "${HOME}/.git-profiles.conf"
  echo "Created: ~/.git-profiles.conf"
fi

# Create gitconfig.d directory
mkdir -p "${HOME}/.gitconfig.d"
echo "Created: ~/.gitconfig.d/"

# Set git alias
git config --global alias.profile '!git-profile'
echo "Git alias set: git profile -> git-profile"

# Check PATH
if [[ ":$PATH:" != *":$DEST:"* ]]; then
  echo ""
  echo "Warning: '$DEST' is not in your PATH."
  echo "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Installation complete! Run 'git-profile --help' to get started."
```

- [ ] **Step 2: Make executable and test**

Run: `chmod +x install.sh && bash install.sh`
Expected: Script installs successfully, prints confirmation

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add install script with PATH check and git alias setup"
```

### Task 14: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write README**

```markdown
# git-profile

在一台电脑上管理多个 Git 身份（SSH 密钥 + 用户名/邮箱）。

## 安装

```bash
./install.sh
```

默认安装到 `~/.local/bin/`。确保该路径在 `PATH` 中。

## 快速开始

```bash
# 添加身份
git-profile add

# 查看所有身份
git-profile list

# 在当前项目切换身份
git-profile use work

# 查看当前身份
git-profile current

# 撤销覆盖，恢复原始配置
git-profile use --clear

# 添加目录自动匹配规则
git-profile rule add

# 交互式菜单
git-profile
```

## 平台支持

- macOS、Linux
- Bash 3.2+
- 依赖：`git`、`ssh-keygen`、`ssh`

## 设计文档

详见 `docs/superpowers/specs/2026-03-17-git-profile-design.md`
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README with usage instructions"
```

### Task 15: Final integration test run

- [ ] **Step 1: Run full test suite**

Run: `bash tests/test_git_profile.sh`
Expected: All tests PASS, 0 failures

- [ ] **Step 2: Manual end-to-end test**

Run the following sequence manually:

```bash
# Start fresh
./git-profile add          # Create a 'personal' profile
./git-profile add          # Create a 'work' profile
./git-profile list         # Verify both appear
cd /tmp && git init test-repo && cd test-repo
git-profile use personal   # Apply personal profile
git-profile current        # Verify personal shows
git-profile use work       # Switch to work
git-profile current        # Verify work shows
git-profile use --clear    # Restore original
git-profile current        # Verify cleared
cd .. && rm -rf test-repo
```

- [ ] **Step 3: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address issues found in integration testing"
```
