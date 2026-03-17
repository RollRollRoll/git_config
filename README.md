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
1. 复制 `git-profile` 到 `~/.local/bin/`
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

### 场景九：修改已有身份

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

### 场景十：删除身份

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
