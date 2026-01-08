#!/bin/bash
# Validation functions for Raspberry Pi initialization scripts
# Handles configuration validation and disk safety checks

# Requires common.sh to be sourced first

# ==============================================================================
# Configuration Validation
# ==============================================================================

# Validate all configuration settings
validate_config() {
    local errors=0

    log_step "Validating configuration"

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_info "Copy config/config.example.sh to config/config.sh and fill in your values"
        return 1
    fi

    # Validate WiFi configuration
    if ! validate_wifi_config; then
        ((errors++))
    fi

    # Validate network configuration
    if ! validate_network_config; then
        ((errors++))
    fi

    # Validate Telegram configuration if enabled
    if [[ "${ENABLE_TELEGRAM:-false}" == "true" ]]; then
        if ! validate_telegram_config; then
            ((errors++))
        fi
    fi

    # Validate SSH configuration if enabled
    if [[ "${ENABLE_SSH_KEY:-false}" == "true" ]]; then
        if ! validate_ssh_config; then
            ((errors++))
        fi
    fi

    # Validate version format
    if ! validate_version_format; then
        ((errors++))
    fi

    # Validate hostname
    if ! validate_hostname; then
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Configuration validation failed with $errors error(s)"
        return 1
    fi

    log_success "Configuration validation passed"
    return 0
}

