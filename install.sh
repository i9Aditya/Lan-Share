#!/usr/bin/env bash
# =====================================================================
# LAN Share - Native Installer for Fedora & Ubuntu Linux
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="LAN Share"
APP_ID="lan-share"
DEFAULT_DATA_DIR="$HOME/Documents/LAN Share"
DEFAULT_QUOTA="2GB"
DEFAULT_PORT="8080"

# Detect Linux distribution
DISTRO_NAME="Linux"
DISTRO_ID="linux"
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_NAME="${NAME:-Linux}"
    DISTRO_ID="${ID:-linux}"
fi

# Target installation directories (separated from user shared data)
INSTALL_APP_DIR="$HOME/.local/share/$APP_ID"
INSTALL_BIN_DIR="$HOME/.local/bin"
INSTALL_CONFIG_DIR="$HOME/.config/$APP_ID"
INSTALL_SYSTEMD_DIR="$HOME/.config/systemd/user"
INSTALL_DESKTOP_DIR="$HOME/.local/share/applications"
INSTALL_ICONS_DIR="$HOME/.local/share/icons/hicolor"

# Terminal formatting
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

# Command line argument variables
CLI_MODE=false
UNATTENDED=false
ARG_DATA_DIR=""
ARG_QUOTA=""
ARG_PORT=""
ARG_MIGRATE=""
ARG_START=true

# Parse command line flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cli)
            CLI_MODE=true
            shift
            ;;
        --unattended|--non-interactive|-y)
            UNATTENDED=true
            CLI_MODE=true
            shift
            ;;
        --data-dir=*)
            ARG_DATA_DIR="${1#*=}"
            shift
            ;;
        --data-dir)
            ARG_DATA_DIR="$2"
            shift 2
            ;;
        --quota=*)
            ARG_QUOTA="${1#*=}"
            shift
            ;;
        --quota)
            ARG_QUOTA="$2"
            shift 2
            ;;
        --port=*)
            ARG_PORT="${1#*=}"
            shift
            ;;
        --port)
            ARG_PORT="$2"
            shift 2
            ;;
        --migrate)
            ARG_MIGRATE="yes"
            shift
            ;;
        --no-migrate)
            ARG_MIGRATE="no"
            shift
            ;;
        --no-start)
            ARG_START=false
            shift
            ;;
        -h|--help)
            cat << EOF
LAN Share Installer for Linux (Fedora & Ubuntu)

Usage:
  ./install.sh [options]

Options:
  --cli                Run in interactive command-line mode (forces terminal wizard)
  --unattended, -y     Run non-interactively using defaults or provided flags
  --data-dir=<path>    Location for user shared data (default: ~/Documents/LAN Share)
  --quota=<size>       Application storage quota (default: 2GB, e.g. 5GB, 10GB)
  --port=<port>        Server listening port (default: 8080)
  --migrate            Automatically migrate existing files and database
  --no-migrate         Do not migrate existing files
  --no-start           Do not automatically start the service after installation
  -h, --help           Show this help message
EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Run './install.sh --help' for available options."
            exit 1
            ;;
    esac
done

# Decide whether to use Zenity GUI mode
USE_GUI=false
if [ "$CLI_MODE" = false ] && [ -n "${DISPLAY:-${WAYLAND_DISPLAY:-}}" ] && command -v zenity >/dev/null 2>&1; then
    USE_GUI=true
fi

# Expand tilde in path
expand_path() {
    local p="$1"
    if [[ "$p" == ~* ]]; then
        echo "${p/#\~/$HOME}"
    else
        echo "$p"
    fi
}

