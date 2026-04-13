# git-profile & git-relay

本仓库提供两个互补的 Git 工具：

- **`git-profile`** — 在一台电脑上管理多个 Git 身份（SSH 密钥 + 用户名/邮箱）
- **`git-relay`** — 当外网服务器无法直接访问公司 Git 仓库时，管理多远程中转同步链路

---

# git-profile

在一台电脑上管理多个 Git 身份（SSH 密钥 + 用户名/邮箱），支持多 Git 平台和同平台多账号场景。

## 解决什么问题

当你同时拥有以下场景时，手动管理 git 配置和 SSH 密钥会变得混乱且容易出错：

- **多个 Git 平台** — GitHub 个人项目、公司 GitLab、Gitee 开源项目
- **同一平台多个账号** — GitHub 上同时有个人号和工作号
- **不同项目需要不同身份** — 开源项目用个人邮箱，工作项目用公司邮箱

`git-profile` 提供一个统一的工具来管理所有这些身份，一条命令即可切换。

## 设计思路

### 核心机制

- **`core.sshCommand`** 作为主要的密钥选择方案，通过 `ssh -i <key> -o IdentitiesOnly=yes` 精确指定密钥，防止 ssh-agent 串号
- **`git includeIf`** 实现目录级自动匹配，进入特定目录的项目自动使用对应身份
- **SSH Host 别名** 仅在同平台多账号场景下按需生成，单账号不侵入 `~/.ssh/config`

### 两种配置方式

| 方式 | 适用场景 | 生效范围 |
|------|----------|----------|
| `use` 命令 | 单个项目手动指定 | 写入项目 `.git/config` |
| `rule` 规则 | 按目录自动匹配 | 通过 `includeIf` 自动生效 |

两者可以共存。`use` 的优先级高于 `rule`，可以用 `use --clear` 撤销覆盖、恢复到规则匹配。

### 配置文件

所有身份信息集中存储在 `~/.git-profiles.conf`：

```ini
[personal]
name = li
email = li@gmail.com
host = github.com
ssh_key = ~/.ssh/git_profile_personal

[work]
name = Li Jin
email = jin.li@company.com
host = gitlab.company.com
ssh_key = ~/.ssh/git_profile_work

[github-work]
name = lijin-work
email = lijin@work.com
host = github.com
ssh_key = ~/.ssh/git_profile_github-work

[rule "work-projects"]
dir = /Users/lijin/Project/work/
profile = work
```

### 运行时文件

| 文件 | 用途 |
|------|------|
| `~/.git-profiles.conf` | 身份配置中心 |
| `~/.ssh/git_profile_<name>` | 各身份的 SSH 密钥 |
| `~/.gitconfig.d/<name>` | 目录规则对应的 git 配置片段 |
| `~/.gitconfig` | `includeIf` 规则写入处 |
| `~/.ssh/config` | 仅同平台多账号时写入 Host 别名 |

## 安装

```bash
git clone <repo-url>
cd git_config
./install.sh
```

安装脚本会：
1. 复制 `git-profile` 和 `git-relay` 到 `~/.local/bin/`
2. 初始化 `~/.git-profiles.conf`
3. 创建 `~/.gitconfig.d/` 目录
4. 设置 `git profile` 别名（可用 `git profile` 代替 `git-profile`）

如果 `~/.local/bin` 不在 PATH 中，需要添加：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## 使用指南

### 场景一：添加第一个身份

```bash
$ git-profile add

=== Add New Profile ===

Profile name (e.g., personal, work): personal
User name: lijin
Email: lijin@gmail.com
Git platform host (e.g., github.com): github.com
Generate a new SSH key? [Y/n]: Y
Key algorithm [ed25519/rsa] (default: ed25519):

Generating public/private ed25519 key pair.

Public key (add this to your Git platform):
---
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... lijin@gmail.com
---

Profile 'personal' added successfully.
```

将输出的公钥复制到 GitHub → Settings → SSH and GPG keys → New SSH key。

### 场景二：添加工作身份（不同平台）

