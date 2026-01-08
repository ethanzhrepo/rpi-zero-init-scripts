#!/bin/bash
# Telegram bot helper functions
# Provides utilities for testing Telegram bot connectivity

# Requires common.sh to be sourced first

# ==============================================================================
# Telegram API Functions
# ==============================================================================

# Send a test message to Telegram
send_telegram_message() {
    local bot_token="$1"
    local chat_id="$2"
    local message="$3"

    local api_url="https://api.telegram.org/bot${bot_token}/sendMessage"

    log_debug "Sending Telegram message..."
    log_debug "Chat ID: $chat_id"

    # Send message
    local response
    response=$(curl -s -X POST "$api_url" \
        -d chat_id="$chat_id" \
        -d parse_mode="Markdown" \
        -d text="$message" 2>&1)

    # Check if successful
    if echo "$response" | grep -q '"ok":true'; then
        log_debug "Message sent successfully"
        return 0
    else
        log_error "Failed to send message"
        log_debug "Response: $response"
        return 1
    fi
}

# Test Telegram bot configuration
test_telegram_config() {
    local bot_token="${TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${TELEGRAM_CHAT_ID:-}"

    if [[ -z "$bot_token" || -z "$chat_id" ]]; then
        log_error "Telegram credentials not configured"
        return 1
    fi

    log_info "Testing Telegram bot configuration..."

    local test_message="*Test Message from RPi Initialization Script*

This is a test message to verify your Telegram bot configuration.

If you receive this message, your bot is configured correctly!

Bot Token: \`${bot_token:0:10}...\`
Chat ID: \`${chat_id}\`

_Sent at $(date '+%Y-%m-%d %H:%M:%S')_"

    if send_telegram_message "$bot_token" "$chat_id" "$test_message"; then
        log_success "Telegram bot test successful!"
        log_success "Check your Telegram app for the test message"
        return 0
    else
        log_error "Telegram bot test failed"
        log_info "Please check your bot token and chat ID"
        return 1
    fi
}

# Get bot information
get_bot_info() {
    local bot_token="${TELEGRAM_BOT_TOKEN:-}"

    if [[ -z "$bot_token" ]]; then
        log_error "Bot token not configured"
        return 1
    fi

    local api_url="https://api.telegram.org/bot${bot_token}/getMe"

    log_info "Getting bot information..."

    local response
    response=$(curl -s "$api_url")

    if echo "$response" | grep -q '"ok":true'; then
        local bot_name
        bot_name=$(echo "$response" | grep -oP '\"username\":\"[^\"]+' | cut -d'"' -f4)

        if [[ -n "$bot_name" ]]; then
            log_info "Bot username: @$bot_name"
            return 0
        fi
    else
        log_error "Failed to get bot info"
        log_error "Response: $response"
        return 1
    fi
}

# Validate Telegram credentials format
validate_telegram_credentials() {
    local bot_token="${TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${TELEGRAM_CHAT_ID:-}"

    local errors=0

    # Validate bot token format
    if [[ -z "$bot_token" ]]; then
        log_error "TELEGRAM_BOT_TOKEN is not set"
        ((errors++))
    elif [[ ! "$bot_token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        log_error "TELEGRAM_BOT_TOKEN format is invalid"
        log_error "Expected format: 123456789:ABCdef..."
        ((errors++))
    fi

    # Validate chat ID format
    if [[ -z "$chat_id" ]]; then
        log_error "TELEGRAM_CHAT_ID is not set"
        ((errors++))
    elif [[ ! "$chat_id" =~ ^-?[0-9]+$ ]]; then
        log_error "TELEGRAM_CHAT_ID must be numeric"
        ((errors++))
    fi

    return $errors
}

# Show Telegram setup instructions
show_telegram_setup_instructions() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════╗
║          TELEGRAM BOT SETUP INSTRUCTIONS                         ║
╚══════════════════════════════════════════════════════════════════╝

To enable Telegram notifications, you need to:

1. CREATE A TELEGRAM BOT:
   - Open Telegram and search for @BotFather
   - Send: /newbot
   - Follow the prompts to choose a name and username
   - Copy the bot token (looks like: 123456789:ABCdef...)

2. GET YOUR CHAT ID:
   - Search for @userinfobot on Telegram
   - Send: /start
   - Copy your ID (a number like: 123456789)

3. START A CONVERSATION WITH YOUR BOT:
   - Search for your bot by username in Telegram
   - Send: /start
   - This allows the bot to send you messages

4. UPDATE YOUR CONFIG FILE:
   - Edit: config/config.sh
   - Set TELEGRAM_BOT_TOKEN="your-token-here"
   - Set TELEGRAM_CHAT_ID="your-chat-id-here"
   - Set ENABLE_TELEGRAM=true

5. TEST YOUR CONFIGURATION:
   - Run: ./test-telegram.sh
   - You should receive a test message

For more help, visit:
https://core.telegram.org/bots#creating-a-new-bot

EOF
}

log_debug "Telegram library loaded"
