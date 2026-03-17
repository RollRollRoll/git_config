# Git Profile Manager 设计文档

## 概述

一个 Shell (Bash) 脚本工具，用于在一台电脑上管理多个 Git 身份（SSH 密钥 + 用户名/邮箱），支持多 Git 平台和同平台多账号场景。

### 平台支持

- **操作系统**：macOS、Linux（首版目标）
- **Bash 版本**：3.2+（兼容 macOS 自带的 Bash）、4.0+ 均支持
- **依赖工具**：`git`、`ssh-keygen`、`ssh`
- **可选工具**：`realpath`（路径规范化时使用，macOS 需通过 `brew install coreutils` 安装；如不可用，回退到 `cd "$(dirname "$path")" && pwd` 方式解析）

## 使用场景

- 多个 Git 平台账号（GitHub、GitLab、Gitee 等）
- 同一平台多个账号（如 GitHub 个人号 + 工作号）

## 使用方式

两种模式并存：

- **子命令模式** — `git-profile use work`，适合熟练用户和脚本化调用
- **交互式菜单** — 直接运行 `git-profile`，适合新手或不记得命令时
- 子命令缺少必要参数时自动进入交互模式
- 支持 `git-profile --help` 和 `git-profile --version`

## 配置文件格式

文件位于 `~/.git-profiles.conf`，INI 风格：

```ini
# 身份配置
[personal]
name = kgfan
email = 15213243+RollRollRoll@users.noreply.github.com
host = github.com
ssh_key = ~/.ssh/git_profile_personal

[work]
name = Chen Jinfan
email = jinfan.chen@company.com
host = gitlab.company.com
ssh_key = ~/.ssh/git_profile_work

[github-work]
name = jinfan-work
email = jinfan@work.com
host = github.com
ssh_key = ~/.ssh/git_profile_github-work

# 目录规则
[rule "personal-projects"]
dir = ~/Project/personal/
profile = personal

[rule "work-projects"]
dir = ~/Project/work/
profile = work
```

### 语法规则

- 注释行以 `#` 开头，不支持行内注释
- 键值对格式为 `key = value`，等号两侧空格可选
- 值不需要引号包裹，取首尾去空白后的整行内容
- 空行忽略
- 身份名仅允许 `[a-zA-Z0-9_-]`，不能使用 `rule` 作为前缀
- 身份 section 格式：`[name]`，字段：`name`、`email`、`host`、`ssh_key`
- 规则 section 格式：`[rule "规则名"]`，字段：`dir`、`profile`
- `host` 用于判断同平台多账号（相同 host 需配置 SSH 别名）

## 子命令设计

| 子命令 | 功能 | 示例 |
|--------|------|------|
| `(无)` | 进入交互式主菜单 | `git-profile` |
| `add` | 添加新身份（交互式引导，可选生成 SSH 密钥） | `git-profile add` |
| `edit <name>` | 修改已有身份的字段 | `git-profile edit work` |
| `list` | 列出所有已配置的身份 | `git-profile list` |
| `use <name>` | 在当前项目应用指定身份 | `git-profile use work` |
| `use` | 无参数时列出身份让用户选择 | `git-profile use` |
| `use --clear` | 撤销所有 use 覆盖，恢复到首次 use 之前的原始状态 | `git-profile use --clear` |
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

## 核心流程

### SSH 多账号策略

采用 `core.sshCommand` 作为主要方案：

- **`use` 命令**和**目录规则（includeIf）**统一通过 `core.sshCommand = "ssh -i <key_path> -o IdentitiesOnly=yes"` 指定密钥
  - `-o IdentitiesOnly=yes` 防止 OpenSSH 继续尝试 ssh-agent 或其他默认密钥，避免多密钥环境下串号或触发认证次数上限
- **SSH config Host 别名**仅在同平台多账号场景下按需生成，且需用户确认后才写入（方便用户手动 `git clone` 时使用正确的别名 URL）
- **单账号场景不写入 `~/.ssh/config`**，避免侵入用户已有 SSH 策略。`core.sshCommand` 已足够解决密钥选择
- `use` 命令不自动修改 remote URL，因为 `core.sshCommand` 已足够解决密钥选择问题
- 如用户的 remote URL 已使用 Host 别名格式，`core.sshCommand` 和 Host 别名可共存无冲突

