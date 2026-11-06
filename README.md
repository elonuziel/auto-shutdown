# Auto-Shutdown Daemon & Controller for Rooted Android (`asds`)

A lightweight, battery-saving daemon for rooted Android devices (Magisk, KernelSU, BakaSU, and APatch) that automatically powers off the device after prolonged inactivity, with deep sleep awareness, dynamic status-bar notifications, interactive touch snoozing, and an interactive CLI controller.

Tested and validated on **Android 14 through Android 17 (LineageOS 24)**.

---

## Key Features

* **Deep Sleep Resilience:** Uses monotonic hardware uptime from `/proc/uptime` instead of fragile POSIX `sleep` loops, ensuring timers stay accurate without battery-draining CPU wakelocks.
* **Smart Touch Discrimination:** Monitors `mLastUserActivityTime` to distinguish programmatic screen wakeups from physical human contact. Wakes the screen to display a warning without falsely resetting the countdown.
* **Interactive Snooze & Cancel:** 
  * Tap the screen or press a physical button during the 60-second warning countdown to snooze for 20 minutes.
  * Snooze, stop, or query remaining time anytime via the `asds` CLI tool.
* **Reliable Notifications:** Dispatched through UID 2000 (`com.android.shell`) with public system drawables, ensuring notifications display on modern Android (13+) without permission issues.
* **Tiered Safe Shutdown:** Sequentially requests `svc power shutdown` (clean framework shutdown with animations), `setprop sys.powerctl shutdown` (disk sync and unmount), and `/system/bin/reboot -p` as fallback.
* **Built-in Interactive CLI Menu:** Full terminal control interface with live logs, real-time status monitoring, and immediate shutdown controls.

---

## System Requirements

* Android 10 - 17 (AOSP, LineageOS, PixelOS, or stock OEM ROMs)
* Root access via **KernelSU**, **BakaSU**, **Magisk**, or **APatch**
* Terminal emulator (Termux, TermOnePlus, or ADB Shell)

---

## Quick Installation

Run these commands in your root terminal (`su`):

```sh
su
cd /sdcard/Download # or the path where you cloned this repo
sh install.sh
```

### Manual Installation

1. Copy `auto_shutdown.sh` to `/data/adb/service.d/auto_shutdown.sh`.
2. Set file permissions:
   ```sh
   chmod 755 /data/adb/service.d/auto_shutdown.sh
   chown root:root /data/adb/service.d/auto_shutdown.sh
   sed -i 's/\r$//' /data/adb/service.d/auto_shutdown.sh
   ```
3. Create the `asds` symlink for global access:
   ```sh
   mkdir -p /data/adb/ksu/bin
   ln -sf /data/adb/service.d/auto_shutdown.sh /data/adb/ksu/bin/asds
   chmod 755 /data/adb/ksu/bin/asds
   ```
4. Start the service:
   ```sh
   asds restart
   ```

---

## CLI Usage (`asds`)

Typing `asds` without arguments opens the interactive menu:

```text
==========================================
       AUTO-SHUTDOWN CONTROL MENU (ASDS)  
==========================================
 Daemon Status: RUNNING (PID: 4824)
 Inactive Time: 45 min(s)
 Time to Alert: 105 min(s) (6300 seconds)
 Screen State : ASLEEP (Timer actively ticking)
==========================================
 1) Check Status & Remaining Time
 2) Snooze Shutdown (20 mins)
 3) Stop / Cancel Daemon
 4) Start / Restart Daemon
 5) View Live Log (Last 15 lines)
 6) SHUTDOWN NOW (Immediate Power Off)
 0) Exit Menu
==========================================
Select an option [0-6]: 
```

### Direct Commands

You can run individual tasks without entering the menu:

| Command | Action |
| :--- | :--- |
| `asds status` | Displays daemon status, current screen state, and countdown. |
| `asds snooze` | Immediately adds 20 minutes to the timer. |
| `asds stop` | Stops the running daemon and clears notifications. |
| `asds start` | Starts the daemon worker if not already running. |
| `asds restart` | Kills the existing worker and launches a fresh instance. |

---

## Configuration

Edit `/data/adb/service.d/auto_shutdown.sh` to customize behavior:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `INACTIVITY_TIMEOUT` | `$(( 150 * 60 ))` | Time in seconds before triggering warning (2.5 hours). |
| `WARN_TIME` | `60` | Duration in seconds of the active screen warning before shutdown. |
| `SNOOZE_TIME` | `$(( 20 * 60 ))` | Snooze duration in seconds (20 minutes). |
| `CHECK_INTERVAL` | `$(( 15 * 60 ))` | How often the daemon polls state while asleep (15 minutes). |
| `SKIP_IF_CHARGING` | `0` | Set to `1` to prevent auto-shutdown while plugged into a charger. |

---

## How It Works

```
[Boot Complete] 
       │
       ▼
[asds Daemon Starts] ──► Reads /proc/uptime & Screen State
       │
       ├──► Screen ON: Reset Inactivity Timer
       │
       └──► Screen OFF: Count Idle Duration
                 │
                 ▼
       [2.5 Hours Reached]
                 │
                 ▼
       [Turn Screen ON (`input keyevent 224`)]
                 │
                 ├──► Wait 2s for wake-up event to settle
                 ├──► Capture baseline `mLastUserActivityTime`
                 └──► Start 60-second warning countdown
                           │
       ┌───────────────────┴───────────────────┐
       ▼                                       ▼
[Touch / Button Detected]               [Zero Interaction]
       │                                       │
       ▼                                       ▼
Snooze 20 Minutes & Reset              Execute `svc power shutdown`
```

---

## License

MIT License. Feel free to modify and adapt for your ROM or custom kernel setup.