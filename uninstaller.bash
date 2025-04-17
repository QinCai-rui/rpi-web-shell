#!/bin/bash

# RPi Web Shell User Uninstaller
# This script completely removes the RPi Web Shell installation for the current user

# ANSI coluor codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print coloured text
print_green() { echo -e "${GREEN}$1${NC}"; }
print_yellow() { echo -e "${YELLOW}$1${NC}"; }
print_red() { echo -e "${RED}$1${NC}"; }

# Get current user
CURRENT_USER=$(whoami)
USER_HOME=$(eval echo ~$CURRENT_USER)

# paths
INSTALL_DIR="$USER_HOME/.rpi-web-shell"
SERVICE_DIR="$USER_HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/rpi-shell.service"

print_green "========================================"
print_green "    RPi Web Shell User Uninstaller"
print_green "========================================"
echo ""

# Check if installation exists
if [ ! -d "$INSTALL_DIR" ]; then
    print_yellow "RPi Web Shell installation not found at $INSTALL_DIR."
    echo ""
    read -p "Would you like to search for the installation elsewhere? [y/N]: " search_elsewhere
    if [[ "$search_elsewhere" =~ ^[Yy]$ ]]; then
        possible_locations=("$USER_HOME/rpi-web-shell" "/usr/share/rpi-web-shell" "/opt/rpi-web-shell")
        found=false
        
        for loc in "${possible_locations[@]}"; do
            if [ -d "$loc" ]; then
                print_yellow "Found installation at: $loc"
                read -p "Is this the installation you want to remove? [y/N]: " confirm_location
                if [[ "$confirm_location" =~ ^[Yy]$ ]]; then
                    INSTALL_DIR="$loc"
                    found=true
                    break
                fi
            fi
        done
        
        if [ "$found" = false ]; then
            print_yellow "No installation found in common locations."
            read -p "Please enter the path to your installation (or leave empty to abort): " custom_path
            if [ -z "$custom_path" ]; then
                print_red "Uninstallation aborted."
                exit 1
            elif [ -d "$custom_path" ]; then
                INSTALL_DIR="$custom_path"
            else
                print_red "Invalid path: $custom_path does not exist. Uninstallation aborted."
                exit 1
            fi
        fi
    else
        print_red "No installation found. Uninstallation aborted."
        exit 1
    fi
fi

# Confirm 
echo ""
print_yellow "This will completely remove RPi Web Shell from your system."
read -p "Are you sure you want to continue? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_red "Uninstallation aborted."
    exit 1
fi

#Stop and disable systemd service if it exists
print_yellow "Stopping RPi Web Shell service..."
if [ -f "$SERVICE_FILE" ]; then
    # Try user-level service first
    if systemctl --user --version >/dev/null 2>&1; then
        systemctl --user stop rpi-shell 2>/dev/null
        systemctl --user disable rpi-shell 2>/dev/null
        print_green "User service stopped and disabled."
    fi
    
    # Check for system-level service as well
    if [ -f "/etc/systemd/system/rpi-shell.service" ]; then
        print_yellow "System-level service detected. Requires sudo to remove."
        read -p "Would you like to remove the system service as well? [y/N]: " remove_system
        if [[ "$remove_system" =~ ^[Yy]$ ]]; then
            sudo systemctl stop rpi-shell 2>/dev/null
            sudo systemctl disable rpi-shell 2>/dev/null
            sudo rm -f "/etc/systemd/system/rpi-shell.service"
            sudo systemctl daemon-reload
            print_green "System service removed."
        fi
    fi
else
    print_yellow "No service file found at $SERVICE_FILE"
    
    # Check for system-level service (legacy ig)
    if [ -f "/etc/systemd/system/rpi-shell.service" ]; then
        print_yellow "System-level service detected. Requires sudo to remove."
        read -p "Would you like to remove the system service? [y/N]: " remove_system
        if [[ "$remove_system" =~ ^[Yy]$ ]]; then
            sudo systemctl stop rpi-shell 2>/dev/null
            sudo systemctl disable rpi-shell 2>/dev/null
            sudo rm -f "/etc/systemd/system/rpi-shell.service"
            sudo systemctl daemon-reload
            print_green "System service removed."
        fi
    fi
fi

if [ -f "$SERVICE_FILE" ]; then
    print_yellow "Removing service file..."
    rm -f "$SERVICE_FILE"
    
    # Reload systemd user daemon
    if systemctl --user --version >/dev/null 2>&1; then
        systemctl --user daemon-reload
    fi
fi

print_yellow "Checking for running processes..."
pids=$(ps aux | grep "[p]ython.*shell_server.py" | grep "$CURRENT_USER" | awk '{print $2}')
if [ -n "$pids" ]; then
    print_yellow "Found running processes. Terminating them..."
    for pid in $pids; do
        kill -15 "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
    done
    sleep 1
    print_green "Processes terminated."
else
    print_green "No running processes found."
fi

# Remove installation directory
print_yellow "Removing installation directory: $INSTALL_DIR"
if rm -rf "$INSTALL_DIR"; then
    print_green "Installation directory removed successfully."
else
    print_red "Failed to remove installation directory. You may need to remove it manually."
fi

if [ -d "$SERVICE_DIR" ] && [ -z "$(ls -A "$SERVICE_DIR")" ]; then
    rmdir "$SERVICE_DIR" 2>/dev/null
fi

if command -v loginctl >/dev/null 2>&1 && loginctl user-status "$CURRENT_USER" | grep -q "Linger: yes"; then
    print_yellow "User lingering is enabled for your account."
    echo "This allows services to keep running even when you're logged out."
    read -p "Do you want to disable lingering? [y/N]: " disable_linger
    if [[ "$disable_linger" =~ ^[Yy]$ ]]; then
        loginctl disable-linger "$CURRENT_USER"
        print_green "Lingering disabled."
    else
        print_yellow "Lingering remains enabled."
    fi
fi

if command -v ss >/dev/null 2>&1; then
    port=$(ss -tuln | grep ":${PORT:-5001}" | grep -v "^State" | wc -l)
    if [ "$port" -gt 0 ]; then
        print_yellow "Warning: Something is still using port ${PORT:-5001}."
        print_yellow "Use 'ss -tuln | grep :${PORT:-5001}' to check what's using it."
    fi
elif command -v netstat >/dev/null 2>&1; then
    port=$(netstat -tuln | grep ":${PORT:-5001}" | grep -v "^Proto" | wc -l)
    if [ "$port" -gt 0 ]; then
        print_yellow "Warning: Something is still using port ${PORT:-5001}."
        print_yellow "Use 'netstat -tuln | grep :${PORT:-5001}' to check what's using it."
    fi
fi

# Final messagess
echo ""
print_green "========================================"
print_green "      Uninstallation Complete!      "
print_green "========================================"
echo ""
print_green "RPi Web Shell has been successfully removed."
echo ""
print_yellow "If you encounter any issues, please check manually for:"
echo "1. Any remaining processes: ps aux | grep shell_server"
echo "2. Port bindings: ss -tuln (or netstat -tuln)"
echo "3. Systemd services: systemctl --user list-units | grep rpi-shell"
echo ""
print_green "Thank you for using RPi Web Shell!"