```bash
$ git-profile add

Profile name: work
User name: lijin
Email: lijin@company.com
Git platform host: gitlab.company.com
Generate a new SSH key? [Y/n]: Y

Profile 'work' added successfully.
```

因为 `github.com` 和 `gitlab.company.com` 是不同平台，不会写入 SSH config。

### 场景三：添加同平台第二个账号

```bash
$ git-profile add

Profile name: github-work
User name: jinfan-work
Email: jinfan@work.com
Git platform host: github.com
Generate a new SSH key? [Y/n]: Y

Detected another profile using the same host 'github.com'.
Add SSH Host alias 'github.com-github-work' to ~/.ssh/config? [y/N]: y

SSH alias added: github.com-github-work -> github.com
  Use this in clone URLs: git@github.com-github-work:<user>/<repo>.git

Profile 'github-work' added successfully.
```

此时 clone 工作仓库可以用别名 URL：

```bash
git clone git@github.com-github-work:company/project.git
```

### 场景四：查看所有身份

```bash
$ git-profile list

Configured profiles:

  [personal]
    Name:  lijin
    Email: lijin@gmail.com
    Host:  github.com
    Key:   ~/.ssh/git_profile_personal

  [work]
    Name:  jin li
    Email: jin.li@company.com
    Host:  gitlab.company.com
    Key:   ~/.ssh/git_profile_work

  [github-work]
    Name:  li-work
    Email: li@work.com
    Host:  github.com
    Key:   ~/.ssh/git_profile_github-work
```

### 场景五：为当前项目切换身份

```bash
$ cd ~/Project/my-open-source-lib
$ git-profile use personal

Switched to profile 'personal' in this repository.
  Name:  lijin
  Email: lijin@gmail.com
  Key:   /Users/lijin/.ssh/git_profile_personal
```

验证配置已生效：

```bash
$ git-profile current

Current Git Profile: personal
  Name:   lijin
  Email:  lijin@gmail.com
  Host:   github.com
  Key:    ~/.ssh/git_profile_personal
  Source: project config
```

### 场景六：设置目录自动匹配规则

让 `~/Project/work/` 下的所有仓库自动使用 `work` 身份：

```bash
$ git-profile rule add

=== Add Directory Rule ===

Rule name: work-projects
Directory path: ~/Project/work/
Normalized path: /Users/lijin/Project/work/
Confirm this path? [Y/n]: Y

Available profiles:
  1) personal
  2) work
Select profile number: 2

Rule 'work-projects' added.
  Directory: /Users/lijin/Project/work/
  Profile:   work
```

之后在该目录下的任何 git 仓库中，`user.name`、`user.email`、`core.sshCommand` 都会自动设置为 `work` 身份的值，无需手动 `use`。

### 场景七：查看当前规则

```bash
$ git-profile rule list

Directory rules:

  [work-projects]
    Directory: /Users/lijin/Project/work/
    Profile:   work
```

### 场景八：在规则覆盖的项目中临时切换身份

```bash
$ cd ~/Project/work/special-project
$ git-profile use personal

Note: current directory is matched by a directory rule (profile: work).
  'use' will override this rule. To undo, run: git-profile use --clear

Switched to profile 'personal' in this repository.
```

恢复到规则匹配：

```bash
$ git-profile use --clear

Cleared profile override for this repository.

Effective config:
  user.name  = lijin
  user.email = lijin@company.com
```

### 场景九：管理远程 URL（HTTPS ↔ SSH 转换）

当仓库 remote 使用 HTTPS URL 时，SSH 密钥不会生效。`git-profile` 现在支持直接修改 remote URL，也支持在 HTTPS 和 SSH 之间自动转换：

