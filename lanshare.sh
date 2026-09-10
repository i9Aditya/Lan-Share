#!/usr/bin/env bash
# =====================================================================
# LAN Share - Production Management Script for Linux (Fedora & Ubuntu)
# =====================================================================
# Commands:
#   ./lanshare.sh build     - Build production JAR with Maven
#   ./lanshare.sh start     - Start server in background (daemon mode)
#   ./lanshare.sh stop      - Gracefully stop running server
#   ./lanshare.sh restart   - Gracefully restart server
#   ./lanshare.sh status    - Show server status, health, and LAN URLs
#   ./lanshare.sh logs      - View or stream server logs
#   ./lanshare.sh run       - Run server interactively in foreground
# =====================================================================

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(dirname "$SCRIPT_PATH")"
cd "$PROJECT_DIR"

CONF_FILE="$PROJECT_DIR/lan-share.conf"
PID_FILE="$PROJECT_DIR/lan-share.pid"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/lan-share.log"
JAR_FILE="$PROJECT_DIR/target/lan-share-1.0.0.jar"

# Preserve any pre-existing environment variables so they override config file
ENV_PORT="${PORT:-}"
ENV_HOST="${HOST:-}"
ENV_STORAGE_DIR="${STORAGE_DIR:-}"
ENV_DATA_DIR="${DATA_DIR:-}"
ENV_MAX_STORAGE_SIZE="${MAX_STORAGE_SIZE:-}"
ENV_MAX_FILE_SIZE="${MAX_FILE_SIZE:-}"
ENV_MAX_REQUEST_SIZE="${MAX_REQUEST_SIZE:-}"
ENV_JAVA_OPTS="${JAVA_OPTS:-}"

# Load configuration file if present
if [ -f "$CONF_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE"
fi

# Apply environment variable overrides
[ -n "$ENV_PORT" ] && PORT="$ENV_PORT"
[ -n "$ENV_HOST" ] && HOST="$ENV_HOST"
[ -n "$ENV_STORAGE_DIR" ] && STORAGE_DIR="$ENV_STORAGE_DIR"
[ -n "$ENV_DATA_DIR" ] && DATA_DIR="$ENV_DATA_DIR"
[ -n "$ENV_MAX_STORAGE_SIZE" ] && MAX_STORAGE_SIZE="$ENV_MAX_STORAGE_SIZE"
[ -n "$ENV_MAX_FILE_SIZE" ] && MAX_FILE_SIZE="$ENV_MAX_FILE_SIZE"
[ -n "$ENV_MAX_REQUEST_SIZE" ] && MAX_REQUEST_SIZE="$ENV_MAX_REQUEST_SIZE"
[ -n "$ENV_JAVA_OPTS" ] && JAVA_OPTS="$ENV_JAVA_OPTS"

# Fallback defaults if not defined in conf or environment
PORT="${PORT:-8080}"
HOST="${HOST:-0.0.0.0}"
STORAGE_DIR="${STORAGE_DIR:-$PROJECT_DIR/data/uploads}"
DATA_DIR="${DATA_DIR:-$PROJECT_DIR/data}"
MAX_STORAGE_SIZE="${MAX_STORAGE_SIZE:-2GB}"
MAX_FILE_SIZE="${MAX_FILE_SIZE:-5120MB}"
MAX_REQUEST_SIZE="${MAX_REQUEST_SIZE:-5120MB}"
JAVA_OPTS="${JAVA_OPTS:--Xms128m -Xmx1024m -XX:+UseG1GC -Djava.awt.headless=true}"

# Expand tilde in directory paths if needed
expand_path() {
    local path="$1"
    if [[ "$path" == ~* ]]; then
        echo "${path/#\~/$HOME}"
    else
        echo "$path"
    fi
}

STORAGE_DIR="$(expand_path "$STORAGE_DIR")"
DATA_DIR="$(expand_path "$DATA_DIR")"

# Ensure directories exist
ensure_directories() {
    mkdir -p "$STORAGE_DIR"
    mkdir -p "$DATA_DIR/db"
    mkdir -p "$LOG_DIR"
}

# Find local IPv4 address
get_lan_ip() {
    ip -4 -br addr show 2>/dev/null | awk '$1 !~ /^(lo|docker|podman|virbr|veth)/ && $2 == "UP" {print $3}' | cut -d/ -f1 | head -n 1
}

# Print connection banner
print_banner() {
    local lan_ip
    lan_ip="$(get_lan_ip)"
    echo "=================================================================="
    echo "  LAN Share Personal Server"
    echo "=================================================================="
    echo "  Listening Port    : $PORT"
    echo "  Storage Location  : $STORAGE_DIR"
    echo "  Storage Quota     : $MAX_STORAGE_SIZE"
    echo "  Database Location : $DATA_DIR/db"
    echo "  Log File          : $LOG_FILE"
    echo "------------------------------------------------------------------"
    if [ -n "$lan_ip" ]; then
        echo "  LAN Access URL    : http://${lan_ip}:${PORT}"
    fi
    echo "  Local Access URL  : http://localhost:${PORT}"
    echo "=================================================================="
}

# Check if process is running
get_running_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi
    return 1
}

