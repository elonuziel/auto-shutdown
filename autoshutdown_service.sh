#!/system/bin/sh
​=============================================================================
​AUTO-SHUTDOWN DAEMON & CONTROLLER (ASDS)
​Platform: Android 14 - 17 / LineageOS 24
​Supported Root Environments: BakaSU / KernelSU / Magisk / APatch
​Default Installation Path: /data/adb/service.d/auto_shutdown.sh
​=============================================================================
​--- CONFIGURATION ---
​INACTIVITY_TIMEOUT=(( 150 * 60 ))    # 2.5 Hours (9000 seconds)
WARN_TIME=60                          # 60s countdown warning before shutdown
SNOOZE_TIME=(( 20 * 60 ))            # 20m snooze duration when touched/snoozed
CHECK_INTERVAL=$(( 15 * 60 ))         # Polling interval: 15 minutes (900 seconds)
SKIP_IF_CHARGING=0                    # 1 = Do not shutdown while charging
​Temporary runtime files in device-encrypted ramdisk
​LOG_FILE="/data/local/tmp/shutdown_log.txt"
STOP_FILE="/data/local/tmp/stop_shutdown_timer"
SNOOZE_FILE="/data/local/tmp/snooze_shutdown_timer"
PID_FILE="/data/local/tmp/shutdown_timer.pid"
STATE_FILE="/data/local/tmp/shutdown_last_active"
​--- CORE UTILITIES ---
​log_msg() {
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}
​get_boottime_sec() {
# /proc/uptime accurately tracks time across kernel deep sleep / suspend
read -r up _ < /proc/uptime
echo "${up%%.*}"
}
​get_last_user_activity() {
# Captures physical touchscreen contacts and hardware button presses
dumpsys power 2>/dev/null | grep -m1 "mLastUserActivityTime" | grep -oE '[0-9]+'
}
​send_notif() {
# Dispatched via Shell UID (2000) using a guaranteed public Android drawable
su 2000 -c "cmd notification post -i @android:drawable/stat_sys_warning -S bigtext -t "$1" 'autoshutdown' "$2"" > /dev/null 2>&1
}
​is_screen_on() {
dumpsys power 2>/dev/null | grep -q "mWakefulness=Awake"
}
​is_charging() {
dumpsys battery 2>/dev/null | grep -Eqi "(AC|USB|Wireless|Dock) powered: true"
}
​execute_shutdown() {
log_msg "Initiating power off..."
send_notif "🔌 Auto-Shutdown" "Shutting down device now..."
sleep 2
​# Tier 1: Clean framework shutdown (triggers standard power-off animation)
svc power shutdown >/dev/null 2>&1
sleep 3
​# Tier 2: Android init powerctl trigger
setprop sys.powerctl shutdown >/dev/null 2>&1
sleep 3
​# Tier 3: Direct kernel power-off fallback
/system/bin/reboot -p >/dev/null 2>&1 || reboot -p
}
​get_daemon_pid() {
if [ -f "PID_FILE" ]; then
PID=(cat "$PID_FILE" 2>/dev/null)
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
echo "$PID"
return 0
fi
fi
echo ""
return 1
}
​--- BACKGROUND DAEMON ---
​run_daemon() {
# Record actual worker PID
echo $$ > "$PID_FILE"
​trap 'rm -f "$PID_FILE"; log_msg "Daemon stopped."; exit 0' EXIT INT TERM      # Ensure notification privileges for shell subsystem (Android 13 - 17) pm grant com.android.shell android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 cmd appops set com.android.shell POST_NOTIFICATION allow >/dev/null 2>&1      log_msg "Shutdown daemon active (PID: $$). Inactivity limit: ${INACTIVITY_TIMEOUT}s."
rm -f "$STOP_FILE" "$SNOOZE_FILE"
​send_notif "⏰ Auto-Shutdown Active" "Timer started. Shuts down after 2.5h of inactivity."
​LAST_ACTIVE=$(get_boottime_sec)
echo "$LAST_ACTIVE" > "$STATE_FILE"
​while true; do
# 1. External cancel / stop check
if [ -f "$STOP_FILE" ]; then
log_msg "Stop signal detected. Exiting daemon."
send_notif "✓ Auto-Shutdown Cancelled" "Inactivity timer has been manually stopped."
rm -f "$STOP_FILE"
exit 0
fi
​# 2. External snooze check from CLI menu
if [ -f "SNOOZE_FILE" ]; then
log_msg "Manual snooze triggered via CLI."
rm -f "$SNOOZE_FILE"
NOW=$(get_boottime_sec)
LAST_ACTIVE=(( NOW - INACTIVITY_TIMEOUT + SNOOZE_TIME ))
echo "$LAST_ACTIVE" > "$STATE_FILE"
send_notif "😴 Shutdown Snoozed" "Snoozed for $(( SNOOZE_TIME / 60 )) minutes via CLI."
sleep "$CHECK_INTERVAL"
continue
fi
​# 3. Charging bypass
if [ "SKIP_IF_CHARGING" -eq 1 ] && is_charging; then
LAST_ACTIVE=(get_boottime_sec)
echo "$LAST_ACTIVE" > "$STATE_FILE"
send_notif "⚡ Auto-Shutdown Paused" "Device is charging. Timer suspended."
sleep "$CHECK_INTERVAL"
continue
fi
​CURRENT_TIME=$(get_boottime_sec)
​# 4. Screen awake check (resets timer while in use)
if is_screen_on; then
LAST_ACTIVE="$CURRENT_TIME"
echo "$LAST_ACTIVE" > "$STATE_FILE"
send_notif "⏰ Auto-Shutdown Active" "Screen is ON. Timer resets until screen turns off."
sleep "$CHECK_INTERVAL"
continue
fi
​# 5. Inactivity calculation
IDLE_DURATION=(( CURRENT_TIME - LAST_ACTIVE ))
REMAINING_SECS=(( INACTIVITY_TIMEOUT - IDLE_DURATION ))
​if [ "REMAINING_SECS" -gt 0 ]; then
REMAINING_MINS=(( (REMAINING_SECS + 59) / 60 ))
send_notif "⏰ Auto-Shutdown Monitoring" "Device idle. Shutting down in approx ${REMAINING_MINS}m."
​# Dynamic interval adjustment: sleep exact remainder if closer than check interval
if [ "$REMAINING_SECS" -lt "$CHECK_INTERVAL" ]; then
sleep "$REMAINING_SECS"
else
sleep "CHECK_INTERVAL"
fi
else
log_msg "Inactivity limit reached ({IDLE_DURATION}s). Starting 60s warning."
​# 1. Wake screen to display warning
input keyevent 224
​# 2. Settle delay: allow wake transition to register before taking baseline
sleep 2
BASE_USER_ACT=$(get_last_user_activity)
​WARN_REMAINING="$WARN_TIME"
ABORT_SHUTDOWN=0
​while [ "$WARN_REMAINING" -gt 0 ]; do
send_notif "⚠️ SHUTDOWN IMMINENT" "Shutting down in ${WARN_REMAINING}s! Touch screen or unlock to cancel."
​sleep 5
WARN_REMAINING=$(( WARN_REMAINING - 5 ))
​CURRENT_USER_ACT=$(get_last_user_activity)
​# Physical touch or hardware button press detection
if [ -n "$BASE_USER_ACT" ] && [ -n "$CURRENT_USER_ACT" ]; then
if [ "$CURRENT_USER_ACT" -gt "$BASE_USER_ACT" ]; then
log_msg "Physical touch detected during warning. Snoozing for ${SNOOZE_TIME}s."
send_notif "😴 Shutdown Snoozed" "Touch detected. Snoozing for 20 minutes."
ABORT_SHUTDOWN=1
break
fi
fi
​if [ -f "$STOP_FILE" ]; then
log_msg "Stop file created during countdown. Aborting."
send_notif "✓ Auto-Shutdown Cancelled" "Timer cancelled."
rm -f "$STOP_FILE"
exit 0
fi
done
​if [ "ABORT_SHUTDOWN" -eq 1 ]; then
NOW=(get_boottime_sec)
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
​--- CONTROL ACTIONS ---
​start_daemon() {
PID=$(get_daemon_pid)
if [ -n "$PID" ]; then
echo "[!] Daemon is ALREADY running (PID: $PID)."
return 0
fi
rm -f "$STOP_FILE"
/system/bin/sh "0" --worker >/dev/null 2>&1 &
sleep 1
NEW_PID=(get_daemon_pid)
if [ -n "$NEW_PID" ]; then
echo "[+] Daemon started successfully (PID: $NEW_PID)."
else
echo "[-] Failed to start daemon. Check $LOG_FILE."
fi
}
​stop_daemon() {
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
​show_status() {
PID=$(get_daemon_pid)
echo ""
if [ -n "$PID" ]; then
echo " Daemon Status: RUNNING (PID: PID)"
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
LEFT=(( INACTIVITY_TIMEOUT - ELAPSED ))
if [ $LEFT -lt 0 ]; then LEFT=0; fi
echo " Inactive Time: $(( ELAPSED / 60 )) min(s)"
echo " Time to Alert: $(( LEFT / 60 )) min(s) ($LEFT seconds)"
fi
fi
else
echo " Daemon Status: STOPPED"
fi
echo ""
}
​--- INTERACTIVE CLI MENU ---
​interactive_menu() {
while true; do
echo ""
echo ""
echo "       AUTO-SHUTDOWN CONTROL MENU (ASDS)  "
echo ""
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
case "choice" in
1)
;;
2)
PID=(get_daemon_pid)
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
​--- ROUTER & ENTRY POINT ---
​case "1" in
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
# If launched from an interactive terminal -> open menu
if [ -t 0 ]; then
interactive_menu
else
# Boot-time execution from service.d: wait for boot and spawn worker
if [ "$(getprop sys.boot_completed)" = "1" ]; then
start_daemon
else
(
while [ "(getprop sys.boot_completed)" != "1" ]; do
sleep 1
done
start_daemon
) &
fi
fi
;;
esac
​exit 0