### use 与 rule 的优先级模型

Git 配置优先级：project `.git/config` > includeIf > global `~/.gitconfig`。

这意味着一旦 `use` 写入项目级配置，目录规则就会被"压住"。为此引入以下机制：

- **git config 层级规则** — `gitProfile.name` 同时存在于 includeIf 片段和项目级 `.git/config` 中，层级不同，判定时必须区分：
  - `git config gitProfile.name` — 读取最终生效值（含 includeIf），用于 `current` 命令
  - `git config --local gitProfile.name` — 仅读取项目级 `.git/config`，用于判断"是否被 `use` 覆盖"
  - **所有 `gitProfile.backup.*` 的读写都限定 `--local`**，因为 backup 只存在于项目级配置
- **`use` 写入前备份（仅首次）** — 仅当 `git config --local gitProfile.name` 为空时（即当前项目尚未被任何 `use` 覆盖），才备份当前项目级本地值到 `gitProfile.backup.*`：
  ```
  git config --local gitProfile.backup.userName "$(git config --local user.name)"
  git config --local gitProfile.backup.userEmail "$(git config --local user.email)"
  git config --local gitProfile.backup.sshCommand "$(git config --local core.sshCommand)"
  ```
  如果某个键 `--local` 查不到，不写入对应 backup 键（表示"原本就没有本地值"）。
  后续连续 `use` 切换身份时（`--local gitProfile.name` 已存在），**不覆盖 backup**，始终保留首次 use 之前的原始状态。
- **`use --clear` 语义：撤销所有 use 覆盖** — 恢复到首次 `use` 之前的原始状态，而非"撤销最近一次 use"：
  - `git config --local gitProfile.backup.userName` 存在 → 恢复为备份值
  - 该 backup 键不存在 → `git config --local --unset user.name`（恢复到 rule/global）
  - 最后清除所有本地 `gitProfile.*` 键
  - 示例：`use work` → `use personal` → `use --clear` → 恢复到 work 和 personal 之前的原始状态
- **`use` 执行时的提示** — 如果检测到当前项目已在某条目录规则的覆盖范围内，显示提示："当前目录已匹配规则 `<rule_name>` (身份: `<profile>`)，`use` 会覆盖该规则。如需恢复，运行 `git-profile use --clear`"
- **`current` 输出中体现覆盖关系** — 当项目级配置覆盖了 includeIf 规则时，在 Source 字段标注，如 `Source: project config (overrides rule: work-projects)`

### add 流程

1. 输入身份名称（仅允许 `[a-zA-Z0-9_-]`）
2. 检测身份名是否已存在，已存在则提示是否覆盖
3. 输入用户名
4. 输入邮箱
5. 输入 Git 平台 Host（如 github.com）
6. 是否生成新 SSH 密钥？
   - 是 → 选择算法（默认 ed25519，可选 rsa），`ssh-keygen` 生成到 `~/.ssh/git_profile_<身份名>`，显示公钥供用户添加到平台
   - 否 → 输入已有密钥路径
7. 检测同平台多账号（配置文件中已有相同 host 的身份）
   - 是 → 提示用户确认后，在 `~/.ssh/config` 添加 Host 别名条目（如 `Host github.com-work`），用 `# git-profile: <name>` 注释标记，并显示别名 URL 使用示例
   - 否 → 不写入 `~/.ssh/config`（单账号场景由 `core.sshCommand` 全权处理）
8. 保存身份到 `~/.git-profiles.conf`
9. 显示添加成功摘要

### edit 流程

1. 读取当前身份信息并展示
2. 逐字段提示修改（回车跳过保持不变）
3. 同步更新派生文件（任一字段变化都触发）：
   - **name / email / ssh_key 变化** → 重写该身份关联的所有 `~/.gitconfig.d/<name>` 片段（因为片段中包含 user.name、user.email、core.sshCommand）
   - **host 变化** → 更新 SSH config 中的 Host 别名条目（如有）
   - **ssh_key 变化** → 同时更新 SSH config 条目中的 IdentityFile
