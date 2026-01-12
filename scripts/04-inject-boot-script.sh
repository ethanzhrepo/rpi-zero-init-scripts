#!/bin/bash
# Inject Telegram boot notification script
# Args: $1 = boot partition mount point
#
# Strategy: Since macOS cannot mount ext4 (root partition), we use a bootstrap
# approach where we place the notification script in the boot partition (FAT32)
# and create a self-installer that runs on first boot

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$PROJECT_ROOT/scripts/lib/common.sh"

# ==============================================================================
# Configuration
# ==============================================================================
BOOT_MOUNT="${1:-}"
TEMPLATE_DIR="$PROJECT_ROOT/templates"

# ==============================================================================
# Functions
# ==============================================================================

# Create Telegram notification script from template
create_telegram_notify_script() {
    local output_file="$1"

    log_info "Creating Telegram notification script..."

    # Check if template exists
    local template="$TEMPLATE_DIR/telegram-notify.sh.tmpl"
    if [[ ! -f "$template" ]]; then
        log_error "Template not found: $template"
        return 1
    fi

    # Process template
    process_template "$template" "$output_file"

    # Make executable
    chmod +x "$output_file"

    # Verify file was created
    if [[ ! -f "$output_file" ]]; then
        log_error "Failed to create $output_file"
        return 1
    fi

    log_success "Telegram notification script created"
    return 0
}

# Create bootstrap installer script
create_bootstrap_installer() {
    local boot_mount="$1"
    local installer_script="$boot_mount/telegram-bootstrap.sh"

    log_info "Creating bootstrap installer..."

    cat > "$installer_script" << 'INSTALLER_EOF'
#!/bin/bash
# Telegram Notification Bootstrap Installer
# This script runs once on first boot and sets up the Telegram notification service

set -euo pipefail

BOOT_DIR=""
if [[ -d /boot/firmware ]]; then
    BOOT_DIR="/boot/firmware"
elif [[ -d /boot ]]; then
    BOOT_DIR="/boot"
else
    echo "Boot directory not found" >&2
    exit 1
fi

LOG_FILE="/var/log/telegram-bootstrap.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Telegram Bootstrap Installer Started ==="

# Check if already installed
if [[ -f /var/lib/telegram-notify-installed ]]; then
    log "Telegram notification already installed, exiting"
    exit 0
fi

# Copy notification script to final location
log "Installing Telegram notification script..."
cp "$BOOT_DIR/telegram-notify.sh" /usr/local/bin/telegram-notify.sh
chmod +x /usr/local/bin/telegram-notify.sh

# Create systemd service
log "Creating systemd service..."
cat > /lib/systemd/system/telegram-notify.service << 'SERVICE_EOF'
[Unit]
Description=Telegram Boot Notification
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/telegram-notify.sh
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Reload systemd
log "Enabling service..."
systemctl daemon-reload
systemctl enable telegram-notify.service

# Start service now
log "Starting service..."
systemctl start telegram-notify.service || log "Failed to start service (will retry on next boot)"

# Mark as installed
touch /var/lib/telegram-notify-installed

# Clean up bootstrap files
log "Cleaning up bootstrap files..."
rm -f "$BOOT_DIR/telegram-bootstrap.sh"

log "=== Telegram Bootstrap Installer Complete ==="
INSTALLER_EOF

    chmod +x "$installer_script"

    log_success "Bootstrap installer created"
    return 0
}

# Create systemd service that runs bootstrap on first boot
create_bootstrap_service() {
    local boot_mount="$1"
    local service_file="$boot_mount/telegram-bootstrap.service"

    log_info "Creating bootstrap service..."

    cat > "$service_file" << 'EOF'
[Unit]
Description=Telegram Notification Bootstrap
After=network.target
Before=getty@tty1.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'if [ -f /boot/firmware/telegram-bootstrap.sh ]; then exec /bin/bash /boot/firmware/telegram-bootstrap.sh; elif [ -f /boot/telegram-bootstrap.sh ]; then exec /bin/bash /boot/telegram-bootstrap.sh; fi'
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    log_success "Bootstrap service created"
    return 0
}

# Create a marker file that triggers the bootstrap
create_firstboot_marker() {
    local boot_mount="$1"

    # Create a custom script that will be run by Raspberry Pi OS on first boot
    # We'll integrate this with the existing firstboot-setup.sh if it exists

    local firstboot_script="$boot_mount/firstboot-setup.sh"

    # Append to existing firstboot script or create new one
    if [[ -f "$firstboot_script" ]]; then
        log_debug "Appending to existing firstboot script"
        cat >> "$firstboot_script" << 'EOF'

# Run Telegram bootstrap
if [[ -f /boot/firmware/telegram-bootstrap.sh ]]; then
    log "Running Telegram bootstrap..."
    bash /boot/firmware/telegram-bootstrap.sh
elif [[ -f /boot/telegram-bootstrap.sh ]]; then
    log "Running Telegram bootstrap..."
    bash /boot/telegram-bootstrap.sh
fi
EOF
    else
        # Create new firstboot script with telegram bootstrap
        cat > "$firstboot_script" << 'EOF'
#!/bin/bash
# First boot setup script with Telegram integration

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/firstboot.log
}

log "=== First Boot Setup Started ==="