```bash
# 查看当前仓库的远程 URL
$ git-profile remote show
Remote URLs:
  (active profile: personal)

  origin  https://github.com/user/repo.git  [HTTPS]

# 直接修改 origin 的 URL
$ git-profile remote set git@gitlab.company.com:team/project.git
Updated remote 'origin' to git@gitlab.company.com:team/project.git

# 修改指定 remote 的 URL
$ git-profile remote set upstream https://github.com/company/project.git
Updated remote 'upstream' to https://github.com/company/project.git

# 转换为 SSH 格式
$ git-profile remote set-ssh
Converting remote URLs to SSH (profile: personal, host: github.com):
  origin: https://github.com/user/repo.git → git@github.com:user/repo.git
Proceed? [y/N] y
Done.

# 转换为 HTTPS 格式
$ git-profile remote set-https
Converting remote URLs to HTTPS (profile: personal, host: github.com):
  origin: git@github.com:user/repo.git → https://github.com/user/repo.git
Proceed? [y/N] y
Done.
```

在执行 `use` 切换身份时，如果检测到 HTTPS remote，会自动提示是否转换：

```bash
$ git-profile use personal
Switched to profile 'personal' in this repository.
  Name:  kgfan
  Email: kgfan@gmail.com
  Key:   /Users/chenjinfan/.ssh/git_profile_personal

Warning: the following remotes use HTTPS — SSH key will not be used:
  origin: https://github.com/user/repo.git
Convert to SSH? [y/N] y
  origin: https://github.com/user/repo.git → git@github.com:user/repo.git
```

### 场景十：修改已有身份

```bash
$ git-profile edit work

Editing profile 'work' (press Enter to keep current value):

  Name [lijin]:
  Email [lijin.chen@company.com]: lijin@newcompany.com
  Host [gitlab.company.com]:
  SSH Key [~/.ssh/git_profile_work]:

Profile 'work' updated.
```

修改会同步更新关联的 `~/.gitconfig.d/work` 片段文件。

### 场景十一：删除身份

```bash
$ git-profile remove github-work

Profile 'github-work' is referenced by these rules:
  - github-work-rule
Delete these rules as well? [Y/n]: Y

Delete SSH key '/Users/lijin/.ssh/git_profile_github-work'? [y/N]: y
Delete gitconfig fragment '/Users/lijin/.gitconfig.d/github-work'? [y/N]: y

Profile 'github-work' removed.
```

### 交互式菜单

不带参数运行 `git-profile` 进入交互式菜单：

```bash
$ git-profile

Git Profile Manager
━━━━━━━━━━━━━━━━━━━━━
1) 添加新身份
2) 修改身份
3) 查看所有身份
4) 切换当前项目身份
5) 撤销身份覆盖（恢复原始配置）
6) 管理目录规则
7) 查看当前身份
8) 删除身份
0) 退出

请选择:
```

## 命令参考

| 命令 | 功能 |
|------|------|
| `git-profile` | 交互式菜单 |
| `git-profile add` | 添加新身份（交互式引导） |
| `git-profile list` | 查看所有身份 |
| `git-profile use <name>` | 在当前项目应用指定身份 |
| `git-profile use` | 交互式选择身份 |
| `git-profile use --clear` | 撤销 use 覆盖，恢复原始配置 |
| `git-profile current` | 查看当前项目生效的身份 |
| `git-profile remote` | 查看远程 URL |
| `git-profile remote set <url>` | 直接修改 `origin` 的远程 URL |
| `git-profile remote set <remote> <url>` | 直接修改指定 remote 的 URL |
| `git-profile remote set-ssh` | 转换远程 URL 为 SSH 格式 |
| `git-profile remote set-https` | 转换远程 URL 为 HTTPS 格式 |
| `git-profile edit <name>` | 修改已有身份 |
| `git-profile remove <name>` | 删除身份（含级联清理） |
| `git-profile rule add` | 添加目录自动匹配规则 |
| `git-profile rule list` | 查看已有规则 |
| `git-profile rule remove` | 删除目录规则 |
| `git-profile --help` | 显示帮助 |
| `git-profile --version` | 显示版本 |

## 平台支持

- **操作系统**：macOS、Linux
- **Bash 版本**：3.2+（兼容 macOS 自带 Bash）
- **依赖工具**：`git`、`ssh-keygen`、`ssh`
- **可选工具**：`realpath`（路径规范化，不可用时自动回退）

## 手动清理

如需完全卸载 `git-profile`：

