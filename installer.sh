#!/system/bin/sh
​=============================================================================
​AUTO-SHUTDOWN SCRIPT (ASDS) - ONE-STEP INSTALLER
​=============================================================================
​if [ "$(id -u)" -ne 0 ]; then
echo "[!] Error: Root privileges required. Run as 'su'."
exit 1
fi
​echo ""
echo "    Installing Auto-Shutdown Daemon       "
echo ""
​TARGET_DIR="/data/adb/service.d"
TARGET_SCRIPT="TARGET_DIR/auto_shutdown.sh"
SCRIPT_SRC="(dirname "$0")/auto_shutdown.sh"
​if [ ! -f "$SCRIPT_SRC" ]; then
echo "[!] Source auto_shutdown.sh not found in current folder."
exit 1
fi
​Ensure service.d directory exists
​mkdir -p "$TARGET_DIR"
​Copy and set execution permissions
​cp -f "$SCRIPT_SRC" "$TARGET_SCRIPT"
chmod 755 "$TARGET_SCRIPT"
chown root:root "TARGET_SCRIPT"
sed -i 's/\r//' "$TARGET_SCRIPT"
echo "[+] Copied daemon to $TARGET_SCRIPT"
​Setup 'asds' symlink in root binary path
​BIN_DIR="/data/adb/ksu/bin"
mkdir -p "$BIN_DIR"
ln -sf "$TARGET_SCRIPT" "$BIN_DIR/asds"
chmod 755 "$BIN_DIR/asds" 2>/dev/null
echo "[+] Created 'asds' command shortcut in $BIN_DIR/asds"
​Optional fallback link in /data/local/tmp
​ln -sf "$TARGET_SCRIPT" /data/local/tmp/asds 2>/dev/null
​Start daemon
​"$TARGET_SCRIPT" restart
​echo ""
echo " Installation Complete!"
echo " Type 'asds' in any root terminal to control."
echo ""