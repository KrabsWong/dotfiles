#!/usr/bin/env bash
# tests/run_tests.sh — statusline.sh 边界场景测试
# 用法: bash tests/run_tests.sh

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FIXTURES="$SCRIPT_DIR/fixtures"
STATUSLINE="$ROOT_DIR/statusline.sh"

# ── 颜色 ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RESET='\033[0m'

pass=0; fail=0; skip=0

# ── 辅助函数 ──────────────────────────────────────────────────────────────────

# run_statusline <json_stdin> → stdout（strip ANSI）
run_statusline() {
    echo "$1" | /bin/bash "$STATUSLINE" 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g'
}

assert_contains() {
    local label="$1" output="$2" pattern="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo -e "  ${GREEN}PASS${RESET} $label"
        ((pass++))
    else
        echo -e "  ${RED}FAIL${RESET} $label"
        echo -e "       pattern : $(echo "$pattern" | cat -v)"
        echo -e "       output  : $(echo "$output" | head -3 | cat -v)"
        ((fail++))
    fi
}

assert_not_contains() {
    local label="$1" output="$2" pattern="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo -e "  ${RED}FAIL${RESET} $label  (should NOT contain '$pattern')"
        ((fail++))
    else
        echo -e "  ${GREEN}PASS${RESET} $label"
        ((pass++))
    fi
}

assert_line_count() {
    local label="$1" output="$2" expected="$3"
    local actual
    actual=$(echo "$output" | grep -c .)
    if [ "$actual" -eq "$expected" ]; then
        echo -e "  ${GREEN}PASS${RESET} $label (lines=$actual)"
        ((pass++))
    else
        echo -e "  ${RED}FAIL${RESET} $label (expected=$expected actual=$actual)"
        ((fail++))
    fi
}

# ── 基础 JSON 模板 ─────────────────────────────────────────────────────────────
make_json() {
    local dir="${1:-/tmp}" model_id="${2:-claude-sonnet-4-6}" \
          model_display="${3:-Claude Sonnet 4.6}" transcript="${4:-null}" \
          ctx_pct="${5:-42}" in_tok="${6:-50000}" out_tok="${7:-3000}" \
          cache_read="${8:-0}" duration_ms="${9:-120000}"
    cat <<EOF
{
  "workspace": {"current_dir": "$dir"},
  "model": {"display_name": "$model_display", "id": "$model_id"},
  "transcript_path": $( [ "$transcript" = "null" ] && echo "null" || echo "\"$transcript\"" ),
  "context_window": {
    "used_percentage": $ctx_pct,
    "total_input_tokens": $in_tok,
    "total_output_tokens": $out_tok,
    "current_usage": {"cache_read_input_tokens": $cache_read, "cache_creation_input_tokens": 0}
  },
  "cost": {"total_duration_ms": $duration_ms}
}
EOF
}

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 1. 基础输出结构 ══════════════════════════════════════════════════════"

json=$(make_json "/tmp/myproject")
out=$(run_statusline "$json")

assert_contains      "第 1 行包含目录名"        "$out" "myproject"
assert_contains      "第 1 行包含模型 ID"        "$out" "claude-sonnet-4-6"
assert_contains      "第 1 行包含 In: 标签"      "$out" "In:"
assert_contains      "第 1 行包含 Out: 标签"     "$out" "Out:"
assert_contains      "第 1 行包含进度条字符"     "$out" "█"
assert_contains      "第 1 行包含百分比"         "$out" "42%"
assert_line_count    "无工具调用时只输出 1 行"   "$out" 1

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 2. transcript=null（无会话文件）════════════════════════════════════"

json=$(make_json "/tmp/proj" "claude-sonnet-4-6" "Claude Sonnet 4.6" "null" 55 80000 5000 0 900000)
out=$(run_statusline "$json")

assert_contains   "回退到 stdin token：In 显示 80.00K"  "$out" "80.00K"
assert_contains   "回退到 stdin token：Out 显示 5.00K"  "$out" "5.00K"
assert_contains   "回退到 stdin 时长：15m0s"            "$out" "15m0s"
assert_line_count "无工具调用时只输出 1 行"              "$out" 1

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 3. transcript 存在 — 普通会话 ══════════════════════════════════════"

json=$(make_json "/tmp/proj" "claude-sonnet-4-6" "Claude Sonnet 4.6" \
      "$FIXTURES/transcript_normal.jsonl" 50 999999 999999 0 999999000)
out=$(run_statusline "$json")

