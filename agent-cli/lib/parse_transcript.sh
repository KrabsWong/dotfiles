#!/usr/bin/env bash
# lib/parse_transcript.sh — 解析 .jsonl 格式 transcript 文件
# 依赖变量（来自 parse_input.sh）: transcript_path, runtime, input_tokens, output_tokens, tool_calls
# 依赖函数（来自 format.sh）: format_duration
# 设置变量: input_tokens, output_tokens, tool_calls, runtime, tool_counts_file

# 临时文件存储工具名列表，供 render.sh 使用（无论是否解析 transcript 都需要）
workbuddy_usage=0
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

  # WorkBuddy 的 normalized usage 已包含缓存输入；按 yes-sessions 的字段优先级读取。
  def count($values): $values | map(select(type == "number" and . >= 0 and . == floor)) | first;
  def buddy_usage:
    [.providerData.usage, .message.usage, .providerData.rawUsage] |
    map(select(type == "object") |
      {input: count([.inputTokens, .input_tokens, .prompt_tokens]),
       output: count([.outputTokens, .output_tokens, .completion_tokens]),
       cached: count([
         (try .inputTokensDetails[0].cached_tokens catch null),
         (try .inputTokensDetails.cached_tokens catch null),
         .prompt_tokens_details.cached_tokens, .prompt_cache_hit_tokens, .cache_read_input_tokens])} |
      select(.input != null or .output != null or .cached != null)) | first;
  (any($all[]; (.type == "message" and .role == "assistant") or
               (.providerData.usage != null) or (.providerData.rawUsage != null))) as $buddy |
  (reduce ($all[] | select(.isSidechain != true and
      (.type == "assistant" or .type == "reasoning" or .type == "function_call" or
       (.type == "message" and .role == "assistant")))) as $record
    ({seen: {}, count: 0, input: 0, output: 0, cached: 0, cache_known: true};
      ($record | buddy_usage) as $usage |
      ($record.providerData.messageId // $record.message.id // null) as $id |
      if $usage == null or $usage.input == null or $usage.output == null or
         ($id != null and .seen[$id] == true) then .
      else
        (if $id != null then .seen[$id] = true else . end) |
        .count += 1 | .input += $usage.input | .output += $usage.output |
        .cached += ($usage.cached // 0) |
        .cache_known = (.cache_known and $usage.cached != null and $usage.cached <= $usage.input)
      end)) as $totals |
  {
    input_tokens:  (if $buddy and $totals.count > 0 then $totals.input else ($latest.message.usage.input_tokens // 0) end),
    output_tokens: (if $buddy and $totals.count > 0 then $totals.output else ($latest.message.usage.output_tokens // 0) end),
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
                         else gsub("\\.[0-9]+Z$";"Z") | fromdateiso8601 end),
    buddy_mode: (if $buddy then 1 else 0 end),
    buddy_count: $totals.count,
    buddy_cached: (if $totals.cache_known then $totals.cached else -1 end)
  } | to_entries | map(.value) | @tsv
' "$transcript_path" 2>/dev/null || printf '0\t0\t0\t0\t0\t0\t0\t-1\n')

# tool_calls 由此处赋值（覆盖 parse_input.sh 中初始化的 0）；若 transcript 不存在则保持为 0
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
if [ "$tool_calls" -gt 0 ]; then
    jq -r '
      if .type == "function_call" then .name                          # CodeBuddy CLI
      elif .type == "tool_use" and .tool_name then .tool_name          # ClaudeCode 顶级记录
      elif .type == "assistant" and .message.content != null then      # CodeBuddy assistant content
        (.message.content | map(select(.type == "tool_use") | .name) | .[])
      else empty
      end // empty' "$transcript_path" 2>/dev/null > "$tool_counts_file"
fi