# Build JAR with Maven
cmd_build() {
    echo "==> Building production JAR for LAN Share..."
    if ! command -v mvn >/dev/null 2>&1; then
        echo "Error: 'mvn' (Maven) is not installed or not in PATH."
        exit 1
    fi
    mvn clean package -DskipTests
    echo "==> Build complete: $JAR_FILE"
}

# Start server in background (daemon mode)
cmd_start() {
    local pid
    if pid=$(get_running_pid); then
        echo "LAN Share is already running with PID $pid."
        echo "Check status with: ./lanshare.sh status"
        return 0
    fi

    if [ ! -f "$JAR_FILE" ]; then
        echo "Application JAR not found. Building now..."
        cmd_build
    fi

    ensure_directories

    echo "==> Starting LAN Share in background..."
    setsid java $JAVA_OPTS \
        -Dserver.port="$PORT" \
        -Dserver.address="$HOST" \
        -Dlan.storage.location="$STORAGE_DIR" \
        -Dlan.storage.max-storage-size="$MAX_STORAGE_SIZE" \
        -DDATA_DIR="$DATA_DIR" \
        -Dspring.servlet.multipart.max-file-size="$MAX_FILE_SIZE" \
        -Dspring.servlet.multipart.max-request-size="$MAX_REQUEST_SIZE" \
        -jar "$JAR_FILE" </dev/null > "$LOG_FILE" 2>&1 &

    local new_pid=$!
    disown "$new_pid" 2>/dev/null || true
    echo "$new_pid" > "$PID_FILE"

    # Wait up to 15 seconds to verify startup
    echo -n "==> Initializing server"
    local count=0
    local started=false
    while [ $count -lt 30 ]; do
        if ! kill -0 "$new_pid" 2>/dev/null; then
            echo ""
            echo "Error: Process exited prematurely. Check logs:"
            tail -n 25 "$LOG_FILE"
            rm -f "$PID_FILE"
            exit 1
        fi

        # Check actuator health or port
        if curl -s -f "http://127.0.0.1:${PORT}/actuator/health" >/dev/null 2>&1 || \
           curl -s "http://127.0.0.1:${PORT}/api/info" >/dev/null 2>&1; then
            started=true
            break
        fi

        sleep 0.5
        echo -n "."
        count=$((count + 1))
    done
    echo ""

    if [ "$started" = true ]; then
        echo "==> Server started successfully (PID: $new_pid)!"
        echo ""
        print_banner
    else
        echo "==> Server started with PID $new_pid (health check still pending)."
        echo "    Check logs with: ./lanshare.sh logs"
    fi
}

# Graceful stop
cmd_stop() {
    local pid
    if ! pid=$(get_running_pid); then
        echo "LAN Share is not currently running."
        rm -f "$PID_FILE"
        return 0
    fi

    echo "==> Sending graceful shutdown signal (SIGTERM) to PID $pid..."
    kill -TERM "$pid" 2>/dev/null || true

    local count=0
    local max_wait=25
    echo -n "==> Waiting for graceful shutdown"
    while kill -0 "$pid" 2>/dev/null; do
        if [ $count -ge $max_wait ]; then
            echo ""
            echo "Warning: Server did not stop within ${max_wait}s. Forcing termination (SIGKILL)..."
            kill -KILL "$pid" 2>/dev/null || true
            break
        fi
        sleep 1
        echo -n "."
        count=$((count + 1))
    done
    echo ""

    rm -f "$PID_FILE"
    echo "==> LAN Share server stopped gracefully."
}