# Validate WiFi configuration
validate_wifi_config() {
    local errors=0

    # Check SSID
    if [[ -z "${WIFI_SSID:-}" ]]; then
        log_error "WIFI_SSID is not set"
        ((errors++))
    elif [[ ${#WIFI_SSID} -gt 32 ]]; then
        log_error "WIFI_SSID is too long (max 32 characters)"
        ((errors++))
    fi

    # Check password
    if [[ -z "${WIFI_PASSWORD:-}" ]]; then
        log_error "WIFI_PASSWORD is not set"
        ((errors++))
    elif [[ ${#WIFI_PASSWORD} -lt 8 ]]; then
        log_warning "WIFI_PASSWORD is less than 8 characters (WPA2 requires minimum 8)"
        ((errors++))
    elif [[ ${#WIFI_PASSWORD} -gt 63 ]]; then
        log_error "WIFI_PASSWORD is too long (max 63 characters)"
        ((errors++))
    fi

    # Check for problematic characters in password
    if [[ "${WIFI_PASSWORD:-}" =~ [\$\`\"] ]]; then
        log_warning "WiFi password contains special characters (\$, \`, \") which may cause issues"
        log_warning "Consider using a simpler password if connection fails"
    fi

    # Check country code
    if [[ -z "${WIFI_COUNTRY_CODE:-}" ]]; then
        log_error "WIFI_COUNTRY_CODE is not set"
        ((errors++))
    elif [[ ! "${WIFI_COUNTRY_CODE}" =~ ^[A-Z]{2}$ ]]; then
        log_error "WIFI_COUNTRY_CODE must be a 2-letter ISO 3166-1 alpha-2 code (e.g., US, GB, DE)"
        ((errors++))
    fi

    return $errors
}

# Validate network configuration
validate_network_config() {
    local errors=0

    # If using static IP, validate all required fields
    if [[ "${USE_DHCP:-true}" == "false" ]]; then
        if [[ -z "${STATIC_IP:-}" ]]; then
            log_error "STATIC_IP is not set (required when USE_DHCP=false)"
            ((errors++))
        elif ! is_valid_ip "$STATIC_IP"; then
            log_error "STATIC_IP is not a valid IP address: $STATIC_IP"
            ((errors++))
        fi

        if [[ -z "${STATIC_GATEWAY:-}" ]]; then
            log_error "STATIC_GATEWAY is not set (required when USE_DHCP=false)"
            ((errors++))
        elif ! is_valid_ip "$STATIC_GATEWAY"; then
            log_error "STATIC_GATEWAY is not a valid IP address: $STATIC_GATEWAY"
            ((errors++))
        fi

        if [[ -z "${STATIC_DNS:-}" ]]; then
            log_warning "STATIC_DNS is not set, using default: 8.8.8.8"
        else
            # Validate each DNS server (comma-separated)
            local IFS=','
            for dns in $STATIC_DNS; do
                dns=$(trim "$dns")
                if ! is_valid_ip "$dns"; then
                    log_error "Invalid DNS server: $dns"
                    ((errors++))
                fi
            done
        fi
    fi

    return $errors
}

# Validate Telegram configuration
validate_telegram_config() {
    local errors=0

    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        log_error "TELEGRAM_BOT_TOKEN is not set (required when ENABLE_TELEGRAM=true)"
        ((errors++))
    elif [[ ! "${TELEGRAM_BOT_TOKEN}" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        log_error "TELEGRAM_BOT_TOKEN format appears invalid (expected: 123456789:ABCdef...)"
        ((errors++))
    fi

    if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_error "TELEGRAM_CHAT_ID is not set (required when ENABLE_TELEGRAM=true)"
        ((errors++))
    elif [[ ! "${TELEGRAM_CHAT_ID}" =~ ^-?[0-9]+$ ]]; then
        log_error "TELEGRAM_CHAT_ID must be numeric"
        ((errors++))
    fi

    return $errors
}

# Validate SSH configuration
validate_ssh_config() {
    local errors=0

    # Only validate if SSH key authentication is enabled
    if [[ "${ENABLE_SSH_KEY:-false}" != "true" ]]; then
        return 0
    fi

    if [[ -z "${SSH_PUBLIC_KEY:-}" ]]; then
        log_error "SSH_PUBLIC_KEY is not set (required when ENABLE_SSH_KEY=true)"
        log_info "Get your public key with: cat ~/.ssh/id_rsa.pub"
        ((errors++))
    else
        # Validate SSH public key format
        # Should start with ssh-rsa, ssh-ed25519, ecdsa-sha2-nistp256, etc.
        if [[ ! "${SSH_PUBLIC_KEY}" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+|ssh-dss)\ [A-Za-z0-9+/]+[=]{0,3}(\ .*)?$ ]]; then
            log_error "SSH_PUBLIC_KEY format appears invalid"
            log_info "Expected format: ssh-rsa AAAAB3NzaC1yc2E... user@hostname"
            log_info "Get your public key with: cat ~/.ssh/id_rsa.pub"
            ((errors++))
        fi
    fi

    # Warn if disabling password auth without SSH key
    if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]]; then
        if [[ "${ENABLE_SSH_KEY:-false}" != "true" || -z "${SSH_PUBLIC_KEY:-}" ]]; then
            log_error "Cannot disable password authentication without SSH public key"
            log_error "Set ENABLE_SSH_KEY=true and provide SSH_PUBLIC_KEY"
            ((errors++))
        else
            log_warning "Password authentication will be DISABLED"
            log_warning "Make sure your SSH key works before enabling this!"
        fi
    fi

    return $errors
}

# Validate version format
validate_version_format() {
    local version="${RPI_OS_VERSION:-latest}"

    if [[ "$version" == "latest" ]]; then
        return 0
    fi

    if [[ ! "$version" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log_error "RPI_OS_VERSION must be 'latest' or in YYYY-MM-DD format (e.g., 2025-12-09)"
        return 1
    fi

    return 0
}

# Validate hostname
validate_hostname() {
    local hostname="${HOSTNAME:-raspberrypi}"

    if [[ ! "$hostname" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log_error "HOSTNAME can only contain letters, numbers, and hyphens"
        return 1
    fi

    if [[ ${#hostname} -gt 63 ]]; then
        log_error "HOSTNAME is too long (max 63 characters)"
        return 1
    fi

    return 0
}

# ==============================================================================
# Disk Validation and Safety Checks
# ==============================================================================

# Validate target disk for SD card flashing
validate_target_disk() {
    local disk="$1"

    log_debug "Validating disk: $disk"

    # Check if disk exists
    if ! diskutil info "$disk" >/dev/null 2>&1; then
        log_error "Disk not found: $disk"
        return 1
    fi

    # Get disk information
    local disk_info
    disk_info=$(diskutil info "$disk" 2>/dev/null)

    # Check if disk is not root disk
    if echo "$disk_info" | grep -q "Mount Point.*/$"; then
        log_error "Cannot flash root disk!"
        log_error "Disk $disk contains the root filesystem"
        return 1
    fi

    # Check if disk is external/removable
    if ! echo "$disk_info" | grep -q "Removable Media:.*Yes"; then
        log_warning "Disk $disk does not appear to be removable/external"
        log_warning "This may not be an SD card!"

        if [[ "${REQUIRE_CONFIRMATION:-true}" != "true" ]]; then
            log_error "Safety check failed: disk is not removable"
            return 1
        fi
    fi

    # Check disk size is reasonable for SD card (between 1GB and 256GB)
    local size_bytes
    size_bytes=$(echo "$disk_info" | grep "Disk Size:" | awk '{print $3}' | sed 's/[^0-9]//g')

    if [[ -n "$size_bytes" ]]; then
        local size_gb=$((size_bytes / 1000000000))

        if [[ $size_gb -lt 1 ]]; then
            log_error "Disk is too small to be an SD card (less than 1GB)"
            return 1
        elif [[ $size_gb -gt 256 ]]; then
            log_warning "Disk is larger than typical SD card (> 256GB)"
            log_warning "Size: ${size_gb}GB"
        fi

        log_info "Disk size: ${size_gb}GB"
    fi

    # Check if disk is whole disk (not a partition)
    if [[ ! "$disk" =~ ^/dev/disk[0-9]+$ ]]; then
        log_error "Target must be a whole disk (e.g., /dev/disk4), not a partition"
        return 1
    fi

    return 0
}

# Display disk information
show_disk_info() {
    local disk="$1"

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "                    DISK INFORMATION"
    echo "═══════════════════════════════════════════════════════════"

    # Get disk info
    local disk_info
    disk_info=$(diskutil info "$disk" 2>/dev/null)

    # Extract and display relevant information
    local device_name size protocol removable

    device_name=$(echo "$disk_info" | grep "Device / Media Name:" | cut -d':' -f2- | xargs)
    size=$(echo "$disk_info" | grep "Disk Size:" | cut -d':' -f2 | awk '{print $1, $2}' | xargs)
    protocol=$(echo "$disk_info" | grep "Protocol:" | cut -d':' -f2 | xargs)
    removable=$(echo "$disk_info" | grep "Removable Media:" | cut -d':' -f2 | xargs)

    echo "  Device:        $disk"
    echo "  Name:          ${device_name:-Unknown}"
    echo "  Size:          ${size:-Unknown}"
    echo "  Protocol:      ${protocol:-Unknown}"
    echo "  Removable:     ${removable:-Unknown}"
    echo ""

    # Show partitions
    echo "  Partitions:"
    diskutil list "$disk" | grep -E "^\s+[0-9]:" | sed 's/^/    /'

    echo "═══════════════════════════════════════════════════════════"
    echo ""
}

# Find SD card automatically
find_sd_card() {
    log_info "Searching for SD card..."

    local candidates=()

    # List all disks
    local disks
    disks=$(diskutil list | grep "^/dev/disk" | awk '{print $1}')

    for disk in $disks; do
        # Skip disk0 (usually internal drive)
        if [[ "$disk" == "/dev/disk0" ]]; then
            continue
        fi

        # Get disk info
        local disk_info
        disk_info=$(diskutil info "$disk" 2>/dev/null)

        # Check if removable
        if echo "$disk_info" | grep -q "Removable Media:.*Yes"; then
            # Check size is reasonable (1GB - 256GB)
            local size_bytes
            size_bytes=$(echo "$disk_info" | grep "Disk Size:" | awk '{print $3}' | sed 's/[^0-9]//g')

            if [[ -n "$size_bytes" ]]; then
                local size_gb=$((size_bytes / 1000000000))

                if [[ $size_gb -ge 1 && $size_gb -le 256 ]]; then
                    candidates+=("$disk")
                fi
            fi
        fi
    done

    if [[ ${#candidates[@]} -eq 0 ]]; then
        log_error "No SD card found"
        log_info "Please insert an SD card and try again"
        return 1
    elif [[ ${#candidates[@]} -eq 1 ]]; then
        echo "${candidates[0]}"
        return 0
    else
        log_warning "Multiple removable disks found:"
        for disk in "${candidates[@]}"; do
            local size
            size=$(diskutil info "$disk" | grep "Disk Size:" | awk '{print $3, $4}')
            local name
            name=$(diskutil info "$disk" | grep "Device / Media Name:" | cut -d':' -f2- | xargs)
            echo "  $disk - $size - $name"
        done
        log_error "Please specify target disk manually in config (TARGET_DISK)"
        return 1
    fi
}

# Confirm disk operation with user
confirm_disk_operation() {
    local disk="$1"
    local operation="${2:-flash}"

    if [[ "${REQUIRE_CONFIRMATION:-true}" != "true" ]]; then
        log_warning "Skipping user confirmation (REQUIRE_CONFIRMATION=false)"
        return 0
    fi

    show_disk_info "$disk"

    echo -e "${COLOR_RED}${COLOR_BOLD}WARNING:${COLOR_RESET} This will ${operation} ${COLOR_BOLD}${disk}${COLOR_RESET}"
    echo -e "${COLOR_RED}${COLOR_BOLD}WARNING:${COLOR_RESET} ALL DATA on this disk will be PERMANENTLY ERASED!"
    echo ""

    require_confirmation "Are you sure you want to continue?" "YES"
}

# ==============================================================================
# Internet Connection Check
# ==============================================================================

# Validate internet connection
validate_internet() {
    log_info "Checking internet connection..."

    if ! has_internet; then
        log_error "No internet connection detected"
        log_info "Internet connection is required to download Raspberry Pi OS image"
        return 1
    fi

    log_success "Internet connection OK"
    return 0
}

# ==============================================================================
# Dependencies Check
# ==============================================================================

# Check required commands are available
check_dependencies() {
    local missing=()

    log_step "Checking dependencies"

    # Required commands
    local required_commands=("curl" "diskutil" "dd" "shasum")

    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
            log_error "Required command not found: $cmd"
        else
            log_debug "Found: $cmd"
        fi
    done

    # Optional but recommended commands
    if ! command_exists "pv"; then
        log_warning "Command 'pv' not found (optional)"
        log_warning "Install with: brew install pv"
        log_warning "Will use dd without progress indicator"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        return 1
    fi

    log_success "All dependencies OK"
    return 0
}

log_debug "Validation library loaded"
