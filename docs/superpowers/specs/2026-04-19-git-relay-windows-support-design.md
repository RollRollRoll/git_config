# git-relay Windows Server 支持设计

## 背景

`git-relay` 当前默认假设中转服务器是类 Unix 环境：

- 默认服务器路径固定为 `/home/<user>/relay/...`
- 初始化逻辑会直接执行 `chmod -R 700`
- 配置阶段展示的默认路径也只有 Linux 形态

这在 Linux 服务器上没有问题，但当中转仓库部署在 Windows Server 上时，即使服务器安装了 Git for Windows 并能通过 SSH 进入 Bash，默认路径与部分命令假设仍然会导致初始化和日常使用体验不正确。

本次变更的目标是在 **Windows Server + Git for Windows + SSH 登录后可执行 Bash/Git** 的前提下，为 `git-relay` 增加明确、稳定、可测试的 Windows 支持。

## 目标

- 为 `git-relay` 增加显式的服务器操作系统配置 `server_os`
- 在 `server_os=windows` 时提供合理的 Windows 默认路径
- 兼容用户输入的常见 Windows 路径格式，并统一转换为 Git Bash 可稳定处理的路径
- 保持现有 Linux 行为不变，避免破坏已有配置和工作流
- 为新增逻辑补充独立测试与文档说明

## 非目标

- 不支持纯 PowerShell 或纯 CMD 作为远端执行环境
- 不自动探测远端操作系统类型
- 不改造 `git-relay` 的整体工作流与命令接口
- 不引入额外依赖或重写为 PowerShell 脚本

## 支持边界

本设计仅承诺支持以下远端环境：

- 操作系统：Windows Server
- Git 运行环境：Git for Windows
- SSH 登录后的远端命令环境：可执行 `bash`、`git`、`mkdir`

不支持以下场景：

- 只能执行 PowerShell、不能执行 Bash 的远端环境
- Git 未安装或未加入远端登录环境 `PATH`
- 依赖 Windows ACL 精细权限管理并希望由脚本自动配置权限

## 方案选择

### 备选方案

1. 仅允许用户手工填写 Windows 路径，不新增平台配置
2. 新增显式配置 `server_os=linux|windows`
3. 通过 SSH 自动探测远端平台后再决定默认行为

### 结论

采用方案 2：**新增显式配置 `server_os=linux|windows`**。

原因如下：

- 用户可明确表达环境类型，行为稳定、易排障
- 只需在少数路径与初始化逻辑上做平台分支，改动集中
- 避免自动探测在不同 SSH 默认 shell 下出现误判

## 配置设计

### 新增配置项

- `server_os`
  - 可选值：`linux`、`windows`
  - 默认值：`linux`

### 配置优先级

保持现有配置优先级不变：

1. 环境变量 `CONF_FILE`
2. 项目根目录 `.git-relay.conf`
3. 全局配置 `~/.git-relay.conf`

### 配置交互调整

在 `git-relay config` 中新增 `server_os` 交互项，顺序调整为：

1. `server_host`
2. `server_os`
3. `server_user`
4. `ssh_port`
5. `project_name`
6. `default_branch`
7. `corp_remote`
8. `relay_remote`
9. `server_bare_path`
10. `server_work_path`
11. `corp_url`

### 默认路径

当用户未显式配置 `server_bare_path` / `server_work_path` 时，脚本根据 `server_os` 推导默认路径。

#### Linux 默认路径

- 裸仓库：`/home/<server_user>/relay/repos/<project>.git`
- 工作区：`/home/<server_user>/relay/worktrees/<project>`

若 `server_user` 为空，则保持现有逻辑，通过 SSH 执行 `whoami` 获取用户名后再推导。

#### Windows 默认路径

- 裸仓库：`/c/relay/repos/<project>.git`
- 工作区：`/c/relay/worktrees/<project>`

Windows 模式下不再通过 `whoami` 推导默认目录，也不再构造 `/home/<user>/...` 形式路径。

## 路径规范化设计

### 设计原则

脚本内部统一使用 **Git Bash 风格路径**，即 `/c/...` 这类格式。这样可以同时兼容：

- 远端 `bash` 脚本执行
- `git clone` / `git init --bare`
- 通过 SSH 使用的 relay remote URL

### 允许输入的路径格式

当 `server_os=windows` 时，用户输入以下任一种路径格式都应被接受：

- `C:\relay\repos\demo.git`
- `C:/relay/repos/demo.git`
- `/c/relay/repos/demo.git`

### 规范化结果

统一转换为 `/c/relay/repos/demo.git` 这类路径。规则如下：