# Restart
cmd_restart() {
    echo "==> Restarting LAN Share server..."
    cmd_stop
    sleep 1
    cmd_start
}

# Status
cmd_status() {
    local pid
    if pid=$(get_running_pid); then
        echo "● LAN Share Server: RUNNING"
        echo "  PID               : $pid"

        # Memory and CPU stats on Linux
        if command -v ps >/dev/null 2>&1; then
            local mem cpu etime
            mem=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
            cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
            etime=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
            echo "  Uptime            : $etime"
            echo "  Memory (RSS)      : $mem"
            echo "  CPU Usage         : ${cpu}%"
        fi

        # Read actual runtime config from process cmdline if available
        if [ -f "/proc/$pid/cmdline" ]; then
            local proc_port proc_storage
            proc_port=$(tr '\0' '\n' < "/proc/$pid/cmdline" | sed -n 's/^-Dserver\.port=//p')
            [ -n "$proc_port" ] && PORT="$proc_port"
            proc_storage=$(tr '\0' '\n' < "/proc/$pid/cmdline" | sed -n 's/^-Dlan\.storage\.location=//p')
            [ -n "$proc_storage" ] && STORAGE_DIR="$proc_storage"
        fi

        echo "  Port              : $PORT"
        echo "  Storage Location  : $STORAGE_DIR"

        # Actuator health check
        local health
        health=$(curl -s --max-time 2 "http://127.0.0.1:${PORT}/actuator/health" 2>/dev/null)
        if echo "$health" | grep -q '"status":"UP"'; then
            echo "  Health Status     : UP (healthy)"
        else
            echo "  Health Status     : Responding (HTTP)"
        fi

        local lan_ip
        lan_ip="$(get_lan_ip)"
        if [ -n "$lan_ip" ]; then
            echo "  LAN URL           : http://${lan_ip}:${PORT}"
        fi
        echo "  Local URL         : http://localhost:${PORT}"
        echo "  Log File          : $LOG_FILE"
    else
        echo "○ LAN Share Server: STOPPED"
        if [ -f "$PID_FILE" ]; then
            echo "  (Found stale PID file: $PID_FILE - removing)"
            rm -f "$PID_FILE"
        fi
    fi
}

# Logs
cmd_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "No log file found at $LOG_FILE."
        return 0
    fi

    local follow=false
    local lines=50

    while [ $# -gt 0 ]; do
        case "$1" in
            -f|--follow)
                follow=true
                shift
                ;;
            -n|--lines)
                lines="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ "$follow" = true ]; then
        echo "==> Streaming logs from $LOG_FILE (Ctrl+C to exit)..."
        tail -n "$lines" -f "$LOG_FILE"
    else
        echo "==> Showing last $lines lines of $LOG_FILE:"
        tail -n "$lines" "$LOG_FILE"
        echo ""
        echo "Tip: Stream real-time logs with: ./lanshare.sh logs -f"
    fi
}

# Run in foreground
cmd_run() {
    local pid
    if pid=$(get_running_pid); then
        echo "Error: LAN Share is already running in background (PID: $pid)."
        echo "Stop it first with: ./lanshare.sh stop"
        exit 1
    fi

    if [ ! -f "$JAR_FILE" ]; then
        echo "Application JAR not found. Building now..."
        cmd_build
    fi

    ensure_directories
    print_banner
    echo "==> Starting in foreground. Press Ctrl+C for graceful shutdown."
    echo ""

    trap 'echo ""; echo "==> Received shutdown signal. Gracefully stopping..."; exit 0' SIGINT SIGTERM

    exec java $JAVA_OPTS \
        -Dserver.port="$PORT" \
        -Dserver.address="$HOST" \
        -Dlan.storage.location="$STORAGE_DIR" \
        -Dlan.storage.max-storage-size="$MAX_STORAGE_SIZE" \
        -DDATA_DIR="$DATA_DIR" \
        -Dspring.servlet.multipart.max-file-size="$MAX_FILE_SIZE" \
        -Dspring.servlet.multipart.max-request-size="$MAX_REQUEST_SIZE" \
        -jar "$JAR_FILE"
}