4. 显示修改结果摘要

### use 流程

`git-profile use <name>` — 将指定身份应用到当前项目。

1. 检测当前目录是否为 git 仓库，否则提示退出
2. 读取身份信息
3. 检测当前目录是否在某条目录规则覆盖范围内，如果是则提示：
   > 当前目录已匹配规则 "work-projects" (身份: work)，use 会覆盖该规则。如需恢复，运行 git-profile use --clear
4. 仅当 `git config --local gitProfile.name` 为空时（首次 use），备份当前项目级本地值到 `gitProfile.backup.*`（详见"use 与 rule 的优先级模型"）
5. 设置当前项目 git config：
   - `git config gitProfile.name "<profile_name>"` — 显式标记当前使用的 profile
   - `git config user.name "xxx"`
   - `git config user.email "xxx"`
   - `git config core.sshCommand "ssh -i <key_path> -o IdentitiesOnly=yes"`
6. 检测 remote URL 协议类型，如果是 HTTPS 则提示"SSH 配置不影响 HTTPS remote，是否转换为 SSH URL？"
7. 显示配置结果摘要

`git-profile use --clear` — 撤销所有 `use` 覆盖，恢复到首次 `use` 之前的原始状态。

1. 检测当前目录是否为 git 仓库
2. 检查 `git config --local gitProfile.name` 是否存在，不存在则提示"当前项目未被 use 覆盖"并退出
3. 读取 `--local gitProfile.backup.*` 键逐一恢复：
   - `git config --local gitProfile.backup.userName` 存在 → `git config user.name "<backup_value>"`
   - 该 backup 键不存在 → `git config --local --unset user.name`
   - `userEmail` / `sshCommand` 同理
4. 清除所有本地 `gitProfile.*` 键（`git config --local --remove-section gitProfile`）
5. 显示恢复结果，并提示当前生效的配置来源（原始本地值 / includeIf 规则 / 全局配置）

### current 流程

通过 `gitProfile.name` 获取显式标记的 profile 名称，而非根据 user/email 反向推断。

识别逻辑：
1. 读取 `git config gitProfile.name`（不加 `--local`，读取最终生效值，包含 includeIf 片段）
2. 如果存在，直接使用该值确定当前 profile
3. 判断来源：`git config --local gitProfile.name` 有值 → 来自 `use` 覆盖；无值但步骤 1 有值 → 来自 includeIf 规则
4. 如果步骤 1 不存在，尝试匹配当前 user.name + user.email 与已知 profiles（作为 fallback，标注为"推断"）
5. 如果都不匹配，显示当前 git 配置的原始值

输出格式：

```
Current Git Profile: work
  Name:   Chen Jinfan
  Email:  jinfan.chen@company.com
  Host:   gitlab.company.com
  Key:    ~/.ssh/git_profile_work
  Source: project config (.git/config)
```

`Source` 标明配置来源：
- `project config` — 由 `use` 命令写入
- `project config (overrides rule: work-projects)` — 项目级配置覆盖了目录规则
- `includeIf rule: work-projects` — 由目录规则生效
- `global config` — 全局配置
- `未配置`

### rule add 流程

1. 输入目录路径（如 `~/Project/work/`）
2. **路径规范化处理**（在写入前执行，双路径策略）：
   - `~` 展开为 `$HOME` 绝对路径
   - 相对路径转换为绝对路径（基于 `pwd`）
   - **路径存在时** → 使用 `realpath` 解析符号链接，因为 `gitdir:` 匹配的是 `.git` 目录的真实位置
   - **路径不存在时** → 仅做上述 `~` 展开和绝对路径化，跳过 `realpath`，并警告："目录不存在，无法解析符号链接，如果路径包含符号链接，规则可能不会生效"
   - 确保尾部以 `/` 结尾（git 的 `gitdir:` 规则中尾部 `/` 表示递归匹配该目录下所有仓库，无 `/` 则精确匹配）
   - 规范化后的路径显示给用户确认