# Parse size string into bytes
parse_bytes() {
    local str
    str=$(echo "$1" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    local mult=1
    if [[ "$str" =~ GB|G ]]; then mult=$((1024 * 1024 * 1024)); fi
    if [[ "$str" =~ MB|M ]]; then mult=$((1024 * 1024)); fi
    if [[ "$str" =~ KB|K ]]; then mult=1024; fi
    local num
    num=$(echo "$str" | grep -o '^[0-9]\+')
    echo $(( num * mult ))
}

# Format bytes into human readable string
format_bytes() {
    local bytes="$1"
    if [ "$bytes" -ge 1073741824 ]; then
        awk "BEGIN {printf \"%.1f GB\", $bytes / 1073741824}"
    elif [ "$bytes" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.1f MB\", $bytes / 1048576}"
    elif [ "$bytes" -ge 1024 ]; then
        awk "BEGIN {printf \"%.1f KB\", $bytes / 1024}"
    else
        echo "${bytes} B"
    fi
}

# Get free space on directory's filesystem in bytes
get_free_space_bytes() {
    local dir="$1"
    local check_dir="$dir"
    while [ ! -d "$check_dir" ]; do
        check_dir="$(dirname "$check_dir")"
    done
    local free_kb
    free_kb=$(df -Pk "$check_dir" 2>/dev/null | tail -1 | awk '{print $4}')
    echo $(( free_kb * 1024 ))
}

# Find local IPv4 address
get_lan_ip() {
    ip -4 -br addr show 2>/dev/null | awk '$1 !~ /^(lo|docker|podman|virbr|veth)/ && $2 == "UP" {print $3}' | cut -d/ -f1 | head -n 1
}

# Check prerequisites
check_prerequisites() {
    if ! command -v java >/dev/null 2>&1; then
        echo -e "${RED}Error: Java 21+ runtime is required but 'java' was not found in PATH.${RESET}"
        local pkg_cmd="sudo dnf install -y java-21-openjdk"
        if [[ "$DISTRO_ID" =~ (ubuntu|debian) ]] || [[ "${ID_LIKE:-}" =~ (ubuntu|debian) ]]; then
            pkg_cmd="sudo apt update && sudo apt install -y openjdk-21-jre"
        fi
        if [ "$USE_GUI" = true ]; then
            zenity --error --title="Prerequisite Missing" --text="Java 21+ is required but not installed.\n\nPlease run:\n${pkg_cmd}"
        fi
        echo -e "Please install Java with:\n  ${pkg_cmd}"
        exit 1
    fi
}

# Detect existing data in project directory
detect_existing_data() {
    local existing_files_count=0
    local has_existing=false
    if [ -d "$SCRIPT_DIR/data/uploads" ]; then
        existing_files_count=$(find "$SCRIPT_DIR/data/uploads" -maxdepth 1 -type f 2>/dev/null | wc -l || echo 0)
    fi
    if [ -f "$SCRIPT_DIR/data/db/lanshare.mv.db" ] || [ "$existing_files_count" -gt 0 ]; then
        has_existing=true
    fi
    echo "$has_existing:$existing_files_count"
}

# =====================================================================
# GUI WIZARD (ZENITY)
# =====================================================================
run_gui_wizard() {
    # Step 1: Welcome
    zenity --info --title="Welcome to LAN Share" --width=450 --text="\
<b>Welcome to the LAN Share Installation Wizard!</b>

LAN Share turns your $DISTRO_NAME PC into a private, high-speed local network cloud for:
  • Effortless Wi-Fi file transfer between PC and phones
  • Instant link and clipboard sharing
  • Optional password protection for sensitive downloads
  • Application storage quota management

Click <b>Next</b> to begin setup." --ok-label="Next"

    # Step 2: Choose Shared Data Location
    local chosen_dir=""
    while true; do
        chosen_dir=$(zenity --file-selection --directory --title="Step 2: Choose Shared Data Folder" --filename="$DEFAULT_DATA_DIR") || {
            zenity --info --text="Installation cancelled."
            exit 0
        }
        chosen_dir=$(expand_path "$chosen_dir")

        if [ ! -d "$chosen_dir" ]; then
            if zenity --question --title="Create Folder?" --text="The folder:\n<b>$chosen_dir</b>\ndoes not exist.\n\nWould you like to create it now?"; then
                mkdir -p "$chosen_dir"
                break
            fi
        else
            break
        fi
    done

    # Check available space
    local free_space
    free_space=$(get_free_space_bytes "$chosen_dir")
    local free_str
    free_str=$(format_bytes "$free_space")

    # Step 3: Choose Storage Limit
    local chosen_quota=""
    local quota_options="2GB\n1GB\n5GB\n10GB\nCustom"
    local selected_choice
    selected_choice=$(echo -e "$quota_options" | zenity --list --title="Step 3: Application Storage Limit" \
        --column="Quota Option" --text="Select the storage quota LAN Share is allowed to use:\n(Available disk space: $free_str)\n\nNote: This is an application limit, NOT a disk partition." --width=400 --height=300) || exit 0

    if [ "$selected_choice" = "Custom" ]; then
        chosen_quota=$(zenity --entry --title="Custom Storage Limit" --text="Enter desired storage limit (e.g., 4GB, 500MB):" --entry-text="2GB") || exit 0
    else
        chosen_quota="$selected_choice"
    fi

    local quota_bytes
    quota_bytes=$(parse_bytes "$chosen_quota")
    if [ "$quota_bytes" -gt "$free_space" ]; then
        zenity --warning --title="Storage Warning" --text="<b>Warning:</b> The selected quota (<b>$chosen_quota</b>) exceeds available disk space (<b>$free_str</b>) on this drive!\n\nUploads will be bounded by available disk space."
    fi

    # Server Port
    local chosen_port
    chosen_port=$(zenity --entry --title="Server Port" --text="Enter LAN Share listening port:" --entry-text="$DEFAULT_PORT") || chosen_port="$DEFAULT_PORT"

    # Step 4: Existing Data Migration
    local migration_choice="no"
    local existing_info
    existing_info=$(detect_existing_data)
    local has_existing="${existing_info%%:*}"
    local file_count="${existing_info##*:}"

    if [ "$has_existing" = "true" ]; then
        if zenity --question --title="Existing Data Detected" --text="Existing LAN Share data was found in:\n<b>$SCRIPT_DIR/data</b>\n($file_count uploaded files &amp; database)\n\nWould you like to migrate this data to your new shared folder:\n<b>$chosen_dir</b>?"; then
            migration_choice="yes"
        fi
    fi

    # Step 5: Review settings
    local review_text="<b>Please review your installation settings:</b>\n\n"
    review_text+="• <b>Application Directory:</b> $INSTALL_APP_DIR\n"
    review_text+="• <b>User Shared Data:</b> $chosen_dir\n"
    review_text+="• <b>Storage Limit:</b> $chosen_quota (Available: $free_str)\n"
    review_text+="• <b>Server Port:</b> $chosen_port\n"
    review_text+="• <b>Systemd Service:</b> $INSTALL_SYSTEMD_DIR/lan-share.service\n"
    review_text+="• <b>CLI Command:</b> $INSTALL_BIN_DIR/lanshare\n"
    review_text+="• <b>Migrate Data:</b> $migration_choice\n\n"
    review_text+="Click <b>Install</b> to complete setup."

    if ! zenity --question --title="Step 4: Review & Install" --width=500 --text="$review_text" --ok-label="Install" --cancel-label="Cancel"; then
        zenity --info --text="Installation cancelled."
        exit 0
    fi

    FINAL_DATA_DIR="$chosen_dir"
    FINAL_QUOTA="$chosen_quota"
    FINAL_PORT="$chosen_port"
    FINAL_MIGRATE="$migration_choice"
}

# =====================================================================
# TERMINAL CLI WIZARD
# =====================================================================
run_cli_wizard() {
    echo -e "${BOLD}${CYAN}==================================================================${RESET}"
    echo -e "${BOLD}${CYAN}  LAN Share - $DISTRO_NAME Installation Wizard${RESET}"
    echo -e "${BOLD}${CYAN}==================================================================${RESET}"
    echo -e "  LAN Share transforms your $DISTRO_NAME PC into a personal local"
    echo -e "  network cloud for fast, private file sharing across your Wi-Fi."
    echo -e "------------------------------------------------------------------"
    echo ""

    # Step 1: Shared Data Directory
    echo -e "${BOLD}Step 1: Choose Shared Data Location${RESET}"
    echo -e "Where should LAN Share store your uploaded files and database?"
    echo -e "Default: ${CYAN}$DEFAULT_DATA_DIR${RESET}"
    
    local chosen_dir=""
    if [ -n "$ARG_DATA_DIR" ]; then
        chosen_dir="$ARG_DATA_DIR"
        echo -e "Using specified location: ${GREEN}$chosen_dir${RESET}"
    elif [ "$UNATTENDED" = true ]; then
        chosen_dir="$DEFAULT_DATA_DIR"
    else
        read -r -p "Shared data location [default: $DEFAULT_DATA_DIR]: " input_dir
        chosen_dir="${input_dir:-$DEFAULT_DATA_DIR}"
    fi
    chosen_dir=$(expand_path "$chosen_dir")

    # Offer to create directory if not exists
    if [ ! -d "$chosen_dir" ]; then
        echo -e "Directory ${YELLOW}$chosen_dir${RESET} does not exist."
        if [ "$UNATTENDED" = true ]; then
            mkdir -p "$chosen_dir"
        else
            read -r -p "Create this folder now? [Y/n]: " create_confirm
            if [[ ! "${create_confirm:-y}" =~ ^[Yy] ]]; then
                echo -e "${RED}Installation aborted. Please select an existing directory.${RESET}"
                exit 1
            fi
            mkdir -p "$chosen_dir"
        fi
    fi
    echo -e "Shared data folder confirmed: ${GREEN}$chosen_dir${RESET}"
    echo ""

    # Check free disk space
    local free_space
    free_space=$(get_free_space_bytes "$chosen_dir")
    local free_str
    free_str=$(format_bytes "$free_space")

    # Step 2: Storage Quota
    echo -e "${BOLD}Step 2: Choose Application Storage Limit${RESET}"
    echo -e "How much storage quota is LAN Share allowed to use?"
    echo -e "(Available physical disk space on drive: ${BOLD}$free_str${RESET})"
    echo -e "${YELLOW}Note: This is an application storage limit, not a partition resize.${RESET}"
    
    local chosen_quota=""
    if [ -n "$ARG_QUOTA" ]; then
        chosen_quota="$ARG_QUOTA"
        echo -e "Using specified quota: ${GREEN}$chosen_quota${RESET}"
    elif [ "$UNATTENDED" = true ]; then
        chosen_quota="$DEFAULT_QUOTA"
    else
        echo "Options: [1] 1GB   [2] 2GB (default)   [3] 5GB   [4] 10GB   [5] Custom"
        read -r -p "Select storage limit [1-5, or enter size like 2GB]: " quota_choice
        case "$quota_choice" in
            1) chosen_quota="1GB" ;;
            2|"") chosen_quota="2GB" ;;
            3) chosen_quota="5GB" ;;
            4) chosen_quota="10GB" ;;
            5)
                read -r -p "Enter custom quota (e.g., 4GB, 500MB): " custom_quota
                chosen_quota="${custom_quota:-2GB}"
                ;;
            *)
                chosen_quota="$quota_choice"
                ;;
        esac
    fi

    # Standardize quota format
    chosen_quota=$(echo "$chosen_quota" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    if [[ ! "$chosen_quota" =~ ^[0-9]+(\.[0-9]+)?(GB|G|MB|M|KB|K|B)?$ ]]; then
        chosen_quota="2GB"
    fi
    if [[ ! "$chosen_quota" =~ (GB|G|MB|M|KB|K|B)$ ]]; then
        chosen_quota="${chosen_quota}GB"
    fi

    local quota_bytes
    quota_bytes=$(parse_bytes "$chosen_quota")
    if [ "$quota_bytes" -gt "$free_space" ]; then
        echo -e "${RED}${BOLD}WARNING: Configured quota ($chosen_quota) exceeds available free space ($free_str) on this partition!${RESET}"
        echo -e "${YELLOW}Uploads will be prevented once disk space or quota is exhausted.${RESET}"
    fi
    echo -e "Storage limit confirmed: ${GREEN}$chosen_quota${RESET}"
    echo ""

    # Step 3: Port
    local chosen_port=""
    if [ -n "$ARG_PORT" ]; then
        chosen_port="$ARG_PORT"
    elif [ "$UNATTENDED" = true ]; then
        chosen_port="$DEFAULT_PORT"
    else
        read -r -p "LAN Share server port [default: $DEFAULT_PORT]: " input_port
        chosen_port="${input_port:-$DEFAULT_PORT}"
    fi
    echo -e "Server port confirmed: ${GREEN}$chosen_port${RESET}"
    echo ""

    # Step 4: Existing Data Migration
    local migration_choice="no"
    local existing_info
    existing_info=$(detect_existing_data)
    local has_existing="${existing_info%%:*}"
    local file_count="${existing_info##*:}"

    if [ "$has_existing" = "true" ]; then
        echo -e "${BOLD}Step 3: Existing Data Migration${RESET}"
        echo -e "Detected existing LAN Share data in: ${CYAN}$SCRIPT_DIR/data${RESET}"
        echo -e "Found: ${BOLD}$file_count uploaded files${RESET} and H2 metadata database."
        
        if [ "$ARG_MIGRATE" = "yes" ]; then
            migration_choice="yes"
        elif [ "$ARG_MIGRATE" = "no" ]; then
            migration_choice="no"
        elif [ "$UNATTENDED" = true ]; then
            migration_choice="yes"
        else
            read -r -p "Migrate existing files & database to your new shared folder? [Y/n]: " mig_input
            if [[ "${mig_input:-y}" =~ ^[Yy] ]]; then
                migration_choice="yes"
            fi
        fi
        echo -e "Migration: ${GREEN}$migration_choice${RESET}"
        echo ""
    fi

    # Step 5: Review
    echo -e "${BOLD}${CYAN}==================================================================${RESET}"
    echo -e "${BOLD}Step 4: Review Installation Settings${RESET}"
    echo -e "${BOLD}${CYAN}==================================================================${RESET}"
    echo -e "  Application Dir   : $INSTALL_APP_DIR"
    echo -e "  CLI Executable    : $INSTALL_BIN_DIR/lanshare"
    echo -e "  Config File       : $INSTALL_CONFIG_DIR/lan-share.conf"
    echo -e "  Shared Data Dir   : $chosen_dir"
    echo -e "  Storage Quota     : $chosen_quota (Available disk: $free_str)"
    echo -e "  Server Port       : $chosen_port"
    echo -e "  Systemd Service   : $INSTALL_SYSTEMD_DIR/lan-share.service"
    echo -e "  Migrate Data      : $migration_choice"
    echo -e "------------------------------------------------------------------"

    if [ "$UNATTENDED" = false ]; then
        read -r -p "Proceed with installation? [Y/n]: " install_confirm
        if [[ ! "${install_confirm:-y}" =~ ^[Yy] ]]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi

    FINAL_DATA_DIR="$chosen_dir"
    FINAL_QUOTA="$chosen_quota"
    FINAL_PORT="$chosen_port"
    FINAL_MIGRATE="$migration_choice"
}

