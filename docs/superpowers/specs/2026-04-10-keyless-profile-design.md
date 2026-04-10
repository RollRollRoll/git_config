# 设计文档：支持不绑定密钥的 Profile

## 概述

扩展 git-profile，使 Profile 的 SSH 密钥字段变为可选。支持两类用户：

- **纯 HTTPS 用户**：只用 HTTPS 协议推拉代码，不需要 SSH 密钥
- **已有全局 SSH 配置的用户**：SSH 认证由 ssh-agent 或 `~/.ssh/config` 管理，只需 git-profile 控制 `user.name` / `user.email`

## 配置格式

`ssh_key` 字段变为可选，空值表示"无密钥绑定"：

```ini
[https-only]
name    = Chen Jinfan
email   = jinfan@company.com
host    = github.com
ssh_key =
```

- 老配置（有 `ssh_key` 值）完全向下兼容，无需迁移
- `host` 字段保留，供 `cmd_remote` 的 HTTPS ↔ SSH URL 转换使用

## 变更点

### 1. `cmd_add` 交互流程

在步骤 4（host）之后、步骤 5（密钥）之前，插入新问题：

```
需要绑定 SSH 密钥？[Y/n]
```

- 选 **Y**（默认）→ 保持原有流程（生成新密钥 或 指定现有密钥路径）
- 选 **N** → 跳过所有密钥步骤，以空字符串调用 `_add_profile`

### 2. `_add_profile` 核心逻辑

当 `key_path` 为空时，跳过 SSH alias 判断块（`host_has_other_profiles` 整体跳过）：

```bash
# 仅在有密钥时才检查是否需要 SSH alias
if [[ -n "$key_path" ]] && host_has_other_profiles "$host" "$name"; then
    # ... SSH alias 写入逻辑 ...
fi
```

### 3. `cmd_use` 应用逻辑

当 `p_key` 为空时，对 `core.sshCommand` 采用"保留不干预"策略：

```bash
if [[ -n "$p_key" ]]; then
    git config --local core.sshCommand "ssh -i \"${p_key}\" -o IdentitiesOnly=yes"
else
    # 无密钥 profile：若本地已有 sshCommand 则保留，否则不写
    # 什么也不做
    :
fi
```

- backup / restore 逻辑（`cmd_use_clear`）不变
- HTTPS 远程检测与转换提示不变

### 4. `write_gitconfig_fragment`（Rule 自动应用）

当 `key_path` 为空时，生成的 fragment 不含 `sshCommand` 行：

```bash
if [[ -n "$key_path" ]]; then
    # 写含 sshCommand 的 fragment
else
    # 只写 [gitProfile] 和 [user] 块
fi
```

Rule 通过 `includeIf` 加载此 fragment，无密钥时只覆盖 `user.name` / `user.email`，SSH 行为由用户全局配置决定。

### 5. 显示逻辑（无需改动）

`cmd_list`、`cmd_show`、`cmd_current` 中已有 `[[ -n "$p_key" ]]` 守卫，无密钥时自动不显示 `Key:` 行，无需修改。

## 测试覆盖

新增测试用例：

| 层级 | 用例 |
|------|------|
| `_add_profile` | 无密钥 profile 可写入配置，`ssh_key` 字段为空 |
| `_add_profile` | 无密钥 profile 不触发 SSH alias 写入 |
| `cmd_use` | 无密钥 + 本地无 `sshCommand` → 不写 `core.sshCommand` |
| `cmd_use` | 无密钥 + 本地已有 `sshCommand` → 保留原值不覆盖 |
| `cmd_use` | 有密钥 profile → 行为与现在一致（回归） |
| `write_gitconfig_fragment` | 无密钥时 fragment 不含 `sshCommand` 行 |
| `write_gitconfig_fragment` | 有密钥时 fragment 含 `sshCommand` 行（回归） |

## 不在本次范围内

- `cmd_edit` 中修改密钥绑定状态（后续可扩展）
- HTTPS 凭据管理（credential helper 等）
