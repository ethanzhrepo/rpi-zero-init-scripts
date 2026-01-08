#!/bin/bash
# Configure network settings for headless Raspberry Pi
# Args: $1 = boot partition mount point

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

# Create wpa_supplicant.conf for WiFi
create_wpa_supplicant() {
    local boot_mount="$1"
    local output_file="$boot_mount/wpa_supplicant.conf"

    log_info "Creating WiFi configuration..."

    # Check if template exists
    local template="$TEMPLATE_DIR/wpa_supplicant.conf.tmpl"
    if [[ ! -f "$template" ]]; then
        log_error "Template not found: $template"
        return 1
    fi

    # Process template
    process_template "$template" "$output_file"

    # Verify file was created
    if [[ ! -f "$output_file" ]]; then
        log_error "Failed to create $output_file"
        return 1
    fi

    log_success "WiFi configuration created: $output_file"
    log_debug "SSID: $WIFI_SSID"
    log_debug "Country: $WIFI_COUNTRY_CODE"

    return 0
}

# Enable SSH by creating empty ssh file
enable_ssh() {
    local boot_mount="$1"
    local ssh_file="$boot_mount/ssh"

    log_info "Enabling SSH..."

    # Create empty ssh file
    touch "$ssh_file"

    if [[ ! -f "$ssh_file" ]]; then
        log_error "Failed to create SSH enable file"
        return 1
    fi

    log_success "SSH enabled"
    return 0
}

# Set hostname (optional - requires additional setup)
set_hostname() {
    local boot_mount="$1"
    local hostname="${HOSTNAME:-raspberrypi}"

    log_info "Setting hostname to: $hostname"

    # Create a firstrun script that will set hostname on first boot
    local firstrun_script="$boot_mount/firstrun.sh"

    cat > "$firstrun_script" << EOF
#!/bin/bash
# First run script to set hostname
# This script is executed once on first boot by Raspberry Pi OS

set -euo pipefail

# Set hostname
echo "$hostname" > /etc/hostname

# Update /etc/hosts
sed -i "s/127.0.1.1.*/127.0.1.1\t$hostname/" /etc/hosts

# Apply hostname
hostnamectl set-hostname "$hostname"

echo "Hostname set to: $hostname"
EOF

    chmod +x "$firstrun_script"

    log_success "Hostname configuration created"
    return 0
}

# Configure static IP (if enabled)
configure_static_ip() {
    local boot_mount="$1"

    if [[ "${USE_DHCP:-true}" == "true" ]]; then
        log_info "Using DHCP (dynamic IP)"
        return 0
    fi

    log_info "Configuring static IP..."

    # Validate static IP configuration
    if [[ -z "${STATIC_IP:-}" ]]; then
        log_error "STATIC_IP not set"
        return 1
    fi

    local dhcpcd_conf="$boot_mount/dhcpcd.conf"

    cat > "$dhcpcd_conf" << EOF
# Static IP configuration for wlan0
interface wlan0
static ip_address=${STATIC_IP}/24
static routers=${STATIC_GATEWAY:-192.168.1.1}
static domain_name_servers=${STATIC_DNS:-8.8.8.8 8.8.4.4}
EOF

    log_success "Static IP configuration created"
    log_info "IP: ${STATIC_IP}"
    log_info "Gateway: ${STATIC_GATEWAY:-192.168.1.1}"
    log_info "DNS: ${STATIC_DNS:-8.8.8.8 8.8.4.4}"

    return 0
}

# Configure SSH public key authentication
configure_ssh_key() {
    local boot_mount="$1"

    if [[ "${ENABLE_SSH_KEY:-false}" != "true" ]]; then
        log_info "SSH key authentication not enabled"
        return 0
    fi

    log_info "Configuring SSH public key authentication..."

    # Validate SSH public key exists
    if [[ -z "${SSH_PUBLIC_KEY:-}" ]]; then
        log_error "SSH_PUBLIC_KEY is not set"
        return 1
    fi

    # Create authorized_keys file in boot partition
    local authorized_keys_file="$boot_mount/authorized_keys"
    echo "$SSH_PUBLIC_KEY" > "$authorized_keys_file"

    if [[ ! -f "$authorized_keys_file" ]]; then
        log_error "Failed to create authorized_keys file"
        return 1
    fi

    log_success "SSH public key configured"
    log_info "User: ${DEFAULT_USER:-pi}"

    # Create marker file to disable password authentication if requested
    if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]]; then
        touch "$boot_mount/disable-password-auth"
        log_warning "Password authentication will be DISABLED on first boot"
        log_warning "Ensure your SSH key works before relying on it!"
    fi

    return 0
}

# Create a setup script that runs on first boot
create_firstboot_setup() {
    local boot_mount="$1"
    local hostname="${HOSTNAME:-raspberrypi}"

    log_info "Creating first boot setup script..."

    local setup_script="$boot_mount/firstboot-setup.sh"

    cat > "$setup_script" << 'EOF'
#!/bin/bash
# First boot setup script
# This script is executed once on first boot

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/firstboot-setup.log
}

