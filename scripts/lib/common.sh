#!/bin/bash
# Common utilities for Raspberry Pi initialization scripts
# Provides logging, colors, error handling, and helper functions

# ==============================================================================
# Color Definitions
# ==============================================================================
if [[ -t 1 ]]; then
    # Terminal supports colors
    COLOR_RESET="\033[0m"
    COLOR_RED="\033[0;31m"
    COLOR_GREEN="\033[0;32m"
    COLOR_YELLOW="\033[0;33m"
    COLOR_BLUE="\033[0;34m"
    COLOR_MAGENTA="\033[0;35m"
    COLOR_CYAN="\033[0;36m"
    COLOR_BOLD="\033[1m"
else
    # No colors in non-interactive mode
    COLOR_RESET=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_CYAN=""
    COLOR_BOLD=""
fi

# ==============================================================================
# Logging Functions
# ==============================================================================

# Print info message
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*" >&2
}

# Print success message
log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*" >&2
}

# Print warning message
log_warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $*" >&2
}

# Print error message
log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

# Print debug message (only if VERBOSE=true)
log_debug() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${COLOR_MAGENTA}[DEBUG]${COLOR_RESET} $*" >&2
    fi
}

# Print step header
log_step() {
    echo "" >&2
    echo -e "${COLOR_CYAN}${COLOR_BOLD}==> $*${COLOR_RESET}" >&2
    echo "" >&2
}

# ==============================================================================
# Error Handling
# ==============================================================================

# Print error and exit
die() {
    log_error "$*"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running on macOS
is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Require root privileges
require_root() {
    if ! is_root; then
        die "This script must be run as root (use sudo)"
    fi
}

# ==============================================================================
# File System Utilities
# ==============================================================================

# Get script directory
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -h "$source" ]]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

# Get project root directory
get_project_root() {
    local script_dir="$(get_script_dir)"
    cd "$script_dir/../.." && pwd
}

# Create directory if it doesn't exist
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_debug "Creating directory: $dir"
        mkdir -p "$dir" || die "Failed to create directory: $dir"
    fi
}

# Check if file exists
file_exists() {
    [[ -f "$1" ]]
}

# Check if directory exists
dir_exists() {
    [[ -d "$1" ]]
}

# Get file size in bytes
get_file_size() {
    if is_macos; then
        stat -f%z "$1" 2>/dev/null
    else
        stat -c%s "$1" 2>/dev/null
    fi
}

# Get human-readable file size
get_human_size() {
    local bytes="$1"
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$(( bytes / 1024 ))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$(( bytes / 1048576 ))MB"
    else
        echo "$(( bytes / 1073741824 ))GB"
    fi
}

# Get available disk space in bytes
get_free_space() {
    local path="${1:-.}"
    if is_macos; then
        df -k "$path" | awk 'NR==2 {print $4 * 1024}'
    else
        df -B1 "$path" | awk 'NR==2 {print $4}'
    fi
}

# ==============================================================================
# String Utilities
# ==============================================================================

# Trim whitespace from string
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

# Convert string to lowercase
to_lower() {
    echo "$*" | tr '[:upper:]' '[:lower:]'
}

# Convert string to uppercase
to_upper() {
    echo "$*" | tr '[:lower:]' '[:upper:]'
}

# ==============================================================================
# User Interaction
# ==============================================================================

# Ask yes/no question (default: no)
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        read -p "${prompt} [Y/n]: " response </dev/tty >&2
        response=$(to_lower "${response:-y}")
    else
        read -p "${prompt} [y/N]: " response </dev/tty >&2
        response=$(to_lower "${response:-n}")
    fi

    [[ "$response" == "y" || "$response" == "yes" ]]
}

# Require exact confirmation
require_confirmation() {
    local prompt="$1"
    local expected="${2:-YES}"
    local response

    echo -e "${COLOR_YELLOW}${COLOR_BOLD}WARNING:${COLOR_RESET} ${prompt}" >&2
    read -p "Type '$expected' to confirm: " response </dev/tty >&2

    if [[ "$response" != "$expected" ]]; then
        log_info "Confirmation failed. Aborted."
        return 1
    fi

    return 0
}

# ==============================================================================
# Progress Indicators
# ==============================================================================

# Show spinner while command runs
with_spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'

    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done

    printf "    \b\b\b\b"
    wait $pid
    return $?
}

# ==============================================================================
# Template Processing
# ==============================================================================

# Process template file by substituting variables
# Usage: process_template input_template output_file
process_template() {
    local template="$1"
    local output="$2"

    if [[ ! -f "$template" ]]; then
        die "Template file not found: $template"
    fi

    log_debug "Processing template: $template -> $output"

    # Read template and substitute variables
    local content
    content=$(<"$template")

    # Substitute {{VAR_NAME}} with ${VAR_NAME}
    # This is a simple substitution - for more complex needs, use envsubst
    while IFS= read -r line; do
        # Find all {{VAR}} patterns and replace with their values
        while [[ "$line" =~ \{\{([A-Z_][A-Z0-9_]*)\}\} ]]; do
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${!var_name}"
            line="${line//\{\{${var_name}\}\}/${var_value}}"
        done
        echo "$line"
    done < "$template" > "$output"

    log_debug "Template processed successfully"
}

# ==============================================================================
# Network Utilities
# ==============================================================================

# Check if internet connection is available
has_internet() {
    if command_exists curl; then
        curl -s --connect-timeout 5 https://www.google.com > /dev/null 2>&1
    elif command_exists wget; then
        wget -q --timeout=5 --spider https://www.google.com > /dev/null 2>&1
    else
        ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1
    fi
}

# ==============================================================================
# Validation Utilities
# ==============================================================================

# Check if string is a valid IP address
is_valid_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! $ip =~ $regex ]]; then
        return 1
    fi

    # Check each octet
    local IFS='.'
    local -a octets=($ip)
    for octet in "${octets[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done

    return 0
}

# Check if string is a valid MAC address
is_valid_mac() {
    local mac="$1"
    [[ $mac =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]
}

# ==============================================================================
# Cleanup Handlers
# ==============================================================================

# Array to store cleanup functions
declare -a CLEANUP_FUNCTIONS=()

# Register cleanup function
register_cleanup() {
    CLEANUP_FUNCTIONS+=("$1")
}

# Run all cleanup functions
run_cleanup() {
    log_debug "Running cleanup functions"
    if [[ ${#CLEANUP_FUNCTIONS[@]} -gt 0 ]]; then
        for func in "${CLEANUP_FUNCTIONS[@]}"; do
            log_debug "Running cleanup: $func"
            $func || log_warning "Cleanup function failed: $func"
        done
    fi
}

# Set trap to run cleanup on exit
trap run_cleanup EXIT INT TERM

# ==============================================================================
# Initialization
# ==============================================================================

# Check if running on macOS (required for this project)
if ! is_macos; then
    log_warning "This script is designed for macOS. Some features may not work on other platforms."
fi

log_debug "Common library loaded"
