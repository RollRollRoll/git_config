#!/usr/bin/env bash
# tests/test_git_relay.sh — git-relay 的集成测试
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GIT_RELAY="$SCRIPT_DIR/git-relay"
PASS=0
FAIL=0
ERRORS=""

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

run_selected_tests() {
  local selected="${1:-}"
  local tests=(
    test_normalize_windows_path_backslashes
    test_normalize_windows_path_forward_slashes
    test_default_windows_paths
    test_build_windows_remote_url_default_port
    test_build_windows_remote_url_rejects_explicit_port
    test_build_windows_bash_bridge_script
    test_build_remote_stdin_runner
    test_build_windows_init_script_skips_chmod
    test_load_conf_normalizes_windows_paths_and_url
    test_config_writes_windows_defaults
    test_menu_init_loads_project_config_after_config
    test_init_server_script_contains_linux_chmod
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
  output="$("$GIT_RELAY" _build_relay_remote_url windows 'gitrelay@relay-win' '22' '/c/relay/repos/demo.git' 2>&1 || true)"
  assert_eq "windows 22 端口 relay URL 使用盘符路径" "gitrelay@relay-win:C:/relay/repos/demo.git" "$output"
}

test_build_windows_remote_url_rejects_explicit_port() {
  local output
  output="$("$GIT_RELAY" _build_relay_remote_url windows 'gitrelay@relay-win' '2222' '/c/relay/repos/demo.git' 2>&1 || true)"
  assert_contains "windows 显式端口要求改用 SSH config" "Windows 服务器使用非默认 SSH 端口时" "$output"
}

test_build_windows_bash_bridge_script() {
  local output
  output="$("$GIT_RELAY" _build_windows_bash_bridge_script 2>&1 || true)"
  assert_contains "windows 桥接脚本关闭 PowerShell 进度输出" "\$ProgressPreference = 'SilentlyContinue'" "$output"
  assert_contains "windows 桥接脚本通过 stdin 读取 bash 脚本" "[Console]::In.ReadToEnd()" "$output"
  assert_contains "windows 桥接脚本优先检查 PATH 中的 bash" "Get-Command bash" "$output"
  assert_contains "windows 桥接脚本检查 Git for Windows 默认路径" '$env:ProgramFiles\Git\bin\bash.exe' "$output"
  assert_contains "windows 桥接脚本以 bash -s 启动子进程" "Arguments = '-s'" "$output"
  assert_contains "windows 桥接脚本将脚本写入 bash 标准输入" "RedirectStandardInput = \$true" "$output"
}

test_build_remote_stdin_runner() {
  local linux_output windows_output
  linux_output="$("$GIT_RELAY" _build_remote_stdin_runner linux 2>&1 || true)"
  windows_output="$("$GIT_RELAY" _build_remote_stdin_runner windows 2>&1 || true)"

  assert_eq "linux 远端执行器保持 bash" "bash" "$linux_output"
  assert_contains "windows 远端执行器使用 powershell 编码命令" "powershell -NoProfile -NonInteractive -EncodedCommand " "$windows_output"
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
  assert_contains "load_conf 生成 windows relay URL 使用盘符路径" "RELAY_REMOTE_URL=gitrelay@relay-win:C:/relay/repos/demo.git" "$output"
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

test_menu_init_loads_project_config_after_config() {
  setup_test_home
  local repo_dir="$TEST_HOME/repo"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init >/dev/null

  local output
  output="$(printf '1\n1\nrelay-win\nwindows\ngitrelay\n22\ndemo\nmain\norigin\nrelay\n\n\n\n\n3\nn\nq\n' \
    | (cd "$repo_dir" && "$GIT_RELAY" menu) 2>&1 || true)"

  assert_contains "菜单配置后 init 能加载项目级配置" "本命令将依次执行" "$output"
  teardown_test_home
}

test_init_server_script_contains_linux_chmod() {
  local output
  output="$("$GIT_RELAY" _build_init_server_script linux '/home/gitrelay/relay/repos/demo.git' '/home/gitrelay/relay/worktrees/demo' main)"
  assert_contains "linux init-server 包含 chmod" "chmod -R 700 '/home/gitrelay/relay/repos'" "$output"
}

run_selected_tests "${1:-}"
report
