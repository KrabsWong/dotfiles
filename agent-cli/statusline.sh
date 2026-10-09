#!/usr/bin/env bash
# statusline.sh — CodeBuddy 状态栏主入口
# 从 stdin 读取 JSON，输出两行（简化模式）或三行（完整模式）彩色状态信息
# 详见 README.md

# 工具展示默认简化；通过启动参数切换为完整明细。
tools_mode=simple
for arg in "$@"; do
    case "$arg" in
        --tools=simple) tools_mode=simple ;;
        --tools=full) tools_mode=full ;;
        *) printf '未知参数：%s（支持 --tools=simple 或 --tools=full）\n' "$arg" >&2; exit 2 ;;
    esac
done

# 获取脚本真实路径（解析符号链接）
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# 格式化工具函数（需最先加载，其他模块依赖）
source "$SCRIPT_DIR/lib/format.sh"

# 解析 stdin JSON（会读取 stdin，必须在此处调用）
source "$SCRIPT_DIR/lib/parse_input.sh"

# 解析 transcript 文件（依赖 parse_input.sh 设置的变量）
source "$SCRIPT_DIR/lib/parse_transcript.sh"

# 检测 git 状态
source "$SCRIPT_DIR/lib/git_info.sh"

# 渲染并输出状态栏
source "$SCRIPT_DIR/lib/render.sh"
