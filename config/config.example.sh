#!/bin/bash
# Raspberry Pi Zero W Initialization Script Configuration
# Copy this file to config.sh and fill in your values
# WARNING: config.sh is gitignored and contains sensitive credentials

# ==============================================================================
# Raspberry Pi OS Version
# ==============================================================================
# Use "latest" to automatically download the newest version
# Or specify a specific version like "2025-12-09"
# Find versions at: https://downloads.raspberrypi.org/raspios_lite_armhf/images/
RPI_OS_VERSION="latest"

# ==============================================================================
# WiFi Configuration
# ==============================================================================
# Your WiFi network name (SSID)
WIFI_SSID="YourNetworkName"

# Your WiFi password
# Special characters are supported, but avoid using $ ` " \ if possible
WIFI_PASSWORD="YourNetworkPassword"

# WiFi country code (ISO 3166-1 alpha-2 code)
# Examples: US, GB, DE, FR, JP, CN, AU, CA
# Required for regulatory compliance
WIFI_COUNTRY_CODE="US"

# ==============================================================================
# Network Configuration
# ==============================================================================
# Use DHCP to automatically obtain IP address
# Set to false to use static IP configuration below
USE_DHCP=true

# Static IP Configuration (only used if USE_DHCP=false)
# Uncomment and set these values if you want a static IP
# STATIC_IP="192.168.1.100"
# STATIC_GATEWAY="192.168.1.1"
# STATIC_DNS="8.8.8.8,8.8.4.4"
# STATIC_NETMASK="255.255.255.0"

# ==============================================================================
# Telegram Bot Configuration (Optional)
# ==============================================================================
# Enable Telegram notifications on boot
# Set to false to disable Telegram integration
ENABLE_TELEGRAM=true

# Telegram Bot Token (get from @BotFather on Telegram)
# Example: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_BOT_TOKEN=""

# Telegram Chat ID (your user ID or group chat ID)
# Use @userinfobot on Telegram to get your chat ID
# Example: 123456789
TELEGRAM_CHAT_ID=""

# ==============================================================================
# Device Configuration
# ==============================================================================
# Hostname for your Raspberry Pi
# Will appear in your network and SSH connections
HOSTNAME="raspberrypi"

# Default username (usually 'pi' for Raspberry Pi OS)
DEFAULT_USER="pi"

# ==============================================================================
# SSH Configuration
# ==============================================================================
# Enable SSH public key authentication (recommended for security)
ENABLE_SSH_KEY=true

# SSH public key for passwordless login
# Paste your public key here (from ~/.ssh/id_rsa.pub or ~/.ssh/id_ed25519.pub)
# Example: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@hostname
SSH_PUBLIC_KEY=""

# Disable password authentication after setting up key (recommended)
# WARNING: Make sure your SSH key works before enabling this!
DISABLE_PASSWORD_AUTH=false

# ==============================================================================
# SD Card Detection
# ==============================================================================
# Automatically detect SD card
# Set to false to manually specify target disk below
AUTO_DETECT_SD=true

# Target disk (only used if AUTO_DETECT_SD=false)
# WARNING: Be EXTREMELY careful with this setting!
# Example: /dev/disk4
# TARGET_DISK="/dev/disk4"

# ==============================================================================
# Safety Options
# ==============================================================================
# Require user confirmation before flashing
# Set to false for automated/unattended operation (DANGEROUS!)
REQUIRE_CONFIRMATION=true

# Verify flash integrity after writing (slow but thorough)
# Recommended: false (flashing is generally reliable)
VERIFY_FLASH=false

# ==============================================================================
# Advanced Options
# ==============================================================================
# Enable verbose logging
VERBOSE=false

# Keep downloaded image after flashing
# Set to false to save disk space
KEEP_CACHED_IMAGES=true