assert_contains   "token 来自 transcript：In 2.00K"     "$out" "2.00K"
assert_contains   "token 来自 transcript：Out 400"       "$out" "400"
assert_contains   "时长来自 transcript：3m0s"            "$out" "3m0s"
assert_line_count "有工具调用时输出 2 行"                 "$out" 2
assert_contains   "工具行包含 Read:2"                    "$out" "Read:2"
# Bash/Edit 各调用 1 次，Read 调用 2 次 → 有 multi，有 2 个 singles → 折叠为 ...+2 others
assert_contains      "工具行折叠单次工具为 others"        "$out" "others"
assert_not_contains  "Bash 被折叠不单独展示"              "$out" "Bash"
assert_not_contains  "Edit 被折叠不单独展示"              "$out" "Edit"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 3b. ClaudeCode transcript 格式 ══════════════════════════════════════"

json=$(make_json "/tmp/proj" "claude-sonnet-4-6" "Claude Sonnet 4.6" \
      "$FIXTURES/transcript_claudecode.jsonl" 50 999999 999999 0 999999000)
out=$(run_statusline "$json")

assert_contains   "ClaudeCode: token 来自 transcript In 1.50K"  "$out" "1.50K"
# 传入 stdin duration=999999000ms(277h)，transcript 实际时长=3m0s
# 若时间戳解析正确，应显示 3m0s 而非 277h
assert_contains      "ClaudeCode: 时长来自 ISO 时间戳（非 stdin 回退）3m0s"  "$out" "3m0s"
assert_not_contains  "ClaudeCode: 时长不应是 stdin 的 277h"                  "$out" "277h"
assert_line_count "ClaudeCode: 有工具调用时输出 2 行"            "$out" 2
assert_contains   "ClaudeCode: 工具行包含 read:2"               "$out" "read:2"
# bash/edit 各调用 1 次，read 调用 2 次 → 折叠为 ...+2 others
assert_contains      "ClaudeCode: 工具行折叠单次工具为 others"  "$out" "others"
assert_not_contains  "ClaudeCode: bash 被折叠不单独展示"        "$out" " bash"
assert_not_contains  "ClaudeCode: edit 被折叠不单独展示"        "$out" " edit"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 4. Compact 感知 ════════════════════════════════════════════════════"

json=$(make_json "/tmp/proj" "claude-sonnet-4-6" "Claude Sonnet 4.6" \
      "$FIXTURES/transcript_with_compact.jsonl" 50 999999 999999 0 999999000)
out=$(run_statusline "$json")

# compact 后最新 assistant 消息 input_tokens=1200, output_tokens=300
assert_contains   "token 仅计 compact 后：In 1.20K"     "$out" "1.20K"
assert_contains   "token 仅计 compact 后：Out 300"       "$out" "300"
# 工具调用全局统计（含 compact 前的 OldTool）
assert_contains   "工具行包含 compact 前的 OldTool"     "$out" "OldTool"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 5. 工具折叠显示逻辑 ════════════════════════════════════════════════"

json=$(make_json "/tmp/proj" "claude-sonnet-4-6" "Claude Sonnet 4.6" \
      "$FIXTURES/transcript_many_singles.jsonl" 50 999999 999999 0 999999000)
out=$(run_statusline "$json")

assert_contains      "高频工具 Read:3 展示计数"           "$out" "Read:3"
assert_contains      "折叠摘要含 others"                  "$out" "others"
assert_contains      "折叠符号 ×1 正确显示"               "$out" "×1"
assert_not_contains  "低频工具 Bash 不单独展示"           "$out" "Bash"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 6. Cache 命中率 ════════════════════════════════════════════════════"

json=$(make_json "/tmp/proj" "claude-sonnet-4-6" "Claude Sonnet 4.6" "null" 42 50000 3000 10000 120000)
out=$(run_statusline "$json")

assert_contains   "Cache 命中率显示"   "$out" "Cache:20%"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 7. 上下文颜色阈值 ══════════════════════════════════════════════════"

# 用 raw 输出（含 ANSI 码）检测颜色
run_raw() { echo "$1" | /bin/bash "$STATUSLINE" 2>/dev/null | head -1; }

