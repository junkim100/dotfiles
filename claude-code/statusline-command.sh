#!/bin/bash

# Read JSON input
input=$(cat)

# Colors (Powerlevel10k Snazzy theme)
blue=$(printf '\033[38;2;87;199;255m')     # #57C7FF
magenta=$(printf '\033[38;2;255;106;193m') # #FF6AC1
green=$(printf '\033[38;2;90;247;142m')    # #5AF78E
yellow=$(printf '\033[38;2;243;249;157m')  # #F3F99D
grey=$(printf '\033[38;5;242m')
reset=$(printf '\033[0m')

# Separator
sep="${grey} | ${reset}"

# Get directory
dir=$(echo "$input" | jq -r '.workspace.current_dir // empty' 2>/dev/null)
[[ -z "$dir" ]] && dir="$PWD"

# 1. Project name (blue)
project=$(basename "$dir")
project_str="${blue}${project}${reset}"

# 2. Git branch (yellow if exists, grey "None" if not)
if git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    if [[ -z "$branch" ]]; then
        branch="@$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
    fi
    branch_str="${yellow}${branch}${reset}"
else
    branch_str="${grey}None${reset}"
fi

# 3. Context usage (tokens only)
tokens_str=""
usage_data=$(echo "$input" | jq '.context_window.current_usage' 2>/dev/null)
if [[ "$usage_data" != "null" ]] && [[ -n "$usage_data" ]]; then
    current=$(echo "$usage_data" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens' 2>/dev/null)
    size=$(echo "$input" | jq '.context_window.context_window_size' 2>/dev/null)
    if [[ -n "$current" ]] && [[ -n "$size" ]] && [[ "$size" -gt 0 ]]; then
        # Tokens
        if [[ $current -ge 1000 ]]; then
            current_fmt="$((current / 1000))k"
        else
            current_fmt="$current"
        fi
        if [[ $size -ge 1000 ]]; then
            size_fmt="$((size / 1000))k"
        else
            size_fmt="$size"
        fi
        tokens_str="${green}${current_fmt}/${size_fmt}${reset}"
    fi
fi

# 5. Model name (magenta)
model=$(echo "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
model_str="${magenta}${model}${reset}"

# Build output: Project | Branch | Tokens | Model
output="${project_str}${sep}${branch_str}${sep}${tokens_str}${sep}${model_str}"

printf "%s" "$output"
