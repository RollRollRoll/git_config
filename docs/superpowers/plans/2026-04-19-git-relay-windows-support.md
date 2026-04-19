# git-relay Windows Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `git-relay` 在 Windows Server + Git for Windows + SSH 登录后可执行 Bash/Git 的环境下，能够正确配置路径、生成 relay remote URL，并完成服务器初始化。

**Architecture:** 保持 `git-relay` 现有 Bash 主流程不变，只新增少量平台辅助函数，并把平台差异集中在路径规范化、默认路径推导、remote URL 生成、`init-server` 脚本生成四个位置。测试通过隐藏子命令暴露纯逻辑结果，避免依赖真实 SSH 环境。

**Tech Stack:** Bash、Git CLI、SSH、`mktemp`、`grep`、`sed`、仓库内 Bash 测试脚本

---

## File Structure

- Modify: `git-relay`
  - 新增 `server_os` 读取与校验
  - 新增 `_normalize_server_os`、`_normalize_server_path`、`_default_server_paths`、`_build_relay_remote_url`、`_build_init_server_script`
  - 调整 `cmd_config`、`load_conf`、`cmd_init_server`
  - 增加仅供测试使用的隐藏子命令
- Create: `tests/test_git_relay.sh`
  - 提供独立测试入口、断言工具、临时 HOME / 仓库初始化工具
  - 覆盖 Windows 路径规范化、默认路径、relay URL、初始化脚本、配置文件落盘
- Modify: `README.md`
  - 补充 `server_os` 配置与 Windows Server 支持边界
- Modify: `docs/guides/2026-04-12-git-relay-script.md`
  - 补充 Windows Server 配置示例与路径格式说明

## Implementation Notes

- 只改动上面列出的文件，不要触碰当前工作区中无关的 `.gitignore` 与 `.git-relay.conf`
- 所有新增注释保持中文
- Bash 兼容性按仓库现有风格处理，避免使用 Bash 4 专属语法如 `${var,,}`
- 测试脚本接受可选的单个测试函数名参数，便于做 TDD 的红绿循环

### Task 1: 建立 `git-relay` 的独立测试脚手架

**Files:**
- Create: `tests/test_git_relay.sh`
- Test: `tests/test_git_relay.sh`

- [ ] **Step 1: 写出失败中的测试脚手架和首批 Windows 行为测试**

```bash
#!/usr/bin/env bash
# tests/test_git_relay.sh — integration tests for git-relay
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GIT_RELAY="$SCRIPT_DIR/git-relay"
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

run_selected_tests() {
  local selected="${1:-}"
  local tests=(
    test_normalize_windows_path_backslashes
    test_normalize_windows_path_forward_slashes
    test_default_windows_paths
    test_build_windows_remote_url_default_port
    test_build_windows_init_script_skips_chmod
  )

  local test_name
  for test_name in "${tests[@]}"; do
    if [[ -n "$selected" && "$selected" != "$test_name" ]]; then
      continue
    fi
    "$test_name"
  done
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

test_normalize_windows_path_backslashes() {
  local output
  output="$("$GIT_RELAY" _normalize_server_path windows 'C:\relay\repos\demo.git' 2>&1 || true)"
  assert_eq "windows 反斜杠路径规范化" "/c/relay/repos/demo.git" "$output"
}

test_normalize_windows_path_forward_slashes() {
  local output
  output="$("$GIT_RELAY" _normalize_server_path windows 'D:/relay/worktrees/demo' 2>&1 || true)"
  assert_eq "windows 正斜杠路径规范化" "/d/relay/worktrees/demo" "$output"
}

test_default_windows_paths() {
  local output
  output="$("$GIT_RELAY" _default_server_paths windows '' demo-app 2>&1 || true)"
  assert_contains "windows 默认裸仓库路径" "BARE=/c/relay/repos/demo-app.git" "$output"
  assert_contains "windows 默认工作区路径" "WORK=/c/relay/worktrees/demo-app" "$output"
}

test_build_windows_remote_url_default_port() {
  local output
  output="$("$GIT_RELAY" _build_relay_remote_url 'gitrelay@relay-win' '22' '/c/relay/repos/demo.git' 2>&1 || true)"
  assert_eq "windows 22 端口 relay URL" "gitrelay@relay-win:/c/relay/repos/demo.git" "$output"
}

test_build_windows_init_script_skips_chmod() {
  local output
  output="$("$GIT_RELAY" _build_init_server_script windows '/c/relay/repos/demo.git' '/c/relay/worktrees/demo' main 2>&1 || true)"
  assert_contains "windows init-server 包含 git init" "git init --bare '/c/relay/repos/demo.git'" "$output"
  if [[ "$output" == *"chmod -R 700"* ]]; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\nFAIL: windows init-server 脚本不应包含 chmod -R 700"
  else
    PASS=$((PASS + 1))
  fi
}

run_selected_tests "${1:-}"
report
```

