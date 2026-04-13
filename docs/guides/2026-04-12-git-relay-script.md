# git-relay 使用手册

## 概述

`git-relay` 是对《Git 多远程中转同步操作手册》的脚本化实现。  
它将手册中每一个需要手动输入的操作序列封装为单条命令，适合长期、重复使用的中转同步场景。

**适用场景**：外网服务器无法直接访问公司 Git 服务器时，建立如下同步链路：

```
公司仓库 (corp)  ↔  本地工作仓库  ↔  外网裸仓库 (relay)  ↔  外网服务器工作区
```

**核心约束**（与手册保持一致）：

- 本地是唯一能同时连接 `corp` 和 `relay` 的节点
- 外网服务器只与裸仓库通信，不配置 `corp` remote
- 所有回流公司仓库的操作只能在本地执行

---

## 安装

### 方式一：使用 install.sh（推荐）

```bash
git clone <本仓库地址>
cd git_config
./install.sh
```

安装完成后 `git-relay` 会被复制到 `~/.local/bin/`，确保该目录在 `$PATH` 中。

### 方式二：手动复制

```bash
cp git-relay ~/.local/bin/
chmod +x ~/.local/bin/git-relay
```

---

## 快速开始

### 第一步：填写配置

```bash
git-relay config
```

交互式填写以下参数，保存到 `~/.git-relay.conf`：

| 参数 | 说明 | 示例 |
|---|---|---|
| `server_user` | 外网服务器用户名 | `gitrelay` |
| `server_host` | 外网服务器地址 | `1.2.3.4` |
| `ssh_port` | SSH 端口（默认 22） | `22` |
| `project_name` | 项目名 | `my-app` |
| `default_branch` | 默认分支 | `main` |
| `corp_url` | 公司 Git 仓库地址 | `git@corp.example.com:team/my-app.git` |

### 第二步：一次性初始化

在项目目录下执行：

```bash
cd ~/Project/my-app
git-relay init
```

该命令依次完成：

1. SSH 到外网服务器，创建裸仓库和目录结构
2. 本地配置 `corp` / `relay` 两个 remote
3. 将主分支首次推送到外网裸仓库
4. 在外网服务器 clone 工作区

完成后服务器目录结构如下：

```
/home/<server_user>/relay/
├── repos/
│   └── my-app.git          # 裸仓库（中转节点）
└── worktrees/
    └── my-app              # 工作区（开发节点）
```

---

## 日常工作流

### 场景一：开始远程开发前，同步公司最新代码

```bash
git-relay sync-to-relay
```

等价于：

```
本地：git fetch corp → git pull corp → git push relay
服务器：git pull origin（SSH 自动执行）
```

执行后，外网服务器工作区已是公司仓库最新代码，可以开始开发。

---

### 场景二：在外网服务器上创建功能分支开发

**1. 在服务器创建功能分支**

```bash
git-relay feature-start my-feature
```

SSH 到服务器，从主分支切出 `feature/my-feature`。

**2. 登录服务器进行开发**

```bash
ssh <server_user>@<server_host>
cd ~/relay/worktrees/my-app

# ... 正常编辑、提交 ...
git add .
git commit -m "feat: 实现某功能"
```

**3. 开发完毕，服务器推回裸仓库**

```bash
git-relay relay-push
```

SSH 执行服务器上的 `git push -u origin HEAD`，将功能分支推入裸仓库。

---

### 场景三：本地将服务器功能分支同步回公司仓库

**逐步执行：**

```bash
# 本地拉取功能分支（首次自动建立跟踪，后续自动更新）
git-relay relay-pull my-feature

# 本地合并并推回公司仓库
git-relay relay-merge my-feature
```

**或一键完成（服务器推送 + 本地拉取 + 合并 + 推公司）：**

```bash
git-relay sync-from-relay my-feature
```

`relay-merge` 执行时会显示合并结果并要求确认，确认后：

1. 推送到 `corp` 主分支
2. 同步回 `relay` 主分支
3. 可选：SSH 更新服务器工作区主分支

---

### 场景四：清理已合并的功能分支

```bash
git-relay feature-clean my-feature
```

依次删除：

- 本地分支 `feature/my-feature`
- relay remote 分支 `relay/feature/my-feature`
- 服务器本地分支 `feature/my-feature`（切回主分支后删除）

