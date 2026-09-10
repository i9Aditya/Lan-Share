#!/usr/bin/env bash
# =====================================================================
# LAN Share - Uninstaller for Linux (Fedora & Ubuntu)
# =====================================================================
set -e

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

USER_CONF_FILE="$XDG_CONFIG_HOME/lan-share/lan-share.conf"
USER_APP_DIR="$XDG_DATA_HOME/lan-share"
USER_BIN="$HOME/.local/bin/lanshare"
USER_SERVICE="$XDG_CONFIG_HOME/systemd/user/lan-share.service"
DESKTOP_FILE="$XDG_DATA_HOME/applications/lan-share.desktop"

SHARED_DATA_DIR=""
if [ -f "$USER_CONF_FILE" ]; then
    SHARED_DATA_DIR=$(grep "^DATA_DIR=" "$USER_CONF_FILE" 2>/dev/null | cut -d= -f2- | tr -d '"')
fi

echo "=================================================================="
echo "  LAN Share - Uninstallation"
echo "=================================================================="

# 1. Stop and disable systemd service
if command -v systemctl >/dev/null 2>&1; then
    echo "==> Stopping LAN Share service..."
    systemctl --user stop lan-share.service 2>/dev/null || true
    systemctl --user disable lan-share.service 2>/dev/null || true
fi

# Also kill any standalone process
pkill -f "lan-share.*\.jar" 2>/dev/null || true

# 2. Remove systemd service file
if [ -f "$USER_SERVICE" ]; then
    echo "==> Removing systemd user service..."
    rm -f "$USER_SERVICE"
    systemctl --user daemon-reload 2>/dev/null || true
fi

# 3. Remove desktop launcher and icons
echo "==> Removing desktop integration..."
rm -f "$DESKTOP_FILE"
rm -f "$HOME/.local/share/icons/hicolor/128x128/apps/lan-share.png" 2>/dev/null || true
rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/lan-share.svg" 2>/dev/null || true
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# 4. Remove CLI executable
if [ -f "$USER_BIN" ]; then
    echo "==> Removing command line executable ($USER_BIN)..."
    rm -f "$USER_BIN"
fi

# 5. Remove application files
if [ -d "$USER_APP_DIR" ]; then
    echo "==> Removing application files ($USER_APP_DIR)..."
    rm -rf "$USER_APP_DIR"
fi

# 6. User shared data safety
echo ""
echo "------------------------------------------------------------------"
echo "  USER SHARED DATA PRESERVATION"
echo "------------------------------------------------------------------"
if [ -n "$SHARED_DATA_DIR" ] && [ -d "$SHARED_DATA_DIR" ]; then
    echo "  Your shared files and database have been safely preserved at:"
    echo "  $SHARED_DATA_DIR"
    echo "  (No user files were deleted)."
fi
echo "=================================================================="
echo "  LAN Share application has been successfully uninstalled."
echo "=================================================================="
