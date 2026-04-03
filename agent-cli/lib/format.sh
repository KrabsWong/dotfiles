#!/usr/bin/env bash
# lib/format.sh — 纯格式化工具函数，无副作用

# 将秒数格式化为人类可读时间
# 用法: format_duration <seconds>
format_duration() {
    local seconds=$1
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m$((seconds % 60))s"
    else
        echo "$((seconds / 3600))h$((seconds / 60 % 60))m"
    fi
}

# 将大数字格式化为带后缀的短形式（K/M/B），使用纯 bash
# 用法: format_number <number>
format_number() {
    local number=${1:-0}

    [[ ! "$number" =~ ^[0-9]+$ ]] && { echo "0"; return; }

    if [ "$number" -ge 1000000000 ]; then
        local int_part=$((number / 1000000000))
        local dec_part=$(( (number % 1000000000) / 10000000 ))
        printf "%d.%02dB" "$int_part" "$dec_part"
    elif [ "$number" -ge 1000000 ]; then
        local int_part=$((number / 1000000))
        local dec_part=$(( (number % 1000000) / 10000 ))
        printf "%d.%02dM" "$int_part" "$dec_part"
    elif [ "$number" -ge 1000 ]; then
        local int_part=$((number / 1000))
        local dec_part=$(( (number % 1000) / 10 ))
        printf "%d.%02dK" "$int_part" "$dec_part"
    else
        printf "%d" "$number"
    fi
}

# 根据上下文使用百分比返回 ANSI 颜色码
# 用法: get_context_color <pct>
get_context_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then
        echo "\033[0;31m"  # 红色 — 临界
    elif [ "$pct" -ge 75 ]; then
        echo "\033[0;33m"  # 黄色 — 警告
    else
        echo "\033[0;32m"  # 绿色 — 正常
    fi
}

# 构建 8 格 Unicode 进度条
# 用法: build_progress_bar <pct>
build_progress_bar() {
    local pct=$1
    local width=8
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar=""

    for ((i=0; i<filled; i++)); do
        bar="${bar}█"
    done
    for ((i=0; i<empty; i++)); do
        bar="${bar}░"
    done

    echo "${bar} "
}
