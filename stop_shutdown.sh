#!/system/bin/sh

# =============================================================================
# STOP AUTO-SHUTDOWN TIMER
# Creates a stop signal file to cancel the shutdown timer
# =============================================================================

STOP_FILE="/sdcard/stop_shutdown_timer"
PID_FILE="/data/local/tmp/shutdown_timer.pid"

# Create stop signal
touch "$STOP_FILE" 2>/dev/null

# Also try to kill the process directly
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        echo "Shutdown timer stopped (PID: $PID)"
    else
        echo "No running timer found (cleaned up stale PID)."
        rm -f "$PID_FILE" 2>/dev/null
    fi
else
    echo "Stop signal created. Timer will cancel on next check."
fi
