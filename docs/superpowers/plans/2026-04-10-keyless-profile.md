# Keyless Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使 `ssh_key` 字段变为可选，支持不绑定 SSH 密钥的 Profile。

**Architecture:** 四处修改均在 `git-profile` 单文件中：`_add_profile` 跳过 SSH alias 逻辑、`cmd_add` 新增密钥选项提示、`cmd_use` 条件写 `core.sshCommand`、`write_gitconfig_fragment` 条件写 `sshCommand` 行。测试追加在 `tests/test_git_profile.sh` 末尾。

**Tech Stack:** Bash 3.2+，现有测试框架（`assert_eq` / `assert_contains` / `setup_test_home` / `teardown_test_home`）

---

## 文件变更清单

| 操作 | 文件 | 位置 |
|------|------|------|
| Modify | `git-profile` | 第 425 行（`_add_profile` SSH alias 判断） |
| Modify | `git-profile` | 第 558–584 行（`cmd_add` 步骤 5） |
| Modify | `git-profile` | 第 983–988 行（`cmd_use` sshCommand 写入） |
| Modify | `git-profile` | 第 1432–1440 行（`write_gitconfig_fragment`） |
| Modify | `tests/test_git_profile.sh` | 文件末尾追加 |

---

## Task 1：`_add_profile` — 无密钥时跳过 SSH alias 逻辑

**Files:**
- Modify: `git-profile:425`
- Test: `tests/test_git_profile.sh`

- [ ] **步骤 1：写失败测试**

在 `tests/test_git_profile.sh` 末尾追加：

```bash
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
```

- [ ] **步骤 2：运行测试确认失败**

```bash
bash tests/test_git_profile.sh 2>&1 | tail -20
```

预期：`FAIL: keyless profile should not write SSH alias`

- [ ] **步骤 3：修改 `_add_profile`（第 425 行）**

将：
```bash
  if host_has_other_profiles "$host" "$name"; then
```
改为：
```bash
  if [[ -n "$key_path" ]] && host_has_other_profiles "$host" "$name"; then
```

- [ ] **步骤 4：运行测试确认通过**

```bash
bash tests/test_git_profile.sh 2>&1 | tail -5
```

预期：`All tests passed.`

- [ ] **步骤 5：提交**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "fix: skip SSH alias logic for keyless profiles in _add_profile"
```

---

## Task 2：`cmd_add` — 新增"是否绑定密钥"提示

**Files:**
- Modify: `git-profile:558–584`
- Test: `tests/test_git_profile.sh`

- [ ] **步骤 1：写失败测试**

在 `tests/test_git_profile.sh` 末尾追加：

```bash
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
  # ssh_key 行应存在且值为空
  assert_contains "interactive keyless has ssh_key line" "ssh_key = " "$content"
  teardown_test_home
}

test_add_keyless_interactive
```

- [ ] **步骤 2：运行测试确认失败**

```bash
bash tests/test_git_profile.sh 2>&1 | tail -20
```

预期：`FAIL: interactive keyless creates section`（因为现有流程不允许跳过密钥）

- [ ] **步骤 3：替换 `cmd_add` 步骤 5（第 558–584 行）**

将原有的：
```bash
  # ── 5. SSH key: generate new or use existing ──────────────────────────────
  printf "Generate a new SSH key? [Y/n] "
  read -r gen_key
  case "$gen_key" in
    [nN]*)
      # Use existing key
      local key_path=""
      while [[ -z "$key_path" ]]; do
        printf "Path to existing SSH private key: "
        read -r key_path
        if [[ -z "$key_path" ]]; then
          echo "Key path cannot be empty." >&2
        elif [[ ! -f "$key_path" ]]; then
          echo "File not found: ${key_path}" >&2
          key_path=""
        fi
      done
      _add_profile "$name" "$fullname" "$email" "$host" "$key_path"
      ;;
    *)
      # Generate new key — ask for algorithm
      printf "Key algorithm [ed25519/rsa] (default: ed25519): "
      read -r algorithm
      algorithm="${algorithm:-ed25519}"
      _add_profile_with_keygen "$name" "$fullname" "$email" "$host" "$algorithm"
      ;;
  esac
```

替换为：
```bash
  # ── 5. SSH key: bind or skip ──────────────────────────────────────────────
  printf "需要绑定 SSH 密钥？[Y/n] "
  read -r need_key
  case "$need_key" in
    [nN]*)
      # 不绑定密钥
      _add_profile "$name" "$fullname" "$email" "$host" ""
      ;;
    *)
      # ── 5a. Generate new or use existing ─────────────────────────────────
      printf "Generate a new SSH key? [Y/n] "
      read -r gen_key
      case "$gen_key" in
        [nN]*)
          # Use existing key
          local key_path=""
          while [[ -z "$key_path" ]]; do
            printf "Path to existing SSH private key: "
            read -r key_path
            if [[ -z "$key_path" ]]; then
              echo "Key path cannot be empty." >&2
            elif [[ ! -f "$key_path" ]]; then
              echo "File not found: ${key_path}" >&2
              key_path=""
            fi
          done
          _add_profile "$name" "$fullname" "$email" "$host" "$key_path"
          ;;
        *)
          # Generate new key — ask for algorithm
          printf "Key algorithm [ed25519/rsa] (default: ed25519): "
          read -r algorithm
          algorithm="${algorithm:-ed25519}"
          _add_profile_with_keygen "$name" "$fullname" "$email" "$host" "$algorithm"
          ;;
      esac
      ;;
  esac
```

- [ ] **步骤 4：运行测试确认通过**

```bash
bash tests/test_git_profile.sh 2>&1 | tail -5
```

预期：`All tests passed.`

- [ ] **步骤 5：提交**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: add keyless SSH option to cmd_add interactive flow"
```