cmd_qr() {
    local target_url="$1"
    if [ -z "$target_url" ]; then
        local lan_ip
        lan_ip="$(get_lan_ip)"
        target_url="http://${lan_ip:-127.0.0.1}:${PORT}"
    fi
    if [ -f "$PROJECT_DIR/tools/terminal_qr.py" ] && command -v python3 >/dev/null 2>&1; then
        python3 "$PROJECT_DIR/tools/terminal_qr.py" "$target_url"
    elif command -v qrencode >/dev/null 2>&1; then
        qrencode -t ANSI256 "$target_url"
    else
        echo "Open $target_url in your browser to view the QR code."
    fi
}

cmd_set_quota() {
    local new_quota="$1"
    if [ -z "$new_quota" ]; then
        echo "Error: Please specify the desired quota limit (e.g. 5GB, 10GB, 500MB)."
        echo "Usage: ./lanshare.sh set-quota <size>"
        exit 1
    fi
    new_quota=$(echo "$new_quota" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    if [[ ! "$new_quota" =~ ^[0-9]+(\.[0-9]+)?(GB|G|MB|M|KB|K|B)?$ ]]; then
        echo "Error: Invalid quota format '$new_quota'. Example: 2GB, 5GB, 500MB"
        exit 1
    fi
    if [[ ! "$new_quota" =~ (GB|G|MB|M|KB|K|B)$ ]]; then
        new_quota="${new_quota}GB"
    fi

    echo "==> Setting LAN Share application storage quota to $new_quota..."
    if [ -f "$CONF_FILE" ]; then
        if grep -q "^MAX_STORAGE_SIZE=" "$CONF_FILE"; then
            sed -i "s/^MAX_STORAGE_SIZE=.*/MAX_STORAGE_SIZE=$new_quota/" "$CONF_FILE"
        else
            echo "MAX_STORAGE_SIZE=$new_quota" >> "$CONF_FILE"
        fi
        echo "  Updated $CONF_FILE"
    fi
    if pid=$(get_running_pid); then
        curl -s -X POST -H "Content-Type: application/json" -d "{\"quota\": \"$new_quota\"}" "http://127.0.0.1:${PORT}/api/info/quota" >/dev/null 2>&1 || true
    fi
    echo "==> Storage quota successfully configured to $new_quota."
}

# Print help
cmd_help() {
    cat << 'EOF'
LAN Share - Self-hosted local file & link sharing personal server.

Usage:
  ./lanshare.sh <command>

Available commands:
  install     Run the Linux desktop installation wizard
  build       Build the production JAR with Maven
  start       Start the server in background
  stop        Stop the server gracefully
  restart     Restart the server
  status      Show server status, storage quota, and LAN URLs
  set-quota   Set application storage limit (e.g., 2GB, 5GB)
  qr          Show terminal QR code for phone connection
  logs        Show recent logs
  logs -f     Follow logs in real time
  run         Run server in foreground
  --help      Show help
  -h          Show help

Examples:
  ./lanshare.sh install
  ./lanshare.sh start
  ./lanshare.sh status
  ./lanshare.sh set-quota 5GB
  ./lanshare.sh logs -f
EOF
}

# Route commands
case "${1:-}" in
    start)
        shift
        cmd_start "$@"
        ;;
    stop)
        shift
        cmd_stop "$@"
        ;;
    restart)
        shift
        cmd_restart "$@"
        ;;
    status)
        shift
        cmd_status "$@"
        ;;
    logs)
        shift
        cmd_logs "$@"
        ;;
    build)
        shift
        cmd_build "$@"
        ;;
    run)
        shift
        cmd_run "$@"
        ;;
    qr)
        shift
        cmd_qr "$@"
        ;;
    set-quota|quota)
        shift
        cmd_set_quota "$@"
        ;;
    install)
        shift
        exec "$PROJECT_DIR/install.sh" "$@"
        ;;
    --help|-h|help|"")
        cmd_help
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo "Run './lanshare.sh --help' to see available commands."
        exit 1
        ;;
esac
