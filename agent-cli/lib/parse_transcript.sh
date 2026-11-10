#!/usr/bin/env bash
# parse_transcript <jq_program>: 读取 transcript_path、tools_mode 及输入阶段的默认值。
# 设置 input_tokens、output_tokens、cache_read_tokens、workbuddy_usage、tool_calls、runtime、tool_names。
# 日志发现和调用编排留在 Shell，聚合规则位于 transcript.jq。

parse_transcript() {
    local jq_program=$1 last_compact_ts subagents_dir agent_path jq_output
    local first_epoch last_epoch buddy_mode buddy_count buddy_cached total_duration
    local -a usage_paths

    workbuddy_usage=0
    tool_names=""

    # transcript 不存在时直接跳过
    if [ -z "$transcript_path" ] || [ "$transcript_path" = "null" ] || [ ! -f "$transcript_path" ]; then
        return 0
    fi

    # 第一步：找到最后一次 compact 的时间戳
    last_compact_ts=$(jq -r '[
        .[] | select(.type == "message" and .role == "user"
            and (.content[0].text | contains("Compact Instructions")))
        | .timestamp
    ] | max // empty' "$transcript_path" 2>/dev/null)

    # 子 agent 使用独立日志；仅扫描当前 session，包含嵌套的子 agent。
    usage_paths=("$transcript_path")
    subagents_dir="${transcript_path%.jsonl}/subagents"
    if [ -d "$subagents_dir" ]; then
        while IFS= read -r -d '' agent_path; do
            usage_paths+=("$agent_path")
        done < <(find "$subagents_dir" -type f -name 'agent-*.jsonl' -print0)
    fi

    # 第二步：逐行解析，忽略仍在写入的残缺行；主日志单独保留用于工具和时长统计。
    jq_output=$(jq -r -n -R --arg compact_ts "$last_compact_ts" --arg main_path "$transcript_path" -f "$jq_program" "${usage_paths[@]}" 2>/dev/null || printf '0\t0\t0\t0\t0\t0\t0\t-1\n')

    # 写入统计结果；若 transcript 不存在则保持输入阶段的初始值。
    read -r input_tokens output_tokens tool_calls first_epoch last_epoch buddy_mode buddy_count buddy_cached <<< "$jq_output"
    if [ "$buddy_mode" = "1" ]; then
        # 不把累计输入与 stdin 最近一次请求的缓存量混用。
        cache_read_tokens=-1
        if [ "$buddy_count" -gt 0 ]; then
            workbuddy_usage=1
            cache_read_tokens=$buddy_cached
        fi
    fi

    # 从 transcript 时间戳计算会话时长（优先于 stdin 的 total_duration_ms）
    if [ "${first_epoch:-0}" -gt 0 ] && [ "${last_epoch:-0}" -gt 0 ] 2>/dev/null; then
        total_duration=$((last_epoch - first_epoch))
        [ "$total_duration" -gt 0 ] && runtime=$(format_duration $total_duration)
    fi

    # 提取工具名列表（全局统计，不受 compact 影响）
    if [ "$tools_mode" = "full" ] && [ "$tool_calls" -gt 0 ]; then
        tool_names=$(jq -r '
          if .type == "function_call" then .name                          # CodeBuddy CLI
          elif .type == "tool_use" and .tool_name then .tool_name          # ClaudeCode 顶级记录
          elif .type == "assistant" and .message.content != null then      # CodeBuddy assistant content
            (.message.content | map(select(.type == "tool_use") | .name) | .[])
          else empty
          end // empty' "$transcript_path" 2>/dev/null)
    fi
}

# 在渲染前确定 token 回退和缓存比例，保持现有统计口径。
prepare_usage() {
    # --- Token 回退：transcript 无数据时使用 stdin context_window 数据 ---
    if [ "$workbuddy_usage" -eq 0 ] && [ "$input_tokens" -eq 0 ] && [ "${context_input_tokens:-0}" -gt 0 ] 2>/dev/null; then
        input_tokens=$context_input_tokens
    fi
    if [ "$workbuddy_usage" -eq 0 ] && [ "$output_tokens" -eq 0 ] && [ "${context_output_tokens:-0}" -gt 0 ] 2>/dev/null; then
        output_tokens=$context_output_tokens
    fi

    # --- Cache 命中率 ---
    cache_hit_pct=""
    if [ "${cache_read_tokens:-0}" -ge 0 ] && [ "$input_tokens" -gt 0 ] &&
       { [ "$cache_read_tokens" -gt 0 ] || [ "$workbuddy_usage" -eq 1 ]; }; then
        cache_hit_pct=$(LC_ALL=C awk -v cached="$cache_read_tokens" -v input="$input_tokens" 'BEGIN { printf "%.2f", cached * 100 / input }')
    fi
}
