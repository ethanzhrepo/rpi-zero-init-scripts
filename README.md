# Raspberry Pi Zero W Initialization Scripts

Automated initialization system for Raspberry Pi Zero W with headless setup, WiFi configuration, and Telegram boot notifications.

## Features

- **Automated Image Download**: Downloads and verifies Raspberry Pi OS Lite images
- **SD Card Flashing**: Safely detects and flashes SD cards on macOS with multiple safety checks
- **Headless WiFi Setup**: Configures WiFi credentials before first boot
- **SSH Access**: Enables SSH for immediate remote access
- **SSH Key Authentication**: Configure public key authentication for passwordless, secure login
- **Telegram Notifications**: Sends system status to Telegram on every boot
- **Safety First**: Multiple validation checks prevent accidental data loss

## Quick Start

### 1. Prerequisites

**System Requirements:**
- macOS 10.15 or later
- Admin/sudo access
- Internet connection

**Install Dependencies:**
```bash
# Required: pv for progress indicator
brew install pv

# Optional: xz for image extraction (usually pre-installed)
brew install xz
```

### 2. Clone and Configure

```bash
# Clone this repository
git clone <your-repo-url>
cd rpi-zero-init-scripts

# Copy example configuration
cp config/config.example.sh config/config.sh

# Edit configuration with your settings
nano config/config.sh
```

### 3. Configure Your Settings

Edit `config/config.sh` and set at minimum:

```bash
# WiFi Configuration
WIFI_SSID="YourNetworkName"
WIFI_PASSWORD="YourPassword"
WIFI_COUNTRY_CODE="US"

# Telegram (optional but recommended)
ENABLE_TELEGRAM=true
TELEGRAM_BOT_TOKEN="your-bot-token-here"
TELEGRAM_CHAT_ID="your-chat-id-here"

# SSH Key (optional but highly recommended)
ENABLE_SSH_KEY=true
SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc... user@hostname"
```

### 4. Test Configuration (Optional)

```bash
# Test Telegram configuration
./test-telegram.sh

# Test SSH key configuration
./test-ssh-key.sh
```

### 5. Run the Script

```bash
# Insert SD card into your Mac
# Run the initialization script
./main.sh
```

The script will:
1. Download Raspberry Pi OS image (if not cached)
2. Detect your SD card
3. Ask for confirmation before flashing
4. Flash the image (requires sudo)
5. Configure WiFi and SSH
6. Setup Telegram notifications
7. Complete in 5-15 minutes

### 6. Boot Your Raspberry Pi

1. Eject the SD card safely
2. Insert into Raspberry Pi Zero W
3. Power on
4. Wait 2-3 minutes for first boot
5. Receive Telegram notification with IP address (if enabled)
6. SSH into your Pi: `ssh pi@<ip-address>`
   - Default password: `raspberry`

## Configuration Options

### WiFi Settings

```bash
WIFI_SSID="MyNetwork"           # Your WiFi network name
WIFI_PASSWORD="MyPassword"       # Your WiFi password
WIFI_COUNTRY_CODE="US"           # ISO 3166-1 alpha-2 code
```

### Network Configuration

**DHCP (Recommended):**
```bash
USE_DHCP=true
```

**Static IP:**
```bash
USE_DHCP=false
STATIC_IP="192.168.1.100"
STATIC_GATEWAY="192.168.1.1"
STATIC_DNS="8.8.8.8,8.8.4.4"
```

### SSH Configuration

**Enable SSH Key Authentication (Recommended):**
```bash
# Get your public key
cat ~/.ssh/id_rsa.pub
# or for ed25519 keys:
cat ~/.ssh/id_ed25519.pub

# Configure in config.sh
ENABLE_SSH_KEY=true
SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@hostname"
```

**Disable Password Authentication (More Secure):**
```bash
DISABLE_PASSWORD_AUTH=true
```

**Important:**
- Make sure you have the correct public key before disabling password auth
- Test SSH key login first before disabling passwords
- If you lose your private key and disabled passwords, you'll need physical access to reset

