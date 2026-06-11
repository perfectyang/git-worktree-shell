#!/bin/bash
# git-worktree-create - 便捷管理 Git Worktree

set -e

# ── 颜色 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()  { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
error() { printf "${RED}✗${NC} %s\n" "$*" >&2; }
header(){ printf "\n${BOLD}${BLUE}%s${NC}\n" "$*"; }

# ── 检查是否在 git 仓库 ──
require_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "当前目录不在 Git 仓库中"
        exit 1
    fi
}

# ── 解析路径（展开 ~ 和相对路径） ──
resolve_path() {
    local p="$1"
    local orig_p="$p"
    # 展开 ~
    p="${p/#\~/$HOME}"
    orig_p="$p"
    # 转成绝对路径（若不是绝对路径，则相对于当前目录）
    if [[ "$p" != /* ]]; then
        p="$(cd "$(pwd)" && cd "$p" 2>/dev/null && pwd)" || {
            # 如果路径还不存在，基于当前目录构造
            p="$(pwd)/$orig_p"
        }
    fi
    # 移除尾部 /
    p="${p%%/}"
    printf '%s' "$p"
}

# ── 获取 worktree 详细信息 ──
list_worktrees() {
    require_git_repo
    local current_repo
    current_repo="$(git rev-parse --show-toplevel)"

    header "Worktree 列表"
    printf "${BOLD}%-6s %-30s %-22s %-10s %s${NC}\n" "#" "路径" "分支" "状态" "最新提交"
    printf "%-6s %-30s %-22s %-10s %s\n" "------" "------------------------------" "----------------------" "----------" "----------------------------------------"

    local idx=0
    while IFS= read -r line; do
        if [[ "$line" == worktree\ * ]]; then
            local wtpath="${line#worktree }"
            local wtpath_short=""
            if [[ "$wtpath" == "$current_repo" ]]; then
                wtpath_short="$(basename "$wtpath") (当前)"
            else
                wtpath_short="$(basename "$wtpath")"
            fi

            # 读取下一行（branch 或 detached）
            IFS= read -r branch_line
            local branch_name=""
            local is_detached=false
            if [[ "$branch_line" == branch\ refs/heads/* ]]; then
                branch_name="${branch_line#branch refs/heads/}"
            elif [[ "$branch_line" == detached ]]; then
                branch_name="(detached)"
                is_detached=true
            fi

            # 读取 bare/子模块等标记
            IFS= read -r extra_line

            # 检查是否为当前 worktree
            local status=""
            if [[ "$wtpath" == "$current_repo" ]]; then
                status="${GREEN}active${NC}"
            elif $is_detached; then
                status="${YELLOW}detached${NC}"
            else
                status="active"
            fi

            # 获取最新提交
            local last_commit=""
            if [[ -d "$wtpath" ]]; then
                last_commit="$(cd "$wtpath" && git log --oneline -1 2>/dev/null || true)"
            else
                status="${RED}missing${NC}"
                last_commit="(路径不存在)"
            fi

            idx=$((idx + 1))
            printf "%-6s %-30s %-22s %-10s %s\n" "[$idx]" "${wtpath_short:0:29}" "${branch_name:0:21}" "$status" "${last_commit:0:39}"
        fi
    done < <(git worktree list --porcelain)
    echo ""
}

# ── 删除 worktree ──
remove_worktree() {
    local path="$1"
    path="$(resolve_path "$path")"

    if [[ ! -d "$path" ]]; then
        error "路径 $path 不存在"
        exit 1
    fi

    if ! git worktree list --porcelain | grep -q "^worktree $path"; then
        error "路径 $path 不是 Git worktree"
        exit 1
    fi

    local saved_pwd
    saved_pwd="$(pwd)"
    local branch
    branch=$(git worktree list --porcelain | grep -A1 "worktree $path" | grep "branch " | awk '{print $2}' | sed 's|refs/heads/||')
    local is_detached
    is_detached=$(git worktree list --porcelain | grep -A1 "worktree $path" | grep -c "detach " || true)

    if [[ "$(git rev-parse --show-toplevel)" == "$(cd "$path" && git rev-parse --show-toplevel)" ]]; then
        error "不能删除当前的 worktree ($(basename "$path"))"
        info "请切换到其他目录后再删除"
        exit 1
    fi

    # 检查是否有未提交的更改（子 shell 执行 cd，不影响当前目录）
    if ! (cd "$path" && git diff --quiet HEAD 2>/dev/null); then
        local answer
        read -p "$(printf "${YELLOW}⚠ Worktree 有未提交的更改，确定删除？(y/N): ${NC}")" -n 1 -r answer
        echo
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            info "取消删除"
            exit 0
        fi
    fi

    echo ""
    if [[ $is_detached -gt 0 ]]; then
        warn "删除 detached head worktree：$path"
    else
        warn "删除 worktree (${branch:-无分支})：$path"
    fi

    echo "执行: git worktree remove $path"
    if git worktree remove "$path"; then
        info "Worktree 删除成功：$(basename "$path")"
    else
        error "Worktree 删除失败，尝试强制删除..."
        echo "执行: git worktree remove --force $path"
        git worktree remove --force "$path"
        info "Worktree 强制删除成功：$(basename "$path")"
    fi

    if [[ $is_detached -eq 0 && -n "$branch" ]]; then
        local other_worktrees
        other_worktrees=$(git worktree list --porcelain | grep -A1 "branch refs/heads/$branch" | grep -c "worktree " || true)
        if [[ $other_worktrees -eq 0 ]]; then
            local answer
            read -p "$(printf "分支 ${CYAN}%s${NC} 未被其他 worktree 使用，是否删除分支？(y/N): " "$branch")" -n 1 -r answer
            echo
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                echo "执行: git branch -D $branch"
                git branch -D "$branch"
                info "分支删除成功：$branch"
            else
                info "分支保留：$branch"
            fi
        fi
    fi

    # 恢复原始工作目录
    cd "$saved_pwd" 2>/dev/null || cd / 2>/dev/null || true
}


# ── 交互式删除（从列表中选择） ──
interactive_remove() {
    require_git_repo

    local -a paths
    local -a branches
    local current_repo
    current_repo="$(git rev-parse --show-toplevel)"

    while IFS= read -r line; do
        if [[ "$line" == worktree\ * ]]; then
            local wtpath="${line#worktree }"
            if [[ "$wtpath" != "$current_repo" ]]; then
                paths+=("$wtpath")
                IFS= read -r branch_line
                if [[ "$branch_line" == branch\ refs/heads/* ]]; then
                    branches+=("${branch_line#branch refs/heads/}")
                else
                    branches+=("(detached)")
                fi
                IFS= read -r extra_line
            else
                IFS= read -r branch_line
                IFS= read -r extra_line
            fi
        fi
    done < <(git worktree list --porcelain)

    if [[ ${#paths[@]} -eq 0 ]]; then
        warn "没有可删除的 worktree（当前 worktree 除外）"
        exit 0
    fi

    local -a selected=()
    for ((i = 0; i < ${#paths[@]}; i++)); do
        selected+=("false")
    done

    local current=0
    local key
    local extra
    local scroll_offset=0
    local term_lines
    term_lines=$(tput lines)

    # 隐藏光标，设置退出时自动恢复
    tput civis
    trap 'tput cnorm 2>/dev/null || true' EXIT
    # 在标题前保存光标位置，用于每次重绘时恢复
    tput sc

    render_list() {
        local max_visible=$(( term_lines - 3 ))
        (( max_visible < 3 )) && max_visible=3

        # 调整滚动偏移，确保当前项可见
        if (( current < scroll_offset )); then
            scroll_offset=$current
        elif (( current >= scroll_offset + max_visible )); then
            scroll_offset=$(( current - max_visible + 1 ))
        fi

        tput rc
        # 清空从光标位置到屏幕底部，避免旧内容残留
        printf "\033[J"

        # 重新打印标题，固定在交互区域顶部
        printf "\n${BOLD}${BLUE}%s${NC}\n" "选择要删除的 worktree（↑↓ 移动，空格选择/取消，回车确认）"

        local end_idx=$(( scroll_offset + max_visible ))
        (( end_idx > ${#paths[@]} )) && end_idx=${#paths[@]}

        for (( i = scroll_offset; i < end_idx; i++ )); do
            local mark=" "
            [[ "${selected[$i]}" == "true" ]] && mark="${GREEN}✓${NC}"
            if [[ "$i" -eq "$current" ]]; then
                printf "${BOLD}${CYAN}>${NC} [${mark}] %-30s [%s]\033[K\n" "$(basename "${paths[$i]}")" "${branches[$i]}"
            else
                printf "  [${mark}] %-30s [%s]\033[K\n" "$(basename "${paths[$i]}")" "${branches[$i]}"
            fi
        done

        printf "\033[K"
    }

    render_list

    while true; do
        IFS= read -rsn1 key
        if [[ "$key" == $'\e' ]]; then
            read -rsn2 extra 2>/dev/null || true
            key+="$extra"
        fi

        case "$key" in
            $'\e[A'|$'k')
                if [[ "$current" -gt 0 ]]; then
                    ((current--))
                    render_list
                fi
                ;;
            $'\e[B'|$'j')
                if [[ "$current" -lt $((${#paths[@]} - 1)) ]]; then
                    ((current++))
                    render_list
                fi
                ;;
            ' ')
                selected[$current]="$([[ "${selected[$current]}" == "true" ]] && echo "false" || echo "true")"
                render_list
                # 清理可能的多余空格（键盘重复）
                read -rsn1 -t 0.05 2>/dev/null || true
                ;;
            '')
                break
                ;;
            $'\e')
                echo ""
                tput cnorm
                info "取消操作"
                exit 0
                ;;
        esac
    done

    # 恢复光标
    tput cnorm
    echo ""

    # 收集被选中的索引（从大到小，先删后面的避免索引变化）
    local -a sorted_indices=()
    local idx
    for ((i = ${#paths[@]} - 1; i >= 0; i--)); do
        if [[ "${selected[$i]}" == "true" ]]; then
            sorted_indices+=("$((i + 1))")
        fi
    done

    if [[ ${#sorted_indices[@]} -eq 0 ]]; then
        warn "未选择任何 worktree"
        exit 0
    fi

    echo ""
    for idx in "${sorted_indices[@]}"; do
        local real_idx=$((idx - 1))
        remove_worktree "${paths[$real_idx]}"
        echo ""
    done
}

# ── 锁定 worktree ──
lock_worktree() {
    local path="$1"
    path="$(resolve_path "$path")"
    if [[ ! -d "$path" ]]; then
        error "路径 $path 不存在"
        exit 1
    fi
    local reason="${2:-}"
    if [[ -n "$reason" ]]; then
        echo "执行: git worktree lock --reason \"$reason\" $path"
        git worktree lock --reason "$reason" "$path"
    else
        echo "执行: git worktree lock $path"
        git worktree lock "$path"
    fi
    info "Worktree 已锁定：$(basename "$path")"
}

# ── 解锁 worktree ──
unlock_worktree() {
    local path="$1"
    path="$(resolve_path "$path")"
    if [[ ! -d "$path" ]]; then
        error "路径 $path 不存在"
        exit 1
    fi
    echo "执行: git worktree unlock $path"
    git worktree unlock "$path"
    info "Worktree 已解锁：$(basename "$path")"
}

# ── 移动 worktree ──
move_worktree() {
    local src="$1"
    local dst="$2"
    src="$(resolve_path "$src")"
    dst="$(resolve_path "$dst")"
    if [[ ! -d "$src" ]]; then
        error "源路径 $src 不存在"
        exit 1
    fi
    if [[ -e "$dst" ]]; then
        error "目标路径 $dst 已存在"
        exit 1
    fi
    echo "执行: git worktree move $src $dst"
    git worktree move "$src" "$dst"
    info "Worktree 已移动：$(basename "$src") → $(basename "$dst")"
}

# ── 仓库 main 分支名检测 ──
detect_main_branch() {
    for b in main master; do
        if git show-ref --verify --quiet "refs/heads/$b"; then
            printf '%s' "$b"
            return 0
        fi
    done
    # 如果都找不到，获取当前默认分支
    git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main"
}

# ── 显示帮助 ──
usage() {
    cat <<EOF
用法: wt.sh <命令> [选项] [参数]

命令:
  create      创建新的 Git Worktree（默认命令）
  add         同 create
  rm, remove  删除指定的 worktree
  ls, list    列出所有 worktree
  lock        锁定 worktree
  unlock      解锁 worktree
  mv, move    移动 worktree 到新路径
  prune       清理已失效的 worktree
  help        显示帮助信息

创建选项 (wt.sh create 或 wt.sh [路径]):
  -b <分支>       指定新分支名
  -B              强制创建分支（覆盖已有）
  --detach        分离头指针模式（不关联分支）
  --commit <提交>  基于指定提交/标签创建
  --from <分支>   基于已有分支创建 worktree（不创建新分支）
  --main          基于仓库主分支（main/master）创建

删除选项 (wt.sh rm):
  -i              交互式选择 worktree 删除

锁定选项 (wt.sh lock):
  -m <原因>       添加锁定原因

说明:
  create/add 为默认命令，可以直接传路径。
  如 wt.sh ../feature/my-feat 等价于 wt.sh create ../feature/my-feat。

示例:
  # ── 创建 ──
  wt.sh ../feature/new-feature           # 基于当前 HEAD 创建新分支 new-feature
  wt.sh -b hotfix ../hotfix/issue-123    # 指定分支名
  wt.sh -B ../feature/reset              # 强制创建分支（覆盖已有）
  wt.sh --detach ../test-commit          # 分离头指针模式
  wt.sh --commit v1.0.0 ../rel/v1        # 基于标签创建（分离头指针）
  wt.sh --commit main -b rel/v2 ../rel   # 基于 main 创建新分支
  wt.sh --from existing-branch ../work   # 基于已有分支创建（不创建新分支）
  wt.sh --main ../fix/main-fix           # 基于仓库主分支创建

  # ── 查看 ──
  wt.sh ls                               # 列出所有 worktree

  # ── 删除 ──
  wt.sh rm ../feature/new-feature        # 删除指定 worktree
  wt.sh rm -i                            # 交互式选择删除

  # ── 锁定 / 解锁 ──
  wt.sh lock ../feature/new-feature      # 锁定 worktree
  wt.sh lock -m "正在测试" ../feat/test  # 锁定并添加原因
  wt.sh unlock ../feature/new-feature    # 解锁

  # ── 移动 ──
  wt.sh mv ../old/path ../new/path       # 移动 worktree

  # ── 清理 ──
  wt.sh prune                            # 清理失效 worktree
EOF
}

# ════════════════════════════════════════════
#  主流程
# ════════════════════════════════════════════

# 变量初始化
command=""
branch=""
force_branch=""
detach=""
commit=""
from_branch=""
from_main=""
delete_path=""
interactive=""
lock_path=""
lock_reason=""
unlock_path=""
move_src=""
move_dst=""
prune=""
list=""
new_path=""
raw_path=""
abs_new_path=""
main_branch=""
base_ref=""
repo_name=""

# 如果第一个参数是已知命令，则提取
if [[ $# -gt 0 ]]; then
    case "$1" in
        create|add)
            command="$1"
            shift
            ;;
        rm|remove|delete)
            command="remove"
            shift
            ;;
        ls|list)
            command="list"
            shift
            ;;
        lock)
            command="lock"
            shift
            ;;
        unlock)
            command="unlock"
            shift
            ;;
        mv|move)
            command="move"
            shift
            ;;
        prune)
            command="prune"
            shift
            ;;
        help|--help|-h)
            usage
            exit 0
            ;;
    esac
fi

# 按命令解析参数
case "$command" in
    remove)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -i|--interactive)
                    interactive="yes"
                    shift
                    ;;
                -*)
                    error "未知选项 $1"
                    echo "用法: wt.sh rm [-i] [路径]" >&2
                    exit 1
                    ;;
                *)
                    if [[ -z "$delete_path" ]]; then
                        delete_path="$1"
                    else
                        error "多余参数 $1"
                        exit 1
                    fi
                    shift
                    ;;
            esac
        done
        ;;
    list)
        # list 不接受额外参数
        ;;
    lock)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -m|--reason)
                    lock_reason="$2"
                    shift 2
                    ;;
                -*)
                    error "未知选项 $1"
                    echo "用法: wt.sh lock [-m 原因] <路径>" >&2
                    exit 1
                    ;;
                *)
                    if [[ -z "$lock_path" ]]; then
                        lock_path="$1"
                    else
                        error "多余参数 $1"
                        exit 1
                    fi
                    shift
                    ;;
            esac
        done
        ;;
    unlock)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -*)
                    error "未知选项 $1"
                    exit 1
                    ;;
                *)
                    if [[ -z "$unlock_path" ]]; then
                        unlock_path="$1"
                    else
                        error "多余参数 $1"
                        exit 1
                    fi
                    shift
                    ;;
            esac
        done
        ;;
    move)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -*)
                    error "未知选项 $1"
                    exit 1
                    ;;
                *)
                    if [[ -z "$move_src" ]]; then
                        move_src="$1"
                    elif [[ -z "$move_dst" ]]; then
                        move_dst="$1"
                    else
                        error "多余参数 $1"
                        exit 1
                    fi
                    shift
                    ;;
            esac
        done
        ;;
    prune)
        # prune 不接受额外参数
        ;;
    "")
        # 无命令 → 创建模式，解析通用选项
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -b)
                    branch="$2"
                    shift 2
                    ;;
                -B)
                    force_branch="-B"
                    shift
                    ;;
                --detach)
                    detach="--detach"
                    shift
                    ;;
                --commit)
                    commit="$2"
                    shift 2
                    ;;
                --from)
                    from_branch="$2"
                    shift 2
                    ;;
                --main)
                    from_main="yes"
                    shift
                    ;;
                -d|--delete)
                    # 兼容旧用法
                    command="remove"
                    shift
                    ;;
                -l|--list)
                    command="list"
                    shift
                    ;;
                -L)
                    command="lock"
                    shift
                    ;;
                -U)
                    command="unlock"
                    shift
                    ;;
                -h|--help)
                    usage
                    exit 0
                    ;;
                -*)
                    error "未知选项 $1"
                    usage >&2
                    exit 1
                    ;;
                *)
                    if [[ -z "$new_path" ]]; then
                        new_path="$1"
                    else
                        error "多余参数 $1"
                        usage >&2
                        exit 1
                    fi
                    shift
                    ;;
            esac
        done
        ;;
esac

# ════════════════════════════════════════════
#  命令分发
# ════════════════════════════════════════════

case "$command" in
    remove)
        # ── 删除 worktree ──
        require_git_repo
        if [[ -n "$interactive" ]]; then
            interactive_remove
        elif [[ -n "$delete_path" ]]; then
            remove_worktree "$delete_path"
        else
            error "缺少 worktree 路径"
            echo "用法: wt.sh rm [-i] <路径>" >&2
            exit 1
        fi
        ;;

    list)
        # ── 列出 worktree ──
        list_worktrees
        ;;

    lock)
        # ── 锁定 worktree ──
        require_git_repo
        if [[ -z "$lock_path" ]]; then
            error "缺少 worktree 路径"
            echo "用法: wt.sh lock [-m 原因] <路径>" >&2
            exit 1
        fi
        lock_worktree "$lock_path" "$lock_reason"
        ;;

    unlock)
        # ── 解锁 worktree ──
        require_git_repo
        if [[ -z "$unlock_path" ]]; then
            error "缺少 worktree 路径"
            echo "用法: wt.sh unlock <路径>" >&2
            exit 1
        fi
        unlock_worktree "$unlock_path"
        ;;

    move)
        # ── 移动 worktree ──
        require_git_repo
        if [[ -z "$move_src" || -z "$move_dst" ]]; then
            error "需要源路径和目标路径"
            echo "用法: wt.sh mv <源路径> <目标路径>" >&2
            exit 1
        fi
        move_worktree "$move_src" "$move_dst"
        ;;

    prune)
        # ── 清理失效 worktree ──
        require_git_repo
        echo "执行: git worktree prune"
        git worktree prune
        info "已清理失效 worktree"
        ;;

    "")
        # ── 创建 worktree（默认命令） ──
        require_git_repo

        if [[ -z "$new_path" ]]; then
            error "缺少路径参数"
            usage >&2
            exit 1
        fi

        raw_path="$new_path"
        # 获取当前仓库名作为标识
        repo_name="$(basename "$(dirname "$(git rev-parse --git-common-dir)")")"
        # 扁平化：repo名-basename 作为 worktree 目录，避免嵌套子目录
        new_path="$(basename "$raw_path")"
        # 如果原始路径以 ../ 开头，放在同级目录下
        if [[ "$raw_path" == ../* ]]; then
            new_path="../${repo_name}-$new_path"
        fi
        new_path="$(resolve_path "$new_path")"

        # 检查路径是否已存在
        if [[ -e "$new_path" ]]; then
            error "路径已存在：$new_path"
            exit 1
        fi

        # 检查路径是否已被其他 worktree 使用
        abs_new_path="$(cd "$(dirname "$new_path")" 2>/dev/null && pwd)/$(basename "$new_path")"
        if git worktree list --porcelain | grep -q "^worktree $abs_new_path"; then
            error "路径已被其他 worktree 使用：$new_path"
            exit 1
        fi

        # 处理 --from（基于已有分支创建，不创建新分支）
        if [[ -n "$from_branch" ]]; then
            if ! git show-ref --verify --quiet "refs/heads/$from_branch"; then
                error "分支 $from_branch 不存在"
                exit 1
            fi
            branch="$from_branch"
            # 不添加 -b，直接基于已有分支创建
        fi

        # 处理 --main（保存主分支为起始点，但不覆盖分支名）
        if [[ -n "$from_main" ]]; then
            base_ref="$(detect_main_branch)"
            info "检测到主分支：$base_ref"
        fi

        # 自动派生分支名
        if [[ -z "$branch" && -z "$detach" && -z "$commit" && -z "$from_branch" ]]; then
            branch="$raw_path"
            while [[ "$branch" == ../* || "$branch" == ./* ]]; do
                branch="${branch#../}"
                branch="${branch#./}"
            done
            info "自动使用分支名: ${CYAN}$branch${NC}"
        fi

        # 指定了 --commit 但没指定分支 → 分离头指针
        if [[ -n "$commit" && -z "$branch" ]]; then
            detach="--detach"
        fi

        # 构建 git worktree add 命令
        cmd=(git worktree add)

        # 路径
        cmd+=("$new_path")

        # 处理起点
        start_point=""
        if [[ -n "$branch" ]]; then
            if [[ -n "$commit" ]]; then
                # 基于 commit 创建新分支
                cmd+=(-b "$branch")
                start_point="$commit"
            else
                # 检查分支是否存在
                if git show-ref --verify --quiet "refs/heads/$branch"; then
                    # 分支已存在，直接关联
                    if [[ -n "$force_branch" ]]; then
                        cmd+=(--force)
                    fi
                    start_point="$branch"
                else
                    # 分支不存在，创建新分支
                    cmd+=(-b "$branch")
                    if [[ -n "$commit" ]]; then
                        start_point="$commit"
                    elif [[ -n "$base_ref" ]]; then
                        start_point="$base_ref"
                    else
                        start_point="HEAD"
                    fi
                fi
            fi
        else
            if [[ -n "$commit" ]]; then
                start_point="$commit"
            elif [[ -n "$base_ref" ]]; then
                start_point="$base_ref"
            fi
        fi

        if [[ -n "$detach" ]]; then
            cmd+=(--detach)
        fi

        if [[ -n "$start_point" ]]; then
            cmd+=("$start_point")
        fi

        # 执行
        echo ""
        printf "${BOLD}执行:${NC} %s\n" "${cmd[*]}"
        "${cmd[@]}"
        echo ""
        info "Worktree 创建成功：${CYAN}$new_path${NC}"
        echo ""
        # 显示创建后的 worktree 简要信息
        printf "  路径:  %s\n" "$(cd "$new_path" && pwd)"
        printf "  分支:  %s\n" "$(cd "$new_path" && git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')"
        printf "  Commit: %s\n" "$(cd "$new_path" && git log --oneline -1 2>/dev/null)"
        ;;
esac