- [ ] **Step 2: 运行单个测试，确认它因隐藏子命令尚未实现而失败**

Run:

```bash
bash tests/test_git_relay.sh test_normalize_windows_path_backslashes
```

Expected:

```text
FAIL: windows 反斜杠路径规范化
  expected: /c/relay/repos/demo.git
  actual:   ...
```

其中 `actual` 应包含 `未知子命令: _normalize_server_path` 或等价错误，证明测试真的在约束缺失行为。

- [ ] **Step 3: 提交测试脚手架**

```bash
git add tests/test_git_relay.sh
git commit -m "test: add git-relay windows behavior harness"
```

### Task 2: 先实现纯平台辅助函数，再让首批测试转绿

**Files:**
- Modify: `git-relay`
- Test: `tests/test_git_relay.sh`

- [ ] **Step 1: 为路径、URL、初始化脚本写出最小实现**

在 `git-relay` 的配置读取逻辑前加入以下函数：

```bash
_normalize_server_os() {
  local raw="${1:-linux}"
  local normalized
  normalized="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    ""|linux) printf '%s\n' "linux" ;;
    windows) printf '%s\n' "windows" ;;
    *) die "server_os 只支持 linux 或 windows，当前值: ${raw}" ;;
  esac
}

_normalize_server_path() {
  local server_os
  server_os="$(_normalize_server_os "${1:-linux}")"
  local raw_path="${2:-}"

  if [[ "$server_os" != "windows" ]]; then
    printf '%s\n' "$raw_path"
    return
  fi

  raw_path="${raw_path//\\//}"

  if [[ "$raw_path" =~ ^([A-Za-z]):/(.*)$ ]]; then
    local drive="${BASH_REMATCH[1]}"
    local rest="${BASH_REMATCH[2]}"
    drive="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
    printf '/%s/%s\n' "$drive" "$rest"
    return
  fi

  if [[ "$raw_path" =~ ^/([A-Za-z])/(.*)$ ]]; then
    local drive="${BASH_REMATCH[1]}"
    local rest="${BASH_REMATCH[2]}"
    drive="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"
    printf '/%s/%s\n' "$drive" "$rest"
    return
  fi

  printf '%s\n' "$raw_path"
}

_default_server_paths() {
  local server_os
  server_os="$(_normalize_server_os "${1:-linux}")"
  local server_user="${2:-}"
  local project_name="$3"

  if [[ "$server_os" == "windows" ]]; then
    printf 'BARE=/c/relay/repos/%s.git\n' "$project_name"
    printf 'WORK=/c/relay/worktrees/%s\n' "$project_name"
    return
  fi

  if [[ -n "$server_user" ]]; then
    printf 'BARE=/home/%s/relay/repos/%s.git\n' "$server_user" "$project_name"
    printf 'WORK=/home/%s/relay/worktrees/%s\n' "$server_user" "$project_name"
  fi
}

_build_relay_remote_url() {
  local ssh_target="$1"
  local ssh_port="$2"
  local bare_path="$3"

  if [[ -n "$ssh_port" && "$ssh_port" != "22" ]]; then
    printf 'ssh://%s:%s%s\n' "$ssh_target" "$ssh_port" "$bare_path"
  else
    printf '%s:%s\n' "$ssh_target" "$bare_path"
  fi
}

_build_init_server_script() {
  local server_os
  server_os="$(_normalize_server_os "$1")"
  local bare_path="$2"
  local work_path="$3"
  local branch="$4"

  cat <<EOF
set -e
mkdir -p '$(dirname "$bare_path")'
mkdir -p '$(dirname "$work_path")'
git init --bare '$bare_path'
git --git-dir='$bare_path' config receive.denyNonFastForwards true
git --git-dir='$bare_path' config core.logAllRefUpdates true
git --git-dir='$bare_path' symbolic-ref HEAD 'refs/heads/$branch'
EOF

  if [[ "$server_os" == "linux" ]]; then
    cat <<EOF
chmod -R 700 '$(dirname "$bare_path")'
chmod -R 700 '$(dirname "$work_path")'
EOF
  fi
}
```

- [ ] **Step 2: 暴露隐藏子命令，给测试直接调用**

在 `main()` 的 `case` 中加入这些分支：

