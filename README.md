# LAN Share - Self-Hosted Local File & Link Sharing

> [!IMPORTANT]
> **Local Network Only**: LAN Share is designed for high-speed file and link sharing over your trusted local network (LAN / Wi-Fi). It is not intended to be exposed directly to the public internet without a secure reverse proxy and TLS encryption.

A fast, lightweight, personal local-network file and link sharing application built for **Linux (Fedora & Ubuntu)** and mobile devices connected to the same Wi-Fi.

---

## Operating System Support

* **Fedora Linux**: **Tested & Verified**. Live-tested directly on Fedora Linux Workstation. Native systemd user services, Zenity installer, desktop shortcuts, and dynamic quota management have been verified.
* **Ubuntu Linux**: **Supported by Design**. Adheres strictly to Linux standards (Java NIO filesystem operations, XDG Base Directory specification, standard systemd user session model, and Debian/Ubuntu package references). Not live-tested on this development machine.

---

## Features

* **Installable Linux Desktop Software**: Native user-level application for Fedora Linux and Ubuntu Linux with desktop launcher, application icons, systemd user service (`systemctl --user`), and a global `lanshare` CLI tool in `$PATH`.
* **Architectural Separation**: Application binaries (`~/.local/share/lan-share/`) are kept separate from user shared data (`~/Documents/LAN Share/` or custom folder). Reinstalling or upgrading the app never touches user files.
* **Password Protection for Files**: Optional password protection for individual files at upload time. Plaintext passwords are never stored (BCrypt hashed), never put in URLs or logs, and enforced across both download and preview endpoints. Unprotected files remain accessible without passwords.
* **Hard Application Storage Quota**: Configurable storage quota (e.g., 2 GB, 5 GB, 10 GB) preventing uploads when exceeded, with space reclaimed instantly when files are deleted. Live quota indicators in the UI and dynamic CLI configuration (`lanshare set-quota 5GB`) without restarting the server.
* **Direct LAN Transfer**: All transfers occur directly over your Wi-Fi network between your devices and your PC. No third-party servers, no cloud subscriptions, no external tracking.
* **Bidirectional File Sharing**: Upload photos, videos, documents, or large files directly from your phone or PC with drag-and-drop, real-time upload progress bars, and transfer speeds.
* **Link & Clipboard Sharing**: Save URLs and text snippets with automatic title detection, one-click clipboard copying, and direct open buttons.
* **Mobile Connection QR Code**: Generate an instant terminal QR code or view the in-app QR code to connect mobile devices over Wi-Fi.
* **Security**: Built-in path traversal defense, UUID file storage naming on disk, POSIX non-executable permissions on uploads, and temporary single-file access tokens for media previews.
* **Embedded Database**: Zero-configuration embedded H2 database (`lanshare.mv.db`) persists file metadata and links across server restarts.
* **Graceful Shutdown**: Handles `SIGTERM`/`SIGINT` cleanly, allowing in-flight transfers to finish and safely flushing database transactions.

---

## Quick Start Guide

### 1. Clone the Repository
```bash
git clone https://github.com/<your-username>/lan-share.git
cd lan-share
```

### 2. Install Prerequisites

LAN Share requires Java 21+ runtime.

**On Fedora Linux:**
```bash
sudo dnf install java-21-openjdk zenity
```

**On Ubuntu Linux:**
```bash
sudo apt update
sudo apt install openjdk-21-jre zenity
```
*(Note: `zenity` provides the graphical installation wizard. If omitted or running in a headless SSH session, the installer automatically runs the interactive CLI terminal wizard).*

---

## Installation & Setup

### 1. Run the Installer
Run the native installer script:
```bash
./install.sh
```

During installation, the wizard allows you to:
1. **Choose your Shared Data Directory**: Specify where uploaded files and database should live (default: `~/Documents/LAN Share/`).
2. **Choose your Storage Quota**: Set the maximum storage LAN Share is allowed to use (e.g., `2GB`, `5GB`, `10GB`, or custom).
3. **Set Server Port**: Default is `8080`.
4. **Migrate Existing Data**: Automatically imports existing files if upgrading from an earlier version.

**Unattended / Scripted Installation:**
```bash
./install.sh --unattended --data-dir="$HOME/Documents/LAN Share" --quota="5GB" --port=8080 --migrate
```

---

## Connecting Your Phone Over Wi-Fi

1. Ensure your phone and Linux PC are connected to the **same Wi-Fi network**.
2. Start LAN Share if not already running:
   ```bash
   lanshare start
   ```
3. Display the connection QR code in your terminal:
   ```bash
   lanshare qr
   ```
   *(Or open `http://localhost:8080` in your browser and click "Connect Phone" to view the QR code on screen).*
