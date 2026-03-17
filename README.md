# git-profile

在一台电脑上管理多个 Git 身份（SSH 密钥 + 用户名/邮箱）。

## 安装

```bash
./install.sh
```

默认安装到 `~/.local/bin/`。确保该路径在 `PATH` 中。

## 快速开始

```bash
# 添加身份
git-profile add

# 查看所有身份
git-profile list

# 在当前项目切换身份
git-profile use work

# 查看当前身份
git-profile current

# 撤销覆盖，恢复原始配置
git-profile use --clear

# 添加目录自动匹配规则
git-profile rule add

# 交互式菜单
git-profile
```

## 平台支持

- macOS、Linux
- Bash 3.2+
- 依赖：`git`、`ssh-keygen`、`ssh`

## 设计文档

详见 `docs/superpowers/specs/2026-03-17-git-profile-design.md`
