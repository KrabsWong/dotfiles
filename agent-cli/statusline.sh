#!/usr/bin/env bash
# CodeBuddy / Claude Code 状态栏：加载函数后，按顺序采集、准备并渲染。

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/format.sh"
source "$SCRIPT_DIR/lib/parse_input.sh"
source "$SCRIPT_DIR/lib/parse_transcript.sh"
source "$SCRIPT_DIR/lib/git_info.sh"
source "$SCRIPT_DIR/lib/render.sh"

main() {
    # Bash 动态作用域：各阶段共享这些结果变量，模块内部的中间值使用 local。
    local tools_mode current_dir model_display model_id transcript_path display_identifier
    local context_used_pct context_input_tokens context_output_tokens
    local cache_read_tokens cache_creation_tokens total_duration_ms
    local input_tokens output_tokens tool_calls runtime workbuddy_usage tool_names cache_hit_pct
    local branch git_is_dirty arg

    # 工具展示默认简化；通过启动参数切换为完整明细。
    tools_mode=simple
    for arg in "$@"; do
        case "$arg" in
            --tools=simple) tools_mode=simple ;;
            --tools=full) tools_mode=full ;;
            *) printf '未知参数：%s（支持 --tools=simple 或 --tools=full）\n' "$arg" >&2; exit 2 ;;
        esac
    done

    parse_input
    parse_transcript "$SCRIPT_DIR/lib/transcript.jq"
    prepare_usage
    collect_git_info
    render_statusline
}

main "$@"
