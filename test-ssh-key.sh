#!/bin/bash
# Test SSH key configuration
# Run this to verify your SSH key before flashing

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Configuration file
CONFIG_FILE="$PROJECT_ROOT/config/config.sh"

# Source libraries
source "$PROJECT_ROOT/scripts/lib/common.sh"
source "$PROJECT_ROOT/scripts/lib/validation.sh"

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log_info "Please create config/config.sh from config.example.sh"
    exit 1
fi

# Source configuration
source "$CONFIG_FILE"

# Main
log_step "SSH Key Configuration Test"

# Check if SSH key authentication is enabled
if [[ "${ENABLE_SSH_KEY:-false}" != "true" ]]; then
    log_info "SSH key authentication is not enabled"
    log_info "Set ENABLE_SSH_KEY=true in config/config.sh to enable"
    echo ""
    exit 0
fi

log_info "Testing SSH key configuration..."
echo ""

# Validate SSH key
if ! validate_ssh_config; then
    log_error "SSH configuration validation failed"
    exit 1
fi

log_success "SSH key configuration is valid!"
echo ""

# Display SSH key info
log_info "SSH Key Details:"
echo ""

# Parse key type
KEY_TYPE=$(echo "$SSH_PUBLIC_KEY" | awk '{print $1}')
KEY_DATA=$(echo "$SSH_PUBLIC_KEY" | awk '{print $2}')
KEY_COMMENT=$(echo "$SSH_PUBLIC_KEY" | awk '{$1=$2=""; print $0}' | xargs)

log_info "  Key Type: $KEY_TYPE"

# Calculate key fingerprint (if ssh-keygen available)
if command_exists ssh-keygen; then
    # Create temporary file
    TEMP_KEY=$(mktemp)
    echo "$SSH_PUBLIC_KEY" > "$TEMP_KEY"

    # Get fingerprint
    FINGERPRINT=$(ssh-keygen -lf "$TEMP_KEY" 2>/dev/null | awk '{print $2}')
    KEY_BITS=$(ssh-keygen -lf "$TEMP_KEY" 2>/dev/null | awk '{print $1}')

    rm "$TEMP_KEY"

    log_info "  Key Size: $KEY_BITS bits"
    log_info "  Fingerprint: $FINGERPRINT"
fi

if [[ -n "$KEY_COMMENT" ]]; then
    log_info "  Comment: $KEY_COMMENT"
fi

echo ""

# Check private key exists
log_info "Checking for private key..."
PRIVATE_KEY_FOUND=false

# Common private key locations
PRIVATE_KEY_PATHS=(
    "$HOME/.ssh/id_rsa"
    "$HOME/.ssh/id_ed25519"
    "$HOME/.ssh/id_ecdsa"
    "$HOME/.ssh/id_dsa"
)

for key_path in "${PRIVATE_KEY_PATHS[@]}"; do
    if [[ -f "$key_path" ]]; then
        # Check if this is the matching private key
        if command_exists ssh-keygen; then
            PUBLIC_FROM_PRIVATE=$(ssh-keygen -y -f "$key_path" 2>/dev/null || echo "")
            if [[ "$PUBLIC_FROM_PRIVATE" == "$KEY_TYPE $KEY_DATA"* ]]; then
                log_success "  Found matching private key: $key_path"
                PRIVATE_KEY_FOUND=true

                # Check permissions
                PERMS=$(stat -f "%Lp" "$key_path" 2>/dev/null || stat -c "%a" "$key_path" 2>/dev/null)
                if [[ "$PERMS" == "600" || "$PERMS" == "400" ]]; then
                    log_success "  Private key permissions: $PERMS (secure)"
                else
                    log_warning "  Private key permissions: $PERMS (should be 600)"
                    log_warning "  Fix with: chmod 600 $key_path"
                fi

                break
            fi
        fi
    fi
done

if [[ "$PRIVATE_KEY_FOUND" == "false" ]]; then
    log_warning "Could not find matching private key"
    log_warning "Make sure you have the private key that matches this public key"
fi

echo ""

# Check password auth setting
if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]]; then
    log_warning "Password authentication will be DISABLED"
    log_warning "Make sure:"
    log_warning "  1. You have access to the private key"
    log_warning "  2. The private key is on the machine you'll SSH from"
    log_warning "  3. You test SSH key login before losing password access"
    echo ""
fi

# Summary
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    TEST SUMMARY                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

log_success "SSH key format: Valid"
if [[ "$PRIVATE_KEY_FOUND" == "true" ]]; then
    log_success "Private key: Found"
else
    log_warning "Private key: Not found locally"
fi

log_info "Configuration: ${DEFAULT_USER:-pi}@raspberrypi"
if [[ "${DISABLE_PASSWORD_AUTH:-false}" == "true" ]]; then
    log_warning "Password auth: DISABLED (key only)"
else
    log_info "Password auth: Enabled (key + password)"
fi

echo ""
log_info "After flashing and booting your Pi, test connection with:"
log_info "  ssh -v ${DEFAULT_USER:-pi}@<pi-ip-address>"
echo ""
