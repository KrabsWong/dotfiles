# 输入：逐行 JSONL；参数：compact_ts、main_path。输出：usage、工具数、时长等 TSV 字段。
[inputs | input_filename as $source | fromjson? | {source: $source, record: .}] as $logs |
[$logs[] | select(.source == $main_path) | .record] as $all |

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
(any($logs[].record; (.type == "message" and .role == "assistant") or
             (.providerData.usage != null) or (.providerData.rawUsage != null))) as $buddy |
(reduce ($logs[].record | select(
    (.type == "assistant" or .type == "reasoning" or .type == "function_call" or
     (.type == "message" and .role == "assistant")))) as $record
  ({seen: {}, count: 0, input: 0, output: 0, cached: 0, cache_known: true};
    ($record | buddy_usage) as $usage |
    ($record.providerData.messageId // $record.message.id // $record.id // null) as $id |
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
