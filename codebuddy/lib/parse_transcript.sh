#!/usr/bin/env bash
# lib/parse_transcript.sh — 解析 .jsonl 格式 transcript 文件
# 依赖变量（来自 parse_input.sh）: transcript_path, runtime, input_tokens, output_tokens, tool_calls
# 依赖函数（来自 format.sh）: format_duration
# 设置变量: input_tokens, output_tokens, tool_calls, runtime, tool_counts_file

# 临时文件存储工具名列表，供 render.sh 使用（无论是否解析 transcript 都需要）
tool_counts_file=$(mktemp)
trap "rm -f '$tool_counts_file'" EXIT

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

# 第二步：单次 jq 调用提取所有统计数据
jq_output=$(jq -r -s --arg compact_ts "$last_compact_ts" '
  . as $all |

  # compact 后的记录（无 compact 则取全部）
  (if $compact_ts != "" and $compact_ts != "null" then
     [$all[] | select(.timestamp > $compact_ts)]
   else
     $all
   end) as $after |

  # 取 compact 后最新的主链 assistant 消息（有非零 usage 数据）
  ($after |
    map(select(
      .isSidechain != true and
      .type == "assistant" and
      .message.usage != null and
      ((.message.usage.input_tokens // 0) > 0 or (.message.usage.output_tokens // 0) > 0)
    )) |
    sort_by(.timestamp) |
    last // {message: {usage: {input_tokens: 0, output_tokens: 0}}}
  ) as $latest |

  {
    input_tokens:  ($latest.message.usage.input_tokens // 0),
    output_tokens: ($latest.message.usage.output_tokens // 0),
    tool_calls: (
      # CodeBuddy: type=function_call
      ($all | map(select(.type == "function_call")) | length) +
      # CodeBuddy: tool_use 嵌套在 assistant.message.content 中
      ($all | map(select(.type == "assistant" and .message.content != null)
               | .message.content | map(select(.type == "tool_use")) | length)
             | add // 0) +
      # ClaudeCode: 顶级 type=tool_use 记录
      ($all | map(select(.type == "tool_use")) | length)
    ),
    # timestamp 兼容两种格式：
    #   CodeBuddy: 毫秒整数（如 1700000000000），除以 1000 得到秒
    #   ClaudeCode: ISO 8601 字符串（如 "2026-03-06T15:02:59.559Z"），截断毫秒后用 fromdateiso8601
    first_epoch: ($all | map(select(.timestamp != null)) | map(.timestamp) | min // 0
                       | if type == "number" then . / 1000 | floor
                         else gsub("\\.[0-9]+Z$";"Z") | fromdateiso8601 end),
    last_epoch:  ($all | map(select(.timestamp != null)) | map(.timestamp) | max // 0
                       | if type == "number" then . / 1000 | floor
                         else gsub("\\.[0-9]+Z$";"Z") | fromdateiso8601 end)
  } | to_entries | map(.value) | @tsv
' "$transcript_path" 2>/dev/null || echo "0	0	0	0	0")

# tool_calls 由此处赋值（覆盖 parse_input.sh 中初始化的 0）；若 transcript 不存在则保持为 0
read -r input_tokens output_tokens tool_calls first_epoch last_epoch <<< "$jq_output"

# 从 transcript 时间戳计算会话时长（优先于 stdin 的 total_duration_ms）
if [ "${first_epoch:-0}" -gt 0 ] && [ "${last_epoch:-0}" -gt 0 ] 2>/dev/null; then
    total_duration=$((last_epoch - first_epoch))
    [ "$total_duration" -gt 0 ] && runtime=$(format_duration $total_duration)
fi

# 提取工具名列表（全局统计，不受 compact 影响）
if [ "$tool_calls" -gt 0 ]; then
    jq -r '
      if .type == "function_call" then .name                          # CodeBuddy CLI
      elif .type == "tool_use" and .tool_name then .tool_name          # ClaudeCode 顶级记录
      elif .type == "assistant" and .message.content != null then      # CodeBuddy assistant content
        (.message.content | map(select(.type == "tool_use") | .name) | .[])
      else empty
      end // empty' "$transcript_path" 2>/dev/null > "$tool_counts_file"
fi
