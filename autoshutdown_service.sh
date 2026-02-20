#!/system/bin/sh

# =============================================================================
# AUTO-SHUTDOWN SCRIPT FOR MAGISK SERVICE.D
# Automatically shuts down device after inactivity to save battery
# Optimized for /data/adb/service.d execution
# =============================================================================

# --- CONFIGURATION ---

# Calculate times using awk (Hours * Minutes * Seconds)
WAIT_TIME=$(awk 'BEGIN {print 2.5*60*60}')   # 2.5 Hours initial wait
SNOOZE_TIME=$(awk 'BEGIN {print 20*60}')     # 20 Minutes snooze
WARN_TIME=60                                  # 60 Seconds warning
CHECK_INTERVAL=30                             # Check screen state every 30s (saves battery)

# File paths
LOG_FILE="/data/local/tmp/shutdown_log.txt"
STOP_FILE="/sdcard/stop_shutdown_timer"
PID_FILE="/data/local/tmp/shutdown_timer.pid"

# Optional: Skip shutdown if charging (set to 1 to enable)
SKIP_IF_CHARGING=0

# Wakelock name (prevents deep sleep from freezing timers)
WAKELOCK_NAME="autoshutdown_timer"

# --- FUNCTIONS ---

send_toast() {
    # Uses UID 2000 (Shell) to force notification to appear
    su -lp 2000 -c "cmd notification post -S bigtext -t 'Auto Shutdown' 'System' '$1'" > /dev/null 2>&1
}

acquire_wakelock() {
    echo "$WAKELOCK_NAME" > /sys/power/wake_lock
}

release_wakelock() {
    echo "$WAKELOCK_NAME" > /sys/power/wake_unlock 2>/dev/null
}

is_charging() {
    # Check if device is plugged in
    CHARGING=$(dumpsys battery | grep "AC powered: true\|USB powered: true\|Wireless powered: true")
    [ -n "$CHARGING" ]
}

cleanup() {
    # Release wakelock and remove PID file on exit
    release_wakelock
    rm -f "$PID_FILE"
    echo "[$(date)] Script terminated. PID file cleaned up." >> "$LOG_FILE"
}

check_for_existing_instance() {
    # Prevent multiple instances from running
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "[$(date)] Another instance (PID: $OLD_PID) is already running. Exiting." >> "$LOG_FILE"
            send_toast "Shutdown timer already running!"
            exit 1
        else
            echo "[$(date)] Stale PID file found. Cleaning up." >> "$LOG_FILE"
            rm -f "$PID_FILE"
        fi
    fi
}

do_shutdown() {
    # Set up cleanup trap
    trap cleanup EXIT INT TERM
    
    # Check for existing instance
    check_for_existing_instance
    
    # Save our PID
    echo $$ > "$PID_FILE"
    
    # Acquire wakelock to prevent deep sleep from freezing timers
    acquire_wakelock
    
    # 1. Log Start & Clear old stop signs
    echo "[$(date)] ========================================" >> "$LOG_FILE"
    echo "[$(date)] Timer started. Waiting ${WAIT_TIME}s ($(awk -v t=$WAIT_TIME 'BEGIN {printf "%.1f hours", t/3600}'))" >> "$LOG_FILE"
    rm -f "$STOP_FILE"
    
    # 2. Send startup notification
    HOURS=$(awk -v t=$WAIT_TIME 'BEGIN {printf "%.1f", t/3600}')
    send_toast "⏰ Shutdown Timer Active! Will check in ${HOURS} hours."
    
    # 3. The Big Wait (with periodic checks for cancel signal)
    # Subtract WARN_TIME so the warning fires WARN_TIME seconds before the full wait expires
    EFFECTIVE_WAIT=$((WAIT_TIME - WARN_TIME))
    ELAPSED=0
    while [ $ELAPSED -lt $EFFECTIVE_WAIT ]; do
        if [ -f "$STOP_FILE" ]; then
            echo "[$(date)] Stop signal found during initial wait. Timer cancelled!" >> "$LOG_FILE"
            send_toast "✓ Shutdown Timer Cancelled!"
            rm -f "$STOP_FILE"
            exit 0
        fi
        
        # Sleep in smaller chunks to respond to stop signal faster
        sleep 60  # Check every minute during initial wait
        ELAPSED=$((ELAPSED + 60))
    done

    # 4. Main shutdown logic loop
    while true; do
        # --- CHECK FOR CANCEL SIGNAL ---
        if [ -f "$STOP_FILE" ]; then
            echo "[$(date)] Stop signal found. Timer cancelled!" >> "$LOG_FILE"
            send_toast "✓ Shutdown Timer Cancelled!"
            rm -f "$STOP_FILE"
            exit 0
        fi

        # --- CHECK IF CHARGING (optional) ---
        if [ "$SKIP_IF_CHARGING" -eq 1 ] && is_charging; then
            echo "[$(date)] Device is charging. Skipping shutdown check." >> "$LOG_FILE"
            sleep $CHECK_INTERVAL
            continue
        fi

        # --- CHECK SCREEN STATE ---
        SCREEN_STATE=$(dumpsys power | grep "mWakefulness=" | grep -o "Awake")

        if [ "$SCREEN_STATE" = "Awake" ]; then
            # --- WARNING PHASE ---
            echo "[$(date)] Screen is ON. Warning user." >> "$LOG_FILE"
            
            # Send Notification
            send_toast "⚠️ Shutdown in ${WARN_TIME} seconds! Keep screen ON to snooze."
            
            # Wait warning period
            sleep $WARN_TIME
            
            # Re-check Screen State
            SCREEN_STATE_2=$(dumpsys power | grep "mWakefulness=" | grep -o "Awake")
            
            # Re-check Cancel Signal (in case cancelled during warning)
            if [ -f "$STOP_FILE" ]; then
                send_toast "✓ Shutdown Cancelled!"
                rm -f "$STOP_FILE"
                exit 0
            fi

            if [ "$SCREEN_STATE_2" = "Awake" ]; then
                # User is still active (Screen still ON) -> Snooze
                SNOOZE_MIN=$(awk -v t=$SNOOZE_TIME 'BEGIN {printf "%.0f", t/60}')
                echo "[$(date)] User active. Snoozing for ${SNOOZE_TIME}s." >> "$LOG_FILE"
                send_toast "😴 Snoozing for ${SNOOZE_MIN} minutes..."
                sleep $SNOOZE_TIME
            else
                # User turned screen OFF (or let it timeout) -> Shutdown
                echo "[$(date)] Screen turned OFF after warning. Shutting down NOW." >> "$LOG_FILE"
                send_toast "🔌 Shutting down..."
                sleep 2  # Give notification time to display
                /system/bin/svc power shutdown
                exit 0
            fi
        else
            # Screen was already OFF -> Shutdown immediately
            echo "[$(date)] Screen is OFF. Shutting down NOW." >> "$LOG_FILE"
            send_toast "🔌 Shutting down..."
            sleep 2  # Give notification time to display
            /system/bin/svc power shutdown
            exit 0
        fi
        
        # Wait before next check (battery saving)
        sleep $CHECK_INTERVAL
    done
}

# IMPORTANT: Run in background with proper detachment for service.d
# This prevents blocking the boot process
(
    # Wait for boot to complete before starting timer
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
    done
    
    # Now run the shutdown timer
    do_shutdown
) &

# Exit immediately so Magisk can continue boot process
exit 0