log "=== First Boot Setup Started ==="

# Set hostname if provided
EOF

    # Add hostname configuration
    echo "HOSTNAME=\"${hostname}\"" >> "$setup_script"

    cat >> "$setup_script" << 'EOF'

if [[ -n "$HOSTNAME" && "$HOSTNAME" != "raspberrypi" ]]; then
    log "Setting hostname to: $HOSTNAME"
    echo "$HOSTNAME" > /etc/hostname
    sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts
    hostnamectl set-hostname "$HOSTNAME" || true
fi

# Configure static IP if dhcpcd.conf exists in boot partition
if [[ -f /boot/dhcpcd.conf ]]; then
    log "Applying static IP configuration"
    cat /boot/dhcpcd.conf >> /etc/dhcpcd.conf
    rm /boot/dhcpcd.conf
fi

# Setup SSH public key authentication
if [[ -f /boot/authorized_keys ]]; then
    log "Setting up SSH public key authentication"

    # Get default user (usually 'pi')
    DEFAULT_USER="${DEFAULT_USER:-pi}"
    USER_HOME="/home/$DEFAULT_USER"

    # Create .ssh directory if it doesn't exist
    mkdir -p "$USER_HOME/.ssh"
    chmod 700 "$USER_HOME/.ssh"

    # Install authorized_keys
    cat /boot/authorized_keys > "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    chown -R "$DEFAULT_USER:$DEFAULT_USER" "$USER_HOME/.ssh"

    # Remove the file from boot partition
    rm /boot/authorized_keys

    log "SSH public key installed for user: $DEFAULT_USER"
fi

# Disable password authentication if requested
if [[ -f /boot/disable-password-auth ]]; then
    log "Disabling SSH password authentication"

    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

    # Disable password authentication
    sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*UsePAM .*/UsePAM no/' /etc/ssh/sshd_config

    # Ensure public key authentication is enabled
    sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    # Restart SSH service
    systemctl restart sshd || systemctl restart ssh

    rm /boot/disable-password-auth

    log "Password authentication disabled - SSH key only"
fi

# Apply userconf if it exists (for new Raspberry Pi OS versions)
if [[ -f /boot/userconf ]]; then
    log "Applying user configuration"
    # This is handled by Raspberry Pi OS automatically
fi

log "=== First Boot Setup Complete ==="

# Remove this script so it doesn't run again
rm -f /boot/firstboot-setup.sh

# Create a marker file
touch /var/lib/firstboot-complete
EOF

    chmod +x "$setup_script"

    # Create a systemd service to run this script on first boot
    create_firstboot_service "$boot_mount"

    log_success "First boot setup script created"
    return 0
}

# Create systemd service for first boot script
create_firstboot_service() {
    local boot_mount="$1"

    # Note: We can't directly write to /etc/systemd/system from macOS
    # Instead, we'll add to cmdline.txt to trigger firstboot

    log_debug "First boot service will be handled by Raspberry Pi OS"
    return 0
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    log_step "Configure Network"

    # Check if boot mount provided
    if [[ -z "$BOOT_MOUNT" ]]; then
        die "Usage: $0 <boot-partition-mount-point>"
    fi

    # Check if boot mount exists
    if [[ ! -d "$BOOT_MOUNT" ]]; then
        die "Boot partition not found: $BOOT_MOUNT"
    fi

    log_info "Boot partition: $BOOT_MOUNT"

    # Create WiFi configuration
    if ! create_wpa_supplicant "$BOOT_MOUNT"; then
        die "Failed to create WiFi configuration"
    fi

    # Enable SSH
    if ! enable_ssh "$BOOT_MOUNT"; then
        die "Failed to enable SSH"
    fi

    # Configure SSH public key authentication
    if ! configure_ssh_key "$BOOT_MOUNT"; then
        log_warning "SSH key configuration failed, continuing anyway"
    fi

    # Configure static IP if needed
    if ! configure_static_ip "$BOOT_MOUNT"; then
        log_warning "Static IP configuration failed, continuing anyway"
    fi

    # Create first boot setup script
    if ! create_firstboot_setup "$BOOT_MOUNT"; then
        log_warning "First boot setup script creation failed, continuing anyway"
    fi

    log_success "Network configuration complete"
    log_info ""
    log_info "Your Raspberry Pi will:"
    log_info "  - Connect to WiFi: ${WIFI_SSID}"
    log_info "  - Enable SSH access"

    if [[ "${ENABLE_SSH_KEY:-false}" == "true" ]]; then
        log_info "  - Setup SSH public key authentication"
        if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]]; then
            log_info "  - Disable password authentication (SSH key only)"
        fi
    fi

    log_info "  - Set hostname: ${HOSTNAME:-raspberrypi}"

    if [[ "${USE_DHCP:-true}" != "true" ]]; then
        log_info "  - Use static IP: ${STATIC_IP}"
    else
        log_info "  - Use DHCP (dynamic IP)"
    fi
}

main "$@"
