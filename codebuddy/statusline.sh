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

# Parse transcript file once and extract all needed data
if [ -n "$transcript_path" ] && [ "$transcript_path" != "null" ] && [ -f "$transcript_path" ]; then
    # Read file once into memory for processing
    first_timestamp=""
    last_timestamp=""
    
    while IFS= read -r line; do
        # Extract tokens (using sed for bash 3 compatibility)
        case "$line" in
            *'"inputTokens":'*)
                val=$(echo "$line" | sed -n 's/.*"inputTokens":\([0-9]*\).*/\1/p')
                [ -n "$val" ] && input_tokens=$((input_tokens + val))
                ;;
        esac
        case "$line" in
            *'"outputTokens":'*)
                val=$(echo "$line" | sed -n 's/.*"outputTokens":\([0-9]*\).*/\1/p')
                [ -n "$val" ] && output_tokens=$((output_tokens + val))
                ;;
        esac
        
        # Process function calls
        case "$line" in
            *'"type":"function_call"'*)
                tool_calls=$((tool_calls + 1))
                
                # Extract timestamp
                ts=$(echo "$line" | sed -n 's/.*"timestamp":\([0-9]*\).*/\1/p')
                if [ -n "$ts" ]; then
                    [ -z "$first_timestamp" ] && first_timestamp="$ts"
                    last_timestamp="$ts"
                fi
                
                # Extract tool name
                tool_name=$(echo "$line" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
                [ -n "$tool_name" ] && echo "$tool_name" >> "$tool_counts_file"
                
                # Count MCP services
                case "$tool_name" in
                    mcp__*)
                        mcp_svc=$(echo "$tool_name" | sed 's/mcp__\([^_]*\).*/\1/')
                        mcp_services_list="$mcp_services_list $mcp_svc"
                        ;;
                esac
                ;;
        esac
        
        # Count command calls in user messages
        case "$line" in
            *'"type":"message"'*'"role":"user"'*'<command-name>'*)
                command_calls=$((command_calls + 1))
                ;;
        esac
    done < "$transcript_path"
    
    # Calculate duration
    if [ -n "$first_timestamp" ] && [ -n "$last_timestamp" ]; then
        total_api_duration_ms=$((last_timestamp - first_timestamp))
        [ "$total_api_duration_ms" -gt 0 ] && runtime=$(format_duration $((total_api_duration_ms / 1000)))
    fi
    
    # Count unique MCP services
    if [ -n "$mcp_services_list" ]; then
        mcp_services=$(echo "$mcp_services_list" | tr ' ' '\n' | sort -u | grep -c . || echo "0")
    fi
fi

# Check if we're in a git repository
# Use current_dir if valid, otherwise fallback to current working directory
git_work_dir="$current_dir"
if [ "$current_dir" = "null" ] || [ "$current_dir" = "unknown" ] || [ ! -d "$current_dir" ]; then
    git_work_dir="$(pwd)"
fi

git_info=""
added_lines=""
deleted_lines=""
if git -C "$git_work_dir" rev-parse --git-dir > /dev/null 2>&1; then
    # Get current branch name
    branch=$(git -C "$git_work_dir" branch --show-current 2>/dev/null || echo "")
    if [ -n "$branch" ]; then
        # Get short commit hash (7 chars)
        commit_hash=$(git -C "$git_work_dir" rev-parse --short=7 HEAD 2>/dev/null || echo "")
        
        # Check if working directory is dirty
        if [ -z "$(git -C "$git_work_dir" status --porcelain 2>/dev/null)" ]; then
            # Clean state - show branch and hash
            git_info=" (${branch}@${commit_hash})"
        else
            # Dirty state - show branch, hash, and dirty indicator
            # Get added/deleted lines from git diff
            git_stats=$(git -C "$git_work_dir" diff --numstat 2>/dev/null)
            added_lines=""
            deleted_lines=""
            if [ -n "$git_stats" ]; then
                added=$(echo "$git_stats" | awk '{added+=$1} END {print added+0}')
                deleted=$(echo "$git_stats" | awk '{deleted+=$2} END {print deleted+0}')
                # Only show if we have actual numbers > 0
                if [ -n "$added" ] && [ "$added" -gt 0 ] 2>/dev/null; then
                    added_lines=" +${added}"
                fi
                if [ -n "$deleted" ] && [ "$deleted" -gt 0 ] 2>/dev/null; then
                    deleted_lines=" -${deleted}"
                fi
            fi
            # Combine git info with change stats
            git_info=" (${branch}@${commit_hash}${added_lines}${deleted_lines}) ✗"
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