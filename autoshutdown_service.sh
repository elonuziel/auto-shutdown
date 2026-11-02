#!/system/bin/sh

# =============================================================================
# AUTO-SHUTDOWN SCRIPT FOR SERVICE.D (MAGISK / KERNELSU / BAKASU)
# =============================================================================

# --- CONFIGURATION ---
INACTIVITY_TIMEOUT=$(( 150 * 60 ))    # 2.5 Hours (9000 seconds)
WARN_TIME=60                          # 60 Seconds warning before shutdown
SNOOZE_TIME=$(( 20 * 60 ))            # 20 Minutes snooze if canceled/active
CHECK_INTERVAL=$(( 15 * 60 ))         # Check interval: 15 minutes (900 seconds)
SKIP_IF_CHARGING=0                    # 1 = Do not shutdown if charging

LOG_FILE="/data/local/tmp/shutdown_log.txt"
STOP_FILE="/data/local/tmp/stop_shutdown_timer"
PID_FILE="/data/local/tmp/shutdown_timer.pid"

# --- HELPER FUNCTIONS ---

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

get_boottime_sec() {
    read -r up _ < /proc/uptime
    echo "${up%%.*}"
}

send_notif() {
    # Post via shell UID 2000 with system warning icon
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
    send_notif "🔌 Auto-Shutdown" "Shutting down device now..."
    sleep 2
    setprop sys.powerctl shutdown || svc power shutdown || reboot -p
}

cleanup() {
    su 2000 -c "cmd notification post -i @android:drawable/stat_sys_warning -S bigtext -t 'Auto-Shutdown' 'autoshutdown' 'Daemon stopped.'" > /dev/null 2>&1
    rm -f "$PID_FILE"
    log_msg "Daemon stopped."
}

# --- MAIN DAEMON ---

run_daemon() {
    trap cleanup EXIT INT TERM

    # Ensure permissions for shell user
    pm grant com.android.shell android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
    cmd appops set com.android.shell POST_NOTIFICATION allow >/dev/null 2>&1

    # Kill duplicate instances
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            exit 1
        fi
    fi
    echo $$ > "$PID_FILE"

    log_msg "Shutdown daemon active. Target inactivity: ${INACTIVITY_TIMEOUT}s. Check interval: ${CHECK_INTERVAL}s."
    rm -f "$STOP_FILE"

    # Immediate notification on launch
    send_notif "⏰ Auto-Shutdown Active" "Timer started. Device will power off after 2.5h of inactivity."

    LAST_ACTIVE=$(get_boottime_sec)

    while true; do
        # 1. Stop file check
        if [ -f "$STOP_FILE" ]; then
            log_msg "Stop signal detected. Terminating daemon."
            send_notif "✓ Auto-Shutdown Cancelled" "Inactivity timer has been manually stopped."
            rm -f "$STOP_FILE"
            exit 0
        fi

        # 2. Charging bypass
        if [ "$SKIP_IF_CHARGING" -eq 1 ] && is_charging; then
            LAST_ACTIVE=$(get_boottime_sec)
            send_notif "⚡ Auto-Shutdown Paused" "Device is charging. Inactivity timer suspended."
            sleep "$CHECK_INTERVAL"
            continue
        fi

        CURRENT_TIME=$(get_boottime_sec)

        # 3. User activity / screen state
        if is_screen_on; then
            LAST_ACTIVE="$CURRENT_TIME"
            send_notif "⏰ Auto-Shutdown Active" "Device in use. 2.5h inactivity timer will begin once screen turns off."
            sleep "$CHECK_INTERVAL"
            continue
        fi

        # 4. Inactivity countdown
        IDLE_DURATION=$(( CURRENT_TIME - LAST_ACTIVE ))
        REMAINING_SECS=$(( INACTIVITY_TIMEOUT - IDLE_DURATION ))

        if [ "$REMAINING_SECS" -gt 0 ]; then
            REMAINING_MINS=$(( (REMAINING_SECS + 59) / 60 ))
            send_notif "⏰ Auto-Shutdown Monitoring" "Device idle. Shutting down in approx ${REMAINING_MINS} minute(s)."

            # If remaining time is less than 15 minutes, sleep only the remaining time
            # to hit the exact 2.5-hour target rather than overshooting
            if [ "$REMAINING_SECS" -lt "$CHECK_INTERVAL" ]; then
                sleep "$REMAINING_SECS"
            else
                sleep "$CHECK_INTERVAL"
            fi
        else
            # Threshold hit: enter warning countdown phase
            log_msg "Inactivity limit reached (${IDLE_DURATION}s). Starting 60s warning."

            # Turn screen on
            input keyevent 224 # KEYCODE_WAKEUP

            WARN_REMAINING="$WARN_TIME"
            ABORT_SHUTDOWN=0

            # Dynamic rapid countdown loop (updates every 5 seconds)
            while [ "$WARN_REMAINING" -gt 0 ]; do
                send_notif "⚠️ SHUTDOWN IMMINENT" "Shutting down in ${WARN_REMAINING}s! Turn on or unlock screen to cancel."
                
                sleep 5
                WARN_REMAINING=$(( WARN_REMAINING - 5 ))

                if is_screen_on || [ -f "$STOP_FILE" ]; then
                    log_msg "Activity detected during warning. Snoozing for ${SNOOZE_TIME}s."
                    send_notif "😴 Shutdown Snoozed" "Activity detected. Snoozing for 20 minutes."
                    rm -f "$STOP_FILE"
                    ABORT_SHUTDOWN=1
                    break
                fi
            done

            if [ "$ABORT_SHUTDOWN" -eq 1 ]; then
                NOW=$(get_boottime_sec)
                LAST_ACTIVE=$(( NOW - INACTIVITY_TIMEOUT + SNOOZE_TIME ))
                sleep "$CHECK_INTERVAL"
            else
                execute_shutdown
                exit 0
            fi
        fi
    done
}

# --- LAUNCH HANDLER ---
if [ "$(getprop sys.boot_completed)" = "1" ]; then
    ( run_daemon ) &
else
    (
        while [ "$(getprop sys.boot_completed)" != "1" ]; do
            sleep 2
        done
        sleep 5
        run_daemon
    ) &
fi

exit 0