```bash
    _normalize_server_path) shift; _normalize_server_path "${1:-linux}" "${2:-}" ;;
    _default_server_paths) shift; _default_server_paths "${1:-linux}" "${2:-}" "${3:-}" ;;
    _build_relay_remote_url) shift; _build_relay_remote_url "${1:-}" "${2:-}" "${3:-}" ;;
    _build_init_server_script) shift; _build_init_server_script "${1:-linux}" "${2:-}" "${3:-}" "${4:-main}" ;;
```

- [ ] **Step 3: 运行完整测试脚本，确认首批测试全部通过**

Run:

```bash
bash tests/test_git_relay.sh
```

Expected:

```text
Results: 7 passed, 0 failed
All tests passed.
```

- [ ] **Step 4: 提交最小实现**

```bash
git add git-relay tests/test_git_relay.sh
git commit -m "feat: add git-relay windows path helpers"
```

### Task 3: 把平台逻辑接入真实配置读取与初始化流程

**Files:**
- Modify: `git-relay`
- Modify: `tests/test_git_relay.sh`
- Test: `tests/test_git_relay.sh`

- [ ] **Step 1: 追加失败中的配置与加载测试**

在 `tests/test_git_relay.sh` 里补上临时 HOME / 仓库工具和以下测试：

```bash
setup_test_home() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig"
  mkdir -p "$TEST_HOME/.ssh"
  touch "$TEST_HOME/.gitconfig"
}

teardown_test_home() {
  rm -rf "$TEST_HOME"
}

test_load_conf_normalizes_windows_paths_and_url() {
  setup_test_home
  cat > "$TEST_HOME/.git-relay.conf" <<'EOF'
server_host=relay-win
server_os=windows
server_user=gitrelay
ssh_port=22
project_name=demo
default_branch=main
corp_remote=origin
relay_remote=relay
corp_url=git@corp.example.com:team/demo.git
server_bare_path=C:\relay\repos\demo.git
server_work_path=D:/relay/worktrees/demo
EOF

  local output
  output="$(CONF_FILE="$TEST_HOME/.git-relay.conf" "$GIT_RELAY" _dump_loaded_conf 2>&1 || true)"
  assert_contains "load_conf 规范化裸仓库路径" "RELAY_BARE_PATH=/c/relay/repos/demo.git" "$output"
  assert_contains "load_conf 规范化工作区路径" "RELAY_WORK_PATH=/d/relay/worktrees/demo" "$output"
  assert_contains "load_conf 生成 windows relay URL" "RELAY_REMOTE_URL=gitrelay@relay-win:/c/relay/repos/demo.git" "$output"
  teardown_test_home
}

test_config_writes_windows_defaults() {
  setup_test_home
  local repo_dir="$TEST_HOME/repo"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init >/dev/null
  git -C "$repo_dir" remote add origin git@corp.example.com:team/demo.git

  printf '1\nrelay-win\nwindows\ngitrelay\n22\ndemo\nmain\norigin\nrelay\n\n\n1\n' \
    | (cd "$repo_dir" && CONF_FILE="$repo_dir/.git-relay.conf" "$GIT_RELAY" config >/dev/null 2>&1)

  local content
  content="$(cat "$repo_dir/.git-relay.conf")"
  assert_contains "config 写入 server_os" "server_os=windows" "$content"
  assert_contains "config 写入 windows 裸仓库默认路径" "server_bare_path=/c/relay/repos/demo.git" "$content"
  assert_contains "config 写入 windows 工作区默认路径" "server_work_path=/c/relay/worktrees/demo" "$content"
  teardown_test_home
}

test_init_server_script_contains_linux_chmod() {
  local output
  output="$("$GIT_RELAY" _build_init_server_script linux '/home/gitrelay/relay/repos/demo.git' '/home/gitrelay/relay/worktrees/demo' main)"
  assert_contains "linux init-server 包含 chmod" "chmod -R 700 '/home/gitrelay/relay/repos'" "$output"
}
```

并把这 3 个函数加入 `run_selected_tests()` 的 `tests=(...)` 列表。

- [ ] **Step 2: 运行配置测试，确认它因真实流程尚未接线而失败**

Run:

```bash
bash tests/test_git_relay.sh test_load_conf_normalizes_windows_paths_and_url
```

Expected:

```text
FAIL: load_conf 规范化裸仓库路径
```

失败原因应该是 `load_conf` 仍然把 `server_bare_path` 原样保留为 `C:\...`，或者 `_dump_loaded_conf` 尚未实现。

- [ ] **Step 3: 将平台逻辑接入 `conf_get` / `cmd_config` / `load_conf` / `cmd_init_server`**

按下面的改法落地真实行为：

