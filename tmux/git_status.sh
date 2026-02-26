#!/bin/bash

# 获取当前 pane 的路径
cd "$1" 2>/dev/null || exit

# 检查是否是 git 仓库
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # 获取分支名或 commit hash
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD)
    
    # 检查是否有未提交的更改 (可选，用 * 标记)
    dirty=""
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        dirty="*"
    fi
    
    # 输出格式:  master* (使用 git 分支图标)
    echo "#[fg=#c099ff] ${branch}${dirty} #[fg=#444444]|"
else
    echo ""
fi
