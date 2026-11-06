# Auto-Shutdown Daemon & Controller (ASDS) — Complete Root Module Guide

A battery-saving module for rooted Android devices (**Android 10 through Android 17 / LineageOS 24**) running **BakaSU**, **KernelSU**, **Magisk**, or **APatch**.

---

## Table of Contents
1. [Module Architecture & Files](#1-module-architecture--files)
   - [`module.prop`](#moduleprop)
   - [`customize.sh`](#customizesh)
   - [`service.sh`](#servicesh)
   - [`system/bin/asds`](#systembinasds)
   - [`auto_shutdown.sh` (Main Daemon & CLI)](#auto_shutdownsh)
2. [Fast Direct Install (No ZIP Required)](#2-fast-direct-install-no-zip-required)
3. [Creating the Flashable ZIP in MiXplorer](#3-creating-the-flashable-zip-in-mixplorer)
4. [CLI Command Reference & Menu Usage](#4-cli-command-reference--menu-usage)
5. [Troubleshooting & Verification](#5-troubleshooting--verification)

---

## 1. Module Architecture & Files

A standard root module layout requires only four lightweight files alongside the main daemon:

```text
asds-module.zip (or /data/adb/modules/auto_shutdown/)
├── module.prop          # Module metadata (name, version, author)
├── customize.sh         # Installer hook (sets permissions during flash)
├── service.sh           # Boot hook (starts daemon when boot completes)
├── auto_shutdown.sh     # Production daemon + interactive CLI
└── system/
    └── bin/
        └── asds         # Systemless wrapper placed into global $PATH
```

---

### `module.prop`
Module metadata shown inside KernelSU / BakaSU / Magisk Manager.

```ini
id=auto_shutdown
name=Auto-Shutdown Daemon (ASDS)
version=v2.1
versionCode=210
author=elonuziel
description=Powers off device after inactivity with deep sleep awareness, touch-to-snooze warning, and an interactive CLI controller ('asds').
```

---

### `customize.sh`
Executed by the root manager app when installing or flashing the module.

```sh
#!/system/bin/sh

# Set full execution permissions
set_perm_recursive "$MODPATH" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/auto_shutdown.sh" 0 0 0755
set_perm "$MODPATH/system/bin/asds" 0 0 0755

ui_print "****************************************"
ui_print "  Auto-Shutdown Daemon (ASDS) Installed "
ui_print "  Control CLI: Type 'asds' as root      "
ui_print "****************************************"
```

---

### `service.sh`
Late-start service executed in the background immediately after the system finishes booting.

```sh
#!/system/bin/sh
MODDIR="${0%/*}"

# Wait until Android framework finishes booting
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Start the background daemon
/system/bin/sh "$MODDIR/auto_shutdown.sh" start
```

---

### `system/bin/asds`
Provides the `asds` CLI command across any terminal emulator without requiring custom environment variables.

```sh
#!/system/bin/sh

# Detect module location across all root frameworks
if [ -d "/data/adb/modules/auto_shutdown" ]; then
    MODDIR="/data/adb/modules/auto_shutdown"
elif [ -d "/data/adb/modules_update/auto_shutdown" ]; then
    MODDIR="/data/adb/modules_update/auto_shutdown"
else
    MODDIR="/data/adb/service.d"
fi

SCRIPT="$MODDIR/auto_shutdown.sh"

if [ ! -f "$SCRIPT" ]; then
    echo "[!] Error: auto_shutdown.sh not found in $MODDIR"
    exit 1
fi

exec /system/bin/sh "$SCRIPT" "$@"
```

---

### `auto_shutdown.sh`
The core engine: handles deep sleep timing via `/proc/uptime`, touch detection via `mLastUserActivityTime`, visual warnings, shell-level status notifications, clean multi-tier shutdowns, and the interactive terminal menu.

```sh
#!/system/bin/sh

# =============================================================================
# AUTO-SHUTDOWN DAEMON & CONTROLLER (ASDS)
# Platform: Android 14 - 17 / LineageOS 24
# Supported Root Environments: BakaSU / KernelSU / Magisk / APatch
# =============================================================================

# --- CONFIGURATION ---
INACTIVITY_TIMEOUT=$(( 150 * 60 ))    # 2.5 Hours (9000 seconds)
WARN_TIME=60                          # 60s countdown warning before shutdown
SNOOZE_TIME=$(( 20 * 60 ))            # 20m snooze duration
CHECK_INTERVAL=$(( 15 * 60 ))         # Polling interval: 15 minutes (900s)
SKIP_IF_CHARGING=0                    # 1 = Do not shutdown while charging

# Temporary runtime files in device-encrypted ramdisk
LOG_FILE="/data/local/tmp/shutdown_log.txt"
STOP_FILE="/data/local/tmp/stop_shutdown_timer"
SNOOZE_FILE="/data/local/tmp/snooze_shutdown_timer"
PID_FILE="/data/local/tmp/shutdown_timer.pid"
STATE_FILE="/data/local/tmp/shutdown_last_active"

# --- CORE UTILITIES ---

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

get_boottime_sec() {
    # /proc/uptime includes time elapsed during hardware deep sleep
    read -r up _ < /proc/uptime
    echo "${up%%.*}"
}

get_last_user_activity() {
    # Captures physical touchscreen taps and hardware button presses
    dumpsys power 2>/dev/null | grep -m1 "mLastUserActivityTime" | grep -oE '[0-9]+'
}

send_notif() {
    # Dispatched via Shell UID 2000 with a public Android drawable
    su 2000 -c "cmd notification post -i @android:drawable/stat_sys_warning -S bigtext -t \"$1\" 'autoshutdown' \"$2\"" > /dev/null 2>&1
}

is_screen_on() {
    dumpsys power 2>/dev/null | grep -q "mWakefulness=Awake"
}

is_charging() {
    dumpsys battery 2>/dev/null | grep -Eqi "(AC|USB|Wireless|Dock) powered: true"
}

execute_shutdown() {
    log_msg "Initiating power off..."
    send_notif "Auto-Shutdown" "Shutting down device now..."
    sleep 2
    
    # Tier 1: Clean framework shutdown with animation
    svc power shutdown >/dev/null 2>&1
    sleep 3
    
    # Tier 2: Init powerctl disk sync & unmount
    setprop sys.powerctl shutdown >/dev/null 2>&1
    sleep 3
    
    # Tier 3: Direct kernel poweroff fallback
    /system/bin/reboot -p >/dev/null 2>&1 || reboot -p
}

get_daemon_pid() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "$PID"
            return 0
        fi
    fi
    echo ""
    return 1
}

# --- BACKGROUND DAEMON ---

run_daemon() {
    echo $$ > "$PID_FILE"

    trap 'rm -f "$PID_FILE"; log_msg "Daemon stopped."; exit 0' EXIT INT TERM

    # Ensure shell notification permissions on Android 13+
    pm grant com.android.shell android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
    cmd appops set com.android.shell POST_NOTIFICATION allow >/dev/null 2>&1

    log_msg "Shutdown daemon active (PID: $$). Inactivity limit: ${INACTIVITY_TIMEOUT}s."
    rm -f "$STOP_FILE" "$SNOOZE_FILE"

    send_notif "Auto-Shutdown Active" "Timer started. Shuts down after 2.5h of inactivity."

    LAST_ACTIVE=$(get_boottime_sec)
    echo "$LAST_ACTIVE" > "$STATE_FILE"

    while true; do
        # 1. External cancel / stop check
        if [ -f "$STOP_FILE" ]; then
            log_msg "Stop signal detected. Exiting daemon."
            send_notif "Auto-Shutdown Cancelled" "Inactivity timer has been manually stopped."
            rm -f "$STOP_FILE"
            exit 0
        fi

        # 2. External snooze check from CLI menu
        if [ -f "$SNOOZE_FILE" ]; then
            log_msg "Manual snooze triggered via CLI."
            rm -f "$SNOOZE_FILE"
            NOW=$(get_boottime_sec)
            LAST_ACTIVE=$(( NOW - INACTIVITY_TIMEOUT + SNOOZE_TIME ))
            echo "$LAST_ACTIVE" > "$STATE_FILE"
            send_notif "Shutdown Snoozed" "Snoozed for $(( SNOOZE_TIME / 60 )) minutes via CLI."
            sleep "$CHECK_INTERVAL"
            continue
        fi

        # 3. Charging bypass
        if [ "$SKIP_IF_CHARGING" -eq 1 ] && is_charging; then
            LAST_ACTIVE=$(get_boottime_sec)
            echo "$LAST_ACTIVE" > "$STATE_FILE"
            send_notif "Auto-Shutdown Paused" "Device is charging. Timer suspended."
            sleep "$CHECK_INTERVAL"
            continue
        fi

        CURRENT_TIME=$(get_boottime_sec)

        # 4. Screen awake check (resets timer while in use)
        if is_screen_on; then
            LAST_ACTIVE="$CURRENT_TIME"
            echo "$LAST_ACTIVE" > "$STATE_FILE"
            send_notif "Auto-Shutdown Active" "Screen is ON. Timer resets until screen turns off."
            sleep "$CHECK_INTERVAL"
            continue
        fi

        # 5. Inactivity calculation
        IDLE_DURATION=$(( CURRENT_TIME - LAST_ACTIVE ))
        REMAINING_SECS=$(( INACTIVITY_TIMEOUT - IDLE_DURATION ))

        if [ "$REMAINING_SECS" -gt 0 ]; then
            REMAINING_MINS=$(( (REMAINING_SECS + 59) / 60 ))
            send_notif "Auto-Shutdown Monitoring" "Device idle. Shutting down in approx ${REMAINING_MINS}m."

            if [ "$REMAINING_SECS" -lt "$CHECK_INTERVAL" ]; then
                sleep "$REMAINING_SECS"
            else
                sleep "$CHECK_INTERVAL"
            fi
        else
            log_msg "Inactivity limit reached (${IDLE_DURATION}s). Starting 60s warning."

            # 1. Wake screen to display warning
            input keyevent 224

            # 2. Settle delay: allow wake transition to complete before capturing baseline
            sleep 2
            BASE_USER_ACT=$(get_last_user_activity)

            WARN_REMAINING="$WARN_TIME"
            ABORT_SHUTDOWN=0

            while [ "$WARN_REMAINING" -gt 0 ]; do
                send_notif "SHUTDOWN IMMINENT" "Shutting down in ${WARN_REMAINING}s! Touch screen or unlock to cancel."

                sleep 5
                WARN_REMAINING=$(( WARN_REMAINING - 5 ))

                CURRENT_USER_ACT=$(get_last_user_activity)

                # Physical touch or hardware button press detection
                if [ -n "$BASE_USER_ACT" ] && [ -n "$CURRENT_USER_ACT" ]; then
                    if [ "$CURRENT_USER_ACT" -gt "$BASE_USER_ACT" ]; then
                        log_msg "Physical touch detected during warning. Snoozing for ${SNOOZE_TIME}s."
                        send_notif "Shutdown Snoozed" "Touch detected. Snoozing for 20 minutes."
                        ABORT_SHUTDOWN=1
                        break
                    fi
                fi

                if [ -f "$STOP_FILE" ]; then
                    log_msg "Stop file created during countdown. Aborting."
                    send_notif "Auto-Shutdown Cancelled" "Timer cancelled."
                    rm -f "$STOP_FILE"
                    exit 0
                fi
            done

            if [ "$ABORT_SHUTDOWN" -eq 1 ]; then
                NOW=$(get_boottime_sec)
                LAST_ACTIVE=$(( NOW - INACTIVITY_TIMEOUT + SNOOZE_TIME ))
                echo "$LAST_ACTIVE" > "$STATE_FILE"
                sleep "$CHECK_INTERVAL"
            else
                execute_shutdown
                exit 0
            fi
        fi
    done
}

# --- CONTROL ACTIONS ---

start_daemon() {
    PID=$(get_daemon_pid)
    if [ -n "$PID" ]; then
        echo "[!] Daemon is ALREADY running (PID: $PID)."
        return 0
    fi
    rm -f "$STOP_FILE"
    /system/bin/sh "$0" --worker >/dev/null 2>&1 &
    sleep 1
    NEW_PID=$(get_daemon_pid)
    if [ -n "$NEW_PID" ]; then
        echo "[+] Daemon started successfully (PID: $NEW_PID)."
    else
        echo "[-] Failed to start daemon. Check $LOG_FILE."
    fi
}

stop_daemon() {
    PID=$(get_daemon_pid)
    if [ -z "$PID" ]; then
        echo "[!] Daemon is not running."
        rm -f "$PID_FILE" "$STOP_FILE"
        return 0
    fi
    echo "[*] Sending stop signal to PID $PID..."
    touch "$STOP_FILE"
    kill "$PID" 2>/dev/null
    rm -f "$PID_FILE"
    su 2000 -c "cmd notification post -i @android:drawable/stat_sys_warning -S bigtext -t 'Auto-Shutdown' 'autoshutdown' 'Daemon stopped via CLI.'" > /dev/null 2>&1
    echo "[+] Daemon stopped."
}

show_status() {
    PID=$(get_daemon_pid)
    echo "=========================================="
    if [ -n "$PID" ]; then
        echo " Daemon Status: RUNNING (PID: $PID)"
        if is_screen_on; then
            echo " Screen State : AWAKE (Device in use - timer reset)"
            echo " Inactive Time: 0 min(s)"
            echo " Time to Alert: $(( INACTIVITY_TIMEOUT / 60 )) min(s)"
        else
            echo " Screen State : ASLEEP (Timer actively ticking)"
            if [ -f "$STATE_FILE" ]; then
                LAST=$(cat "$STATE_FILE" 2>/dev/null)
                NOW=$(get_boottime_sec)
                ELAPSED=$(( NOW - LAST ))
                LEFT=$(( INACTIVITY_TIMEOUT - ELAPSED ))
                if [ $LEFT -lt 0 ]; then LEFT=0; fi
                echo " Inactive Time: $(( ELAPSED / 60 )) min(s)"
                echo " Time to Alert: $(( LEFT / 60 )) min(s) ($LEFT seconds)"
            fi
        fi
    else
        echo " Daemon Status: STOPPED"
    fi
    echo "=========================================="
}

# --- INTERACTIVE CLI MENU ---

interactive_menu() {
    while true; do
        echo ""
        echo "=========================================="
        echo "       AUTO-SHUTDOWN CONTROL MENU (ASDS)  "
        echo "=========================================="
        show_status
        echo " 1) Check Status & Remaining Time"
        echo " 2) Snooze Shutdown (20 mins)"
        echo " 3) Stop / Cancel Daemon"
        echo " 4) Start / Restart Daemon"
        echo " 5) View Live Log (Last 15 lines)"
        echo " 6) SHUTDOWN NOW (Immediate Power Off)"
        echo " 0) Exit Menu"
        echo "=========================================="
        printf "Select an option [0-6]: "
        read -r choice
        case "$choice" in
            1)
                ;;
            2)
                PID=$(get_daemon_pid)
                if [ -n "$PID" ]; then
                    touch "$SNOOZE_FILE"
                    echo "[+] Snooze signal sent to daemon."
                else
                    echo "[!] Cannot snooze: Daemon is not running."
                fi
                ;;
            3)
                stop_daemon
                ;;
            4)
                stop_daemon
                start_daemon
                ;;
            5)
                echo "--- Last 15 Log Entries ---"
                tail -n 15 "$LOG_FILE" 2>/dev/null || echo "[No logs yet]"
                echo "---------------------------"
                ;;
            6)
                printf "Are you sure you want to turn off the device? (y/n): "
                read -r confirm
                case "$confirm" in
                    y*|Y*)
                        echo "[*] Shutting down device now..."
                        execute_shutdown
                        exit 0
                        ;;
                    *)
                        echo "[-] Shutdown aborted."
                        ;;
                esac
                ;;
            0|q|Q)
                echo "Exiting menu. Daemon remains running in background."
                exit 0
                ;;
            *)
                echo "Invalid option. Enter 0 to 6."
                ;;
        esac
        printf "\nPress [ENTER] to continue..."
        read -r _
    done
}

# --- ROUTER & ENTRY POINT ---

case "$1" in
    --worker)
        run_daemon
        ;;
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        start_daemon
        ;;
    status)
        show_status
        ;;
    snooze)
        touch "$SNOOZE_FILE"
        echo "[+] Snooze request written."
        ;;
    menu)
        interactive_menu
        ;;
    *)
        if [ -t 0 ]; then
            interactive_menu
        else
            if [ "$(getprop sys.boot_completed)" = "1" ]; then
                start_daemon
            else
                (
                    while [ "$(getprop sys.boot_completed)" != "1" ]; do
                        sleep 1
                    done
                    start_daemon
                ) &
            fi
        fi
        ;;
esac

exit 0
```

---

## 2. Fast Direct Install (No ZIP Required)

In BakaSU and KernelSU, a module is just a directory inside `/data/adb/modules/auto_shutdown`. You can register and activate it directly without building or flashing a `.zip`.

Run this single command block in your terminal as root (`su`):

```sh
su
MOD="/data/adb/modules/auto_shutdown"
mkdir -p "$MOD/system/bin"

# Copy files from your existing working setup:
cp -f /data/adb/service.d/auto_shutdown.sh "$MOD/auto_shutdown.sh"

# Create module.prop
cat << 'EOF' > "$MOD/module.prop"
id=auto_shutdown
name=Auto-Shutdown Daemon (ASDS)
version=v2.1
versionCode=210
author=elonuziel
description=Powers off device after inactivity with deep sleep awareness, touch-to-snooze warning, and an interactive CLI controller ('asds').
EOF

# Create service.sh
cat << 'EOF' > "$MOD/service.sh"
#!/system/bin/sh
MODDIR="${0%/*}"
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
/system/bin/sh "$MODDIR/auto_shutdown.sh" start
EOF

# Create systemless asds binary link
cat << 'EOF' > "$MOD/system/bin/asds"
#!/system/bin/sh
exec /system/bin/sh /data/adb/modules/auto_shutdown/auto_shutdown.sh "$@"
EOF

# Set permissions and sanitize line endings
chmod -R 755 "$MOD"
chown -R root:root "$MOD"
sed -i 's/\r$//' "$MOD/module.prop" "$MOD/service.sh" "$MOD/system/bin/asds" "$MOD/auto_shutdown.sh"

# Remove loose service.d copy to prevent double instances
rm -f /data/adb/service.d/auto_shutdown.sh

# Restart daemon
"$MOD/auto_shutdown.sh" restart
```

*Open your **KernelSU** or **BakaSU** Manager app — **Auto-Shutdown Daemon (ASDS)** will now be listed in your active modules.*

---

## 3. Creating the Flashable ZIP in MiXplorer

If you want an `asds-module.zip` to share or flash on other devices:

1. Open **MiXplorer**.
2. Navigate to `/data/adb/modules/auto_shutdown` (or where the 4 files and `system` folder are located).
3. Tap the top-right menu and choose **Select All** (make sure `module.prop`, `service.sh`, `auto_shutdown.sh`, and the `system` folder are highlighted).
4. Tap the **3-dot action menu** at the bottom $\rightarrow$ **Archive**.
5. Select **ZIP** format.
6. Name the archive `asds-module.zip` and choose your **Download** folder as the destination.

*This ZIP can now be flashed directly in Magisk, KernelSU, or BakaSU.*

---

## 4. CLI Command Reference & Menu Usage

Type `su` followed by `asds` to open the interactive controller:

```text
==========================================
       AUTO-SHUTDOWN CONTROL MENU (ASDS)  
==========================================
 Daemon Status: RUNNING (PID: 4824)
 Screen State : ASLEEP (Timer actively ticking)
 Inactive Time: 30 min(s)
 Time to Alert: 120 min(s) (7200 seconds)
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

### Direct Terminal Commands

| Command | Action |
| :--- | :--- |
| `asds` / `asds menu` | Launches the interactive text UI menu. |
| `asds status` | Prints whether the daemon is running, screen state, and minutes left. |
| `asds snooze` | Extends the countdown by 20 minutes immediately. |
| `asds stop` | Stops the background worker and clears the notification drawer. |
| `asds start` | Launches the background worker if not already running. |
| `asds restart` | Terminates any existing worker and spawns a fresh process. |

---

## 5. Troubleshooting & Verification

### Verify Daemon is Running
```sh
su -c "asds status"
```

### View Live Execution Log
```sh
su -c "tail -n 20 /data/local/tmp/shutdown_log.txt"
```

### Manual 10-Second Unattended Shutdown Test
Run this dry-run test in your root terminal to verify that the screen wakes up and powers down cleanly without false touch triggers:

```sh
su -c 'sh -c "
input keyevent 26
sleep 3
input keyevent 224
sleep 2
BASE_ACT=\$(dumpsys power 2>/dev/null | grep -m1 mLastUserActivityTime | grep -oE [0-9]+)
echo Countdown started. Do not touch the tablet...
COUNT=10
while [ \$COUNT -gt 0 ]; do
    echo Shutting down in \$COUNT...
    sleep 2
    COUNT=\$((COUNT - 2))
    CURR_ACT=\$(dumpsys power 2>/dev/null | grep -m1 mLastUserActivityTime | grep -oE [0-9]+)
    if [ -n \"\$BASE_ACT\" ] && [ -n \"\$CURR_ACT\" ] && [ \"\$CURR_ACT\" -gt \"\$BASE_ACT\" ]; then
        echo Touch detected! Test aborted.
        exit 0
    fi
done
echo Triggering shutdown...
svc power shutdown
"'
```