```bash
rm -f ~/.local/bin/git-profile        # 删除脚本
rm -f ~/.git-profiles.conf            # 删除配置
rm -rf ~/.gitconfig.d/                # 删除 gitconfig 片段
git config --global --unset alias.profile  # 删除 git 别名
# SSH 密钥和 ~/.ssh/config 中的别名条目需手动检查删除
```

---

# git-relay

在"外网服务器不能直接访问公司 Git 服务器"的场景下，`git-relay` 将手册中的每个操作序列封装为单条命令，实现以下链路的一键管理：

```
公司仓库 (corp)  ↔  本地工作仓库  ↔  外网裸仓库 (relay)  ↔  外网服务器工作区
```

**核心约束**：

- 本地是唯一能同时连接 `corp` 和 `relay` 的节点
- 外网服务器只与裸仓库通信，不配置 `corp` remote
- 所有回流公司仓库的操作只能在本地执行

## 快速开始

### 第一步：填写配置

```bash
git-relay config
```

在 git 仓库内运行时，会先询问保存位置：

```
保存位置：
  1) 项目级  /path/to/project/.git-relay.conf
  2) 全局    ~/.git-relay.conf
```

选择项目级时，会自动提示将 `.git-relay.conf` 加入 `.gitignore`，防止服务器信息提交进仓库。

交互式填写以下参数：

| 参数 | 说明 | 默认值 / 示例 |
|---|---|---|
| `server_host` | 外网服务器地址或 SSH Host 别名 | `1.2.3.4` 或 `relay-server` |
| `server_user` | 外网服务器用户名（**可选**，SSH config 中有则留空） | `gitrelay` |
| `ssh_port` | SSH 端口（**可选**，SSH config 中有则留空） | `2222` |
| `project_name` | 项目名（默认预填目录名） | `my-app` |
| `default_branch` | 默认分支 | `main` |
| `corp_remote` | 公司仓库 remote 名 | `corp` |
| `relay_remote` | 中转仓库 remote 名 | `relay` |
| `corp_url` | 公司仓库 URL（可选择已有 remote 代替手动输入） | `git@corp.example.com:team/my-app.git` |
| `server_bare_path` | 服务器裸仓库路径（可选，有默认值） | `/data/repos/my-app.git` |
| `server_work_path` | 服务器工作区路径（可选，有默认值） | `/data/worktrees/my-app` |

**`corp_url` 的两种填写方式**：
- 选择已有 remote — 列出当前仓库所有 remote，选一个即可，URL 自动读取
- 手动输入 — 若 `corp_remote` 对应的 remote 已存在且 URL 一致，也可不单独存储 `corp_url`

### 第二步：一次性初始化

在项目目录下执行：

```bash
cd ~/Project/my-app
git-relay init
```

该命令依次完成：

1. SSH 到外网服务器，创建裸仓库和目录结构
2. 本地配置 `<corp_remote>` / `<relay_remote>` 两个 remote（名称可在 config 中自定义）
3. 将主分支首次推送到外网裸仓库
4. 在外网服务器 clone 工作区

完成后服务器默认目录结构如下（路径可通过 `server_bare_path` / `server_work_path` 自定义）：

```
/home/<server_user>/relay/
├── repos/
│   └── <project_name>.git   # 裸仓库（中转节点）
└── worktrees/
    └── <project_name>       # 工作区（开发节点）
```

## 日常工作流

### 开始远程开发前：同步公司最新代码到服务器

```bash
git-relay sync-to-relay
```

等价于：本地从 `corp_remote` 拉取 → 推送到 `relay_remote` → SSH 让服务器自动 pull。

### 在外网服务器上开发功能分支

```bash
# 1. 在服务器创建功能分支（SSH 自动执行）
git-relay feature-start my-feature

# 2. 登录服务器进行开发
ssh <server_user>@<server_host>
cd <server_work_path>   # 默认：~/relay/worktrees/<project_name>
# ... 编辑、git add、git commit ...

# 3. 开发完毕，服务器推回裸仓库（SSH 自动执行）
git-relay relay-push
```

### 将服务器功能分支同步回公司仓库

**逐步执行：**

