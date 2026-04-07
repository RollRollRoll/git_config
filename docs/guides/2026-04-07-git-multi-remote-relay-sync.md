# Git 多远程中转同步操作手册

## 目标

在“外网服务器不能直接访问公司 Git 服务器”的前提下，建立一套稳定的代码同步链路：

```text
公司仓库(corp) <-> 本地工作仓库 <-> 外网裸仓库(relay) <-> 外网工作区
```

该方案用于实现以下目标：

- 本地从公司仓库拉取代码
- 本地将代码同步到外网服务器上的裸仓库
- 外网服务器从裸仓库检出工作区并编辑代码
- 服务器上的提交先推回裸仓库
- 本地再从裸仓库拉回改动并推回公司仓库

## 角色定义

统一使用以下远程命名：

### 本地仓库

- `corp`：公司 Git 仓库
- `relay`：外网服务器上的裸仓库

### 外网服务器工作区

- `origin`：本机裸仓库

## 路径约定

请按实际环境替换以下占位符：

- `<公司仓库URL>`：公司 Git 仓库地址
- `<server-user>`：外网服务器用户名
- `<server-host>`：外网服务器地址
- `<project-name>`：项目名
- `<default-branch>`：默认分支名，例如 `main` 或 `master`

推荐目录结构：

```text
本地：
~/Project/<project-name>

外网服务器：
/home/<server-user>/relay/
├── repos/
│   └── <project-name>.git
└── worktrees/
    └── <project-name>
```

## 约束原则

- 本地是唯一能同时访问 `corp` 和 `relay` 的节点
- 外网服务器上禁止配置公司仓库 remote
- 外网服务器只和裸仓库通信
- 推回公司仓库的动作只能在本地执行
- 外网服务器上的开发优先使用功能分支，不直接在主分支长期开发

## 一次性初始化

### 1. 外网服务器创建裸仓库

登录外网服务器：

```bash
ssh <server-user>@<server-host>
```

创建目录并初始化裸仓库：

```bash
mkdir -p "/home/<server-user>/relay/repos"
mkdir -p "/home/<server-user>/relay/worktrees"

git init --bare "/home/<server-user>/relay/repos/<project-name>.git"
git --git-dir="/home/<server-user>/relay/repos/<project-name>.git" config receive.denyNonFastForwards true
git --git-dir="/home/<server-user>/relay/repos/<project-name>.git" config core.logAllRefUpdates true
chmod -R 700 "/home/<server-user>/relay"
```

设置裸仓库默认分支：

```bash
git --git-dir="/home/<server-user>/relay/repos/<project-name>.git" symbolic-ref HEAD "refs/heads/<default-branch>"
```

### 2. 本地克隆公司代码

如果本地还没有仓库：

```bash
git clone "<公司仓库URL>" "<project-name>"
cd "<project-name>"
git remote rename origin corp
```

如果本地已经有仓库，只需改名：

```bash
git remote rename origin corp
```

检查远程：

```bash
git remote -v
```

预期结果：

```text
corp    <公司仓库URL> (fetch)
corp    <公司仓库URL> (push)
```

### 3. 本地添加中转远程 `relay`

```bash
git remote add relay "<server-user>@<server-host>:/home/<server-user>/relay/repos/<project-name>.git"
git remote -v
```
或者
```bash
git remote add relay "ssh://<server-user>@<server-host>:<port>/home/<server-user>/relay/repos/<project-name>.git“
git remote -v
```

预期结果应包含：

```text
corp     ...
relay    <server-user>@<server-host>:/home/<server-user>/relay/repos/<project-name>.git
```

### 4. 首次将公司代码推送到 `relay`

```bash
git fetch corp --prune
git switch <default-branch>
git pull --ff-only corp <default-branch>
git push -u relay <default-branch>
git push relay --tags
```

如需同步更多分支：

```bash
git push relay "refs/remotes/corp/*:refs/heads/*"
```

### 5. 外网服务器检出工作区

在外网服务器执行：

```bash
git clone "/home/<server-user>/relay/repos/<project-name>.git" "/home/<server-user>/relay/worktrees/<project-name>"
cd "/home/<server-user>/relay/worktrees/<project-name>"
git remote -v
```

预期结果：

```text
origin  /home/<server-user>/relay/repos/<project-name>.git (fetch)
origin  /home/<server-user>/relay/repos/<project-name>.git (push)
```

注意：

- 不要在服务器工作区添加 `corp`
- 不要在服务器保存公司 Git 凭证

## 日常同步流程

### 1. 公司代码同步到外网服务器

本地执行：

```bash
cd "~/Project/<project-name>"
git fetch corp --prune
git switch <default-branch>
git pull --ff-only corp <default-branch>
git push relay <default-branch>
git push relay --tags
```

外网服务器执行：

```bash
cd "/home/<server-user>/relay/worktrees/<project-name>"
git switch <default-branch>
git pull --ff-only origin <default-branch>
```

### 2. 在外网服务器上开发功能分支

创建功能分支：

```bash
cd "/home/<server-user>/relay/worktrees/<project-name>"
git switch <default-branch>
git pull --ff-only origin <default-branch>
git switch -c "feature/<topic>"
```

提交并推回裸仓库：

```bash
git add .
git commit -m "feat: <topic>"
git push -u origin "feature/<topic>"
```

后续继续开发：

```bash
git switch "feature/<topic>"
git add .
git commit -m "feat: update <topic>"
git push
```

### 3. 本地拉回服务器功能分支

首次拉取：

```bash
cd "~/Project/<project-name>"
git fetch relay --prune
git switch -c "feature/<topic>" --track "relay/feature/<topic>"
```

