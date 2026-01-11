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

# Validate target disk for SD card flashing (cross-platform wrapper)
validate_target_disk() {
    if is_macos; then
        validate_target_disk_macos "$@"
    else
        validate_target_disk_linux "$@"
    fi
}

# Validate target disk for SD card flashing (macOS)
validate_target_disk_macos() {
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

    # Check disk size is reasonable for SD card (between 1GB and 512GB)
    # Extract bytes from parentheses: "Disk Size: 62.5 GB (62534975488 Bytes)"
    local size_bytes
    size_bytes=$(echo "$disk_info" | grep "Disk Size:" | sed -n 's/.*(\([0-9]*\) Bytes).*/\1/p')

    if [[ -n "$size_bytes" ]] && [[ "$size_bytes" =~ ^[0-9]+$ ]]; then
        local size_gb=$((size_bytes / 1000000000))

        if [[ $size_gb -lt 1 ]]; then
            log_error "Disk is too small to be an SD card (less than 1GB)"
            return 1
        elif [[ $size_gb -gt 512 ]]; then
            log_warning "Disk is larger than typical SD card (> 512GB)"
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

# Validate target disk for SD card flashing (Linux)
validate_target_disk_linux() {
    local disk="$1"

    log_debug "Validating disk: $disk"

    if [[ ! -b "$disk" ]]; then
        log_error "Disk not found: $disk"
        return 1
    fi

    # Must be a whole disk device
    local disk_type
    disk_type=$(lsblk -dn -o TYPE "$disk" 2>/dev/null | head -n1)
    if [[ "$disk_type" != "disk" ]]; then
        log_error "Target must be a whole disk (e.g., /dev/sdb), not a partition"
        return 1
    fi

    # Check if this is the root disk
    local root_source root_parent
    root_source=$(findmnt -no SOURCE / 2>/dev/null || true)
    if [[ -n "$root_source" ]]; then
        root_parent=$(lsblk -no PKNAME "$root_source" 2>/dev/null | head -n1 || true)
        if [[ -n "$root_parent" && "$disk" == "/dev/${root_parent}" ]]; then
            log_error "Cannot flash root disk!"
            log_error "Disk $disk contains the root filesystem"
            return 1
        fi
    fi

    # Check removable flag
    local block_dev
    block_dev=$(basename "$disk")
    local removable="0"
    if [[ -f "/sys/block/$block_dev/removable" ]]; then
        removable=$(cat "/sys/block/$block_dev/removable" 2>/dev/null || echo "0")
    fi

    if [[ "$removable" != "1" ]]; then
        log_warning "Disk $disk does not appear to be removable/external"
        log_warning "This may not be an SD card!"

        if [[ "${REQUIRE_CONFIRMATION:-true}" != "true" ]]; then
            log_error "Safety check failed: disk is not removable"
            return 1
        fi
    fi

    # Check size is reasonable for SD card (between 1GB and 512GB)
    local size_bytes=""
    if [[ -f "/sys/block/$block_dev/size" ]]; then
        local sectors
        sectors=$(cat "/sys/block/$block_dev/size" 2>/dev/null || echo "")
        if [[ -n "$sectors" && "$sectors" =~ ^[0-9]+$ ]]; then
            size_bytes=$((sectors * 512))
        fi
    fi

    if [[ -n "$size_bytes" ]]; then
        local size_gb=$((size_bytes / 1000000000))
        if [[ $size_gb -lt 1 ]]; then
            log_error "Disk is too small to be an SD card (less than 1GB)"
            return 1
        elif [[ $size_gb -gt 512 ]]; then
            log_warning "Disk is larger than typical SD card (> 512GB)"
            log_warning "Size: ${size_gb}GB"
        fi

        log_info "Disk size: ${size_gb}GB"
    fi

    return 0
}

# Display disk information (cross-platform wrapper)
show_disk_info() {
    if is_macos; then
        show_disk_info_macos "$@"
    else
        show_disk_info_linux "$@"
    fi
}

# Display disk information (macOS)
show_disk_info_macos() {
    local disk="$1"

    echo "" >&2
    echo "═══════════════════════════════════════════════════════════" >&2
    echo "                    DISK INFORMATION" >&2
    echo "═══════════════════════════════════════════════════════════" >&2

    # Get disk info
    local disk_info
    disk_info=$(diskutil info "$disk" 2>/dev/null)

    # Extract and display relevant information
    local device_name size protocol removable location

    device_name=$(echo "$disk_info" | grep "Device / Media Name:" | cut -d':' -f2- | xargs)
    size=$(echo "$disk_info" | awk -F':' '/Disk Size:/{print $2}' | cut -d '(' -f1 | xargs)
    protocol=$(echo "$disk_info" | grep "Protocol:" | cut -d':' -f2 | xargs)
    removable=$(echo "$disk_info" | grep "Removable Media:" | cut -d':' -f2 | xargs)
    location=$(echo "$disk_info" | grep "Device Location:" | cut -d':' -f2 | xargs)

    echo "  Device:        $disk" >&2
    echo "  Name:          ${device_name:-Unknown}" >&2
    echo "  Size:          ${size:-Unknown}" >&2
    echo "  Protocol:      ${protocol:-Unknown}" >&2
    echo "  Location:      ${location:-Unknown}" >&2
    echo "  Removable:     ${removable:-Unknown}" >&2
    echo "" >&2

    # Show partitions
    echo "  Partitions:" >&2
    diskutil list "$disk" | grep -E "^\s+[0-9]:" | sed 's/^/    /' >&2

    echo "═══════════════════════════════════════════════════════════" >&2
    echo "" >&2
}

# Display disk information (Linux)
show_disk_info_linux() {
    local disk="$1"

    echo "" >&2
    echo "═══════════════════════════════════════════════════════════" >&2
    echo "                    DISK INFORMATION" >&2
    echo "═══════════════════════════════════════════════════════════" >&2

    echo "  Device:        $disk" >&2
    echo "" >&2
    echo "  Summary:" >&2
    lsblk -o NAME,SIZE,TYPE,TRAN,RM,MODEL,SERIAL "$disk" 2>/dev/null | sed 's/^/    /' >&2
    echo "" >&2
    echo "  Partitions:" >&2
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$disk" 2>/dev/null | sed 's/^/    /' >&2

    echo "═══════════════════════════════════════════════════════════" >&2
    echo "" >&2
}

# Check if disk is SD card candidate (cross-platform)
is_sd_card_candidate() {
    local disk="$1"

    if is_macos; then
        is_sd_card_candidate_macos "$disk"
    else
        is_sd_card_candidate_linux "$disk"
    fi
}

# Check if disk is SD card candidate - macOS version
is_sd_card_candidate_macos() {
    local disk="$1"

    # Get disk info
    local disk_info
    disk_info=$(diskutil info "$disk" 2>/dev/null)

    if [[ -z "$disk_info" ]]; then
        return 1
    fi

    # Extract disk information - get bytes from parentheses
    # Format: "Disk Size:  62.5 GB (62534975488 Bytes) ..."
    local size_bytes
    size_bytes=$(echo "$disk_info" | grep "Disk Size:" | sed -n 's/.*(\([0-9]*\) Bytes).*/\1/p')

    # Check size is reasonable (1GB - 512GB)
    if [[ -n "$size_bytes" ]] && [[ "$size_bytes" =~ ^[0-9]+$ ]]; then
        local size_gb=$((size_bytes / 1000000000))

        # Size must be in reasonable range for SD card
        if [[ $size_gb -lt 1 || $size_gb -gt 512 ]]; then
            log_debug "Size $size_gb GB out of range (1-512 GB)"
            return 1
        fi
        log_debug "Size check passed: $size_gb GB"
    else
        # No size info, skip
        log_debug "No size information found"
        return 1
    fi

    # First, exclude virtual disk images and other non-physical media
    local protocol
    protocol=$(echo "$disk_info" | grep "Protocol:" | cut -d':' -f2 | xargs)

    if [[ -n "$protocol" ]]; then
        # Exclude virtual disk images and other non-physical devices
        if echo "$protocol" | grep -qi -E "(disk.?image|virtual)"; then
            log_debug "Excluded virtual/disk image: $protocol"
            return 1
        fi
    fi

    # Method 1: Check if removable media (USB card readers and built-in readers)
    # Value can be "Yes" (USB) or "Removable" (built-in SD card readers)
    if echo "$disk_info" | grep -qi "Removable Media:.*\(Yes\|Removable\)"; then
        log_debug "Detected removable media"
        return 0
    fi

    # Method 2: Check for SD/Card reader in device name
    # Built-in SD card readers show as "Internal" but have "Reader" or "Card" in name
    local device_name
    device_name=$(echo "$disk_info" | grep "Device / Media Name:" | cut -d':' -f2- | xargs)

    if [[ -n "$device_name" ]]; then
        # Check for card reader keywords (case-insensitive)
        if echo "$device_name" | grep -qi -E "(reader|card|sdxc|sdhc|sd card|microsd)"; then
            log_debug "Detected card reader by name: $device_name"
            return 0
        fi
    fi

    # Method 3: Check protocol
    # SD cards may use various protocols: "Secure Digital", "SDXC", "USB", etc.

    if [[ -n "$protocol" ]]; then
        # Check for SD-related protocols (case-insensitive, partial match)
        if echo "$protocol" | grep -qi -E "(secure.?digital|sdxc|sdhc|\\bsd\\b|mmc)"; then
            log_debug "Detected SD card by protocol: $protocol"
            return 0
        fi

        # USB protocol might be card reader - check name too
        if echo "$protocol" | grep -qi "usb"; then
            if [[ -n "$device_name" ]] && echo "$device_name" | grep -qi -E "(reader|card)"; then
                log_debug "Detected USB card reader: $device_name"
                return 0
            fi
        fi
    fi

    return 1
}

# Check if disk is SD card candidate - Linux version
is_sd_card_candidate_linux() {
    local disk="$1"

    # Convert /dev/sdX or /dev/mmcblkX to block device name
    local block_dev
    block_dev=$(basename "$disk")

    # Check if device exists in /sys/block
    if [[ ! -d "/sys/block/$block_dev" ]]; then
        return 1
    fi

    # Get device size in bytes
    local size_bytes
    if [[ -f "/sys/block/$block_dev/size" ]]; then
        local sectors
        sectors=$(cat "/sys/block/$block_dev/size" 2>/dev/null)
        # Sector size is usually 512 bytes
        size_bytes=$((sectors * 512))
    else
        return 1
    fi

    # Check size is reasonable (1GB - 512GB)
    local size_gb=$((size_bytes / 1000000000))
    if [[ $size_gb -lt 1 || $size_gb -gt 512 ]]; then
        return 1
    fi

    # Method 1: Check if removable
    if [[ -f "/sys/block/$block_dev/removable" ]]; then
        local removable
        removable=$(cat "/sys/block/$block_dev/removable" 2>/dev/null)
        if [[ "$removable" == "1" ]]; then
            return 0
        fi
    fi

    # Method 2: Check device path patterns for SD/MMC
    # SD cards usually appear as /dev/mmcblk* on Linux
    if [[ "$disk" =~ /dev/mmcblk[0-9]+ ]]; then
        log_debug "Detected SD card by device path: $disk"
        return 0
    fi

    # Method 3: Check device model/vendor for card reader keywords
    if [[ -f "/sys/block/$block_dev/device/model" ]]; then
        local model
        model=$(cat "/sys/block/$block_dev/device/model" 2>/dev/null | xargs)
        if echo "$model" | grep -qi -E "(reader|card|sdxc|sdhc|sd|mmc)"; then
            log_debug "Detected card reader by model: $model"
            return 0
        fi
    fi

    return 1
}

# Find SD card with user selection (cross-platform wrapper)
find_sd_card() {
    if is_macos; then
        find_sd_card_macos
    else
        find_sd_card_linux
    fi
}

# Detect existing boot partition on a disk (cross-platform wrapper)
detect_existing_boot_partition() {
    if is_macos; then
        detect_existing_boot_partition_macos "$@"
    else
        detect_existing_boot_partition_linux "$@"
    fi
}

# Detect existing boot partition on a disk (macOS)
detect_existing_boot_partition_macos() {
    local disk="$1"

    local partitions
    partitions=$(diskutil list "$disk" | awk '/^ *[0-9]+:/{print $NF}')

    local part
    for part in $partitions; do
        local info
        info=$(diskutil info "$part" 2>/dev/null)

        if echo "$info" | grep -qiE "Volume Name:.*(boot|bootfs)"; then
            return 0
        fi

        if echo "$info" | grep -qiE "Mount Point:.*(/Volumes/)?(boot|bootfs)"; then
            return 0
        fi
    done

    return 1
}

# Detect existing boot partition on a disk (Linux)
detect_existing_boot_partition_linux() {
    local disk="$1"

    while read -r label mountpoints; do
        if [[ -n "$label" ]] && echo "$label" | grep -qiE '^(boot|bootfs)$'; then
            return 0
        fi

        if [[ -n "$mountpoints" ]] && echo "$mountpoints" | grep -qiE '/boot'; then
            return 0
        fi
    done < <(lsblk -ln -o LABEL,MOUNTPOINTS "$disk" 2>/dev/null)

    return 1
}

# Find SD card with user selection - macOS version
find_sd_card_macos() {
    log_info "Searching for available disks..."

    # Arrays to store disk information
    local -a all_disks=()
    local -a disk_sizes=()
    local -a disk_names=()
    local -a disk_protocols=()
    local -a disk_locations=()
    local -a disk_removable=()
    local -a is_candidate=()

    local root_disk=""
    local root_dev
    root_dev=$(diskutil info / 2>/dev/null | awk -F':' '/Device Identifier/{print $2}' | xargs)
    if [[ -n "$root_dev" ]]; then
        root_disk=$(diskutil info "$root_dev" 2>/dev/null | awk -F':' '/Part of Whole/{print $2}' | xargs)
    fi

    # List all disks
    local disks
    disks=$(diskutil list | grep "^/dev/disk" | awk '{print $1}')

    local candidate_count=0

    for disk in $disks; do
        # Skip root disk if detected
        if [[ -n "$root_disk" && "$disk" == "/dev/${root_disk}" ]]; then
            continue
        fi

        # Get disk info
        local disk_info
        disk_info=$(diskutil info "$disk" 2>/dev/null)

        if [[ -z "$disk_info" ]]; then
            continue
        fi

        # Skip virtual/synthesized disks
        if echo "$disk_info" | grep -qi "Virtual:.*Yes"; then
            continue
        fi

        # Extract information
        local size
        size=$(echo "$disk_info" | awk -F':' '/Disk Size:/{print $2}' | cut -d '(' -f1 | xargs)
        [[ -z "$size" ]] && size="Unknown"

        local name
        name=$(echo "$disk_info" | grep "Device / Media Name:" | cut -d':' -f2- | xargs)
        [[ -z "$name" ]] && name="Unknown"

        # Get protocol
        local protocol
        protocol=$(echo "$disk_info" | grep "Protocol:" | cut -d':' -f2 | xargs)
        [[ -z "$protocol" ]] && protocol="Unknown"

        local location
        location=$(echo "$disk_info" | grep "Device Location:" | cut -d':' -f2 | xargs)
        [[ -z "$location" ]] && location="Unknown"

        local removable
        removable=$(echo "$disk_info" | grep "Removable Media:" | cut -d':' -f2 | xargs)
        [[ -z "$removable" ]] && removable="Unknown"

        # Check if this is an SD card candidate
        local candidate="No"
        if is_sd_card_candidate "$disk"; then
            candidate="Yes"
            ((candidate_count++))
        fi

        # Store information
        all_disks+=("$disk")
        disk_sizes+=("$size")
        disk_names+=("$name")
        disk_protocols+=("$protocol")
        disk_locations+=("$location")
        disk_removable+=("$removable")
        is_candidate+=("$candidate")
    done

    # Check if any disks found
    if [[ ${#all_disks[@]} -eq 0 ]]; then
        log_error "No disks found"
        log_info "Please insert an SD card and try again"
        return 1
    fi

    if [[ $candidate_count -eq 0 ]]; then
        log_warning "No SD card candidates detected"
    else
        log_info "Found ${candidate_count} SD card candidate(s)"
    fi

    # Display selection menu (to terminal, not captured stdout)
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════" >&2
    echo "                          AVAILABLE DISKS" >&2
    echo "═══════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    printf "  %-4s %-12s %-10s %-10s %-10s %-10s %-30s %-3s\n" \
        "No." "Device" "Size" "Removable" "Protocol" "Location" "Name" "SD" >&2
    echo "───────────────────────────────────────────────────────────────────────────" >&2

    for i in "${!all_disks[@]}"; do
        local marker=" "
        local color=""
        local reset=""
        if [[ "${is_candidate[$i]}" == "Yes" ]]; then
            marker="*"
            color="${COLOR_GREEN}"
            reset="${COLOR_RESET}"
        fi

        printf "  %s%-4s %-12s %-10s %-10s %-10s %-10s %-30s %-3s%s\n" \
            "$color" \
            "$((i + 1))." \
            "${all_disks[$i]}" \
            "${disk_sizes[$i]}" \
            "${disk_removable[$i]}" \
            "${disk_protocols[$i]}" \
            "${disk_locations[$i]}" \
            "${disk_names[$i]}" \
            "$marker" \
            "$reset" >&2
    done

    echo "═══════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    log_info "Disks marked with '*' are likely SD cards"

    # Prompt user for selection (read from terminal)
    local selection
    while true; do
        read -p "Select disk number (1-${#all_disks[@]}) or 'q' to quit: " selection </dev/tty >&2

        if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
            log_info "Selection cancelled by user"
            return 1
        fi

        # Validate selection
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            if [[ $selection -ge 1 && $selection -le ${#all_disks[@]} ]]; then
                break
            fi
        fi

        log_error "Invalid selection. Please enter a number between 1 and ${#all_disks[@]}"
    done

    # Get selected disk
    local selected_index=$((selection - 1))
    local selected_disk="${all_disks[$selected_index]}"

    # Warn if selected disk is not a candidate
    if [[ "${is_candidate[$selected_index]}" != "Yes" ]]; then
        echo "" >&2
        log_warning "WARNING: Selected disk is NOT detected as an SD card candidate"
        log_warning "Disk: $selected_disk (${disk_removable[$selected_index]})"
        log_warning "This may be an internal drive or unsupported device"
        echo "" >&2

        if ! ask_yes_no "Are you sure you want to use this disk?" "n"; then
            log_info "Selection cancelled"
            return 1
        fi
    fi

    log_success "Selected disk: $selected_disk"
    echo "$selected_disk"
    return 0
}

# Find SD card with user selection - Linux version
find_sd_card_linux() {
    log_info "Searching for available disks..."

    # Arrays to store disk information
    local -a all_disks=()
    local -a disk_sizes=()
    local -a disk_names=()
    local -a disk_transports=()
    local -a disk_removable=()
    local -a disk_serials=()
    local -a disk_mounts=()
    local -a is_candidate=()

    # Determine root disk to avoid listing it
    local root_source root_parent root_disk=""
    root_source=$(findmnt -no SOURCE / 2>/dev/null || true)
    if [[ -n "$root_source" ]]; then
        root_parent=$(lsblk -no PKNAME "$root_source" 2>/dev/null | head -n1 || true)
        if [[ -n "$root_parent" ]]; then
            root_disk="/dev/${root_parent}"
        fi
    fi

    # List all block devices (excluding loop devices and partitions)
    local disk_lines
    disk_lines=$(lsblk -dn -o NAME,SIZE,MODEL,TRAN,RM,SERIAL,TYPE -P)

    local candidate_count=0

    while read -r line; do
        [[ -z "$line" ]] && continue
        eval "$line"

        if [[ "${TYPE:-}" != "disk" ]]; then
            continue
        fi

        local disk="/dev/${NAME}"
        local block_dev="${NAME}"

        # Skip root disk if detected
        if [[ -n "$root_disk" && "$disk" == "$root_disk" ]]; then
            continue
        fi

        local size="${SIZE:-Unknown}"

        local model="${MODEL:-Unknown}"
        local vendor="Unknown"
        if [[ -f "/sys/block/$block_dev/device/vendor" ]]; then
            vendor=$(cat "/sys/block/$block_dev/device/vendor" 2>/dev/null | xargs)
        fi

        local name="${vendor} ${model}"
        name=$(echo "$name" | xargs)
        [[ -z "$name" ]] && name="Unknown"

        local transport="${TRAN:-Unknown}"
        local removable="${RM:-Unknown}"
        if [[ "$removable" == "1" ]]; then
            removable="Yes"
        elif [[ "$removable" == "0" ]]; then
            removable="No"
        fi

        local serial="${SERIAL:-Unknown}"

        local mounts
        mounts=$(lsblk -ln -o MOUNTPOINTS "$disk" 2>/dev/null | awk 'NF {print}' | xargs)
        [[ -z "$mounts" ]] && mounts="-"

        # Check if this is an SD card candidate
        local candidate="No"
        if is_sd_card_candidate "$disk"; then
            candidate="Yes"
            ((candidate_count++))
        fi

        # Store information
        all_disks+=("$disk")
        disk_sizes+=("$size")
        disk_names+=("$name")
        disk_transports+=("$transport")
        disk_removable+=("$removable")
        disk_serials+=("$serial")
        disk_mounts+=("$mounts")
        is_candidate+=("$candidate")
    done <<< "$disk_lines"

    # Check if any disks found
    if [[ ${#all_disks[@]} -eq 0 ]]; then
        log_error "No disks found"
        log_info "Please insert an SD card and try again"
        return 1
    fi

    if [[ $candidate_count -eq 0 ]]; then
        log_warning "No SD card candidates detected"
    else
        log_info "Found ${candidate_count} SD card candidate(s)"
    fi

    # Display selection menu (to terminal, not captured stdout)
    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════════════════" >&2
    echo "                          AVAILABLE DISKS" >&2
    echo "═══════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    printf "  %-4s %-15s %-9s %-3s %-8s %-24s %-14s %-3s\n" \
        "No." "Device" "Size" "RM" "Tran" "Model" "Serial" "SD" >&2
    echo "───────────────────────────────────────────────────────────────────────────" >&2

    for i in "${!all_disks[@]}"; do
        local marker=" "
        local color=""
        local reset=""
        if [[ "${is_candidate[$i]}" == "Yes" ]]; then
            marker="*"
            color="${COLOR_GREEN}"
            reset="${COLOR_RESET}"
        fi

        printf "  %s%-4s %-15s %-9s %-3s %-8s %-24s %-14s %-3s%s\n" \
            "$color" \
            "$((i + 1))." \
            "${all_disks[$i]}" \
            "${disk_sizes[$i]}" \
            "${disk_removable[$i]}" \
            "${disk_transports[$i]}" \
            "${disk_names[$i]}" \
            "${disk_serials[$i]}" \
            "$marker" \
            "$reset" >&2

        if [[ -n "${disk_mounts[$i]}" && "${disk_mounts[$i]}" != "-" ]]; then
            printf "       Mounts: %s\n" "${disk_mounts[$i]}" >&2
        fi
    done

    echo "═══════════════════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    log_info "Disks marked with '*' are likely SD cards"

    # Prompt user for selection (read from terminal)
    local selection
    while true; do
        read -p "Select disk number (1-${#all_disks[@]}) or 'q' to quit: " selection </dev/tty >&2

        if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
            log_info "Selection cancelled by user"
            return 1
        fi

        # Validate selection
        if [[ "$selection" =~ ^[0-9]+$ ]]; then
            if [[ $selection -ge 1 && $selection -le ${#all_disks[@]} ]]; then
                break
            fi
        fi

        log_error "Invalid selection. Please enter a number between 1 and ${#all_disks[@]}"
    done

    # Get selected disk
    local selected_index=$((selection - 1))
    local selected_disk="${all_disks[$selected_index]}"

    # Warn if selected disk is not a candidate
    if [[ "${is_candidate[$selected_index]}" != "Yes" ]]; then
        echo "" >&2
        log_warning "WARNING: Selected disk is NOT detected as an SD card candidate"
        log_warning "Disk: $selected_disk (${disk_removable[$selected_index]})"
        log_warning "This may be an internal drive or unsupported device"
        echo "" >&2

        if ! ask_yes_no "Are you sure you want to use this disk?" "n"; then
            log_info "Selection cancelled"
            return 1
        fi
    fi

    log_success "Selected disk: $selected_disk"
    echo "$selected_disk"
    return 0
}

# Confirm disk operation with user
confirm_disk_operation() {
    local disk="$1"
    local operation="${2:-flash}"

    show_disk_info "$disk"

    if detect_existing_boot_partition "$disk"; then
        echo "" >&2
        log_warning "Detected an existing boot partition on $disk"
        log_warning "This looks like a previously flashed card and will be overwritten"
        echo "" >&2

        if [[ "${REQUIRE_CONFIRMATION:-true}" == "true" ]]; then
            if ! require_confirmation "Boot partition detected. Continue and overwrite?" "BOOT"; then
                return 1
            fi
        fi
    fi

    if [[ "${REQUIRE_CONFIRMATION:-true}" != "true" ]]; then
        log_warning "Skipping user confirmation (REQUIRE_CONFIRMATION=false)"
        return 0
    fi

    echo -e "${COLOR_RED}${COLOR_BOLD}WARNING:${COLOR_RESET} This will ${operation} ${COLOR_BOLD}${disk}${COLOR_RESET}" >&2
    echo -e "${COLOR_RED}${COLOR_BOLD}WARNING:${COLOR_RESET} ALL DATA on this disk will be PERMANENTLY ERASED!" >&2
    echo "" >&2

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
    local required_commands=("curl" "dd")

    if is_macos; then
        required_commands+=("diskutil")
        if ! command_exists shasum; then
            missing+=("shasum")
            log_error "Required command not found: shasum"
        fi
    else
        required_commands+=("lsblk" "mount" "umount" "findmnt")
        if ! command_exists sha256sum && ! command_exists shasum; then
            missing+=("sha256sum or shasum")
            log_error "Required command not found: sha256sum (or shasum)"
        fi
    fi

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
        if is_macos; then
            log_warning "Install with: brew install pv"
        else
            log_warning "Install with: apt install pv (or your distro's package manager)"
        fi
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
