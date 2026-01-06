#!/usr/bin/env bash

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
if [ -n "$transcript_path" ] && [ "$transcript_path" != "null" ] && [ -f "$transcript_path" ]; then
    # Use jq with -s to read all lines and extract all statistics in a single pass
    jq_output=$(jq -r -s '{
      input_tokens: map(.providerData.usage.inputTokens // 0) | add,
      output_tokens: map(.providerData.usage.outputTokens // 0) | add,
      tool_calls: map(select(.type == "function_call")) | length,
      first_ts: (map(select(.type == "function_call")) | map(.timestamp // 0) | min),
      last_ts: (map(select(.type == "function_call")) | map(.timestamp // 0) | max),
      command_calls: map(select(.type == "message" and .role == "user" and (.content | tostring | contains("<command-name>")))) | length
    } | to_entries | map(.value) | @tsv' "$transcript_path" 2>/dev/null || echo "0	0	0	0	0	0")
    
    read -r input_tokens output_tokens tool_calls first_timestamp last_timestamp command_calls <<< "$jq_output"
    
    # Calculate duration
    if [ -n "$first_timestamp" ] && [ "$first_timestamp" != "0" ] && [ -n "$last_timestamp" ] && [ "$last_timestamp" != "0" ]; then
        total_api_duration_ms=$((last_timestamp - first_timestamp))
        [ "$total_api_duration_ms" -gt 0 ] && runtime=$(format_duration $((total_api_duration_ms / 1000)))
    fi
    # Extract tool names for counting (only if we have tool calls)
    if [ "$tool_calls" -gt 0 ]; then
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

# Build status line with proper formatting
# Using printf with %b to interpret escape sequences
# All information in a single line for CodeBuddy compatibility

status_line="\\033[1;32m➜\\033[0m \\033[0;36m${display_dir}\\033[0m${git_info}"

# Add separator and model info
status_line="${status_line} | \\033[0;33m${model_short}\\033[0m"

# Add separator and runtime
status_line="${status_line} | \\033[0;34m⏰${runtime}\\033[0m"

# Add combined tokens (in/out)
status_line="${status_line}(\\033[0;35m${input_tokens_formatted}/${output_tokens_formatted}\\033[0m)"

# Add tool statistics in compact format (if any)
if [ "$tool_calls" -gt 0 ] && [ -s "$tool_counts_file" ]; then
    # Build compact tool usage string
    # Format: Tool abbreviation + count (e.g., B99 R31 E23)
    tool_compact_str=""
    
    # Get tool abbreviation
    get_abbrev() {
        case "$1" in
            Bash) echo "Bash" ;;
            Read) echo "Read" ;;
            Write) echo "Write" ;;
            Edit) echo "Edit" ;;
            MultiEdit) echo "ME" ;;
            TodoWrite) echo "Todo" ;;
            Grep) echo "Grep" ;;
            Glob) echo "Glob" ;;
            WebFetch) echo "WebF" ;;
            WebSearch) echo "WebS" ;;
            Task) echo "Task" ;;
            AskUserQuestion) echo "Q" ;;
            NotebookEdit) echo "NE" ;;
            *) echo "$(echo "$1" | cut -c1)" ;;  # First char as fallback
        esac
    }
    
    # Count and sort tools by frequency
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
    
    [ -n "$tool_compact_str" ] && status_line="${status_line} | 🔧${tool_compact_str}"
fi

# Add MCP services count (if any)
if [ "$mcp_services" -gt 0 ]; then
    status_line="${status_line} \\033[0;90m🔌${mcp_services}\\033[0m"
fi

# Add command calls count (if any)
if [ "$command_calls" -gt 0 ]; then
    status_line="${status_line} \\033[0;90m⚡${command_calls}\\033[0m"
fi

# Print status line with %b to interpret escape sequences
printf "%b" "$status_line"