后续更新：

```bash
git fetch relay --prune
git switch "feature/<topic>"
git pull --ff-only relay "feature/<topic>"
```

### 4. 本地合并并推回公司仓库

先更新本地主分支：

```bash
git fetch corp --prune
git switch <default-branch>
git pull --ff-only corp <default-branch>
```

合并服务器功能分支：

```bash
git merge --no-ff "feature/<topic>"
```

验证通过后推回公司仓库：

```bash
git push corp <default-branch>
```

再同步回外网中转仓库：

```bash
git push relay <default-branch>
```

最后在外网服务器更新工作区主分支：

```bash
cd "/home/<server-user>/relay/worktrees/<project-name>"
git switch <default-branch>
git pull --ff-only origin <default-branch>
```

### 5. 功能完成后的清理

本地删除分支：

```bash
git branch -d "feature/<topic>"
git push relay --delete "feature/<topic>"
```

外网服务器删除分支：

```bash
cd "/home/<server-user>/relay/worktrees/<project-name>"
git switch <default-branch>
git branch -d "feature/<topic>"
git fetch --prune
```

## 最小闭环流程

如果只看核心链路，最小流程如下。

### 1. 本地从公司同步到外网裸仓库

```bash
git fetch corp --prune
git switch <default-branch>
git pull --ff-only corp <default-branch>
git push relay <default-branch>
```

### 2. 外网服务器拉取最新代码

```bash
git switch <default-branch>
git pull --ff-only origin <default-branch>
```

### 3. 外网服务器提交并推回裸仓库

```bash
git add .
git commit -m "feat: server update"
git push origin HEAD
```

### 4. 本地拉回并推回公司仓库

如果服务器上使用的是功能分支：

```bash
git fetch relay --prune
git switch -c "feature/<topic>" --track "relay/feature/<topic>"
git switch <default-branch>
git pull --ff-only corp <default-branch>
git merge --no-ff "feature/<topic>"
git push corp <default-branch>
git push relay <default-branch>
```

## 冲突处理规范

- 冲突优先在本地处理，不在外网服务器处理主分支冲突
- 外网服务器不要对公共分支执行 `git push --force`
- 外网服务器不要直接改写 `origin/<default-branch>` 历史
- 公司仓库只接受本地推送

如果服务器功能分支落后于公司主分支，建议在本地处理：

```bash
git fetch corp --prune
git switch <default-branch>
git pull --ff-only corp <default-branch>
git switch "feature/<topic>"
git rebase <default-branch>
```

如不希望改写历史，也可改为：

```bash
git switch "feature/<topic>"
git merge <default-branch>
```

## 安全建议

- 外网服务器单独使用一个 Linux 用户，例如 `gitrelay`
- 裸仓库和工作区目录权限设置为 `700`
- 本地到服务器使用独立 SSH 密钥
- 公司 Git 的访问凭证只保留在本地
- 外网服务器不配置 `corp`
- 同步主分支优先使用 `--ff-only`

## 常用检查命令

本地查看远程：

```bash
git remote -v
```

本地查看分支跟踪关系：

```bash
git branch -vv
```

本地查看远程分支：

```bash
git branch -r
```

外网服务器查看当前工作区状态：

```bash
git status
git branch -vv
git remote -v
```

查看提交流向：

```bash
git log --oneline --graph --decorate --all -20
```

## 常见错误与处理

### 1. 服务器误配置了公司远程

现象：

- 外网服务器上 `git remote -v` 出现公司仓库地址

处理：

```bash
git remote remove <remote-name>
```

要求：

- 外网服务器只允许保留 `origin -> 本机裸仓库`

### 2. 本地推送 `relay` 失败

可能原因：

- SSH 未配置
- 裸仓库路径错误
- 服务器目录权限不足

检查：

```bash
ssh <server-user>@<server-host>
ls -ld "/home/<server-user>/relay"
ls -ld "/home/<server-user>/relay/repos/<project-name>.git"
```

### 3. 服务器工作区拉不到默认分支

可能原因：

- 裸仓库 `HEAD` 未指向默认分支

修复：

```bash
git --git-dir="/home/<server-user>/relay/repos/<project-name>.git" symbolic-ref HEAD "refs/heads/<default-branch>"
```

### 4. 本地从 `relay` 拉分支时报不存在

先检查服务器是否已经推送：

```bash
git fetch relay --prune
git branch -r | grep "relay/"
```

若没有该分支，说明服务器还未成功 `push`。

## 推荐工作习惯

每次开始远程开发前：

```bash
# 本地
git fetch corp --prune
git switch <default-branch>
git pull --ff-only corp <default-branch>
git push relay <default-branch>

# 服务器
git switch <default-branch>
git pull --ff-only origin <default-branch>
git switch -c "feature/<topic>"
```

每次远程开发结束后：

```bash
# 服务器
git add .
git commit -m "feat: <topic>"
git push -u origin "feature/<topic>"

# 本地
git fetch relay --prune
git switch -c "feature/<topic>" --track "relay/feature/<topic>"   # 首次需要
git switch <default-branch>
git pull --ff-only corp <default-branch>
git merge --no-ff "feature/<topic>"
git push corp <default-branch>
git push relay <default-branch>
```

## 结论

该方案的本质是：

- 本地负责连接公司仓库
- 外网服务器负责远程开发
- 裸仓库负责中转
- 公司代码永远不直接暴露给外网服务器的远程配置
- 所有正式回流公司仓库的操作都由本地完成

这是一套风险可控、职责清晰、适合长期使用的 Git 多远程同步方案。