---

## Task 3：`cmd_use` — 无密钥时不写 `core.sshCommand`

**Files:**
- Modify: `git-profile:983–988`
- Test: `tests/test_git_profile.sh`

- [ ] **步骤 1：写失败测试**

在 `tests/test_git_profile.sh` 末尾追加：

```bash
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
```

- [ ] **步骤 2：运行测试确认失败**

```bash
bash tests/test_git_profile.sh 2>&1 | tail -20
```

预期：`FAIL: keyless use does not write sshCommand`（当前代码无条件写 sshCommand）

- [ ] **步骤 3：修改 `cmd_use`（第 983–988 行）**

将：
```bash
  # Apply profile
  git config --local gitProfile.name "$profile_arg"
  git config --local user.name "$p_name"
  git config --local user.email "$p_email"
  git config --local core.sshCommand "ssh -i \"${p_key}\" -o IdentitiesOnly=yes"
```
改为：
```bash
  # Apply profile
  git config --local gitProfile.name "$profile_arg"
  git config --local user.name "$p_name"
  git config --local user.email "$p_email"
  if [[ -n "$p_key" ]]; then
    git config --local core.sshCommand "ssh -i \"${p_key}\" -o IdentitiesOnly=yes"
  fi
```

- [ ] **步骤 4：运行测试确认通过**

```bash
bash tests/test_git_profile.sh 2>&1 | tail -5
```

预期：`All tests passed.`

- [ ] **步骤 5：提交**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "fix: skip core.sshCommand when profile has no SSH key in cmd_use"
```

---

## Task 4：`write_gitconfig_fragment` — 无密钥时不写 `sshCommand` 行

**Files:**
- Modify: `git-profile:1432–1440`
- Test: `tests/test_git_profile.sh`

- [ ] **步骤 1：写失败测试**

在 `tests/test_git_profile.sh` 末尾追加：

```bash
test_fragment_keyless_no_sshcommand() {
  setup_test_home
  mkdir -p "$TEST_HOME/work"

  cat > "$TEST_HOME/.git-profiles.conf" <<'EOF'
[keyless]
name = Keyless User
email = keyless@mail.com
host = github.com
ssh_key = 
EOF

  GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig" \
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
  GITCONFIG_D="$TEST_HOME/.gitconfig.d" \
    "$GIT_PROFILE" _rule_add "myrule" "$TEST_HOME/work/" "keyless" >/dev/null 2>&1

  local fragment_file="$TEST_HOME/.gitconfig.d/keyless"
  if [[ ! -f "$fragment_file" ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: fragment file not created at $fragment_file"
    teardown_test_home
    return
  fi

  local fragment
  fragment="$(cat "$fragment_file")"
  assert_contains "fragment has gitProfile.name" "name = keyless" "$fragment"
  assert_contains "fragment has user.name" "name = Keyless User" "$fragment"
  assert_contains "fragment has user.email" "email = keyless@mail.com" "$fragment"

  if [[ "$fragment" == *"sshCommand"* ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: keyless fragment should not contain sshCommand, got:\n$fragment"
  else
    PASS=$((PASS + 1))
  fi
  teardown_test_home
}

test_fragment_keyed_has_sshcommand() {
  setup_test_home
  mkdir -p "$TEST_HOME/work"
  touch "$TEST_HOME/.ssh/git_profile_keyed"

  cat > "$TEST_HOME/.git-profiles.conf" <<EOF
[keyed]
name = Keyed User
email = keyed@mail.com
host = github.com
ssh_key = $TEST_HOME/.ssh/git_profile_keyed
EOF

  GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig" \
  CONF_FILE="$TEST_HOME/.git-profiles.conf" \
  GITCONFIG_D="$TEST_HOME/.gitconfig.d" \
    "$GIT_PROFILE" _rule_add "keyed-rule" "$TEST_HOME/work/" "keyed" >/dev/null 2>&1

  local fragment_file="$TEST_HOME/.gitconfig.d/keyed"
  local fragment
  fragment="$(cat "$fragment_file")"
  assert_contains "keyed fragment has sshCommand" "sshCommand" "$fragment"
  assert_contains "keyed fragment references key path" "git_profile_keyed" "$fragment"
  teardown_test_home
}

test_fragment_keyless_no_sshcommand
test_fragment_keyed_has_sshcommand
```

- [ ] **步骤 2：运行测试确认失败**

```bash
bash tests/test_git_profile.sh 2>&1 | tail -20
```

预期：`FAIL: keyless fragment should not contain sshCommand`

- [ ] **步骤 3：修改 `write_gitconfig_fragment`（第 1432–1440 行）**

将原有的 `cat > "$fragment_file" <<EOF ... EOF` 替换为：

```bash
  if [[ -n "$key_path" ]]; then
    cat > "$fragment_file" <<EOF
[gitProfile]
  name = ${profile}
[user]
  name = ${fullname}
  email = ${email}
[core]
  sshCommand = ssh -i "${key_path}" -o IdentitiesOnly=yes
EOF
  else
    cat > "$fragment_file" <<EOF
[gitProfile]
  name = ${profile}
[user]
  name = ${fullname}
  email = ${email}
EOF
  fi
```

- [ ] **步骤 4：运行全量测试确认通过**

```bash
bash tests/test_git_profile.sh 2>&1
```

预期：最后一行 `All tests passed.`

- [ ] **步骤 5：提交**

```bash
git add git-profile tests/test_git_profile.sh
git commit -m "feat: omit sshCommand from gitconfig fragment when profile has no SSH key"
```