# =====================================================================
# PERFORM ACTUAL INSTALLATION
# =====================================================================
do_install() {
    echo ""
    echo -e "${BOLD}==> Installing LAN Share on $DISTRO_NAME...${RESET}"

    # 1. Ensure target directory structure exists
    mkdir -p "$INSTALL_APP_DIR"
    mkdir -p "$INSTALL_BIN_DIR"
    mkdir -p "$INSTALL_CONFIG_DIR"
    mkdir -p "$INSTALL_SYSTEMD_DIR"
    mkdir -p "$INSTALL_DESKTOP_DIR"
    mkdir -p "$INSTALL_ICONS_DIR/128x128/apps"
    mkdir -p "$INSTALL_ICONS_DIR/scalable/apps"

    # User Shared Data directory structure
    mkdir -p "$FINAL_DATA_DIR/uploads"
    mkdir -p "$FINAL_DATA_DIR/db"
    chmod 0750 "$FINAL_DATA_DIR"

    # 2. Build production JAR if not present
    local src_jar="$SCRIPT_DIR/target/lan-share-1.0.0.jar"
    if [ ! -f "$src_jar" ]; then
        echo "==> Building production application JAR..."
        (cd "$SCRIPT_DIR" && mvn clean package -DskipTests)
    fi

    # 3. Copy Application Files
    echo "==> Copying application files to $INSTALL_APP_DIR..."
    cp "$src_jar" "$INSTALL_APP_DIR/lan-share.jar"
    cp -r "$SCRIPT_DIR/tools" "$INSTALL_APP_DIR/"
    cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_APP_DIR/uninstall.sh"
    chmod +x "$INSTALL_APP_DIR/uninstall.sh"
    chmod +x "$INSTALL_APP_DIR/tools/"*.py 2>/dev/null || true

    # 4. Copy Icons & Desktop file
    if [ -f "$SCRIPT_DIR/assets/lan-share.png" ]; then
        cp "$SCRIPT_DIR/assets/lan-share.png" "$INSTALL_ICONS_DIR/128x128/apps/lan-share.png"
    fi
    if [ -f "$SCRIPT_DIR/assets/lan-share.svg" ]; then
        cp "$SCRIPT_DIR/assets/lan-share.svg" "$INSTALL_ICONS_DIR/scalable/apps/lan-share.svg"
    fi
    gtk-update-icon-cache -f -t "$INSTALL_ICONS_DIR" 2>/dev/null || true

    if [ -f "$SCRIPT_DIR/assets/lan-share.desktop" ]; then
        cp "$SCRIPT_DIR/assets/lan-share.desktop" "$INSTALL_DESKTOP_DIR/lan-share.desktop"
        update-desktop-database "$INSTALL_DESKTOP_DIR" 2>/dev/null || true
    fi

    # 5. Install CLI wrapper to ~/.local/bin/lanshare
    echo "==> Installing CLI management command to $INSTALL_BIN_DIR/lanshare..."
    cp "$SCRIPT_DIR/bin/lanshare" "$INSTALL_BIN_DIR/lanshare"
    chmod +x "$INSTALL_BIN_DIR/lanshare"

    # 6. Migrate existing data if requested
    if [ "$FINAL_MIGRATE" = "yes" ]; then
        echo "==> Migrating existing files and database..."
        if [ -d "$SCRIPT_DIR/data/uploads" ]; then
            cp -n "$SCRIPT_DIR/data/uploads/"* "$FINAL_DATA_DIR/uploads/" 2>/dev/null || true
        fi
        if [ -f "$SCRIPT_DIR/data/db/lanshare.mv.db" ]; then
            cp -n "$SCRIPT_DIR/data/db/lanshare.mv.db" "$FINAL_DATA_DIR/db/lanshare.mv.db" 2>/dev/null || true
        fi
        echo "    Data migrated successfully (originals preserved safely in $SCRIPT_DIR/data)."
    fi

    # 7. Write configuration file
    echo "==> Writing configuration to $INSTALL_CONFIG_DIR/lan-share.conf..."
    cat << EOF > "$INSTALL_CONFIG_DIR/lan-share.conf"
# =====================================================================
# LAN Share Configuration - $DISTRO_NAME Desktop
# =====================================================================
PORT=$FINAL_PORT
HOST=0.0.0.0
SHARED_DATA_DIR="$FINAL_DATA_DIR"
STORAGE_DIR="$FINAL_DATA_DIR/uploads"
DATA_DIR="$FINAL_DATA_DIR"
MAX_STORAGE_SIZE=$FINAL_QUOTA
MAX_FILE_SIZE=5120MB
MAX_REQUEST_SIZE=5120MB
JAVA_OPTS="-Xms128m -Xmx1024m -XX:+UseG1GC -Djava.awt.headless=true"
EOF

    # 8. Install and configure systemd user service
    local java_bin
    java_bin="$(command -v java 2>/dev/null || echo /usr/bin/java)"
    local bash_bin
    bash_bin="$(command -v bash 2>/dev/null || echo /usr/bin/bash)"

    echo "==> Configuring systemd user service..."
    cat << EOF > "$INSTALL_SYSTEMD_DIR/lan-share.service"
[Unit]
Description=LAN Share - Personal File & Link Sharing Server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/.local/share/lan-share
EnvironmentFile=%h/.config/lan-share/lan-share.conf
ExecStartPre=$bash_bin -c 'mkdir -p "\${STORAGE_DIR}" "\${DATA_DIR}/db"'
ExecStart=$java_bin \$JAVA_OPTS \\
    -Dserver.port=\${PORT} \\
    -Dserver.address=\${HOST} \\
    -Dlan.storage.location=\${STORAGE_DIR} \\
    -Dlan.storage.max-storage-size=\${MAX_STORAGE_SIZE} \\
    -DDATA_DIR=\${DATA_DIR} \\
    -Dconf.file=%h/.config/lan-share/lan-share.conf \\
    -Dspring.servlet.multipart.max-file-size=\${MAX_FILE_SIZE} \\
    -Dspring.servlet.multipart.max-request-size=\${MAX_REQUEST_SIZE} \\
    -jar %h/.local/share/lan-share/lan-share.jar

Restart=on-failure
RestartSec=5s
TimeoutStopSec=25s
KillSignal=SIGTERM
SendSIGKILL=yes
SuccessExitStatus=143

StandardOutput=journal
StandardError=journal
SyslogIdentifier=lan-share

LimitNOFILE=65536

[Install]
WantedBy=default.target
EOF

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user status >/dev/null 2>&1 || systemctl --user list-units >/dev/null 2>&1; then
            systemctl --user daemon-reload || true
            systemctl --user enable lan-share.service 2>/dev/null || true
        else
            echo "  Notice: systemd user session is inactive in this terminal session."
            echo "  The service unit was installed and will activate upon user login."
        fi
    fi

    echo -e "${GREEN}==> Installation completed successfully!${RESET}"

    # 9. Start service if requested
    if [ "$ARG_START" = true ]; then
        echo "==> Starting LAN Share..."
        "$INSTALL_BIN_DIR/lanshare" start
    fi

    # Display firewall guidance based on distro / tools
    if command -v ufw >/dev/null 2>&1; then
        echo -e "  ${YELLOW}Ubuntu Firewall Tip:${RESET} If remote devices cannot connect, run:"
        echo -e "    sudo ufw allow $FINAL_PORT/tcp"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo -e "  ${YELLOW}Fedora Firewall Tip:${RESET} If remote devices cannot connect, run:"
        echo -e "    sudo firewall-cmd --add-port=$FINAL_PORT/tcp --permanent && sudo firewall-cmd --reload"
    fi
}

# Run execution
check_prerequisites

if [ "$UNATTENDED" = true ] || [ "$CLI_MODE" = true ]; then
    run_cli_wizard
elif [ "$USE_GUI" = true ]; then
    run_gui_wizard
else
    run_cli_wizard
fi

do_install