4. Open your phone's camera or QR scanner app, scan the code, and open the URL. You can now upload and download files directly!

---

## Management Commands

Once installed, the global `lanshare` command is available anywhere in your terminal:

```bash
lanshare start            # Start the service in the background
lanshare stop             # Stop the service gracefully
lanshare restart          # Restart the service
lanshare status           # Display status, storage quota, LAN URLs, and QR code
lanshare set-quota 5GB    # Change application storage quota dynamically
lanshare qr               # Display phone pairing QR code in terminal
lanshare open             # Open LAN Share in default web browser
lanshare logs -f          # Stream real-time logs
lanshare uninstall        # Uninstall application while safely preserving shared files
```

Or manage via standard Linux systemd user commands:
```bash
systemctl --user start lan-share
systemctl --user stop lan-share
systemctl --user status lan-share
```

---

## Management Commands

### 1. Build Production Package
```bash
./lanshare.sh build
```
*(Or via Maven: `mvn clean package -DskipTests`)*

### 2. Start Server
**As a background personal server (recommended):**
```bash
./lanshare.sh start
```
*(Or with start.sh: `./start.sh -d`)*

**In interactive foreground mode (Ctrl+C to stop):**
```bash
./start.sh
# or
./lanshare.sh run
```

### 3. Check Status & Health
```bash
./lanshare.sh status
```
Displays running PID, memory usage (RSS), CPU usage, listening port, active storage directory, actuator health status, and direct LAN URLs.

### 4. View Logs
```bash
# View last 50 lines
./lanshare.sh logs

# Stream real-time logs
./lanshare.sh logs -f

# View last N lines
./lanshare.sh logs -n 100
```
Log files are stored at `logs/lan-share.log`.

### 5. Stop Server
```bash
./lanshare.sh stop
```
Sends a `SIGTERM` signal, allowing Spring Boot to complete active requests before cleanly unmounting database pools.

### 6. Restart Server
```bash
./lanshare.sh restart
```

---

## Configuration

Settings are easily configured in `lan-share.conf`:

```bash
# Server Port (default: 8080)
PORT=8080

# Bind Address (0.0.0.0 listens on all interfaces)
HOST=0.0.0.0

# Directory where uploaded files are stored (tilde ~ is expanded)
STORAGE_DIR=./data/uploads

# Persistent database directory
DATA_DIR=./data

# Maximum upload file size
MAX_FILE_SIZE=5120MB
MAX_REQUEST_SIZE=5120MB

# JVM memory and performance options
JAVA_OPTS="-Xms128m -Xmx1024m -XX:+UseG1GC -Djava.awt.headless=true"
```

### Dynamic One-Off Overrides
You can also override any configuration directly on the command line:
```bash
PORT=9000 STORAGE_DIR=~/Downloads/shared ./lanshare.sh start
```

---

## Linux systemd Service (Optional Auto-Start)

The application includes a systemd unit file configured for standard Linux desktop distributions (Fedora, Ubuntu, Debian, etc.).

### Why systemd User Service?
Running as a **user service** (`systemctl --user`) is recommended on both Fedora and Ubuntu because:
1. It does not require `sudo` or root privileges.
2. Files and uploads remain owned by your standard user account (`$USER`), preventing permission conflicts.
3. Systemd automatically restarts the service if it crashes (`Restart=on-failure`).
4. Logs integrate directly into `journalctl`.

### Location
The unit file is installed at:
`~/.config/systemd/user/lan-share.service`

### Managing via systemd
```bash
# Start service
systemctl --user start lan-share.service

# Stop service gracefully
systemctl --user stop lan-share.service

# Check service status
systemctl --user status lan-share.service

# View live systemd logs
journalctl --user -u lan-share.service -f
```

### Optional: Enable Auto-Start on System Boot
By default, the service is **disabled** from auto-starting.

1. **To start automatically when you log into your Linux desktop:**
   ```bash
   systemctl --user enable lan-share.service
   ```

2. **To start automatically at machine boot (even before graphical login / headless):**
   Systemd user instances normally start on login. To enable the user service to start at boot without logging in:
   ```bash
   loginctl enable-linger $USER
   systemctl --user enable lan-share.service
   ```

3. **To disable auto-start anytime:**
   ```bash
   systemctl --user disable lan-share.service
   ```

---

## Firewall Configuration (If Remote Devices Cannot Connect)

If other phones or laptops on your Wi-Fi cannot access LAN Share:

**On Ubuntu Linux (`ufw`):**
```bash
sudo ufw allow 8080/tcp
```

**On Fedora Linux (`firewalld`):**
```bash
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload
```

---

## License

LAN Share is open-source software licensed under the [MIT License](LICENSE). Copyright (c) 2026 Aditya Mudgal.
