#!/bin/bash
# Raspberry Pi Zero W Initialization Script
# Main orchestration script

set -euo pipefail

# ==============================================================================
# Setup
# ==============================================================================

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Configuration file
CONFIG_FILE="$PROJECT_ROOT/config/config.sh"

# Source libraries
source "$PROJECT_ROOT/scripts/lib/common.sh"
source "$PROJECT_ROOT/scripts/lib/validation.sh"
source "$PROJECT_ROOT/scripts/lib/telegram.sh"

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log_info ""
    log_info "Please copy config/config.example.sh to config/config.sh"
    log_info "and fill in your settings:"
    log_info ""
    log_info "  cp config/config.example.sh config/config.sh"
    log_info "  nano config/config.sh"
    log_info ""
    exit 1
fi

# Source configuration
source "$CONFIG_FILE"

# Create necessary directories
ensure_dir "$PROJECT_ROOT/cache/images"
ensure_dir "$PROJECT_ROOT/logs"

# Setup logging
LOG_FILE="$PROJECT_ROOT/logs/init-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ==============================================================================
# Banner
# ==============================================================================

print_banner() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║     Raspberry Pi Zero W Initialization Script                   ║
║                                                                  ║
║     This script will:                                           ║
║     1. Download Raspberry Pi OS image                           ║
║     2. Flash image to SD card                                   ║
║     3. Configure WiFi for headless access                       ║
║     4. Enable SSH                                               ║
║     5. Setup Telegram boot notifications                        ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

EOF
}

# ==============================================================================
# Main Process
# ==============================================================================

main() {
    local start_time
    start_time=$(date +%s)

    print_banner

    log_info "Started at: $(date)"
    log_info "Log file: $LOG_FILE"
    log_info ""

    # ==============================================================================
    # Step 0: Pre-flight Checks
    # ==============================================================================

    log_step "Pre-flight Checks"

    # Check dependencies
    if ! check_dependencies; then
        die "Dependency check failed"
    fi

    # Check internet connection
    if ! validate_internet; then
        die "Internet connection required"
    fi

    # ==============================================================================
    # Step 1: Validate Configuration
    # ==============================================================================

    if ! validate_config; then
        die "Configuration validation failed"
    fi

    # ==============================================================================
    # Step 2: Download and Verify Image
    # ==============================================================================

    log_step "Step 1/4: Download Raspberry Pi OS Image"

    local image_path
    image_path=$(bash "$PROJECT_ROOT/scripts/01-download-image.sh")
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        die "Failed to download image"
    fi

    if [[ -z "$image_path" || ! -f "$image_path" ]]; then
        die "Image download succeeded but file not found: $image_path"
    fi

    log_success "Image ready: $image_path"

    # ==============================================================================
    # Step 3: Flash SD Card
    # ==============================================================================

    log_step "Step 2/4: Flash SD Card"

    log_warning "This step requires sudo privileges to write to disk"
    log_warning "You will be prompted for your password"
    echo ""

    local boot_partition
    boot_partition=$(bash "$PROJECT_ROOT/scripts/02-flash-sd-card.sh" "$image_path")
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        die "Failed to flash SD card"
    fi

    if [[ -z "$boot_partition" || ! -d "$boot_partition" ]]; then
        die "SD card flashing succeeded but boot partition not found: $boot_partition"
    fi

    log_success "Boot partition mounted at: $boot_partition"

    # ==============================================================================
    # Step 4: Configure Network
    # ==============================================================================

    log_step "Step 3/4: Configure Network"

    bash "$PROJECT_ROOT/scripts/03-configure-network.sh" "$boot_partition"
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        die "Failed to configure network"
    fi

    log_success "Network configuration complete"

    # ==============================================================================
    # Step 5: Inject Telegram Boot Script
    # ==============================================================================

    log_step "Step 4/4: Setup Telegram Notifications"

    if [[ "${ENABLE_TELEGRAM:-false}" == "true" ]]; then
        bash "$PROJECT_ROOT/scripts/04-inject-boot-script.sh" "$boot_partition"
        exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            log_warning "Telegram script injection failed, but continuing"
        else
            log_success "Telegram notifications configured"
        fi
    else
        log_info "Telegram notifications disabled"
    fi

    # ==============================================================================
    # Completion
    # ==============================================================================

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║                    SETUP COMPLETE!                               ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    log_success "SD card preparation complete in ${minutes}m ${seconds}s"
    echo ""

    log_info "Next steps:"
    log_info ""
    log_info "  1. Eject the SD card:"
    log_info "     diskutil eject $boot_partition"
    log_info ""
    log_info "  2. Insert SD card into your Raspberry Pi Zero W"
    log_info ""
    log_info "  3. Power on the Raspberry Pi"
    log_info ""
    log_info "  4. Wait 2-3 minutes for first boot"
    log_info ""

    if [[ "${ENABLE_TELEGRAM:-false}" == "true" ]]; then
        log_info "  5. Check Telegram for boot notification with IP address"
        log_info ""
        log_info "  6. SSH into your Pi:"
        if [[ "${ENABLE_SSH_KEY:-false}" == "true" ]]; then
            log_info "     ssh pi@<ip-from-telegram>"
            log_info "     (Using SSH key authentication)"
        else
            log_info "     ssh pi@<ip-from-telegram>"
            log_info "     Default password: raspberry"
        fi
    else
        log_info "  5. Find your Pi's IP address from your router"
        log_info ""
        log_info "  6. SSH into your Pi:"
        if [[ "${ENABLE_SSH_KEY:-false}" == "true" ]]; then
            log_info "     ssh pi@<your-pi-ip>"
            log_info "     (Using SSH key authentication)"
        else
            log_info "     ssh pi@<your-pi-ip>"
            log_info "     Default password: raspberry"
        fi
    fi

    echo ""
    log_info "Configuration:"
    log_info "  WiFi Network: ${WIFI_SSID}"
    log_info "  Hostname: ${HOSTNAME:-raspberrypi}"

    if [[ "${USE_DHCP:-true}" != "true" ]]; then
        log_info "  Static IP: ${STATIC_IP}"
    fi

    if [[ "${ENABLE_SSH_KEY:-false}" == "true" ]]; then
        log_info "  SSH: Key authentication enabled"
        if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]]; then
            log_info "  Password auth: DISABLED (key only)"
        fi
    fi

    echo ""
    log_warning "SECURITY REMINDER:"
    if [[ "${ENABLE_SSH_KEY:-false}" != "true" ]]; then
        log_warning "Change the default password after first login:"
        log_warning "  passwd"
    else
        log_warning "Test SSH key login after first boot"
        if [[ "${DISABLE_PASSWORD_AUTH:-false}" != "true" ]]; then
            log_warning "Consider disabling password authentication after testing:"
            log_warning "  Set DISABLE_PASSWORD_AUTH=true in config"
        fi
    fi
    echo ""

    log_info "Log saved to: $LOG_FILE"
    echo ""
}

# ==============================================================================
# Error Handler
# ==============================================================================

cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo ""
        log_error "Script failed with exit code: $exit_code"
        log_info "Check the log file for details: $LOG_FILE"
        echo ""
    fi
}

trap cleanup EXIT

# ==============================================================================
# Execute Main
# ==============================================================================

main "$@"
