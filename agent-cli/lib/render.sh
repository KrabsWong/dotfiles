#!/usr/bin/env bash
# 展示层：读取已准备的数据，不修改 token、缓存或日志统计。
# 依赖 format.sh；输入为 parse_input / parse_transcript / prepare_usage / collect_git_info 的结果及 tools_mode。

format_tool_summary() {
    local tool_compact_str

    # --- 工具统计折叠（sort|uniq -c 预处理，awk 做分类，兼容 BSD awk）---
    if [ "$tools_mode" = "full" ] && [ "$tool_calls" -gt 0 ] && [ -n "$tool_names" ]; then
        # sort|uniq -c 得到 "  N name" 格式，按调用次数降序排列
        tool_compact_str=$(printf '%s\n' "$tool_names" | sort | uniq -c | sort -rn | awk -v times="×" '
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
                } else if (!has_multi) {
                    entry = "\\033[0;37m" name ":\\033[1;33m" c "\\033[0m"
                } else if (singles <= 1) {
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

        printf '%s' "$tool_compact_str"
    fi

    return 0
}

render_model_badge() {
    local model_short badge_bg badge_cap badge_fg badge_seed badge_emoji section_model
    local -a badge_emojis

    # --- 模型名（过长时使用 model_id）---
    model_short="$model_display"
    if [ "$model_short" = "null" ] || [ -z "$model_short" ]; then
        model_short="agent"
    elif [ "$model_display" != "$model_id" ] && [ "${#model_display}" -gt 15 ]; then
        model_short="$model_id"
    fi

    # --- 模型徽章配色 ---
    # 注意：app 给整行状态栏硬编码 dimColor（SGR 2），rex/libghostty 会把前景色与该格
    # 背景色做 50% 混合，文字色恒等于 (fg+bg)/2；流内 SGR 22 清不掉这层父级样式。
    # 因此白字在任何彩色底上都只能到"半白"，这是 app 层的限制，不是配色问题。
    case "${COLORTERM:-}" in
        truecolor|24bit)
            badge_bg="\\033[48;2;124;58;237m"   # #7c3aed
            badge_cap="\\033[38;2;124;58;237m"
            ;;
        *)
            badge_bg="\\033[48;5;99m"           # 256 色紫罗兰 #875fd7
            badge_cap="\\033[38;5;99m"
            ;;
    esac
    badge_fg="\\033[1m\\033[38;2;255;255;255m"  # E：真彩白 + 加粗

    # --- 徽章头像：按会话随机挑一个 emoji ---
    # 状态栏每次刷新都会重跑脚本，直接 $RANDOM 会不停跳；用 transcript_path 做种子，同一会话固定、新会话换一个
    badge_emojis=(🤡 🐱 🐶 🦊 🐼 🐸 🐵 🦄 🐙 🦖 👻 👽 🤖 🎃 🐧 🦉 🐳 🍄 🌵 🚀)
    badge_seed=$(printf '%s' "${transcript_path:-$PPID}" | cksum | cut -d' ' -f1)
    badge_emoji=${badge_emojis[$((badge_seed % ${#badge_emojis[@]}))]}

    # 模型名徽章：随机 emoji 头像和模型名都包在底色里，emoji 单独复位前景色
    # 第 0 列不能有背景色：终端会把首列背景延伸到窗口内边距，紫块看起来就会顶出去。
    # 所以首列用前景色画 Nerd Font 左圆角 U+E0B6，从第 1 列起才铺底色；结尾同理用右圆角 U+E0B4 收口。
    # 徽章内部用盲文空白 U+2800 当内边距：app 会按空白切词再用单空格重拼，普通空格位置不可控。
    section_model="\\033[0m${badge_cap}\\xEE\\x82\\xB6${badge_bg}\\033[39m${badge_emoji}${badge_fg}\\xE2\\xA0\\x80${model_short}\\033[0m${badge_cap}\\xEE\\x82\\xB4\\033[0m"
    printf '%s' "$section_model"
}

render_statusline() {
    local display_dir context_percentage cache_hit_str git_compact tool_stats
    local GRAY RESET SEP input_tokens_formatted output_tokens_formatted context_color context_bar
    local section_dir section_model section_context section_tokens section_time line2

    # --- 显示目录 ---
    display_dir="$display_identifier"
    if [ "$display_dir" = "null" ] || [ -z "$display_dir" ]; then
        display_dir="-"
    fi

    # --- 上下文百分比 ---
    context_percentage=0
    if [ -n "$context_used_pct" ] && [ "$context_used_pct" != "null" ]; then
        context_percentage=$(printf "%.0f" "$context_used_pct" 2>/dev/null || echo 0)
    fi

    cache_hit_str=""
    if [ -n "$cache_hit_pct" ]; then
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

    tool_stats=$(format_tool_summary)

    # --- ANSI 常量 ---
    GRAY="\\033[0;90m"
    RESET="\\033[0m"
    SEP="${GRAY}│${RESET}"

    # --- 格式化 token 数字 ---
    input_tokens_formatted=$(format_number "$input_tokens")
    output_tokens_formatted=$(format_number "$output_tokens")

    # --- 上下文颜色和进度条 ---
    context_color=$(get_context_color "$context_percentage")
    context_bar=$(build_progress_bar "$context_percentage" "$context_color")

    section_dir="\\033[0;36m${display_dir}${RESET}${git_compact}"
    section_model=$(render_model_badge)
    section_context="${context_bar}"
    section_tokens="\\033[0;90mIn:\\033[0;32m${input_tokens_formatted} \\033[0;90mOut:\\033[0;33m${output_tokens_formatted}${RESET}${cache_hit_str}"
    section_time="\\033[0;34m${runtime}${RESET}"

    line2="${section_model} ${SEP} ${section_context} ${SEP} ${section_tokens} ${SEP} ${section_time}"
    if [ "$tools_mode" = "simple" ]; then
        line2="${line2} ${SEP} ${GRAY}Tools:\\033[1;33m${tool_calls}${RESET}"
    fi
    printf "%b\n" "$section_dir" "$line2"

    # --- 第 3 行：工具统计（有工具调用时才显示）---
    if [ -n "$tool_stats" ]; then
        printf "%b\n" "🔧 ${tool_stats}"
    fi
}
