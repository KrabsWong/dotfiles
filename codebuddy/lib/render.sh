#!/usr/bin/env bash
# lib/render.sh — 构建并输出两行彩色状态栏
# 依赖变量（来自各 parse_*.sh / git_info.sh）:
#   display_identifier, model_display, model_id,
#   context_used_pct, context_input_tokens, context_output_tokens,
#   cache_read_tokens, input_tokens, output_tokens, tool_calls,
#   runtime, git_info, branch, git_is_dirty, tool_counts_file
# 依赖函数（来自 format.sh）:
#   format_number, get_context_color, build_progress_bar

# --- Token 回退：transcript 无数据时使用 stdin context_window 数据 ---
if [ "$input_tokens" -eq 0 ] && [ "${context_input_tokens:-0}" -gt 0 ] 2>/dev/null; then
    input_tokens=$context_input_tokens
fi
if [ "$output_tokens" -eq 0 ] && [ "${context_output_tokens:-0}" -gt 0 ] 2>/dev/null; then
    output_tokens=$context_output_tokens
fi

# --- 显示目录 ---
display_dir="$display_identifier"
if [ "$display_dir" = "null" ] || [ -z "$display_dir" ]; then
    display_dir="-"
fi

# --- 模型名（过长时使用 model_id）---
model_short="$model_display"
if [ "$model_short" = "null" ] || [ -z "$model_short" ]; then
    model_short="agent"
elif [ "$model_display" != "$model_id" ] && [ "${#model_display}" -gt 15 ]; then
    model_short="$model_id"
fi

# --- 上下文百分比 ---
context_percentage=0
if [ -n "$context_used_pct" ] && [ "$context_used_pct" != "null" ]; then
    context_percentage=$(printf "%.0f" "$context_used_pct" 2>/dev/null || echo 0)
fi

# --- Cache 命中率 ---
cache_hit_str=""
if [ "${cache_read_tokens:-0}" -gt 0 ] 2>/dev/null && [ "$input_tokens" -gt 0 ] 2>/dev/null; then
    cache_hit_pct=$((cache_read_tokens * 100 / input_tokens))
    cache_hit_str=" \\033[0;90mCache:\\033[0;36m${cache_hit_pct}%\\033[0m"
fi

# --- Git 显示 ---
git_compact=""
if [ -n "$branch" ]; then
    if [ "$git_is_dirty" -eq 1 ]; then
        git_compact=" \\033[0;33m(${branch}*)\\033[0m"
    else
        git_compact=" \\033[0;32m(${branch})\\033[0m"
    fi
fi

# --- 工具统计折叠（sort|uniq -c 预处理，awk 做分类，兼容 BSD awk）---
tool_stats=""
if [ "$tool_calls" -gt 0 ] && [ -s "$tool_counts_file" ]; then
    # sort|uniq -c 得到 "  N name" 格式，按调用次数降序排列
    tool_compact_str=$(sort "$tool_counts_file" | uniq -c | sort -rn | awk -v times="×" '
    # 第一遍：收集所有 count 和 name
    { gsub(/^ +/, ""); split($0, a, " "); c=a[1]; name=a[2]; counts[NR]=c; names[NR]=name; total++ }
    END {
        # 统计 has_multi 和 singles
        has_multi = 0
        singles = 0
        for (i = 1; i <= total; i++) {
            if (counts[i] > 1) has_multi = 1
            else singles++
        }

        result = ""
        others = 0
        for (i = 1; i <= total; i++) {
            c = counts[i]
            name = names[i]
            if (c > 1) {
                entry = "\\033[0;37m" name ":\\033[1;33m" c "\\033[0m"
            } else if (!has_multi || singles <= 1) {
                entry = "\\033[0;37m" name "\\033[0m"
            } else {
                others++
                continue
            }
            result = (result == "") ? entry : result " " entry
        }

        if (others > 0) {
            summary = "\\033[0;90m...+" others " others (" times "1)\\033[0m"
            result = (result == "") ? summary : result " " summary
        }

        if (result != "") print result
    }')

    [ -n "$tool_compact_str" ] && tool_stats="$tool_compact_str"
fi

# --- ANSI 常量 ---
GRAY="\\033[0;90m"
RESET="\\033[0m"
SEP="${GRAY}│${RESET}"

# --- 格式化 token 数字 ---
input_tokens_formatted=$(format_number "$input_tokens")
output_tokens_formatted=$(format_number "$output_tokens")

# --- 上下文颜色和进度条 ---
context_color=$(get_context_color "$context_percentage")
context_bar=$(build_progress_bar "$context_percentage")

# --- 组装第 1 行 ---
section_dir="\\033[0;36m${display_dir}${RESET}${git_compact}"
section_model="\\033[1;36m${model_short}${RESET}"
section_context="${context_color}${context_bar}${GRAY}${context_percentage}%${RESET}"
section_tokens="\\033[0;90mIn:\\033[0;32m${input_tokens_formatted} \\033[0;90mOut:\\033[0;33m${output_tokens_formatted}${RESET}${cache_hit_str}"
section_time="\\033[0;34m${runtime}${RESET}"

line1="${section_dir} ${SEP} ${section_model} ${SEP} ${section_context} ${SEP} ${section_tokens} ${SEP} ${section_time}"
printf "%b\n" "${line1}"

# --- 第 2 行：工具统计（有工具调用时才显示）---
if [ -n "$tool_stats" ]; then
    printf "%b\n" "🔧 ${tool_stats}"
fi
