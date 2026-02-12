# Auto-Shutdown for Android

**Set it and forget it!** This script automatically powers off your rooted Android device after you haven't used it for a while. Perfect for tablets, spare phones, or any device draining battery in your drawer.

## ✨ Features

- ⏰ **Customizable** — Change when it shuts down (default: 2.5 hours)
- 🔔 **Smart warnings** — Get notified before shutdown happens
- 😴 **Snooze** — Keep your screen on to pause the shutdown
- 🔌 **Charging aware** — Optionally skip shutdown if plugged in
- ⛔ **Easy to cancel** — Stop it anytime with one command
- 🚀 **Auto-loads** — Runs automatically on boot (needs Magisk)
- 🔋 **Battery friendly** — Smart checks that don't drain power

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

Open `autoshutdown_service.sh` and adjust these settings at the top:

```bash
WAIT_TIME=$(awk 'BEGIN {print 2.5*60*60}')   # How long until first warning (2.5 hours)
SNOOZE_TIME=$(awk 'BEGIN {print 20*60}')     # How long to pause when you snooze (20 minutes)
WARN_TIME=60                                  # Countdown to shutdown after warning (60 seconds)
CHECK_INTERVAL=30                             # How often to check screen (30 seconds)
SKIP_IF_CHARGING=0                            # Set to 1 to prevent shutdown while charging
```

**Quick settings:**
- Increase `WARN_TIME` → get more time to react to the warning
- Decrease `WAIT_TIME` → get warned sooner
- Set `SKIP_IF_CHARGING=1` → never shut down while charging

## 🎯 How It Works

Think of it like a smart timer:

1. **Boot** → Script starts automatically when your phone powers on
2. **Wait** → Your device relaxes for the configured time (default: 2.5 hours)
3. **Check** → Script checks if your screen is on
4. **Screen is ON?** → You get a warning notification with a countdown
   - If you touch/use the device → snooze for 20 minutes
   - If you ignore it → device shuts down
5. **Screen already OFF?** → Shuts down immediately (you're probably not using it anyway!)

## 📱 Usage

### Start the Timer

```bash
# After installation, just reboot your device
adb reboot
```

The script runs automatically in the background. You'll see a notification that it's active.

### Check What's Happening

```bash
# View what the script is doing
adb shell su -c "cat /data/local/tmp/shutdown_log.txt"

# Confirm it's running
adb shell su -c "ps | grep autoshutdown"
```

### Stop or Cancel the Timer

**Option 1: Quick cancel** (if you installed the stop script)
```bash
adb shell su -c "/data/local/tmp/stop_shutdown.sh"
```

**Option 2: Manual cancel**
```bash
adb shell touch /sdcard/stop_shutdown_timer
```

**Option 3: Force kill**
```bash
adb shell su -c "kill $(cat /data/local/tmp/shutdown_timer.pid)"
```

## ❓ Troubleshooting

### 🔔 Notifications aren't showing?

Some Android versions hide system notifications. Try these:
- Check if notifications are enabled for system apps in Settings
- Turn off Do Not Disturb mode
- Check the log file to confirm the script is running: `adb shell su -c "cat /data/local/tmp/shutdown_log.txt"`

### 🚀 Script won't start after reboot?

Make sure it's installed correctly:
```bash
adb shell su -c "ls -la /data/adb/service.d/autoshutdown_service.sh"
```

The file should show as executable (`-rwxr-xr-x`).

### 📝 Line ending problems?

If the script isn't running on your device, it might have Windows line endings. Use a code editor to convert `autoshutdown_service.sh` to **Unix (LF)** line endings, then reinstall.

### ⚡ Script running multiple times?

This shouldn't happen (built-in protection), but if it does:
```bash
adb shell su -c "rm -f /data/local/tmp/shutdown_timer.pid"
adb reboot
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## ⚠️ Important

This script has root access and can shut down your device. Use responsibly and at your own risk.