```bash
load_conf() {
  [[ -f "$CONF_FILE" ]] || die "未找到配置文件 ${CONF_FILE}，请先运行: git-relay config"

  RELAY_SERVER_OS="$(_normalize_server_os "$(conf_get server_os 2>/dev/null || echo 'linux')")"
  RELAY_SERVER_USER="$(conf_get server_user 2>/dev/null || echo '')"
  RELAY_SERVER_HOST="$(conf_get server_host 2>/dev/null)" || die "配置缺少 server_host，请重新运行: git-relay config"
  RELAY_PROJECT="$(conf_get project_name 2>/dev/null)" || die "配置缺少 project_name，请重新运行: git-relay config"
  RELAY_BRANCH="$(conf_get default_branch 2>/dev/null)" || die "配置缺少 default_branch，请重新运行: git-relay config"
  RELAY_SSH_PORT="$(conf_get ssh_port 2>/dev/null || echo '')"
  RELAY_CORP_REMOTE="$(conf_get corp_remote 2>/dev/null || echo 'origin')"
  RELAY_RELAY_REMOTE="$(conf_get relay_remote 2>/dev/null || echo 'relay')"
  RELAY_CORP_URL="$(conf_get corp_url 2>/dev/null || git remote get-url "$RELAY_CORP_REMOTE" 2>/dev/null || echo '')"
  [[ -n "$RELAY_CORP_URL" ]] || die "无法确定原始仓库 URL，请重新运行: git-relay config"

  if [[ -n "$RELAY_SERVER_USER" ]]; then
    RELAY_SSH_TARGET="${RELAY_SERVER_USER}@${RELAY_SERVER_HOST}"
  else
    RELAY_SSH_TARGET="${RELAY_SERVER_HOST}"
  fi

  local custom_bare custom_work
  custom_bare="$(conf_get server_bare_path 2>/dev/null || echo '')"
  custom_work="$(conf_get server_work_path 2>/dev/null || echo '')"

  if [[ -n "$custom_bare" && -n "$custom_work" ]]; then
    RELAY_BARE_PATH="$(_normalize_server_path "$RELAY_SERVER_OS" "$custom_bare")"
    RELAY_WORK_PATH="$(_normalize_server_path "$RELAY_SERVER_OS" "$custom_work")"
  elif [[ "$RELAY_SERVER_OS" == "windows" ]]; then
    RELAY_BARE_PATH="/c/relay/repos/${RELAY_PROJECT}.git"
    RELAY_WORK_PATH="/c/relay/worktrees/${RELAY_PROJECT}"
  else
    local path_user="$RELAY_SERVER_USER"
    if [[ -z "$path_user" ]]; then
      info "server_user 未配置，正在通过 SSH 解析服务器用户名..."
      path_user="$(ssh "$RELAY_SSH_TARGET" 'whoami' 2>/dev/null)" || \
        die "无法获取服务器用户名，请配置 server_user 或显式指定 server_bare_path / server_work_path"
    fi
    RELAY_BARE_PATH="/home/${path_user}/relay/repos/${RELAY_PROJECT}.git"
    RELAY_WORK_PATH="/home/${path_user}/relay/worktrees/${RELAY_PROJECT}"
  fi

  RELAY_REMOTE_URL="$(_build_relay_remote_url "$RELAY_SSH_TARGET" "$RELAY_SSH_PORT" "$RELAY_BARE_PATH")"
}

cmd_config() {
  # 在 server_host 后新增 server_os
  local cur_os v_os
  cur_os="$(conf_get server_os 2>/dev/null || echo 'linux')"

  prompt_input "服务器操作系统 (server_os: linux/windows)" v_os "$cur_os"
  v_os="$(_normalize_server_os "$v_os")"

  local default_bare default_work
  if [[ "$v_os" == "windows" ]]; then
    default_bare="/c/relay/repos/${v_project}.git"
    default_work="/c/relay/worktrees/${v_project}"
  elif [[ -n "$v_user" ]]; then
    default_bare="/home/${v_user}/relay/repos/${v_project}.git"
    default_work="/home/${v_user}/relay/worktrees/${v_project}"
  else
    default_bare="$(conf_get server_bare_path 2>/dev/null || echo '')"
    default_work="$(conf_get server_work_path 2>/dev/null || echo '')"
  fi

  conf_set server_os "$v_os"
  if [[ -n "$v_bare_path" ]]; then
    conf_set server_bare_path "$(_normalize_server_path "$v_os" "$v_bare_path")"
  fi
  if [[ -n "$v_work_path" ]]; then
    conf_set server_work_path "$(_normalize_server_path "$v_os" "$v_work_path")"
  fi
}

cmd_init_server() {
  load_conf
  local init_script
  init_script="$(_build_init_server_script "$RELAY_SERVER_OS" "$RELAY_BARE_PATH" "$RELAY_WORK_PATH" "$RELAY_BRANCH")"
  ssh_run "$init_script"
}
```

