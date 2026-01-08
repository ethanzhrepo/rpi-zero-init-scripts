#!/bin/bash
# Flash Raspberry Pi OS image to SD card
# Args: $1 = path to image file
# Returns: Path to boot partition mount point

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$PROJECT_ROOT/scripts/lib/common.sh"
source "$PROJECT_ROOT/scripts/lib/validation.sh"

# ==============================================================================
# Configuration
# ==============================================================================
IMAGE_FILE="${1:-}"

# ==============================================================================
# Functions
# ==============================================================================

# Unmount all partitions of a disk
unmount_disk() {
    local disk="$1"

    log_info "Unmounting disk: $disk"

    if ! diskutil unmountDisk "$disk" >/dev/null 2>&1; then
        log_warning "Failed to unmount $disk (may already be unmounted)"
    else
        log_success "Disk unmounted"
    fi
}

# Flash image to disk using dd
flash_image() {
    local image="$1"
    local disk="$2"

    log_step "Flashing image to SD card"

    # Use raw device for speed (e.g., /dev/disk4 -> /dev/rdisk4)
    local rdisk="${disk/\/dev\/disk/\/dev\/rdisk}"

    log_info "Image: $image"
    log_info "Target: $disk (using $rdisk for speed)"

    # Get image size for progress
    local image_size
    image_size=$(get_file_size "$image")
    local image_size_human
    image_size_human=$(get_human_size "$image_size")

    log_info "Image size: $image_size_human"

    # Check if pv is available for progress
    if command_exists pv; then
        log_info "Flashing with progress indicator..."
        log_warning "This will take 5-15 minutes depending on SD card speed"
        echo ""

        # Use pv for progress
        if ! sudo pv -tpreb "$image" | sudo dd of="$rdisk" bs=4m conv=sync; then
            log_error "Flashing failed"
            return 1
        fi
    else
        log_info "Flashing without progress indicator (install 'pv' for progress)"
        log_warning "This will take 5-15 minutes depending on SD card speed"
        log_warning "Please be patient, there will be no output until complete"
        echo ""

        # Use dd without progress
        if ! sudo dd if="$image" of="$rdisk" bs=4m conv=sync; then
            log_error "Flashing failed"
            return 1
        fi
    fi

    echo ""
    log_info "Syncing filesystem..."
    sync

    log_success "Flashing complete"
    return 0
}

# Wait for boot partition to mount
wait_for_boot_partition() {
    local disk="$1"
    local max_wait=30
    local waited=0

    log_info "Waiting for boot partition to mount..."

    # Give macOS time to recognize the new partitions
    sleep 3

    while [[ $waited -lt $max_wait ]]; do
        # Look for mounted boot partition
        local boot_mount
        boot_mount=$(diskutil list "$disk" | grep -i "boot" | awk '{print $NF}' | head -1)

        if [[ -n "$boot_mount" ]]; then
            # Check if it's mounted
            local mount_point
            mount_point=$(diskutil info "$boot_mount" 2>/dev/null | grep "Mount Point:" | cut -d: -f2- | xargs)

            if [[ -n "$mount_point" && "$mount_point" != "" ]]; then
                log_success "Boot partition mounted at: $mount_point"
                echo "$mount_point"
                return 0
            fi
        fi

        sleep 1
        ((waited++))
    done

    # If not automatically mounted, try to mount manually
    log_warning "Boot partition not automatically mounted, trying manual mount..."

    # Find boot partition (usually partition 1)
    local boot_partition="${disk}s1"

    if diskutil mount "$boot_partition" >/dev/null 2>&1; then
        local mount_point
        mount_point=$(diskutil info "$boot_partition" | grep "Mount Point:" | cut -d: -f2- | xargs)

        if [[ -n "$mount_point" ]]; then
            log_success "Boot partition mounted at: $mount_point"
            echo "$mount_point"
            return 0
        fi
    fi

    log_error "Failed to mount boot partition"
    return 1
}

# Verify boot partition contents
verify_boot_partition() {
    local mount_point="$1"

    log_info "Verifying boot partition..."

    # Check for expected files
    local expected_files=("config.txt" "cmdline.txt")
    local missing=()

    for file in "${expected_files[@]}"; do
        if [[ ! -f "$mount_point/$file" ]]; then
            missing+=("$file")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Boot partition verification failed"
        log_error "Missing expected files: ${missing[*]}"
        return 1
    fi

    log_success "Boot partition verification passed"
    return 0
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    log_step "Flash SD Card"

    # Check if image file provided
    if [[ -z "$IMAGE_FILE" ]]; then
        die "Usage: $0 <image-file>"
    fi

    # Check if image file exists
    if [[ ! -f "$IMAGE_FILE" ]]; then
        die "Image file not found: $IMAGE_FILE"
    fi

    log_info "Image file: $IMAGE_FILE"

    # Check if running on macOS
    if ! is_macos; then
        die "This script only works on macOS"
    fi

    # Find target disk
    local target_disk

    if [[ "${AUTO_DETECT_SD:-true}" == "true" ]]; then
        log_info "Auto-detecting SD card..."
        if ! target_disk=$(find_sd_card); then
            die "Failed to detect SD card"
        fi
    else
        target_disk="${TARGET_DISK:-}"
        if [[ -z "$target_disk" ]]; then
            die "TARGET_DISK not set in configuration"
        fi
    fi

    log_info "Target disk: $target_disk"

    # Validate target disk
    if ! validate_target_disk "$target_disk"; then
        die "Disk validation failed"
    fi

    # Confirm with user
    if ! confirm_disk_operation "$target_disk" "ERASE and flash"; then
        log_info "Operation cancelled by user"
        exit 1
    fi

    # Unmount disk
    unmount_disk "$target_disk"

    # Flash image
    if ! flash_image "$IMAGE_FILE" "$target_disk"; then
        die "Failed to flash image"
    fi

    # Wait for boot partition to mount
    local boot_mount
    if ! boot_mount=$(wait_for_boot_partition "$target_disk"); then
        die "Failed to mount boot partition"
    fi

    # Verify boot partition
    if ! verify_boot_partition "$boot_mount"; then
        log_warning "Boot partition verification failed, but continuing anyway"
    fi

    log_success "SD card flashed successfully"
    log_info "Boot partition: $boot_mount"

    # Return boot partition path
    echo "$boot_mount"
}

main "$@"