- 将反斜杠 `\` 转为正斜杠 `/`
- 将盘符前缀 `C:/` 转为 `/c/`
- 已是 `/c/...` 形式时保持不变
- 盘符统一转为小写，避免大小写不一致导致 URL 或比较逻辑混乱

### 生效位置

规范化后的路径用于：

- `load_conf` 得到的 `RELAY_BARE_PATH`
- `load_conf` 得到的 `RELAY_WORK_PATH`
- relay remote URL 拼接
- 远端初始化与日常 SSH 命令

配置文件中是否保留原始输入不是关键要求；脚本运行时拿到的是规范化结果即可。

## 远端命令设计

### 保持不变的部分

远端执行方式保持为：

```bash
ssh ... bash
```

不新增 PowerShell 分支，不改变已有命令名和工作流。

### `init-server` 行为

Linux 模式继续执行：

```bash
mkdir -p ...
git init --bare ...
git --git-dir=... config ...
chmod -R 700 ...
```

Windows 模式执行：

```bash
mkdir -p ...
git init --bare ...
git --git-dir=... config ...
```

但**跳过**：

```bash
chmod -R 700 ...
```

原因：

- Git for Windows 环境下 `chmod` 往往没有稳定、可靠的权限语义
- 该权限设置在 Windows Server 上既不必要，也可能造成误导

### 其他命令行为

以下命令在 Windows 模式下仍然复用现有 Bash/Git 逻辑，仅路径使用规范化结果：

- `init-local`
- `relay-pull`
- `feature-start`
- `relay-push`
- `feature-clean`
- `_server_clone_worktree`

## relay remote URL 设计

URL 生成规则保持现有结构，仅路径改为规范化后的服务器路径。

### 标准 SSH 端口 22

```text
user@host:/c/relay/repos/demo.git
```

或当未配置 `server_user` 时：

```text
host:/c/relay/repos/demo.git
```

### 非标准 SSH 端口

```text
ssh://user@host:2222/c/relay/repos/demo.git
```

## 代码结构调整

为降低平台分支对主流程的污染，并便于测试，新增少量内部辅助函数。

### 计划新增的内部函数

- `_normalize_server_os`
  - 校验并标准化 `server_os`
  - 非法值时报错，防止配置拼写错误默默退化

- `_normalize_server_path`
  - 根据 `server_os` 规范化服务器路径
  - Linux 模式原样返回
  - Windows 模式将盘符路径转为 `/c/...`

- `_default_server_paths`
  - 基于 `server_os`、`server_user`、`project_name` 计算默认裸仓库路径与工作区路径

- `_build_init_server_script`
  - 根据 `server_os` 生成 `init-server` 的远端脚本文本
  - Linux 含 `chmod`
  - Windows 不含 `chmod`

### 原则

- 不改变现有对外命令接口
- 平台判断尽量集中到辅助函数中
- 主流程函数只消费已经规范化好的变量

## 测试设计

### 测试文件

新增独立测试脚本：

- `tests/test_git_relay.sh`

不与现有 `git-profile` 测试混用，避免关注点耦合。

### 重点覆盖场景

1. Linux 默认路径逻辑保持不变
2. Windows 默认路径为 `/c/relay/...`
3. Windows 路径规范化
   - `C:\relay\repos\demo.git` → `/c/relay/repos/demo.git`
   - `C:/relay/repos/demo.git` → `/c/relay/repos/demo.git`
   - `/c/relay/repos/demo.git` → `/c/relay/repos/demo.git`
4. relay remote URL 生成
   - 22 端口场景
   - 非 22 端口场景
5. `init-server` 远端脚本差异
   - Linux 包含 `chmod -R 700`
   - Windows 不包含 `chmod -R 700`
6. `server_os` 非法值校验

### 测试策略

- 优先测试纯函数或近似纯函数，减少对真实 SSH 环境的依赖
- 如需验证 `load_conf`，通过构造测试配置文件和环境变量完成
- 单测执行时间控制在 60 秒内，不引入外部网络依赖

## 文档更新

需要同步更新以下文档：

- `README.md`
- `docs/guides/2026-04-12-git-relay-script.md`

### 文档更新要点

- 增加 `server_os` 说明与示例
- 明确 Windows Server 的支持边界
- 说明推荐路径格式为 `/c/...`
- 说明也兼容输入 `C:\...` / `C:/...`
- 提醒远端需安装 Git for Windows，并确保 SSH 登录后可以直接执行 `bash` 与 `git`

## 实施步骤

1. 为 `git-relay` 设计并添加平台辅助函数
2. 在配置读取与交互阶段引入 `server_os`
3. 接入 Windows 默认路径与路径规范化逻辑
4. 调整 `init-server` 的平台差异化脚本生成
5. 新增 `tests/test_git_relay.sh`
6. 更新 README 与使用手册
7. 运行测试并完成回归验证

## 风险与控制

### 风险 1：已有 Linux 用户行为被破坏

控制措施：

- `server_os` 默认值保持为 `linux`
- Linux 路径生成逻辑尽量复用原行为
- 用测试锁定 Linux 默认路径与 URL 生成

### 风险 2：Windows 路径格式过多导致边界遗漏

控制措施：

- 限定支持的输入形态
- 统一转换为 `/c/...` 内部标准格式
- 通过测试覆盖三种主流输入

### 风险 3：Windows 权限行为不一致

控制措施：

- Windows 模式显式跳过 `chmod`
- 在文档中明确脚本不负责配置 Windows ACL

## 验收标准

满足以下条件即可认为本次设计落地完成：

- `git-relay config` 支持设置 `server_os`
- Windows 模式默认路径为 `/c/relay/repos/<project>.git` 与 `/c/relay/worktrees/<project>`
- Windows 常见路径输入可规范化为 `/c/...`
- `init-server` 在 Windows 模式下可生成不带 `chmod` 的初始化脚本
- relay remote URL 在 Windows 模式下生成正确
- 新增测试通过，且 Linux 相关行为无回归
- README 与使用手册已明确记录支持边界和配置方式