再补一个测试专用隐藏子命令：

```bash
    _dump_loaded_conf)
      shift
      load_conf
      cat <<EOF
RELAY_SERVER_OS=${RELAY_SERVER_OS}
RELAY_BARE_PATH=${RELAY_BARE_PATH}
RELAY_WORK_PATH=${RELAY_WORK_PATH}
RELAY_REMOTE_URL=${RELAY_REMOTE_URL}
EOF
      ;;
```

- [ ] **Step 4: 跑完整 `git-relay` 测试，确认接线完成**

Run:

```bash
bash tests/test_git_relay.sh
```

Expected:

```text
Results: 14 passed, 0 failed
All tests passed.
```

- [ ] **Step 5: 提交真实行为变更**

```bash
git add git-relay tests/test_git_relay.sh
git commit -m "feat: support windows relay servers"
```

### Task 4: 更新文档并做总回归验证

**Files:**
- Modify: `README.md`
- Modify: `docs/guides/2026-04-12-git-relay-script.md`
- Test: `tests/test_git_relay.sh`
- Test: `tests/test_git_profile.sh`

- [ ] **Step 1: 更新 README 的配置说明与支持边界**

在 `README.md` 的 `git-relay` 段落里补充以下内容：

```md
### Windows Server 支持

`git-relay` 支持将中转仓库部署在 Windows Server 上，但要求远端满足以下条件：

- 已安装 Git for Windows
- SSH 登录后可以直接执行 `bash` 和 `git`

配置时新增 `server_os`：

```ini
server_host=relay-win
server_os=windows
server_user=gitrelay
ssh_port=22
project_name=my-app
default_branch=main
corp_url=git@corp.example.com:team/my-app.git
server_bare_path=/c/relay/repos/my-app.git
server_work_path=/c/relay/worktrees/my-app
```

Windows 模式下，以下路径输入形式都会被自动规范化为 Git Bash 风格路径：

- `C:\relay\repos\my-app.git`
- `C:/relay/repos/my-app.git`
- `/c/relay/repos/my-app.git`
```

- [ ] **Step 2: 更新详细使用手册中的配置表与示例**

在 `docs/guides/2026-04-12-git-relay-script.md` 中做两处修改：

```md
| `server_os` | 服务器操作系统，`linux` 或 `windows` | `windows` |
```

以及新增说明段：

```md
### Windows Server 说明

如果中转服务器是 Windows Server，请确保安装的是 Git for Windows，并且 SSH 登录后默认环境可以直接执行 `bash`、`git`、`mkdir`。

推荐将路径写成 `/c/...` 形式；如果填写 `C:\...` 或 `C:/...`，`git-relay` 会在运行时自动转换为 `/c/...`。

Windows 模式下 `init-server` 不会执行 `chmod -R 700`，因为 Git for Windows 环境下该权限语义不稳定。
```

- [ ] **Step 3: 运行新增测试与现有回归测试**

Run:

```bash
bash tests/test_git_relay.sh
```

Expected:

```text
Results: 14 passed, 0 failed
All tests passed.
```

然后运行：

```bash
bash tests/test_git_profile.sh
```

Expected:

```text
Results: ... passed, 0 failed
All tests passed.
```

- [ ] **Step 4: 提交文档与验证收尾**

```bash
git add README.md docs/guides/2026-04-12-git-relay-script.md tests/test_git_relay.sh git-relay
git commit -m "docs: document windows relay server support"
```

## Spec Coverage Check

- `server_os=linux|windows`：Task 3
- Windows 默认路径 `/c/relay/...`：Task 2、Task 3
- Windows 路径输入规范化：Task 1、Task 2、Task 3
- relay remote URL 生成：Task 1、Task 2、Task 3
- `init-server` Linux/Windows 差异：Task 1、Task 2、Task 3、Task 4
- 文档同步：Task 4
- Linux 行为不回归：Task 3、Task 4

## Placeholder Scan

- 本计划不包含 `TODO`、`TBD`、"后续补充"、"自行实现" 等占位词
- 每个测试步骤都给出了具体命令与预期
- 每个代码步骤都给出了需要加入的具体函数或片段

## Type / Naming Consistency Check

- 配置名统一使用 `server_os`
- 运行时变量统一使用 `RELAY_SERVER_OS`
- 平台辅助函数统一前缀 `_normalize_` / `_build_`
- 测试隐藏子命令统一与函数同名，减少映射歧义
