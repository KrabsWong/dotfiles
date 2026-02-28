#!/usr/bin/env bash

# Claude Code Statusline Script - adapted from CodeBuddy version
# Reads JSON from stdin, outputs formatted status line

# Read JSON input and extract all fields in a single jq call
input=$(cat 2>/dev/null)

# Extract basic fields
cwd=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null)
model_display=$(echo "$input" | jq -r '.model.display_name // ""' 2>/dev/null)
model_id=$(echo "$input" | jq -r '.model.id // ""' 2>/dev/null)
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null)

# Get context window usage directly from JSON (Claude provides this)
input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)

# Get duration from cost object (milliseconds)
total_api_duration_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0' 2>/dev/null)
if [ "$total_api_duration_ms" -eq 0 ]; then
    total_api_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null)
fi

# Get line changes from cost object
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0' 2>/dev/null)
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0' 2>/dev/null)

# Extract directory name for display
dir_name=$(basename "$cwd" 2>/dev/null || echo "unknown")

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

# Function to format large numbers with suffix (K, M, B)
# Shows 1 decimal place: 12345 -> 12.3K, 1234567 -> 1.2M, 1234567890 -> 1.2B
format_number() {
    local number=${1:-0}
    
    # Handle non-numeric input
    [[ ! "$number" =~ ^[0-9]+$ ]] && { echo "0"; return; }
    
    if [ "$number" -ge 1000000000 ]; then
        # Billions: X.YB
        local billions=$((number / 1000000000))
        local remainder=$((number % 1000000000))
        # Convert remainder to decimal (e.g., 123456789 -> 0.1)
        local tenths=$((remainder * 10 / 1000000000))
        printf "%d.%dB" "$billions" "$tenths"
    elif [ "$number" -ge 1000000 ]; then
        # Millions: X.YM
        local millions=$((number / 1000000))
        local remainder=$((number % 1000000))
        local tenths=$((remainder * 10 / 1000000))
        printf "%d.%dM" "$millions" "$tenths"
    elif [ "$number" -ge 1000 ]; then
        # Thousands: X.YK
        local thousands=$((number / 1000))
        local remainder=$((number % 1000))
        local tenths=$((remainder * 10 / 1000))
        printf "%d.%dK" "$thousands" "$tenths"
    else
        printf "%d" "$number"
    fi
}

# Build display identifier (project/directory)
display_identifier="$dir_name"
parent_dir=$(dirname "$cwd" 2>/dev/null)
if [ -n "$parent_dir" ] && [ "$parent_dir" != "/" ] && [ "$parent_dir" != "." ]; then
    parent_name=$(basename "$parent_dir")
    if [ -n "$parent_name" ] && [ "$parent_name" != "$dir_name" ]; then
        display_identifier="${parent_name}/${dir_name}"
    fi
fi

# Check if we're in a git repository
git_info=""
added_lines=""
deleted_lines=""
untracked_info=""

if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    if [ -n "$branch" ]; then
        commit_hash=$(git -C "$cwd" rev-parse --short=7 HEAD 2>/dev/null)
        dirty_status=$(git -C "$cwd" status --porcelain 2>/dev/null)
        
        if [ -z "$dirty_status" ]; then
            git_info=" (${branch}@${commit_hash})"
        else
            # Calculate added/deleted lines efficiently
            git_stats=$(git -C "$cwd" diff --numstat 2>/dev/null | awk '{added+=$1; deleted+=$2} END {print (added+0) " " (deleted+0)}')
            
            if [ -n "$git_stats" ]; then
                read -r added deleted <<< "$git_stats"
                # Show line changes from git diff (more accurate than cost object for uncommitted changes)
                if [ "$added" -gt 0 ] 2>/dev/null; then
                    added_lines=" +${added}"
                fi
                if [ "$deleted" -gt 0 ] 2>/dev/null; then
                    deleted_lines=" -${deleted}"
                fi
            fi
            
            # Count untracked files
            untracked_count=$(echo "$dirty_status" | grep -c "^??" 2>/dev/null || echo "0")
            if [ "$untracked_count" -gt 0 ] 2>/dev/null; then
                untracked_info=" ?${untracked_count}"
            fi
            
            git_info=" (${branch}@${commit_hash}${added_lines}${deleted_lines}${untracked_info}) ✗"
        fi
    fi
fi

# Build model display (shorten if needed)
model_short="$model_display"
if [ "$model_display" != "$model_id" ] && [ ${#model_display} -gt 15 ]; then
    model_short="$model_id"
fi

# Use display identifier for showing directory info
display_dir="$display_identifier"

# Format token numbers with suffix
input_tokens_formatted=$(format_number $input_tokens)
output_tokens_formatted=$(format_number $output_tokens)

# Format runtime
runtime=$(format_duration $((total_api_duration_ms / 1000)))

# Build status line with proper formatting
status_line="\033[1;32m➜\033[0m \033[0;36m${display_dir}\033[0m${git_info}"

# Add separator and model info
status_line="${status_line} | \033[0;33m${model_short}\033[0m"

# Add separator and runtime
status_line="${status_line} | \033[0;34m⏰${runtime}\033[0m"

# Add combined tokens (in/out)
status_line="${status_line}(\033[0;35m${input_tokens_formatted}/${output_tokens_formatted}\033[0m)"

# Optionally show line changes if available (from cost object)
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
    lines_info=""
    [ "$lines_added" -gt 0 ] && lines_info="${lines_info} +${lines_added}"
    [ "$lines_removed" -gt 0 ] && lines_info="${lines_info} -${lines_removed}"
    status_line="${status_line} | \033[0;90m📝${lines_info}\033[0m"
fi

# If transcript file exists, try to extract tool call statistics (optional enhancement)
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    tool_counts_file=$(mktemp)
    # Try to extract function calls from transcript (similar to CodeBuddy approach)
    # Note: Claude may have different transcript format, so this is best-effort
    if command -v jq &> /dev/null; then
        # Try parsing as JSONL (like CodeBuddy)
        jq -r 'select(.type == "function_call") | .name // empty' "$transcript_path" 2>/dev/null > "$tool_counts_file" 2>/dev/null
        
        if [ -s "$tool_counts_file" ]; then
            tool_calls=$(wc -l < "$tool_counts_file" | tr -d ' ')
            # Count MCP services
            mcp_services=$(grep '^mcp__' "$tool_counts_file" 2>/dev/null | wc -l | tr -d ' ')
            
            if [ "$tool_calls" -gt 0 ]; then
                status_line="${status_line} | \033[0;90m🔧${tool_calls}\033[0m"
            fi
            if [ "$mcp_services" -gt 0 ]; then
                status_line="${status_line} \033[0;90m🔌${mcp_services}\033[0m"
            fi
        fi
    fi
    rm -f "$tool_counts_file"
fi

# Print status line with %b to interpret escape sequences
printf "%b\n" "$status_line"
