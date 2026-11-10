#!/usr/bin/env bash
# collect_git_info: 读取 current_dir，设置 branch 和 git_is_dirty。

collect_git_info() {
    local git_work_dir dirty_status

    branch=""
    git_is_dirty=0

    # 确定工作目录
    git_work_dir="$current_dir"
    if [ "$current_dir" = "null" ] || [ "$current_dir" = "unknown" ] || [ ! -d "$current_dir" ]; then
        git_work_dir="$(pwd)"
    fi

    # 不在 git 仓库时直接返回
    git -C "$git_work_dir" rev-parse --git-dir > /dev/null 2>&1 || return 0

    branch=$(git -C "$git_work_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    [ -z "$branch" ] && return 0

    dirty_status=$(git -C "$git_work_dir" status --porcelain 2>/dev/null)
    [ -n "$dirty_status" ] && git_is_dirty=1

    return 0
}
