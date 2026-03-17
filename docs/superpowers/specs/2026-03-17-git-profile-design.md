# Git Profile Manager 设计文档

## 概述

一个 Shell (Bash) 脚本工具，用于在一台电脑上管理多个 Git 身份（SSH 密钥 + 用户名/邮箱），支持跨平台和同平台多账号场景。

## 使用场景

- 多个 Git 平台账号（GitHub、GitLab、Gitee 等）
- 同一平台多个账号（如 GitHub 个人号 + 工作号）

## 使用方式

两种模式并存：

- **子命令模式** — `git-profile use work`，适合熟练用户和脚本化调用
- **交互式菜单** — 直接运行 `git-profile`，适合新手或不记得命令时
- 子命令缺少必要参数时自动进入交互模式

## 配置文件格式

文件位于 `~/.git-profiles.conf`，INI 风格：

```ini
# 身份配置
[personal]
name = kgfan
email = 15213243+RollRollRoll@users.noreply.github.com
host = github.com
ssh_key = ~/.ssh/id_rsa_github_personal

[work]
name = Chen Jinfan
email = jinfan.chen@company.com
host = gitlab.company.com
ssh_key = ~/.ssh/id_rsa_work

[github-work]
name = jinfan-work
email = jinfan@work.com
host = github.com
ssh_key = ~/.ssh/id_rsa_github_work

# 目录规则（自动匹配）
[rules]
~/Project/personal/ = personal
~/Project/work/ = work
```

- 每个身份是一个 section，字段：`name`、`email`、`host`、`ssh_key`
- `host` 用于判断同平台多账号（相同 host 需配置 SSH 别名）
- `[rules]` 为保留 section，存放目录 → 身份映射
- 身份名不能使用 `rules`

## 子命令设计

| 子命令 | 功能 | 示例 |
|--------|------|------|
| `(无)` | 进入交互式主菜单 | `git-profile` |
| `add` | 添加新身份（交互式引导，可选生成 SSH 密钥） | `git-profile add` |
| `list` | 列出所有已配置的身份 | `git-profile list` |
| `use <name>` | 在当前项目应用指定身份 | `git-profile use work` |
| `use` | 无参数时列出身份让用户选择 | `git-profile use` |
| `rule add` | 添加目录自动匹配规则 | `git-profile rule add` |
| `rule list` | 查看已有目录规则 | `git-profile rule list` |
| `rule remove` | 删除目录规则 | `git-profile rule remove` |
| `remove <name>` | 删除一个身份 | `git-profile remove work` |
| `current` | 显示当前项目生效的身份信息 | `git-profile current` |

### 交互式主菜单

```
Git Profile Manager
━━━━━━━━━━━━━━━━━━━━━
1) 添加新身份
2) 查看所有身份
3) 切换当前项目身份
4) 管理目录规则
5) 查看当前身份
6) 删除身份
0) 退出

请选择:
```

## 核心流程

### add 流程

1. 输入身份名称（如 personal、work）
2. 输入用户名
3. 输入邮箱
4. 输入 Git 平台 Host（如 github.com）
5. 是否生成新 SSH 密钥？
   - 是 → `ssh-keygen` 生成到 `~/.ssh/id_rsa_<身份名>`，显示公钥供用户添加到平台
   - 否 → 输入已有密钥路径
6. 检测同平台多账号（配置文件中已有相同 host 的身份）
   - 是 → 在 `~/.ssh/config` 添加 Host 别名（如 `Host github.com-work`）
   - 否 → 在 `~/.ssh/config` 添加标准 Host 条目
7. 保存身份到 `~/.git-profiles.conf`

### use 流程

1. 读取身份信息
2. 设置当前项目 git config：
   - `git config user.name "xxx"`
   - `git config user.email "xxx"`
   - `git config core.sshCommand "ssh -i <key_path>"`
3. 检查 remote URL 是否需要调整（同平台多账号场景）
   - 需要 → 显示变更内容，询问确认后修改
   - 不需要 → 跳过
4. 显示配置结果摘要

### rule add 流程

1. 输入目录路径（如 `~/Project/work/`）
2. 选择关联身份
3. 保存到 `~/.git-profiles.conf` 的 `[rules]`
4. 生成 gitconfig 片段文件 `~/.gitconfig.d/<身份名>`，内容：
   ```ini
   [user]
     name = xxx
     email = xxx
   [core]
     sshCommand = ssh -i <key_path>
   ```
5. 写入 `~/.gitconfig` 的 includeIf：
   ```ini
   [includeIf "gitdir:~/Project/work/"]
     path = ~/.gitconfig.d/<身份名>
   ```

### remove 流程

提示是否同时清理：SSH 密钥文件、SSH config 条目、gitconfig.d 片段、includeIf 规则。

## 文件结构

### 项目文件

```
git_config/
├── README.md
├── git-profile          # 主脚本
└── install.sh           # 安装脚本
```

### 运行时文件

| 文件 | 用途 |
|------|------|
| `~/.git-profiles.conf` | 身份配置中心 |
| `~/.ssh/config` | SSH Host 别名配置 |
| `~/.ssh/id_rsa_<name>` | 各身份的 SSH 密钥 |
| `~/.gitconfig` | includeIf 规则写入处 |
| `~/.gitconfig.d/<name>` | 各身份的 git 配置片段 |
| `<project>/.git/config` | use 命令写入的项目级配置 |

## 安装脚本

`install.sh` 执行：

1. 复制 `git-profile` 到 `/usr/local/bin/`（或 `~/.local/bin/`）
2. 赋予可执行权限
3. 初始化 `~/.git-profiles.conf`（如不存在）
4. 创建 `~/.gitconfig.d/` 目录
5. 提示安装完成

## 边界情况

- **非 git 目录运行 `use`/`current`** — 检测并提示退出
- **身份名重复** — 提示是否覆盖
- **密钥文件已存在** — 提示跳过或覆盖
- **SSH config 重复 Host** — 添加前检测避免重复
- **includeIf 已存在** — 检测避免重复
- **删除身份时清理** — 提示是否同时删除关联文件

## 错误处理

- `ssh-keygen` 失败 → 提示错误并中止，不写入配置
- 配置文件不存在或格式错误 → 友好提示并提供修复建议
- 依赖检查 — 启动时检查 `git`、`ssh-keygen`、`ssh` 可用性

## 安全考虑

- SSH 密钥权限设为 600
- 修改 `~/.ssh/config` 和 `~/.gitconfig` 前自动备份（`.bak`）
- 修改 remote URL 前必须用户确认

## 不做的事（YAGNI）

- 密钥轮换/过期管理
- GPG 签名配置
- 远程平台 API 交互（如自动上传公钥）
- 多机同步
