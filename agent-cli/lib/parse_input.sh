#!/usr/bin/env bash
# lib/parse_input.sh — 从 stdin 解析 JSON 输入，设置所有输入变量
# 依赖: format_duration（来自 lib/format.sh，需先 source）
# stdin 必须在 source 此文件之前保持可读

# 单次 jq 调用提取全部字段（Tab 分隔）
IFS=$'\t' read -r current_dir model_display model_id transcript_path \
    context_used_pct context_input_tokens context_output_tokens \
    cache_read_tokens cache_creation_tokens total_duration_ms < <(
    jq -r '[
        (.workspace.current_dir // "null"),
        (.model.display_name // "null"),
        (.model.id // "null"),
        (.transcript_path // "null"),
        ((.context_window.used_percentage // null) | tostring),
        ((.context_window.total_input_tokens // 0) | tostring),
        ((.context_window.total_output_tokens // 0) | tostring),
        ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring),
        ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring),
        ((.cost.total_duration_ms // 0) | tostring)
    ] | @tsv' 2>/dev/null
)

dir_name=$(basename "$current_dir" 2>/dev/null || echo "unknown")

# 构建 project/dir 双层路径标识
project_name=""
if [ -n "$current_dir" ] && [ "$current_dir" != "null" ] && [ "$current_dir" != "unknown" ]; then
    parent_dir=$(dirname "$current_dir")
    if [ "$parent_dir" != "/" ]; then
        project_name=$(basename "$parent_dir")
        if [ "$project_name" = "." ] || [ "$project_name" = ".." ]; then
            project_name=""
        fi
    fi
fi

display_identifier="$dir_name"
if [ -n "$project_name" ] && [ "$project_name" != "$dir_name" ]; then
    display_identifier="${project_name}/${dir_name}"
fi

# 初始化 runtime（优先使用 stdin 中的 total_duration_ms）
runtime="0s"
if [ "${total_duration_ms:-0}" -gt 0 ] 2>/dev/null; then
    runtime=$(format_duration $((total_duration_ms / 1000)))
fi

# 初始化 token 计数（transcript 解析后可能覆盖）
input_tokens=0
output_tokens=0
tool_calls=0