# Run Telegram bootstrap
if [[ -f /boot/firmware/telegram-bootstrap.sh ]]; then
    log "Running Telegram bootstrap..."
    bash /boot/firmware/telegram-bootstrap.sh
elif [[ -f /boot/telegram-bootstrap.sh ]]; then
    log "Running Telegram bootstrap..."
    bash /boot/telegram-bootstrap.sh
fi

log "=== First Boot Setup Complete ==="
EOF

        chmod +x "$firstboot_script"
    fi

    log_success "First boot marker created"
    return 0
}

# Create rc.local integration (alternative method)
create_rc_local_integration() {
    local boot_mount="$1"
    local rc_local_addon="$boot_mount/rc.local.addon"

    log_info "Creating rc.local integration..."

    cat > "$rc_local_addon" << 'EOF'
# Telegram Bootstrap Integration
# Add this to /etc/rc.local before "exit 0"

if [ -f /boot/firmware/telegram-bootstrap.sh ]; then
    /bin/bash /boot/firmware/telegram-bootstrap.sh
elif [ -f /boot/telegram-bootstrap.sh ]; then
    /bin/bash /boot/telegram-bootstrap.sh
fi
EOF

    log_success "rc.local integration created"
    log_info "Note: rc.local.addon needs to be manually integrated into /etc/rc.local"
    return 0
}

# Create comprehensive installation instructions
create_install_instructions() {
    local boot_mount="$1"
    local instructions_file="$boot_mount/TELEGRAM-SETUP-INSTRUCTIONS.txt"

    cat > "$instructions_file" << 'EOF'
TELEGRAM NOTIFICATION SETUP INSTRUCTIONS
=========================================

The Telegram notification system has been prepared for installation.

AUTOMATIC INSTALLATION (Recommended):
-------------------------------------
The telegram-bootstrap.sh script will automatically run on first boot.
No manual steps required!

MANUAL INSTALLATION (if automatic fails):
----------------------------------------
If the automatic installation doesn't work, follow these steps after
your Raspberry Pi boots for the first time:

1. SSH into your Raspberry Pi:
   ssh pi@<your-pi-ip-address>

2. Run the bootstrap installer:
   sudo bash /boot/firmware/telegram-bootstrap.sh

3. Verify installation:
   sudo systemctl status telegram-notify.service

4. Test notification manually:
   sudo /usr/local/bin/telegram-notify.sh

TROUBLESHOOTING:
----------------
If you don't receive a notification on boot:

1. Check service status:
   sudo systemctl status telegram-notify.service

2. Check service logs:
   sudo journalctl -u telegram-notify.service

3. Test script manually:
   sudo /usr/local/bin/telegram-notify.sh

4. Check network connectivity:
   ping -c 3 api.telegram.org

5. Verify Telegram credentials:
   - Bot Token: Check with @BotFather on Telegram
   - Chat ID: Use @userinfobot to get your chat ID

DISABLING NOTIFICATIONS:
------------------------
To disable boot notifications:
   sudo systemctl disable telegram-notify.service
   sudo systemctl stop telegram-notify.service

RE-ENABLING NOTIFICATIONS:
--------------------------
To re-enable boot notifications:
   sudo systemctl enable telegram-notify.service
   sudo systemctl start telegram-notify.service

EOF

    log_success "Installation instructions created: $instructions_file"
    return 0
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    log_step "Inject Telegram Boot Script"

    # Check if Telegram is enabled
    if [[ "${ENABLE_TELEGRAM:-false}" != "true" ]]; then
        log_info "Telegram notifications disabled (ENABLE_TELEGRAM=false)"
        log_info "Skipping Telegram setup"
        return 0
    fi

    # Check if boot mount provided
    if [[ -z "$BOOT_MOUNT" ]]; then
        die "Usage: $0 <boot-partition-mount-point>"
    fi

    # Check if boot mount exists
    if [[ ! -d "$BOOT_MOUNT" ]]; then
        die "Boot partition not found: $BOOT_MOUNT"
    fi

    log_info "Boot partition: $BOOT_MOUNT"

    # Create Telegram notification script
    local notify_script="$BOOT_MOUNT/telegram-notify.sh"
    if ! create_telegram_notify_script "$notify_script"; then
        die "Failed to create Telegram notification script"
    fi

    # Create bootstrap installer
    if ! create_bootstrap_installer "$BOOT_MOUNT"; then
        die "Failed to create bootstrap installer"
    fi

    # Integrate with firstboot script
    if ! create_firstboot_marker "$BOOT_MOUNT"; then
        log_warning "Failed to create firstboot marker, continuing anyway"
    fi

    # Create installation instructions
    if ! create_install_instructions "$BOOT_MOUNT"; then
        log_warning "Failed to create instructions, continuing anyway"
    fi

    log_success "Telegram boot script injection complete"
    log_info ""
    log_info "Telegram notifications configured:"
    log_info "  - Notification script: telegram-notify.sh"
    log_info "  - Bootstrap installer: telegram-bootstrap.sh"
    log_info "  - Chat ID: ${TELEGRAM_CHAT_ID}"
    log_info ""
    log_info "The bootstrap installer will run automatically on first boot"
    log_info "You should receive a Telegram notification within 2-3 minutes after boot"
}

main "$@"
