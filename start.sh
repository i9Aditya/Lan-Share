#!/usr/bin/env bash
# =====================================================================
# LAN Share - Simple Server Start Script
# =====================================================================
# Usage:
#   ./start.sh            (Starts server in foreground, Ctrl+C to stop)
#   ./start.sh -d         (Starts server in background as personal daemon)
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ "$1" = "-d" ] || [ "$1" = "--daemon" ] || [ "$1" = "daemon" ]; then
    shift
    exec "$SCRIPT_DIR/lanshare.sh" start "$@"
fi

exec "$SCRIPT_DIR/lanshare.sh" run "$@"
