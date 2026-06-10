# wt.sh — Git Worktree 便捷管理工具

`wt.sh` 是一个命令行工具，用于简化 Git Worktree 的创建、查看、删除、锁定/解锁、移动和清理等操作。

## 安装

```bash
# 下载脚本
curl -O https://your-host/wt.sh

# 赋予执行权限
chmod +x wt.sh

# 推荐：添加到 PATH（如 ~/bin 或 /usr/local/bin）
mv wt.sh /usr/local/bin/wt
```

## 使用方式

```bash
wt.sh <命令> [选项] [参数]
```

`create`/`add` 为默认命令，可直接传路径。

## 命令一览

| 命令 | 说明 |
|------|------|
| `create` / `add` | 创建新的 Git Worktree（默认命令） |
| `ls` / `list` | 列出所有 worktree |
| `rm` / `remove` | 删除指定 worktree |
| `lock` | 锁定 worktree |
| `unlock` | 解锁 worktree |
| `mv` / `move` | 移动 worktree 到新路径 |
| `prune` | 清理已失效的 worktree |
| `help` | 显示帮助信息 |

## 示例

### 创建 Worktree

```bash
# 基于当前 HEAD 创建新分支并关联
wt.sh ../feature/new-feature

# 指定分支名
wt.sh -b hotfix ../hotfix/issue-123

# 强制创建分支（覆盖已有分支）
wt.sh -B ../feature/reset

# 分离头指针模式
wt.sh --detach ../test-commit

# 基于指定标签创建（分离头指针）
wt.sh --commit v1.0.0 ../rel/v1

# 基于已有分支创建（不创建新分支）
wt.sh --from existing-branch ../work

# 基于仓库主分支创建
wt.sh --main ../fix/main-fix
```

### 查看 Worktree

```bash
wt.sh ls
```

输出格式：编号、路径、分支、状态、最新提交。

### 删除 Worktree

```bash
# 指定路径删除
wt.sh rm ../feature/new-feature

# 交互式选择删除
wt.sh rm -i
```

删除时自动检查：
- 不可删除当前所在 worktree
- 有未提交更改时提示确认
- 删除后询问是否清理孤立分支

### 锁定 / 解锁

```bash
# 锁定 worktree
wt.sh lock ../feature/new-feature

# 锁定并添加原因
wt.sh lock -m "正在测试" ../feat/test

# 解锁
wt.sh unlock ../feature/new-feature
```

### 移动 Worktree

```bash
wt.sh mv ../old/path ../new/path
```

### 清理

```bash
wt.sh prune
```

## 特点

- **自动分支名派生**：创建时不指定分支名时，自动取路径的最后一级目录名作为分支名
- **智能分支检测**：创建时若分支已存在则直接关联，不存在则自动创建新分支
- **主分支检测**：支持 `main` / `master` 自动识别
- **交互式删除**：`rm -i` 提供交互式选择界面
- **安全删除**：删除前检查未提交更改，阻止删除当前 worktree
- **分支清理**：删除 worktree 后询问是否删除对应的孤立分支
- **彩色输出**：状态信息使用颜色区分，清晰直观
