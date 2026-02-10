# Installing Auto-Shutdown Script in /data/adb/service.d

## Quick Installation (Recommended)

### Method 1: Using ADB
```bash
# 1. Push the script to your device
adb push autoshutdown_service.sh /sdcard/

# 2. Move it to service.d and set permissions
adb shell
su
mv /sdcard/autoshutdown_service.sh /data/adb/service.d/
chmod +x /data/adb/service.d/autoshutdown_service.sh
exit
exit

# 3. Reboot
adb reboot
```

### Method 2: Using Root File Manager
1. Copy `autoshutdown_service.sh` to `/data/adb/service.d/`
2. Long-press the file → Properties → Permissions
3. Set to: `rwxr-xr-x` (755) or check all "Execute" boxes
4. Reboot

## What is /data/adb/service.d?

This is **Magisk's official boot script directory**:
- ✅ Scripts run automatically at boot
- ✅ Runs in `late_start service` mode (non-blocking)
- ✅ Executes AFTER boot completes (safe for your use case)
- ✅ Has full root access
- ✅ Survives ROM updates (as long as Magisk is reinstalled)

## Differences from Your Original Script

The `/data/adb/service.d` version includes:

1. **Boot completion wait**: 
   ```bash
   while [ "$(getprop sys.boot_completed)" != "1" ]; do
       sleep 1
   done
   ```
   Ensures Android fully boots before starting timer

2. **Proper backgrounding**:
   ```bash
   ( ... ) &
   exit 0
   ```
   Prevents blocking Magisk's boot process

3. **Everything else stays the same**: All your battery optimizations and features intact!

## Stop the Timer

Same as before - create the stop script:

```bash
# Install stop script
adb push stop_shutdown.sh /sdcard/
adb shell
su
mv /sdcard/stop_shutdown.sh /data/local/tmp/
chmod +x /data/local/tmp/stop_shutdown.sh
```

Or simply:
```bash
adb shell touch /sdcard/stop_shutdown_timer
```

## Checking Status

```bash
# View the log
adb shell su -c "cat /data/local/tmp/shutdown_log.txt"

# Check if running
adb shell su -c "cat /data/local/tmp/shutdown_timer.pid"
adb shell su -c "ps | grep autoshutdown"

# View Magisk boot log
adb shell su -c "cat /cache/magisk.log"
```

## Important Notes

### ✅ Advantages of service.d:
- Automatic execution at every boot
- No need for Tasker or other automation apps
- Survives ROM updates (if you reinstall Magisk)
- Official Magisk feature, well-supported

### ⚠️ Things to Know:
- Script must be **executable** (chmod +x)
- Script must have **Unix line endings** (LF, not CRLF)
  - If you edited on Windows, convert with: `dos2unix autoshutdown_service.sh`
  - Or use Notepad++ → Edit → EOL Conversion → Unix (LF)
- Boot process may be delayed by up to 40 seconds if script has issues
- Scripts run with Magisk's BusyBox, not Android's toybox

## Troubleshooting

**Script not running at boot?**
1. Check file permissions: `ls -l /data/adb/service.d/`
2. Check Magisk log: `cat /cache/magisk.log` (look for "service.d: exec")
3. Check for line ending issues: `cat -v /data/adb/service.d/autoshutdown_service.sh`
   - Should NOT see `^M` at line ends

**How to test without rebooting:**
```bash
su
/data/adb/service.d/autoshutdown_service.sh
```

**Disable temporarily:**
```bash
# Rename to disable
mv /data/adb/service.d/autoshutdown_service.sh /data/adb/service.d/autoshutdown_service.sh.disabled

# Re-enable
mv /data/adb/service.d/autoshutdown_service.sh.disabled /data/adb/service.d/autoshutdown_service.sh
```

**Complete removal:**
```bash
su
rm /data/adb/service.d/autoshutdown_service.sh
rm /data/local/tmp/shutdown_timer.pid
rm /data/local/tmp/shutdown_log.txt
rm /sdcard/stop_shutdown_timer
```

## Alternative: post-fs-data.d (Not Recommended)

You could also use `/data/adb/post-fs-data.d/`, but:
- ❌ Runs VERY early in boot (before most system services)
- ❌ **BLOCKS** the boot process (max 40 seconds timeout)
- ❌ Can't use `setprop` (will deadlock)
- ❌ Might not have notifications ready

**Stick with service.d for this script!**

## File Locations Summary

```
/data/adb/service.d/autoshutdown_service.sh  ← Main script (auto-runs at boot)
/data/local/tmp/stop_shutdown.sh             ← Manual stop script
/data/local/tmp/shutdown_log.txt             ← Activity log
/data/local/tmp/shutdown_timer.pid           ← Process tracker
/sdcard/stop_shutdown_timer                  ← Stop signal file
```

## Testing Your Installation

After reboot:
1. You should see notification: "⏰ Shutdown Timer Active! Will check in 2.5 hours"
2. Check log: `cat /data/local/tmp/shutdown_log.txt`
3. Should see entry with timestamp and "Timer started"

If you don't see the notification, check the Magisk log and troubleshoot above!
