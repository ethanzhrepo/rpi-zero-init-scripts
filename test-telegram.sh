#!/bin/bash
# Test Telegram bot configuration
# Run this to verify your Telegram credentials work before flashing

set -euo pipefail

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Configuration file
CONFIG_FILE="$PROJECT_ROOT/config/config.sh"

# Source libraries
source "$PROJECT_ROOT/scripts/lib/common.sh"
source "$PROJECT_ROOT/scripts/lib/telegram.sh"

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log_info "Please create config/config.sh from config.example.sh"
    exit 1
fi

# Source configuration
source "$CONFIG_FILE"

# Main
log_step "Telegram Bot Configuration Test"

# Check if Telegram is enabled
if [[ "${ENABLE_TELEGRAM:-false}" != "true" ]]; then
    log_warning "Telegram is disabled in configuration"
    log_info "Set ENABLE_TELEGRAM=true in config/config.sh to enable"
    exit 1
fi

# Validate credentials format
log_info "Validating credentials format..."
if ! validate_telegram_credentials; then
    log_error "Telegram credentials validation failed"
    echo ""
    show_telegram_setup_instructions
    exit 1
fi

log_success "Credentials format is valid"

# Get bot info
echo ""
if ! get_bot_info; then
    log_error "Failed to connect to Telegram bot"
    log_info "Please check your bot token"
    exit 1
fi

# Send test message
echo ""
if ! test_telegram_config; then
    log_error "Failed to send test message"
    exit 1
fi

echo ""
log_success "Telegram bot is configured correctly!"
log_info "You should have received a test message in Telegram"
echo ""
