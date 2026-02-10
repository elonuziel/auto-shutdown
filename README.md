# Auto-Shutdown for Android

Automatically shuts down your rooted Android device after a period of inactivity. Great for saving battery on tablets, backup phones, or devices you don't need running 24/7.

## Features

- Configurable wait time before shutdown (default: 2.5 hours)
- Warning notification before shutting down
- Snooze by keeping screen on during warning
- Optional: skip shutdown when charging
- Easy to stop/cancel anytime
- Runs automatically on boot via Magisk
- Battery efficient with periodic checks

## Requirements

- Rooted Android device with [Magisk](https://github.com/topjohnwu/Magisk)
- ADB (Android Debug Bridge) for installation
- Android 8.0+ recommended

## Installation

### Using ADB (Recommended)

```bash
# Push the script to your device
adb push autoshutdown_service.sh /sdcard/

# Install to Magisk service.d directory
adb shell
su
mv /sdcard/autoshutdown_service.sh /data/adb/service.d/
chmod +x /data/adb/service.d/autoshutdown_service.sh
exit
exit

# Reboot to activate
adb reboot
```

### Using Root File Manager

1. Copy `autoshutdown_service.sh` to `/data/adb/service.d/`
2. Set permissions to `rwxr-xr-x` (755)
3. Reboot your device

For detailed installation instructions, see [docs/INSTALLATION.md](docs/INSTALLATION.md).

### Optional: Install Stop Script

```bash
adb push stop_shutdown.sh /sdcard/
adb shell su -c "mv /sdcard/stop_shutdown.sh /data/local/tmp/ && chmod +x /data/local/tmp/stop_shutdown.sh"
```

## ⚙️ Configuration

Edit the configuration section in `autoshutdown_service.sh`:

```bash
# Calculate times using awk (Hours * Minutes * Seconds)
WAIT_TIME=$(awk 'BEGIN {print 2.5*60*60}')   # 2.5 hours initial wait
SNOConfiguration

Edit these settings in `autoshutdown_service.sh`:

```bash
WAIT_TIME=$(awk 'BEGIN {print 2.5*60*60}')   # 2.5 hours initial wait
SNOOZE_TIME=$(awk 'BEGIN {print 20*60}')     # 20 minutes snooze
WARN_TIME=60                                  # 60 seconds warning
CHECK_INTERVAL=30                             # Check screen every 30s
SKIP_IF_CHARGING=0                            # Skip if charging (0=disabled, 1=enabled)
```
adb shell su -c "cat /data/local/tmp/shutdown_log.txt"

# Check if timer is running
adb shell su -c "cat /data/local/tmp/shutdown_timer.pid"
adb shell su -c "ps | grep autoshutdown"
```

###Usage

### Check Status

```bash
# View the log
adb shell su -c "cat /data/local/tmp/shutdown_log.txt"

# Check if running
adb shell su -c "cat /data/local/tmp/shutdown_timer.pid"
```

### Stop the Timer

```bash
# Option 1: Use stop script
adb shell su -c "/data/local/tmp/stop_shutdown.sh"

# Option 2: Create stop signal file
adb shell touch /sdcard/stop_shutdown_timer

# Option 3: Kill the process
adb shell su -c "kill $(cat /data/local/tmp/shutdown_timer.pid)"
```

### How It Works

1. Script starts automatically after boot
2. Waits for configured time (default: 2.5 hours)
3. Checks if screen is on or off
4. If screen is on: shows warning → you can keep screen on to snooze
5. If screen is off (or turned off during warning): shuts down
### Notifications Not Appearing

Some Android versions may suppress notifications. Check:
- Notification permissions for system apps
- Do Not Disturb mode settings
- Check log file to verify script is running

### Script Runs Multiple Times

TheTroubleshooting

**Script not running after reboot?**
```bash
# Check if file exists and is executable
adb shell su -c "ls -la /data/adb/service.d/autoshutdown_service.sh"
```

**Line ending issues?** Make sure the script has Unix (LF) line endings, not Windows (CRLF).

**Multiple instances running?**
```bash
adb shell su -c "rm -f /data/local/tmp/shutdown_timer.pid"
adb reboot
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Disclaimer

This script has root access and can shut down your device. Use at your own risk.