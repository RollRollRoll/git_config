# Remote URL 管理重构 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 `git-profile` 增加通用 `remote set` 命令，并重构 remote 子系统的公共逻辑。

**Architecture:** 在 `git-profile` 中新增统一的 remote 辅助函数，复用 Git 仓库校验、remote 存在性校验和 fetch remote 枚举逻辑。基于这些公共函数实现 `remote set`，并将 `show`、`set-ssh`、`set-https` 改造为共享同一套数据来源与错误处理规则。

**Tech Stack:** Bash、Git CLI、现有 Shell 测试脚本

---

### Task 1: 写入 `remote set` 的失败测试

**Files:**
- Modify: `tests/test_git_profile.sh`
- Test: `tests/test_git_profile.sh`

**Step 1: 写失败测试**

补充这些测试：

- `test_remote_set_default_origin`
- `test_remote_set_specific_remote`
- `test_remote_set_missing_remote`
- `test_remote_set_missing_url`
- `test_remote_set_ssh_single_remote`
- `test_remote_set_https_single_remote`

**Step 2: 运行测试确认失败**

Run: `bash tests/test_git_profile.sh`

Expected:

- 新增测试失败
- 失败原因集中在 `remote set` 不存在、单 remote 转换行为未覆盖或错误处理不符合预期

**Step 3: 不修改生产代码前先确认失败输出**

- 确认失败不是测试拼写错误
- 确认失败点对应目标行为缺失

### Task 2: 重构 remote 公共辅助逻辑

**Files:**
- Modify: `git-profile`
- Test: `tests/test_git_profile.sh`

**Step 1: 实现公共辅助函数**

在 `git-profile` 的 remote 管理区域增加：

- `require_git_repo`
- `remote_exists`
- `list_fetch_remotes`

**Step 2: 最小改造 `cmd_remote_show`**

- 改为依赖 `require_git_repo`
- 改为依赖 `list_fetch_remotes`
- 保持现有输出格式和协议标签逻辑

**Step 3: 运行测试**

Run: `bash tests/test_git_profile.sh`

Expected:

- 仍有与 `remote set` 相关的失败
- 现有 `remote show` 测试保持通过

### Task 3: 实现 `cmd_remote_set`

**Files:**
- Modify: `git-profile`
- Test: `tests/test_git_profile.sh`

**Step 1: 写最小实现**

实现：

- `git-profile remote set <url>` 默认改 `origin`
- `git-profile remote set <remote-name> <url>` 改指定 remote
- 缺参时报 usage
- remote 不存在时报明确错误

**Step 2: 接入命令分发**

- 更新 `cmd_remote`
- 更新帮助文本中的 `remote` 用法

**Step 3: 运行测试**

Run: `bash tests/test_git_profile.sh`

Expected:

- `remote set` 相关测试转绿
- 单 remote 转换测试仍可能失败

### Task 4: 改造 `set-ssh` 与 `set-https` 的单 remote 路径

**Files:**
- Modify: `git-profile`
- Test: `tests/test_git_profile.sh`

**Step 1: 统一单 remote 校验**

- 指定 remote 时先用 `remote_exists` 校验
- 未指定 remote 时保持当前批量行为

**Step 2: 改为依赖 `list_fetch_remotes`**

- 避免重复解析 `git remote -v`
- 保持 `ssh://` 跳过策略

**Step 3: 运行测试**

Run: `bash tests/test_git_profile.sh`

Expected:

- 全部 remote 相关测试通过

### Task 5: 更新交互菜单与文档

**Files:**
- Modify: `git-profile`
- Modify: `README.md`

**Step 1: 更新交互菜单**

- 在 remote 菜单中新增“设置远程 URL”
- 读取 remote 名称，空值回退为 `origin`
- 读取新 URL 并调用 `cmd_remote_set`

**Step 2: 更新 README**

- 补充 `remote set` 用法
- 说明默认 remote 为 `origin`

**Step 3: 运行测试**

Run: `bash tests/test_git_profile.sh`

Expected:

- 仍为全绿

### Task 6: 最终验证与收尾

**Files:**
- Modify: `.serena/memories/...`（通过工具写入，不直接编辑文件）

**Step 1: 运行完整验证**

Run: `bash tests/test_git_profile.sh`

Expected:

- `Results: ... 0 failed`

**Step 2: 记录本次任务经验**

写入 Serena memory，记录：

- remote 子系统已统一公共逻辑
- `remote set` 默认修改 `origin`
- `remote set` 不做 URL 格式限制

**Step 3: 整理输出**

- 概述功能变更
- 附上关键文件路径
- 附上验证结果