---

## 完整命令参考

### 配置类

```bash
git-relay config          # 交互式配置（可随时重新运行来修改参数）
git-relay config-show     # 查看当前配置内容
```

### 初始化类（只需执行一次）

```bash
git-relay init            # 完整初始化（推荐）
git-relay init-server     # 仅初始化外网服务器裸仓库
git-relay init-local      # 仅配置本地 remote 并首推
```

### 日常同步类

```bash
git-relay push-to-relay               # 本地 → 推送主分支到 relay
git-relay server-pull                 # 服务器 → 拉取主分支（SSH 执行）
git-relay sync-to-relay          # 以上两步合一
```

### 功能分支类

```bash
git-relay feature-start <名称>        # 服务器上创建功能分支
git-relay relay-push [名称]         # 服务器推送功能分支到裸仓库
git-relay relay-pull <名称>         # 本地从 relay 拉取功能分支
git-relay relay-merge <名称>        # 本地合并并推回公司仓库
git-relay sync-from-relay <名称>  # 以上三步合一
git-relay feature-clean <名称>        # 清理功能分支
```

### 其他

```bash
git-relay status          # 显示 remote 列表、分支跟踪、提交图
git-relay --help          # 显示帮助
git-relay --version       # 显示版本
```

---

## 配置文件

配置保存在 `~/.git-relay.conf`，格式为 `key=value`，示例：

```ini
server_user=gitrelay
server_host=1.2.3.4
ssh_port=22
project_name=my-app
default_branch=main
corp_url=git@corp.example.com:team/my-app.git
```

权限自动设置为 `600`（仅当前用户可读）。

一台本地机器管理多个项目时，可通过环境变量覆盖：

```bash
CONF_FILE=~/.git-relay-project2.conf git-relay config
CONF_FILE=~/.git-relay-project2.conf git-relay push-to-relay
```

---

## SSH 配置建议

推荐在本地 `~/.ssh/config` 中为外网服务器单独配置：

```sshconfig
Host relay-server
    HostName 1.2.3.4
    User gitrelay
    Port 22
    IdentityFile ~/.ssh/id_relay
    ServerAliveInterval 60
```

然后将 `server_host` 配置为 `relay-server`，脚本会直接使用该 Host 别名。

---

## 常见问题

### Q：`push-to-relay` 失败，提示 SSH 无法连接

检查步骤：

```bash
# 手动测试 SSH 连通性
ssh <server_user>@<server_host> echo ok

# 检查裸仓库路径是否存在
ssh <server_user>@<server_host> ls ~/relay/repos/
```

### Q：`relay-merge` 报 `--ff-only` 失败

说明公司主分支在你拉取之后又有新提交，需要先 rebase 功能分支：

```bash
git fetch corp --prune
git switch main
git pull --ff-only corp main
git switch feature/my-feature
git rebase main              # 或 git merge main（不改写历史）
git-relay relay-merge my-feature
```

### Q：服务器工作区拉不到新分支

先确认服务器已推送该分支，再在本地刷新：

```bash
git fetch relay --prune
git branch -r | grep relay/
```

### Q：想在服务器上继续开发已有功能分支

不需要重新 `feature-start`，直接登录服务器切换分支即可：

```bash
ssh <server_user>@<server_host>
cd ~/relay/worktrees/my-app
git switch feature/my-feature
# ... 继续开发 ...
```

完成后照常执行 `git-relay relay-push`。

---

## 与手册的对应关系

| 手册章节 | 对应命令 |
|---|---|
| 一次性初始化 §1–§5 | `git-relay init` |
| 日常同步 §1 公司→外网 | `git-relay sync-to-relay` |
| 日常同步 §2 服务器功能分支 | `git-relay feature-start` |
| 日常同步 §3 本地拉回功能分支 | `git-relay relay-pull` |
| 日常同步 §4 合并推回公司 | `git-relay relay-merge` |
| 日常同步 §5 清理 | `git-relay feature-clean` |
| 最小闭环流程 | `git-relay sync-to-relay` + `git-relay sync-from-relay` |

原始手册：[2026-04-07-git-multi-remote-relay-sync.md](./2026-04-07-git-multi-remote-relay-sync.md)