3. 选择关联身份
4. 保存到 `~/.git-profiles.conf` 的 `[rule "xxx"]` section（存储规范化后的绝对路径）
5. 生成 gitconfig 片段文件 `~/.gitconfig.d/<身份名>`，内容：
   ```ini
   [gitProfile]
     name = <身份名>
   [user]
     name = xxx
     email = xxx
   [core]
     sshCommand = ssh -i <key_path> -o IdentitiesOnly=yes
   ```
6. 使用 `git config --global` 命令写入 includeIf（路径使用规范化后的绝对路径）：
   ```
   git config --global includeIf."gitdir:<normalized_dir>".path ~/.gitconfig.d/<身份名>
   ```

### rule remove 流程

1. 列出已有规则让用户选择
2. 从 `~/.git-profiles.conf` 中删除对应 `[rule "xxx"]` section
3. 从 `~/.gitconfig` 中删除对应 includeIf 条目（使用 `git config --global --unset`）
4. 检查是否还有其他规则引用同一身份，如果没有则提示是否删除 `~/.gitconfig.d/<name>` 片段

### remove 流程

1. 检查该身份是否被 rules 引用，如有则列出并提示是否一并删除关联规则
2. 提示是否同时清理：
   - SSH 密钥文件
   - SSH config 条目（通过 `# git-profile: <name>` 注释定位）
   - gitconfig.d 片段
   - includeIf 规则
3. 执行清理并显示结果摘要

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
| `~/.ssh/config` | 仅同平台多账号时写入 Host 别名（条目用 `# git-profile: <name>` 标记） |
| `~/.ssh/git_profile_<name>` | 各身份的 SSH 密钥 |
| `~/.gitconfig` | includeIf 规则写入处（通过 `git config --global` 操作） |
| `~/.gitconfig.d/<name>` | 各身份的 git 配置片段 |
| `<project>/.git/config` | use 命令写入的项目级配置 |

## 安装脚本

`install.sh` 执行：

1. 复制 `git-profile` 到 `~/.local/bin/`（默认）或用户指定路径
2. 赋予可执行权限
3. 初始化 `~/.git-profiles.conf`（如不存在）
4. 创建 `~/.gitconfig.d/` 目录
5. 设置 git 别名：`git config --global alias.profile '!git-profile'`
6. 提示安装完成

## 边界情况

- **非 git 目录运行 `use`/`current`** — 检测并提示退出
- **身份名重复** — 提示是否覆盖
- **身份名非法字符** — 校验仅允许 `[a-zA-Z0-9_-]`
- **密钥文件已存在** — 提示跳过或覆盖
- **SSH config 重复 Host** — 仅同平台多账号写入，添加前通过注释标记检测避免重复
- **use 覆盖目录规则** — 提示用户并告知 `use --clear` 恢复方式
- **includeIf 已存在** — 检测避免重复
- **删除身份时级联清理** — 检查 rules 引用并提示一并删除
- **HTTPS remote** — `use` 时检测并提示用户是否转换为 SSH URL

## 错误处理

- `ssh-keygen` 失败 → 提示错误并中止，不写入配置
- 配置文件不存在或格式错误 → 友好提示并提供修复建议
- 依赖检查 — 启动时检查 `git`、`ssh-keygen`、`ssh` 可用性；`realpath` 不可用时自动使用内置 fallback（`cd + pwd`）

## 安全考虑

- SSH 密钥权限设为 600
- 修改 `~/.ssh/config` 前自动备份（带时间戳：`.bak.YYYYMMDD_HHMMSS`）
- `~/.gitconfig` 通过 `git config --global` 命令操作，无需直接文本编辑
- 所有操作完成后显示明确的成功/失败反馈

## 不做的事（YAGNI）

- 密钥轮换/过期管理
- GPG 签名配置
- 远程平台 API 交互（如自动上传公钥）
- 多机同步
- 卸载脚本（文件不多，README 中说明手动清理步骤即可）