```bash
git-relay relay-pull my-feature   # 本地从 relay 拉取功能分支
git-relay relay-merge my-feature  # 合并并推回公司仓库
```

**或一键完成（服务器推送 + 本地拉取 + 合并 + 推公司）：**

```bash
git-relay sync-from-relay my-feature
```

### 清理已合并的功能分支

```bash
git-relay feature-clean my-feature
```

一次性删除本地分支、`relay_remote` 远程分支、服务器本地分支。

## 命令参考

### 配置类

| 命令 | 功能 |
|---|---|
| `git-relay config` | 交互式配置（首次必须先执行） |
| `git-relay config-show` | 查看当前配置 |

### 初始化类（只需执行一次）

| 命令 | 功能 |
|---|---|
| `git-relay init` | 完整初始化（推荐） |
| `git-relay init-server` | 仅初始化外网服务器裸仓库 |
| `git-relay init-local` | 仅配置本地 remote 并首推 |

### 日常同步类

| 命令 | 功能 |
|---|---|
| `git-relay push-to-relay` | 本地 → 推送主分支到 relay |
| `git-relay server-pull` | 服务器 → 拉取主分支（SSH 执行） |
| `git-relay sync-to-relay` | 以上两步合一 |

### 功能分支类

| 命令 | 功能 |
|---|---|
| `git-relay feature-start <名称>` | 服务器上创建功能分支 |
| `git-relay relay-push [名称]` | 服务器推送功能分支到裸仓库 |
| `git-relay relay-pull <名称>` | 本地从 relay 拉取功能分支 |
| `git-relay relay-merge <名称>` | 本地合并并推回公司仓库 |
| `git-relay sync-from-relay <名称>` | 以上三步合一 |
| `git-relay feature-clean <名称>` | 清理功能分支（本地 + relay + 服务器） |
| `git-relay status` | 显示 remote、分支跟踪、提交图 |

## 配置文件

### 优先级

配置文件按以下优先级依次查找（高优先级覆盖低优先级）：

1. **环境变量** `CONF_FILE=<路径>`（显式指定）
2. **项目级** `<仓库根目录>/.git-relay.conf`（自动检测）
3. **全局** `~/.git-relay.conf`（默认回退）

### 格式

**完整配置（显式指定所有项）：**

```ini
server_host=1.2.3.4
server_user=gitrelay
ssh_port=22
project_name=my-app
default_branch=main
corp_remote=corp
relay_remote=relay
corp_url=git@corp.example.com:team/my-app.git
```

**使用 SSH config Host 别名时的最简配置：**

```ini
server_host=relay-server   # 对应 ~/.ssh/config 中的 Host 别名
project_name=my-app
default_branch=main
```

`server_user` 和 `ssh_port` 留空时，SSH 连接和 git remote URL 均直接使用 `server_host`，由 `~/.ssh/config` 中的别名提供用户名和端口。若同时省略了 `server_bare_path` / `server_work_path`，脚本会通过一次 `whoami` SSH 调用解析远端用户名来派生默认路径。

**路径默认派生规则：**
- 裸仓库：`/home/<server_user>/relay/repos/<project_name>.git`
- 工作区：`/home/<server_user>/relay/worktrees/<project_name>`

路径与默认值一致时不会写入配置文件，保持简洁。权限自动设为 `600`。

### 多项目管理

**推荐方式：每个项目在仓库内运行 `git-relay config` 选择「项目级」**，脚本自动读取当前仓库的配置，无需额外操作。

也可通过环境变量临时切换：

```bash
CONF_FILE=~/.git-relay-other.conf git-relay push-to-relay
```

### config-show 来源标注

```bash
git-relay config-show
# 输出示例：
# ── 当前配置 [项目级] /path/to/project/.git-relay.conf ──
# ── 当前配置 [全局] ~/.git-relay.conf ──
# ── 当前配置 [环境变量指定] /custom/path.conf ──
```

## 扩展文档

- [git-relay 完整使用手册](docs/guides/2026-04-12-git-relay-script.md)
- [Git 多远程中转同步原理手册](docs/guides/2026-04-07-git-multi-remote-relay-sync.md)
