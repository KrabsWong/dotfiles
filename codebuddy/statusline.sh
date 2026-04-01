#!/usr/bin/env bash

# Cache directory and file for model context data
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codebuddy"
CACHE_FILE="$CACHE_DIR/models_context.json"
CACHE_TTL=86400  # 24 hours in seconds

# Function to get context window size from models.dev API
get_context_window() {
    local model_id="$1"
    local context_size=""
    local cache_valid=false

    # Check if cache exists and is valid
    if [ -f "$CACHE_FILE" ]; then
        local cache_age=$(($(date +%s) - $(stat -f%m "$CACHE_FILE" 2>/dev/null || stat -c%Y "$CACHE_FILE" 2>/dev/null || echo 0)))
        if [ "$cache_age" -lt "$CACHE_TTL" ]; then
            cache_valid=true
        fi
    fi

    # Try to get context from cache first
    if [ "$cache_valid" = true ] && [ -f "$CACHE_FILE" ]; then
        context_size=$(jq -r --arg model "$model_id" '
            to_entries[] | 
            select(.value.models[$model].limit.context != null) | 
            .value.models[$model].limit.context
        ' "$CACHE_FILE" 2>/dev/null | head -1)
    fi

    # If not in cache, fetch from API
    if [ -z "$context_size" ] || [ "$context_size" = "null" ]; then
        # Create cache directory if needed
        mkdir -p "$CACHE_DIR"

        # Fetch and cache the API data
        local api_data=$(curl -s "https://models.dev/api.json" 2>/dev/null)
        if [ -n "$api_data" ]; then
            echo "$api_data" > "$CACHE_FILE"

            # Extract context size for the model
            context_size=$(echo "$api_data" | jq -r --arg model "$model_id" '
                to_entries[] | 
                select(.value.models[$model].limit.context != null) | 
                .value.models[$model].limit.context
            ' 2>/dev/null | head -1)
        fi
    fi

    # Return context size or default fallback
    if [ -n "$context_size" ] && [ "$context_size" != "null" ]; then
        echo "$context_size"
    else
        echo "128000"  # Default fallback
    fi
}

# Read JSON input from stdin and extract all fields in a single jq call
read -r current_dir model_display model_id transcript_path < <(
    jq -r '[.workspace.current_dir, .model.display_name, .model.id, .transcript_path] | @tsv' 2>/dev/null
)
dir_name=$(basename "$current_dir" 2>/dev/null || echo "unknown")

# Function to format time duration
format_duration() {
    local seconds=$1
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m$((seconds % 60))s"
    else
        echo "$((seconds / 3600))h$((seconds / 60 % 60))m"
    fi
}

# Function to format large numbers with suffix (K, M, B) - using pure bash
format_number() {
    local number=${1:-0}
    
    # Handle non-numeric input
    [[ ! "$number" =~ ^[0-9]+$ ]] && { echo "0"; return; }
    
    if [ "$number" -ge 1000000000 ]; then
        local int_part=$((number / 1000000000))
        local dec_part=$(( (number % 1000000000) / 10000000 ))
        printf "%d.%02dB" "$int_part" "$dec_part"
    elif [ "$number" -ge 1000000 ]; then
        local int_part=$((number / 1000000))
        local dec_part=$(( (number % 1000000) / 10000 ))
        printf "%d.%02dM" "$int_part" "$dec_part"
    elif [ "$number" -ge 1000 ]; then
        local int_part=$((number / 1000))
        local dec_part=$(( (number % 1000) / 10 ))
        printf "%d.%02dK" "$int_part" "$dec_part"
    else
        printf "%d" "$number"
    fi
}

# Extract project name for better identification
project_name=""
if [ -n "$current_dir" ] && [ "$current_dir" != "null" ] && [ "$current_dir" != "unknown" ]; then
    # Try to get a more descriptive project name
    parent_dir=$(dirname "$current_dir")
    if [ "$parent_dir" != "/" ]; then
        project_name=$(basename "$parent_dir")
        if [ "$project_name" = "." ] || [ "$project_name" = ".." ]; then
            project_name=""
        fi
    fi
fi

# Create display identifier (removed session_id since model info is shared by design)
display_identifier="$dir_name"
if [ -n "$project_name" ] && [ "$project_name" != "$dir_name" ]; then
    display_identifier="${project_name}/${dir_name}"
fi

# Initialize statistics
input_tokens=0
output_tokens=0
total_api_duration_ms=0
runtime="0s"
tool_calls=0
command_calls=0
mcp_services=0

# Temp file for tool counts (cleaned up at end)
tool_counts_file=$(mktemp)
trap "rm -f '$tool_counts_file'" EXIT

# Parse transcript file (now .jsonl format) once and extract all needed data using jq for better performance
# Handle compact operation: if transcript contains "Compact Instructions", only count token usage after the last compact
# Note: tool_calls, session time, and command_calls keep global statistics (not reset by compact)
if [ -n "$transcript_path" ] && [ "$transcript_path" != "null" ] && [ -f "$transcript_path" ]; then
    # First, find the last compact timestamp
    last_compact_ts=$(jq -r '[.[] | select(.type == "message" and .role == "user" and (.content[0].text | contains("Compact Instructions"))) | .timestamp] | max // empty' "$transcript_path" 2>/dev/null)

    # Get token metrics from the most recent assistant message
    # Use --arg to pass the compact timestamp to jq
    jq_output=$(jq -r -s --arg compact_ts "$last_compact_ts" '
      . as $all |

      # Filter records after compact (or all records if no compact)
      (if $compact_ts != "" and $compact_ts != "null" then
         [$all[] | select(.timestamp > $compact_ts)]
       else
         $all
       end) as $records_after_compact |

      # Get the most recent main chain assistant message with non-zero usage data
      ($records_after_compact |
        map(select(.isSidechain != true and .type == "assistant" and .message.usage != null and
                   ((.message.usage.input_tokens // 0) > 0 or (.message.usage.output_tokens // 0) > 0))) |
        sort_by(.timestamp) |
        last // {message: {usage: {input_tokens: 0, output_tokens: 0}}}) as $latest_message |

      # Calculate stats
      {
        input_tokens: ($latest_message.message.usage.input_tokens // 0),
        output_tokens: ($latest_message.message.usage.output_tokens // 0),
        tool_calls: ($all | map(select(.type == "function_call")) | length),
        first_ts: ($all | map(select(.type == "function_call")) | map(.timestamp // 0) | min // 0),
        last_ts: ($all | map(select(.type == "function_call")) | map(.timestamp // 0) | max // 0),
        command_calls: ($all | map(select(.type == "message" and .role == "user" and (.content | tostring | contains("<command-name>")))) | length)
      } | to_entries | map(.value) | @tsv' "$transcript_path" 2>/dev/null || echo "0	0	0	0	0	0")
    
    read -r input_tokens output_tokens tool_calls first_timestamp last_timestamp command_calls <<< "$jq_output"
    
    # Calculate duration (global, not affected by compact)
    if [ -n "$first_timestamp" ] && [ "$first_timestamp" != "0" ] && [ -n "$last_timestamp" ] && [ "$last_timestamp" != "0" ]; then
        total_api_duration_ms=$((last_timestamp - first_timestamp))
        [ "$total_api_duration_ms" -gt 0 ] && runtime=$(format_duration $((total_api_duration_ms / 1000)))
    fi
    # Extract tool names for counting (global stats, not affected by compact)
    if [ "$tool_calls" -gt 0 ]; then
        # Count all tool calls (global, not reset by compact)
        jq -r 'select(.type == "function_call") | .name // empty' "$transcript_path" 2>/dev/null > "$tool_counts_file"
        
        # Count unique MCP services from tool names
        if [ -s "$tool_counts_file" ]; then
            mcp_count=$(grep '^mcp__' "$tool_counts_file" 2>/dev/null | wc -l | tr -d ' ')
            [ -n "$mcp_count" ] && [ "$mcp_count" -gt 0 ] && mcp_services="$mcp_count"
        fi
    fi
else
    # Debug: show why we skipped parsing
    if [ -z "$transcript_path" ] || [ "$transcript_path" = "null" ]; then
        : # transcript_path is null or empty
    elif [ ! -f "$transcript_path" ]; then
        : # transcript file does not exist
    fi
fi

# Check if we're in a git repository - optimized to reduce git command calls
# Use current_dir if valid, otherwise fallback to current working directory
git_work_dir="$current_dir"
if [ "$current_dir" = "null" ] || [ "$current_dir" = "unknown" ] || [ ! -d "$current_dir" ]; then
    git_work_dir="$(pwd)"
fi

git_info=""
added_lines=""
deleted_lines=""
untracked_info=""
if git -C "$git_work_dir" rev-parse --git-dir > /dev/null 2>&1; then
    # Get branch name, commit hash, and check dirty status in one go
    branch=$(git -C "$git_work_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    if [ -n "$branch" ]; then
        # Get commit hash and check if dirty in parallel using command substitution
        commit_hash=$(git -C "$git_work_dir" rev-parse --short=7 HEAD 2>/dev/null)
        dirty_status=$(git -C "$git_work_dir" status --porcelain 2>/dev/null)
        
        if [ -z "$dirty_status" ]; then
            # Clean state - show branch and hash
            git_info=" (${branch}@${commit_hash})"
        else
            # Dirty state - calculate added/deleted lines efficiently
            git_stats=$(git -C "$git_work_dir" diff --numstat 2>/dev/null | awk '{added+=$1; deleted+=$2} END {print (added+0) " " (deleted+0)}')
            
            if [ -n "$git_stats" ]; then
                read -r added deleted <<< "$git_stats"
                # Only show if we have actual numbers > 0
                if [ "$added" -gt 0 ] 2>/dev/null; then
                    added_lines=" +${added}"
                fi
                if [ "$deleted" -gt 0 ] 2>/dev/null; then
                    deleted_lines=" -${deleted}"
                fi
            fi
            
            # Count untracked files (status code "??")
            untracked_count=$(echo "$dirty_status" | grep -c "^??" 2>/dev/null || echo "0")
            if [ "$untracked_count" -gt 0 ] 2>/dev/null; then
                untracked_info=" ?${untracked_count}"
            fi
            
            # Combine git info with change stats
            git_info=" (${branch}@${commit_hash}${added_lines}${deleted_lines}${untracked_info}) ✗"
        fi
    fi
fi

# Build model display (shorten if needed)
model_short="$model_display"
if [ "$model_display" != "$model_id" ] && [ ${#model_display} -gt 15 ]; then
    # Use ID if display name is too long
    model_short="$model_id"
fi

# Use display identifier for showing directory info
display_dir="$display_identifier"

# Format token numbers with suffix
input_tokens_formatted=$(format_number $input_tokens)
output_tokens_formatted=$(format_number $output_tokens)

# Calculate context window usage percentage
total_tokens=$((input_tokens + output_tokens))
context_window=$(get_context_window "$model_id")
context_percentage=$((total_tokens * 100 / context_window))

# Determine color based on usage level
get_context_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then
        echo "\033[0;31m"  # Red - critical
    elif [ "$pct" -ge 75 ]; then
        echo "\033[0;33m"  # Yellow - warning
    else
        echo "\033[0;32m"  # Green - normal
    fi
}
context_color=$(get_context_color $context_percentage)

# Build visual progress bar for context usage (half-height blocks)
build_progress_bar() {
    local pct=$1
    local width=10
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar=""

    # Build filled portion with half-height blocks (▄)
    for ((i=0; i<filled; i++)); do
        bar="${bar}▄"
    done

    # Build empty portion
    for ((i=0; i<empty; i++)); do
        bar="${bar}░"
    done

    echo "${bar} "
}
context_bar=$(build_progress_bar $context_percentage)

# Format context window size for display
format_context_window() {
    local size=$1
    if [ "$size" -ge 1000000 ]; then
        echo "$((size / 1000000))M"
    elif [ "$size" -ge 1000 ]; then
        echo "$((size / 1000))K"
    else
        echo "$size"
    fi
}
context_window_formatted=$(format_context_window $context_window)

# Tool name abbreviation function
get_abbrev() {
    if [ "$1" = "Bash" ]; then echo "Bash"
    elif [ "$1" = "Read" ]; then echo "Read"
    elif [ "$1" = "Write" ]; then echo "Write"
    elif [ "$1" = "Edit" ]; then echo "Edit"
    elif [ "$1" = "MultiEdit" ]; then echo "ME"
    elif [ "$1" = "TodoWrite" ]; then echo "Todo"
    elif [ "$1" = "Grep" ]; then echo "Grep"
    elif [ "$1" = "Glob" ]; then echo "Glob"
    elif [ "$1" = "WebFetch" ]; then echo "WebF"
    elif [ "$1" = "WebSearch" ]; then echo "WebS"
    elif [ "$1" = "Task" ]; then echo "Task"
    elif [ "$1" = "AskUserQuestion" ]; then echo "Q"
    elif [ "$1" = "NotebookEdit" ]; then echo "NE"
    else echo "$(echo "$1" | cut -c1)"
    fi
}

# Build tool statistics string (if any)
tool_stats=""
if [ "$tool_calls" -gt 0 ] && [ -s "$tool_counts_file" ]; then
    tool_compact_str=""

    sort "$tool_counts_file" | uniq -c | sort -rn | while read -r count name; do
        abbrev=$(get_abbrev "$name")
        if [ -z "$tool_compact_str" ]; then
            tool_compact_str="${abbrev}:${count}"
        else
            tool_compact_str="${tool_compact_str} ${abbrev}:${count}"
        fi
        echo "$tool_compact_str"
    done | tail -1 > "${tool_counts_file}.out"
    
    tool_compact_str=$(cat "${tool_counts_file}.out" 2>/dev/null)
    rm -f "${tool_counts_file}.out"
    
    [ -n "$tool_compact_str" ] && tool_stats=" | ${tool_compact_str}"
fi

if [ "$mcp_services" -gt 0 ]; then
    tool_stats="${tool_stats} 🔌${mcp_services}"
fi

if [ "$command_calls" -gt 0 ]; then
    tool_stats="${tool_stats} ⚡${command_calls}"
fi

# Single-line display inspired by cship/starship
# Format: 🤖 model | ⏱️ time | 📊 tokens ↑↓ | [context_bar] | 🔧 tools | 📁 directory/git

# Build sections
section_model="\\033[1;36m🤖 ${model_short}\\033[0m"
section_time="\\033[0;34m⏱️ ${runtime}\\033[0m"
section_tokens="\\033[0;35m📊 ↑${input_tokens_formatted} ↓${output_tokens_formatted}\\033[0m"
section_context="${context_color}${context_bar}${context_percentage}%\\033[0m"

# Compact git info - reuse existing git_info but simplify
if [ -n "$git_info" ]; then
    # Extract just branch name from git_info (remove hash and stats)
    git_branch_clean=$(echo "$git_info" | sed -E 's/.*\(([a-zA-Z0-9_-]+).*/\1/')
    if echo "$git_info" | grep -q "✗"; then
        git_compact=" \\033[0;33m(${git_branch_clean}*)\\033[0m"
    else
        git_compact=" \\033[0;32m(${git_branch_clean})\\033[0m"
    fi
else
    git_compact=""
fi

section_dir="\\033[0;36m📁 ${display_dir}\\033[0m${git_compact}"

# Combine all sections with separators
statusline="${section_model} │ ${section_time} │ ${section_tokens} │ ${section_context}"

# Add tool stats if present
if [ -n "$tool_stats" ]; then
    # Clean up tool stats format (remove leading " | ")
    clean_tool_stats=$(echo "$tool_stats" | sed 's/^ | //')
    if [ -n "$clean_tool_stats" ]; then
        statusline="${statusline} │ \\033[0;33m🔧 ${clean_tool_stats}\\033[0m"
    fi
fi

# Add directory at the end
statusline="${statusline} │ ${section_dir}"

printf "%b\n" "${statusline}"