assert_color() {
    local label="$1" pct="$2" ansi_code="$3"
    local json out
    json=$(make_json "/tmp/p" "m" "m" "null" "$pct" 1000 100 0 1000)
    out=$(run_raw "$json")
    # 用 printf %b 将 \033[Xm 展开后检查是否包含目标 ANSI 序列
    if printf "%b" "$out" | grep -qF "$(printf '\033['"${ansi_code}"'m')"; then
        echo -e "  ${GREEN}PASS${RESET} $label"
        ((pass++))
    else
        echo -e "  ${RED}FAIL${RESET} $label (ANSI code \\033[${ansi_code}m not found)"
        ((fail++))
    fi
}

assert_color "上下文 < 75% 显示绿色"  50  "0;32"
assert_color "上下文 >= 75% 显示黄色" 80  "0;33"
assert_color "上下文 >= 90% 显示红色" 95  "0;31"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 8. 模型名截断 ══════════════════════════════════════════════════════"

json=$(make_json "/tmp/proj" "claude-model-id-short" "Very Long Display Name Here!" "null")
out=$(run_statusline "$json")
assert_contains   "超长 display_name 时回退到 model_id"  "$out" "claude-model-id-short"
assert_not_contains "超长 display_name 不应显示"         "$out" "Very Long Display Name Here!"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 9. 目录标识 ════════════════════════════════════════════════════════"

json=$(make_json "/Users/krabswang/Personal/dotfiles")
out=$(run_statusline "$json")
assert_contains   "显示 parent/dir 格式"  "$out" "Personal/dotfiles"

json=$(make_json "/myproject")
out=$(run_statusline "$json")
assert_contains   "根目录下只显示 dir 名" "$out" "myproject"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 10. 边界值：空/异常输入 ════════════════════════════════════════════"

# 完全空 JSON
out=$(run_statusline "{}")
assert_line_count "空 JSON 不崩溃，输出 1 行"  "$out" 1
assert_contains   "空 JSON 时目录显示 -"        "$out" "-"

# transcript 路径指向不存在文件
json=$(make_json "/tmp" "m" "m" "/nonexistent/path.jsonl" 30 1000 100 0 5000)
out=$(run_statusline "$json")
assert_line_count "不存在的 transcript 不崩溃"  "$out" 1

# context_used_pct = 0
json=$(make_json "/tmp" "m" "m" "null" 0 0 0 0 0)
out=$(run_statusline "$json")
assert_contains   "0% 时进度条全空"  "$out" "░░░░░░░░"

# context_used_pct = 100
json=$(make_json "/tmp" "m" "m" "null" 100 200000 50000 0 0)
out=$(run_statusline "$json")
assert_contains   "100% 时进度条全满"  "$out" "████████"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 11. format_number 边界值 ════════════════════════════════════════════"

# source 工具函数后直接测试
source "$ROOT_DIR/lib/format.sh"

check_fmt() {
    local label="$1" input="$2" expected="$3"
    local actual
    actual=$(format_number "$input")
    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GREEN}PASS${RESET} format_number($input) = $expected"
        ((pass++))
    else
        echo -e "  ${RED}FAIL${RESET} format_number($input): expected=$expected actual=$actual"
        ((fail++))
    fi
}

check_fmt "0"             0             "0"
check_fmt "999"           999           "999"
check_fmt "1000"          1000          "1.00K"
check_fmt "1500"          1500          "1.50K"
check_fmt "999999"        999999        "999.99K"
check_fmt "1000000"       1000000       "1.00M"
check_fmt "1000000000"    1000000000    "1.00B"
check_fmt "非数字"        "abc"         "0"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "══ 12. format_duration 边界值 ══════════════════════════════════════════"

check_dur() {
    local label="$1" input="$2" expected="$3"
    local actual
    actual=$(format_duration "$input")
    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GREEN}PASS${RESET} format_duration($input) = $expected"
        ((pass++))
    else
        echo -e "  ${RED}FAIL${RESET} format_duration($input): expected=$expected actual=$actual"
        ((fail++))
    fi
}

check_dur "0 秒"      0     "0s"
check_dur "59 秒"     59    "59s"
check_dur "60 秒"     60    "1m0s"
check_dur "90 秒"     90    "1m30s"
check_dur "3600 秒"   3600  "1h0m"
check_dur "3661 秒"   3661  "1h1m"

# ══════════════════════════════════════════════════════════════════════════════
echo ""
total=$((pass + fail + skip))
echo "══ 结果 ════════════════════════════════════════════════════════════════"
echo -e "  总计: $total  ${GREEN}通过: $pass${RESET}  ${RED}失败: $fail${RESET}  ${YELLOW}跳过: $skip${RESET}"
echo ""

[ "$fail" -eq 0 ] && exit 0 || exit 1