**Generate SSH Key (if you don't have one):**
```bash
# Generate ED25519 key (recommended)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Or generate RSA key
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# Display public key
cat ~/.ssh/id_ed25519.pub
```

### Telegram Notifications

**Setup:**
1. Create a Telegram bot:
   - Open Telegram and search for `@BotFather`
   - Send `/newbot` and follow prompts
   - Copy the bot token

2. Get your chat ID:
   - Search for `@userinfobot` on Telegram
   - Send `/start`
   - Copy your chat ID

3. Start conversation with your bot:
   - Search for your bot by username
   - Send `/start`

4. Configure:
```bash
ENABLE_TELEGRAM=true
TELEGRAM_BOT_TOKEN="123456789:ABCdef..."
TELEGRAM_CHAT_ID="123456789"
```

**What You'll Receive:**
On every boot, your Raspberry Pi will send a Telegram message with:
- Hostname
- IP Address
- WiFi SSID and signal strength
- Uptime
- Memory usage
- Disk usage
- CPU temperature
- Boot time

### Device Settings

```bash
HOSTNAME="raspberrypi"          # Set custom hostname
```

### Safety Options

```bash
REQUIRE_CONFIRMATION=true       # Require YES to flash
AUTO_DETECT_SD=true            # Auto-detect SD card
VERIFY_FLASH=false             # Verify after flash (slow)
```

## Project Structure

```
rpi-zero-init-scripts/
├── main.sh                          # Main entry point
├── config/
│   ├── config.example.sh            # Template configuration
│   └── config.sh                    # Your configuration (gitignored)
├── scripts/
│   ├── 01-download-image.sh         # Download & verify RPi OS
│   ├── 02-flash-sd-card.sh          # Flash SD card
│   ├── 03-configure-network.sh      # Configure WiFi/SSH
│   ├── 04-inject-boot-script.sh     # Setup Telegram
│   └── lib/
│       ├── common.sh                # Utility functions
│       ├── validation.sh            # Safety checks
│       └── telegram.sh              # Telegram helpers
├── templates/
│   ├── wpa_supplicant.conf.tmpl     # WiFi config template
│   └── telegram-notify.sh.tmpl      # Notification script
├── cache/images/                    # Downloaded images
└── logs/                            # Operation logs
```

## How It Works

### 1. Image Download

- Downloads Raspberry Pi OS Lite (armhf) from official source
- Verifies SHA256 checksum
- Caches images for reuse
- Supports version pinning or "latest"

### 2. SD Card Flashing

**Safety Checks:**
- Verifies disk is removable/external
- Checks disk size is reasonable (1-256GB)
- Ensures not flashing root disk
- Requires explicit confirmation
- Uses raw device (`/dev/rdisk`) for 5-10x faster writes

**Flashing Process:**
- Unmounts all partitions
- Uses `dd` with progress indicator (`pv`)
- Syncs filesystem
- Waits for boot partition to mount

### 3. Network Configuration

Creates configuration files in the boot partition (FAT32):

**wpa_supplicant.conf:**
- WiFi credentials and country code
- Raspberry Pi OS automatically moves this to `/etc/wpa_supplicant/`

**ssh:**
- Empty file enables SSH daemon

**dhcpcd.conf (if static IP):**
- Static IP configuration

### 4. Telegram Integration

**Bootstrap Approach:**

Since macOS cannot mount ext4 partitions, we use a clever bootstrap method:

1. Places `telegram-notify.sh` in boot partition (FAT32)
2. Creates `telegram-bootstrap.sh` installer
3. Integrates with first boot sequence
4. On first boot, the Pi:
   - Copies notification script to `/usr/local/bin/`
   - Creates systemd service
   - Enables service for future boots
   - Sends first notification

**Notification Script:**
- Waits for network to be ready
- Gathers system information
- Sends formatted message to Telegram
- Retries on failure

## Advanced Usage

### Using Specific Image Version

```bash
# In config.sh
RPI_OS_VERSION="2025-12-09"  # Use specific version
RPI_OS_VERSION="latest"       # Use latest version
```

### Manual SD Card Selection

```bash
# In config.sh
AUTO_DETECT_SD=false
TARGET_DISK="/dev/disk4"  # Specify exact disk
```

### Skip Telegram Setup

```bash
# In config.sh
ENABLE_TELEGRAM=false
```

### Multiple Configurations

Create multiple config files for different Pis:

```bash
cp config/config.sh config/config-pi1.sh
cp config/config.sh config/config-pi2.sh

# Use specific config
CONFIG_FILE=config/config-pi1.sh ./main.sh
```

## Troubleshooting

### SD Card Not Detected

**Problem:** Script can't find SD card

**Solutions:**
1. Check SD card is inserted and recognized: `diskutil list`
2. Try a different SD card reader
3. Manually specify disk in config: `TARGET_DISK="/dev/disk4"`

### WiFi Not Connecting

**Problem:** Pi doesn't connect to WiFi after boot

**Solutions:**
1. Verify WiFi credentials are correct
2. Check country code is correct for your region
3. Try a simpler password (avoid special characters)
4. Check WiFi is 2.4GHz (Pi Zero W doesn't support 5GHz)
5. SSH via Ethernet adapter and check: `sudo journalctl -u wpa_supplicant`

### SSH Connection Issues

**Problem:** Can't SSH into the Pi

**Solutions:**
1. Wait 2-3 minutes after first boot for SSH to start
2. Verify Pi is connected to network (check router or use Telegram notification)
3. Try password: `raspberry` (default)
4. Check SSH is enabled: look for `ssh` file in boot partition before booting
5. Verify firewall settings on your Mac

### SSH Key Authentication Not Working

**Problem:** SSH key login fails

**Solutions:**
1. Verify public key format is correct:
   ```bash
   cat ~/.ssh/id_rsa.pub
   # Should start with: ssh-rsa, ssh-ed25519, etc.
   ```
2. Test SSH connection with verbose output:
   ```bash
   ssh -v pi@<ip-address>
   ```
3. Check Pi logs after boot:
   ```bash
   ssh pi@<ip-address>  # Use password first
   sudo cat /var/log/firstboot-setup.log
   ```
4. Verify authorized_keys was installed:
   ```bash
   ssh pi@<ip-address>
   cat ~/.ssh/authorized_keys
   ```
5. If password auth is disabled and key doesn't work:
   - You'll need physical access
   - Mount SD card and remove `/boot/disable-password-auth`
   - Or edit `/etc/ssh/sshd_config` on the SD card's root partition

**Locked Out (Password auth disabled, key not working):**
1. Mount SD card on another computer
2. Mount root partition (ext4)
3. Edit `/etc/ssh/sshd_config`:
   - Change `PasswordAuthentication no` to `PasswordAuthentication yes`
4. Reboot Pi and fix SSH key issue

### Telegram Notifications Not Received

**Problem:** No Telegram message on boot

**Solutions:**
1. Verify bot token and chat ID are correct
2. Ensure you started conversation with bot (`/start`)
3. Check Pi has internet access
4. SSH into Pi and check service:
   ```bash
   sudo systemctl status telegram-notify.service
   sudo journalctl -u telegram-notify.service
   ```
5. Test notification manually:
   ```bash
   sudo /usr/local/bin/telegram-notify.sh
   ```

### Flashing Takes Too Long

**Problem:** SD card flash is very slow

**Solutions:**
1. Install `pv` for accurate progress: `brew install pv`
2. Use a faster SD card (Class 10 or UHS-I)
3. Try a different SD card reader (USB 3.0)
4. Normal time: 5-15 minutes depending on card speed

### Permission Denied Errors

**Problem:** Script fails with permission errors

**Solutions:**
1. Run with sudo: `sudo ./main.sh` (not recommended)
2. Script will prompt for sudo when needed for `dd`
3. Check you're in admin group: `groups`

## Security Considerations

### Credentials Storage

- `config/config.sh` contains sensitive information
- File is automatically gitignored
- Stored in plain text (consider encryption for production)
- Use `chmod 600 config/config.sh` for restricted access

### Default Password

- Default Raspberry Pi password is `raspberry`
- **CHANGE THIS IMMEDIATELY** after first login:
  ```bash
  passwd
  ```

### SSH Security

**Recommended Setup:**
1. **Use SSH Key Authentication** (enabled in this script):
   ```bash
   ENABLE_SSH_KEY=true
   SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC... user@hostname"
   ```

2. **Disable Password Authentication** (after testing key works):
   ```bash
   DISABLE_PASSWORD_AUTH=true
   ```

3. **Change Default Password** (even with key auth enabled):
   ```bash
   ssh pi@<ip-address>
   passwd
   ```

4. **Additional Hardening** (after first login):
   ```bash
   # Change default username
   sudo adduser newuser
   sudo usermod -aG sudo newuser
   sudo deluser pi

   # Configure firewall
   sudo apt install ufw
   sudo ufw allow ssh
   sudo ufw enable

   # Disable root login
   sudo nano /etc/ssh/sshd_config
   # Set: PermitRootLogin no

   # Keep system updated
   sudo apt update && sudo apt upgrade -y
   ```

**Important Notes:**
- Always test SSH key login before disabling password authentication
- Keep a backup of your private key
- Never share your private key
- Use passphrase protection on your private key

### Telegram Bot Security

- Bot token is sensitive - treat like a password
- Don't share bot token publicly
- Consider IP restrictions on bot
- Revoke and recreate bot if compromised

## FAQ

**Q: Does this work on Linux or Windows?**
A: Currently macOS only. The disk operations use macOS-specific `diskutil` commands. Linux and Windows ports are possible but not yet implemented.

**Q: Can I use Raspberry Pi OS Full instead of Lite?**
A: Yes, but you'll need to modify the download URL in `scripts/01-download-image.sh`. Change `raspios_lite_armhf` to `raspios_armhf`.

**Q: Does this work with Raspberry Pi 4?**
A: With minor modifications, yes. Change the image URL to use 64-bit images (`raspios_arm64`) and adjust accordingly.

**Q: How much disk space does this need?**
A: About 3GB: ~500MB for compressed image, ~2GB for extracted image, plus logs.

**Q: Can I run multiple Pis with different configs?**
A: Yes, create multiple config files and specify: `CONFIG_FILE=config/my-pi.sh ./main.sh`

**Q: Is the image download cached?**
A: Yes, images are cached in `cache/images/` and reused. Delete to force re-download.

**Q: Can I use WPA3 WiFi?**
A: Update the `wpa_supplicant.conf.tmpl` to change `key_mgmt=WPA-PSK` to `key_mgmt=SAE` for WPA3.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - feel free to use and modify for your needs.

## Changelog

### v1.0.0 (2026-01-07)
- Initial release
- macOS support
- Raspberry Pi Zero W support
- Automated SD card flashing
- Headless WiFi configuration
- Telegram boot notifications
- Safety checks and validation

## Credits

Created to simplify Raspberry Pi Zero W setup for headless deployments.

## Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Check the troubleshooting section above
- Review logs in `logs/` directory

---

Made with ❤️ for the Raspberry Pi community
