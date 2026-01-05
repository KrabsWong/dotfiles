#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract information from the JSON input
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
dir_name=$(basename "$current_dir")
model_display=$(echo "$input" | jq -r '.model.display_name')
model_id=$(echo "$input" | jq -r '.model.id')
session_id=$(echo "$input" | jq -r '.session_id')
transcript_path=$(echo "$input" | jq -r '.transcript_path')

# Extract cost statistics
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
session_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
cost_lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
cost_lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
api_duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')

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

# Function to format large numbers with suffix (K, M, B) - precise to 2 decimal places
format_number() {
    local number=$1
    local abs_number=${number#-}
    
    if (( $(echo "$abs_number >= 1000000000" | bc -l) )); then
        printf "%.2fB" $(echo "$number / 1000000000" | bc -l)
    elif (( $(echo "$abs_number >= 1000000" | bc -l) )); then
        printf "%.2fM" $(echo "$number / 1000000" | bc -l)
    elif (( $(echo "$abs_number >= 1000" | bc -l) )); then
        printf "%.2fK" $(echo "$number / 1000" | bc -l)
    else
        printf "%.0f" "$number"
    fi
}

# Calculate session runtime from API duration
if [ "$api_duration_ms" != "null" ] && [ "$api_duration_ms" != "0" ]; then
    runtime=$(format_duration $((api_duration_ms / 1000)))
else
    # Fallback to tracking with session file
    runtime="0s"
    if [ -n "$session_id" ] && [ "$session_id" != "null" ]; then
        session_file="/tmp/codebuddy_session_${session_id}.start"
        if [ -f "$session_file" ]; then
            start_time=$(cat "$session_file")
            current_time=$(date +%s)
            duration=$((current_time - start_time))
            runtime=$(format_duration $duration)
        else
            # Record start time for future calls
            echo "$(date +%s)" > "$session_file"
            runtime="0s"
        fi
    fi
fi

# Calculate total input and output tokens from transcript file
input_tokens=0
output_tokens=0
if [ -n "$transcript_path" ] && [ "$transcript_path" != "null" ] && [ -f "$transcript_path" ]; then
    # Extract all inputTokens and outputTokens from transcript and sum them up
    input_tokens=$(cat "$transcript_path" | grep -o '"inputTokens":[0-9]*' | grep -o '[0-9]*' | awk '{sum+=$1} END {print sum+0}')
    output_tokens=$(cat "$transcript_path" | grep -o '"outputTokens":[0-9]*' | grep -o '[0-9]*' | awk '{sum+=$1} END {print sum+0}')
fi

# Check if we're in a git repository
git_info=""
added_lines=""
deleted_lines=""
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
    # Get current branch name
    branch=$(git -C "$current_dir" branch --show-current 2>/dev/null || echo "")
    if [ -n "$branch" ]; then
        # Check if working directory is dirty
        if [ -z "$(git -C "$current_dir" status --porcelain --no-optional-locks 2>/dev/null)" ]; then
            # Clean state
            git_info=" (${branch})"
        else
            # Dirty state
            git_info=" (${branch}) ✗"

            # Get added/deleted lines from git diff
            git_stats=$(git -C "$current_dir" diff --numstat --no-optional-locks 2>/dev/null)
            if [ -n "$git_stats" ]; then
                added=$(echo "$git_stats" | awk '{added+=$1} END {print added}')
                deleted=$(echo "$git_stats" | awk '{deleted+=$2} END {print deleted}')
                if [ "$added" -gt 0 ] || [ "$deleted" -gt 0 ]; then
                    added_lines=" +${added}"
                    deleted_lines=" -${deleted}"
                fi
            fi
        fi
    fi
fi

# Build model display (shorten if needed)
model_short="$model_display"
if [ "$model_display" != "$model_id" ] && [ ${#model_display} -gt 15 ]; then
    # Use the ID if display name is too long
    model_short="$model_id"
fi

# Format token numbers with suffix
input_tokens_formatted=$(format_number $input_tokens)
output_tokens_formatted=$(format_number $output_tokens)

# Build the status line with proper formatting
# Using printf with %b to interpret escape sequences
# Build each part with separator included

status_line="\\033[1;32m➜\\033[0m \\033[0;36m${dir_name}\\033[0m${git_info}"

# Add separator and model info
status_line="${status_line} | \\033[0;33m${model_short}\\033[0m"

# Add separator and runtime
status_line="${status_line} | \\033[0;34m⏰${runtime}\\033[0m"

# Add separator and git line changes (if any)
if [ -n "$added_lines" ] || [ -n "$deleted_lines" ]; then
    status_line="${status_line} | \\033[0;32m${added_lines}\\033[0m\\033[0;31m${deleted_lines}\\033[0m"
fi

# Add separator and input tokens
status_line="${status_line} | \\033[0;35min:${input_tokens_formatted}\\033[0m"

# Add separator and output tokens
status_line="${status_line} | \\033[0;35mout:${output_tokens_formatted}\\033[0m"

# Print the status line with %b to interpret escape sequences
printf "%b" "$status_line"
