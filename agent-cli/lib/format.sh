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

# 构建胶囊进度条：两端 Nerd Font 半圆收口，百分比居中显示在条内
# 已用部分铺亮色底、剩余部分铺暗灰底，数字统一白色加粗，进度经过数字时只换底色不遮挡
# 条内空白用盲文空白 U+2800：app 会按普通空白切词重拼，会打乱位置
# 用法: build_progress_bar <pct> <fill_color>（fill_color 形如 \033[0;32m）
build_progress_bar() {
    local pct=$1
    local fill=$2
    local width=14
    local fill_bg="${fill#*0;3}"
    fill_bg="4${fill_bg%m}"          # \033[0;32m -> 42
    local track_bg="48;5;238"
    # 注意：app 的 ANSI 解析器吃不下参数很多的合并 SGR（会把尾巴当文字打出来），每个属性单独一条转义
    local filled=$((pct * width / 100))
    [ "$filled" -gt "$width" ] && filled=$width
    # 百分比非零时至少显示 1 格，避免进度条全空与数字不一致
    if [ "$pct" -gt 0 ] && [ "$filled" -eq 0 ]; then
        filled=1
    fi

    # 标签 "context⠀42%"：中间用盲文空白，按字符数组逐格放，避免 bash 子串在非 UTF-8 locale 下切坏多字节字符
    local i
    local label="${pct}%"
    local -a chars=(c o n t e x t "\xE2\xA0\x80")
    for ((i=0; i<${#label}; i++)); do chars+=("${label:i:1}"); done
    local label_len=${#chars[@]}
    local start=$(( (width - label_len) / 2 ))
    local bar="" bg ch prev_bg=""
    for ((i=0; i<width; i++)); do
        bg=$track_bg
        [ "$i" -lt "$filled" ] && bg=$fill_bg
        ch="\xE2\xA0\x80"
        if [ "$i" -ge "$start" ] && [ "$i" -lt $((start + label_len)) ]; then
            ch="${chars[i - start]}"
        fi
        if [ "$bg" != "$prev_bg" ]; then
            bar="${bar}\033[0m\033[${bg}m\033[1m\033[38;2;255;255;255m"
            prev_bg=$bg
        fi
        bar="${bar}${ch}"
    done

    # 圆角颜色跟随相邻格的底色（前景色画，不带背景，避免外溢）
    local left_cap="\033[0;38;5;238m" right_cap="\033[0;38;5;238m"
    [ "$filled" -gt 0 ] && left_cap="\033[0;${fill_bg/4/3}m"
    [ "$filled" -eq "$width" ] && right_cap="\033[0;${fill_bg/4/3}m"
    echo "${left_cap}\xEE\x82\xB6${bar}${right_cap}\xEE\x82\xB4\033[0m"
}
