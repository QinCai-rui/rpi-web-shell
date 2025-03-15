#!/bin/bash

# RPi Web Shell Installer
# This script installs and configures the RPi Web Shell application

####################################################################################################
# Usage: 
# wget https://raw.githubusercontent.com/QinCai-rui/rpi-web-shell/refs/heads/main/quick-installer.sh
# chmod +x quick-installer.sh
# export USERNAME=$(whoami) && sudo ./quick-installer.sh 
####################################################################################################
set -e

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print colored text
print_green() { echo -e "${GREEN}$1${NC}"; }
print_yellow() { echo -e "${YELLOW}$1${NC}"; }
print_red() { echo -e "${RED}$1${NC}"; }

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  print_red "Please run this script as root or with sudo"
  exit 1
fi

# Installation destination
INSTALL_DIR="/usr/share/rpi-web-shell"
SERVICE_FILE="/etc/systemd/system/rpi-shell.service"
PORT=5001
USER=$USERNAME

print_green "========================================"
print_green "      RPi Web Shell Installer"
print_green "========================================"
echo ""

# Check for required utilities
print_yellow "Checking prerequisites..."
command -v git >/dev/null 2>&1 || { print_red "git is required but not installed. Installing git..."; apt-get update && apt-get install -y git; }
command -v python3 >/dev/null 2>&1 || { print_red "python3 is required but not installed. Installing python3..."; apt-get update && apt-get install -y python3 python3-venv; }

# Ask for custom port number
echo ""
read -p "Enter port number for RPi Web Shell [default: 5001]: " custom_port
if [[ ! -z "$custom_port" ]]; then
    if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1 ] && [ "$custom_port" -le 65535 ]; then
        PORT=$custom_port
    else
        print_yellow "Invalid port number. Using default port: 5001"
    fi
fi

# Generate a random API key
API_KEY=$(openssl rand -hex 16)

# Check if the installation directory already exists
if [ -d "$INSTALL_DIR" ]; then
    print_yellow "Installation directory already exists."
    read -p "Do you want to remove the existing installation? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        print_yellow "Removing existing installation..."
        rm -rf "$INSTALL_DIR"
    else
        print_red "Installation aborted."
        exit 1
    fi
fi

# Clone the repository
print_yellow "Cloning the RPi Web Shell repository..."
git clone https://github.com/QinCai-rui/rpi-web-shell.git "$INSTALL_DIR"

# Set up Python virtual environment
print_yellow "Setting up Python virtual environment..."
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate

# Install dependencies
print_yellow "Installing dependencies..."
pip install -r requirements.txt

# Create environment file with API key and port
print_yellow "Creating environment configuration..."
cat > env.py << EOL
API_KEY = "$API_KEY"
SHELL_PORT = $PORT
EOL

# Create systemd service file
print_yellow "Creating systemd service..."
cat > "$SERVICE_FILE" << EOL
[Unit]
Description=RPi Web Shell Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/shell_server.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=rpi-shell

[Install]
WantedBy=multi-user.target
EOL

# Set up locale if needed
if ! locale -a | grep -q "C.UTF-8"; then
    print_yellow "Setting up UTF-8 locale..."
    apt-get update
    apt-get install -y locales
    locale-gen C.UTF-8
    update-locale LC_ALL=C.UTF-8
fi

# Enable and start service
print_yellow "Enabling and starting RPi Web Shell service..."
systemctl daemon-reload
systemctl enable --now rpi-shell

# Check if service started successfully
if systemctl is-active --quiet rpi-shell; then
    print_green "RPi Web Shell service started successfully!"
else
    print_red "Failed to start RPi Web Shell service. Check logs with 'journalctl -u rpi-shell'"
fi

# Get server IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

# Final instructions
echo ""
print_green "========================================"
print_green "      Installation Complete!"
print_green "========================================"
echo ""
print_green "RPi Web Shell has been installed successfully."
echo ""
print_yellow "Access your web shell at: http://$SERVER_IP:$PORT"
print_yellow "API Key: $API_KEY"
echo ""
print_yellow "Please save this API key securely. You will need it to log in."
echo ""
print_yellow "To check the service status:"
echo "  sudo systemctl status rpi-shell"
echo ""
print_yellow "To view logs:"
echo "  sudo journalctl -u rpi-shell -f"
echo ""
print_yellow "To change the API key or port in the future:"
echo "  sudo nano $INSTALL_DIR/env.py"
echo "  sudo systemctl restart rpi-shell"
echo ""
print_yellow "To uninstall:"
echo "  sudo systemctl stop rpi-shell"
echo "  sudo systemctl disable rpi-shell"
echo "  sudo rm $SERVICE_FILE"
echo "  sudo rm -rf $INSTALL_DIR"
echo "  sudo systemctl daemon-reload"
echo ""

systemctl restart rpi-shell.service

print_green "Thank you for installing RPi Web Shell!"
