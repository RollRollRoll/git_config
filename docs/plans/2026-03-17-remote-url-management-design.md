# Remote URL 管理重构设计

## 目标

为 `git-profile` 增加通用的 remote URL 修改能力：

- 支持 `git-profile remote set <url>`，默认修改 `origin`
- 支持 `git-profile remote set <remote-name> <url>`，修改指定 remote

同时重构现有 `remote` 子系统，统一 remote 枚举、仓库校验与目标 remote 校验逻辑，降低后续扩展成本。

## 现状

当前脚本已经支持：

- `git-profile remote show`
- `git-profile remote set-ssh`
- `git-profile remote set-https`

但三个命令各自解析 `git remote -v` 输出，公共逻辑分散，新增通用 `set` 命令后如果继续沿用现状，会形成第四套并行逻辑。

## 设计

### 命令结构

- `git-profile remote show`
- `git-profile remote set [remote-name] <url>`
- `git-profile remote set-ssh [remote-name]`
- `git-profile remote set-https [remote-name]`

其中：

- `remote set` 省略 `remote-name` 时默认修改 `origin`
- `set-ssh` / `set-https` 省略 `remote-name` 时仍保持批量转换语义

### 内部职责拆分

新增并统一以下辅助函数：

- `require_git_repo`
  - 校验当前目录是否位于 Git 仓库内
- `remote_exists <name>`
  - 校验指定 remote 是否存在
- `list_fetch_remotes`
  - 统一枚举 fetch 方向的 remote，输出 `remote_name<TAB>remote_url`

基于这些辅助函数，调整子命令职责：

- `cmd_remote_show`
  - 只负责展示
- `cmd_remote_set`
  - 只负责参数解析、默认值处理、目标 remote 校验与 `git remote set-url`
- `cmd_remote_set_ssh`
  - 只保留 profile 解析、协议转换、确认与执行逻辑
- `cmd_remote_set_https`
  - 只保留 host 解析、协议转换、确认与执行逻辑

### 参数语义

- `git-profile remote set <url>`
  - 修改 `origin`
- `git-profile remote set <remote-name> <url>`
  - 修改指定 remote
- `git-profile remote set-ssh`
  - 批量转换所有可转换的 HTTPS remote
- `git-profile remote set-ssh <remote-name>`
  - 只转换指定 remote
- `git-profile remote set-https`
  - 批量转换所有可转换的 SSH remote
- `git-profile remote set-https <remote-name>`
  - 只转换指定 remote

### 错误处理

- 非 Git 仓库：统一报错并退出
- `remote set` 传参不足：输出 `git-profile remote set [remote-name] <url>`
- 指定 remote 不存在：统一报错 `git-profile: remote '<name>' not found.`
- `remote set` 不限制 URL 格式，允许任意字符串直接写入
- `ssh://` 仍保持“跳过并提示 unsupported”，本次不扩大处理范围

### 交互菜单

remote 菜单新增“设置远程 URL”入口：

1. 输入 remote 名称，回车默认 `origin`
2. 输入新 URL
3. 调用 `cmd_remote_set`

### 测试策略

按 TDD 增加以下覆盖：

- `remote set` 默认修改 `origin`
- `remote set` 修改指定 remote
- `remote set` 指定不存在的 remote 时失败
- `remote set` 缺少 URL 时失败
- `remote set-ssh` 指定单个 remote
- `remote set-https` 指定单个 remote

## 非目标

- 不新增 remote 的添加、删除、重命名功能
- 不处理 `ssh://` 与其他非常见协议的自动转换
- 不对 `remote set` 的 URL 内容做协议合法性校验

## 风险与控制

- 风险：重构 `remote` 子系统可能影响现有转换命令
- 控制：
  - 先补失败测试
  - 仅抽取公共逻辑，不改变已确认的批量转换语义
  - 最终运行完整测试脚本验证回归
