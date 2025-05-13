#!/bin/bash

# RPi Web Shell User Installer
# This script installs and configures the RPi Web Shell application for the current user
# Supports multiple users on the same server

# Parse command line arguments
ASSUME_YES=false
API_KEY=""
PORT=""        # Empty means use default
SHELL_METHOD="" # Empty means use default
PORT_PROVIDED=false
METHOD_PROVIDED=false
FONT_PROVIDED=false

# Process command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --help)
      echo "Usage: $0 [--assume-yes] [--api=API_KEY] [--port=PORT] [--method=METHOD]"
      echo "Options:"
      echo "  --help         Show this help message"
      echo "  --assume-yes   Automatically answer 'yes' to prompts"
      echo "  --api=API_KEY  Specify a custom API key"
      echo "  --port=PORT    Specify a custom port number (default: 5001)"
      echo "  --method=METHOD Specify shell connection method: 1=Direct shell, 2=SSH localhost (default: 1)"
      echo "  --font='FONT-NAME'  Specify a custom font name. Choose from \"Fira Code\" \"JetBrains Mono\" \"Source Code Pro\" \"Ubuntu Mono\""
      exit 0
      ;;
    --assume-yes)
      ASSUME_YES=true
      shift
      ;;
    --port=*)
      PORT="${1#*=}"
      PORT_PROVIDED=true
      if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo "Invalid port number. Must be between 1 and 65535."
        exit 1
      fi
      shift
      ;;
    --api=*)
      API_KEY="${1#*=}"
      shift
      ;;
    --method=*)
      SHELL_METHOD="${1#*=}"
      METHOD_PROVIDED=true
      if [[ ! "$SHELL_METHOD" =~ ^[1-2]$ ]]; then
        echo "Invalid shell method. Must be 1 (Direct shell) or 2 (SSH localhost)."
        exit 1
      fi
      shift
      ;;
    *)
      # Unknown option handling
      echo "Unknown option: $1"
      echo "Usage: $0 [--help] [--assume-yes] [--api=API_KEY] [--port=PORT] [--method=METHOD] [--font='FONT-NAME]"
      exit 1
      ;;
  esac
done

# Set defaults for empty values
if [ -z "$PORT" ]; then
  PORT=5001
fi

if [ -z "$SHELL_METHOD" ]; then
  SHELL_METHOD=1
fi

# ANSI colour codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No colour

# Print coloured text
print_green() { echo -e "${GREEN}$1${NC}"; }
print_yellow() { echo -e "${YELLOW}$1${NC}"; }
print_red() { echo -e "${RED}$1${NC}"; }

# Check if script is run as root and prevent that
#if [ "$EUID" -eq 0 ]; then
#  print_red "Please run this script as a regular user, NOT as root or with sudo. (for security reasons)"
#  exit 1
#fi

# Detect operating system
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VER=$VERSION_CODENAME
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        OS_VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        OS_VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_VER=$(cat /etc/debian_version)
    elif [ -f /etc/fedora-release ]; then
        OS="fedora"
    elif [ -f /etc/centos-release ]; then
        OS="centos"
    elif [ -f /etc/arch-release ]; then
        OS="arch"
    else
        OS=$(uname -s)
        OS_VER=$(uname -r)
    fi
    
    OS=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
    
    # Group similar distros
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "raspbian" ]]; then
        OS_FAMILY="debian"
    elif [[ "$OS" == "fedora" || "$OS" == "rhel" || "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
        OS_FAMILY="redhat"
    elif [[ "$OS" == "arch" || "$OS" == "manjaro" ]]; then
        OS_FAMILY="arch"
    elif [[ "$OS" == "opensuse"* || "$OS" == "sles" ]]; then
        OS_FAMILY="suse"
    else
        OS_FAMILY="unknown"
    fi
    
    print_yellow "Detected: $OS ($OS_FAMILY) version $OS_VER"
}

# Install required packages based on distro
install_required_packages() {
    local packages_to_check=("git" "python3" "python3-venv" "openssl")
    local missing_packages=()
    
    # Check which packages are missing
    for pkg in "${packages_to_check[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            # Special case for python3-venv 
            if [ "$pkg" = "python3-venv" ]; then
                if ! python3 -m venv --help >/dev/null 2>&1; then
                    missing_packages+=("$pkg")
                fi
            else
                missing_packages+=("$pkg")
            fi
        fi
    done
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        print_green "All required packages are already installed."
        return 0
    fi
    
    print_yellow "Missing packages: ${missing_packages[*]}"
    
    if [ "$ASSUME_YES" = false ]; then
        read -p "Do you want to install the missing packages? (y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_red "Required packages missing. Installation cannot continue without them."
            exit 1
        fi
    else
        print_yellow "Auto-installing missing packages (--assume-yes flag used)..."
    fi

    # Install missing packages based on distro
    case $OS_FAMILY in
        debian)
            print_yellow "Installing packages using apt..."
            sudo apt-get update
            sudo apt-get install -y git python3 python3-venv python3-pip openssl
            ;;
        redhat)
            print_yellow "Installing packages using dnf/yum..."
            if command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y git python3 python3-pip openssl
                # Fedora packages python3-venv differently
                if ! python3 -m venv --help >/dev/null 2>&1; then
                    sudo dnf install -y python3-virtualenv
                fi
            else
                sudo yum install -y git python3 python3-pip openssl
                if ! python3 -m venv --help >/dev/null 2>&1; then
                    sudo yum install -y python3-virtualenv
                fi
            fi
            ;;
        arch)
            print_yellow "Installing packages using pacman..."
            sudo pacman -S --noconfirm git python python-pip openssl
            ;;
        suse)
            print_yellow "Installing packages using zypper..."
            sudo zypper install -y git python3 python3-pip python3-virtualenv openssl
            ;;
        *)
            print_red "Unsupported distribution. Please install the required packages manually:"
            print_yellow "git, python3, python3-venv/virtualenv, openssl"
            if [ "$ASSUME_YES" = false ]; then
                read -p "Continue with installation? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            else
                print_yellow "Continuing installation (--assume-yes flag used)..."
            fi
            ;;
    esac
    
    # Check if packages were installed successfully
    for pkg in "${missing_packages[@]}"; do
        if [ "$pkg" = "python3-venv" ]; then
            if ! python3 -m venv --help >/dev/null 2>&1; then
                print_red "Failed to install $pkg. Installation cannot continue."
                exit 1
            fi
        elif ! command -v "$pkg" >/dev/null 2>&1; then
            print_red "Failed to install $pkg. Installation cannot continue."
            exit 1
        fi
    done
    
    print_green "All required packages installed successfully."
}

# Check and install SSH server/client if needed
install_ssh_if_needed() {
    if ! command -v ssh >/dev/null 2>&1; then
        print_yellow "SSH client not installed, but required for the SSH localhost option."
        if [ "$ASSUME_YES" = false ]; then
            read -p "Do you want to install SSH client? (y/n): " -n 1 -r
            echo
            
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_red "SSH client is required for the SSH localhost option. Switching to direct shell method."
                return 1
            fi
        else
            print_yellow "Auto-installing SSH client (--assume-yes flag used)..."
        fi
        
        case $OS_FAMILY in
            debian)
                sudo apt-get install -y openssh-client
                ;;
            redhat)
                if command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y openssh-clients
                else
                    sudo yum install -y openssh-clients
                fi
                ;;
            arch)
                sudo pacman -S --noconfirm openssh
                ;;
            suse)
                sudo zypper install -y openssh
                ;;
            *)
                print_red "Unsupported distribution. Please install SSH client manually."
                ;;
        esac
    fi
    
    # Check if SSH server is running
    local ssh_service="ssh"
    if [[ "$OS_FAMILY" == "redhat" ]]; then
        ssh_service="sshd"
    fi
    
    if ! systemctl is-active --quiet $ssh_service; then
        print_yellow "SSH server is not running, but required for the SSH localhost option."
        if [ "$ASSUME_YES" = false ]; then
            read -p "Do you want to install and start SSH server? (y/n): " -n 1 -r
            echo
            
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_red "SSH server is required for the SSH localhost option. Switching to direct shell method."
                return 1
            fi
        else
            print_yellow "Auto-installing SSH server (--assume-yes flag used)..."
        fi
        
        case $OS_FAMILY in
            debian)
                sudo apt-get install -y openssh-server
                sudo systemctl enable --now ssh
                ;;
            redhat)
                if command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y openssh-server
                else
                    sudo yum install -y openssh-server
                fi
                sudo systemctl enable --now sshd
                ;;
            arch)
                sudo pacman -S --noconfirm openssh
                sudo systemctl enable --now sshd
                ;;
            suse)
                sudo zypper install -y openssh
                sudo systemctl enable --now sshd
                ;;
            *)
                print_red "Unsupported distribution. Please install SSH server manually."
                ;;
        esac
    fi
    
    return 0
}

# Setup SSH public keys for password-less login
setup_ssh_keys() {
    # Check if the user has SSH keys set up
    if [ ! -f "$USER_HOME/.ssh/id_rsa" ] && [ ! -f "$USER_HOME/.ssh/id_ed25519" ]; then
        print_yellow "No SSH keys found. You need to set up passwordless SSH for the SSH localhost option."
        if [ "$ASSUME_YES" = false ]; then
            read -p "Do you want to set up SSH keys now? (y/n): " -n 1 -r
            echo
            
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_red "SSH keys are required for passwordless login. Switching to direct shell method."
                return 1
            fi
        else
            print_yellow "Auto-setting up SSH keys (--assume-yes flag used)..."
        fi
        
        # Create .ssh directory if it doesn't exist
        mkdir -p "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
        
        # Generate SSH key
        ssh-keygen -t ed25519 -f "$USER_HOME/.ssh/id_ed25519" -N "" -q
        
        # Add to authorized_keys
        cat "$USER_HOME/.ssh/id_ed25519.pub" >> "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
        
        print_green "SSH keys set up successfully."
    else
        # Check if public key is in authorized_keys
        local pub_key=""
        if [ -f "$USER_HOME/.ssh/id_ed25519.pub" ]; then
            pub_key=$(cat "$USER_HOME/.ssh/id_ed25519.pub")
        elif [ -f "$USER_HOME/.ssh/id_rsa.pub" ]; then
            pub_key=$(cat "$USER_HOME/.ssh/id_rsa.pub")
        fi
        
        if [ -n "$pub_key" ]; then
            if [ ! -f "$USER_HOME/.ssh/authorized_keys" ] || ! grep -q "$pub_key" "$USER_HOME/.ssh/authorized_keys"; then
                print_yellow "Adding your public key to authorized_keys for passwordless SSH login..."
                mkdir -p "$USER_HOME/.ssh"
                echo "$pub_key" >> "$USER_HOME/.ssh/authorized_keys"
                chmod 600 "$USER_HOME/.ssh/authorized_keys"
            fi
        fi
    fi
    
    # Test SSH connection
    print_yellow "Testing SSH localhost connection..."
    if ! ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no localhost "echo SSH connection successful" >/dev/null 2>&1; then
        print_red "SSH localhost connection test failed. There might be issues with passwordless login."
        if [ "$ASSUME_YES" = false ]; then
            read -p "Continue anyway or switch to direct shell method? (c/d): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Cc]$ ]]; then
                return 1
            fi
        else
            print_yellow "Switching to direct shell method (--assume-yes flag used)..."
            return 1
        fi
    else
        print_green "SSH localhost connection test successful."
    fi
    
    return 0
}

CURRENT_USER=$(whoami)
USER_HOME=$(eval echo ~$CURRENT_USER)

INSTALL_DIR="$USER_HOME/.rpi-web-shell"
SERVICE_DIR="$USER_HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/rpi-shell.service"

print_green "========================================"
print_green "    RPi Web Shell User Installer"
print_green "========================================"
echo ""

print_green "Installing for user '$CURRENT_USER'"

detect_os

install_required_packages

# Ask for custom port number if not provided via command line and not using auto-yes
if [ "$ASSUME_YES" = false ] && [ "$PORT_PROVIDED" = false ]; then
    echo ""
    read -p "Enter port number for RPi Web Shell [default: 5001]: " custom_port
    if [[ ! -z "$custom_port" ]]; then
        if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1 ] && [ "$custom_port" -le 65535 ]; then
            PORT=$custom_port
        else
            print_yellow "Invalid port number. Using default port: 5001"
        fi
    fi
fi

# Display the configured port
print_yellow "Using port: $PORT"

# Ask for custom API key if not specified in command line arguments and not using auto-yes
if [ "$ASSUME_YES" = false ] && [ -z "$API_KEY" ]; then
    echo ""
    read -p "Enter a custom API key or leave blank for auto-generated: " custom_api_key
    if [[ ! -z "$custom_api_key" ]]; then
        API_KEY=$custom_api_key
        print_yellow "Using provided API key"
    fi
fi

# Ask for shell method if not provided via command line and not using auto-yes
if [ "$ASSUME_YES" = false ] && [ "$METHOD_PROVIDED" = false ]; then
    echo ""
    print_yellow "Shell Connection Options:"
    echo "1) Direct shell (recommended for most users)"
    echo "2) SSH localhost (original method)"
    read -p "Choose connection method [1/2, default: 1]: " shell_method
    if [[ ! -z "$shell_method" ]]; then
        if [[ "$shell_method" =~ ^[1-2]$ ]]; then
            SHELL_METHOD=$shell_method
        else
            print_yellow "Invalid selection. Using direct shell method (1)."
        fi
    fi
fi

# Display which shell method is being used
if [ "$SHELL_METHOD" = "1" ]; then
    print_yellow "Using shell connection method: Direct shell"
else
    print_yellow "Using shell connection method: SSH localhost"
fi

# For SSH localhost method, ensure SSH is configured properly
if [ "$SHELL_METHOD" = "2" ]; then
    if ! install_ssh_if_needed || ! setup_ssh_keys; then
        print_yellow "Falling back to direct shell method due to SSH configuration issues."
        SHELL_METHOD=1
    fi
fi

# Generate API key if not specified
if [ -z "$API_KEY" ]; then
    API_KEY=$(openssl rand -hex 16)
    print_yellow "Generated random API key: $API_KEY"
else
    print_yellow "Using provided API key"
fi

# Check if the installation directory already exists
if [ -d "$INSTALL_DIR" ]; then
    print_yellow "Installation directory already exists."
    if [ "$ASSUME_YES" = false ]; then
        read -p "Do you want to remove the existing installation? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            print_yellow "Removing existing installation..."
            rm -rf "$INSTALL_DIR"
        else
            print_red "Installation aborted."
            exit 1
        fi
    else
        print_yellow "Removing existing installation (--assume-yes flag used)..."
        rm -rf "$INSTALL_DIR"
    fi
fi

print_yellow "Cloning the RPi Web Shell repository..."
git clone https://github.com/QinCai-rui/rpi-web-shell.git "$INSTALL_DIR"

##########
# Define available fonts
AVAILABLE_FONTS=("Fira Code" "JetBrains Mono" "Source Code Pro" "Ubuntu Mono")

# Parse command-line arguments
for arg in "$@"; do
    case $arg in
        --font=*)
        SELECTED_FONT="${arg#*=}"
        FONT_PROVIDED=true
        ;;
    esac
done

# Validate the provided font
if [ "$FONT_PROVIDED" = true ]; then
    if [[ ! " ${AVAILABLE_FONTS[@]} " =~ " ${SELECTED_FONT} " ]]; then
        echo "Invalid font: $SELECTED_FONT. Falling back to 'Fira Code'."
        SELECTED_FONT="Fira Code"
    else
        echo "Using font provided via --font flag: $SELECTED_FONT"
    fi
elif [ "$ASSUME_YES" = false ]; then
    # Interactive font selection
    echo -e "\nSelect a font for the RPi Web Shell:"
    for i in "${!AVAILABLE_FONTS[@]}"; do
        echo "$((i+1))) ${AVAILABLE_FONTS[$i]}"
    done
    read -p "Enter the number of your choice (1-${#AVAILABLE_FONTS[@]}): " font_choice
    if [[ "$font_choice" =~ ^[0-9]+$ ]] && (( font_choice >= 1 && font_choice <= ${#AVAILABLE_FONTS[@]} )); then
        SELECTED_FONT="${AVAILABLE_FONTS[$((font_choice-1))]}"
        echo "You selected: $SELECTED_FONT"
    else
        echo "Invalid choice. Defaulting to 'Fira Code'."
        SELECTED_FONT="Fira Code"
    fi
else
    # Default font in non-interactive mode
    SELECTED_FONT="Fira Code"
    echo "Assume-yes flag is set. Defaulting font to 'Fira Code'."
fi

# Apply the selected font to the CSS file
CSS_FILE="$INSTALL_DIR/static/css/shell.css"
sed -i "s/font-family: 'Fira Code'/font-family: '$SELECTED_FONT'/g" "$CSS_FILE"

HTML_FILE="$INSTALL_DIR/templates/shell.html"

# Define function to get Google Fonts URL based on selected font
get_google_fonts_url() {
    local font_name="$1"
    local url=""
    
    case "$font_name" in
        "Fira Code")
            url="https://fonts.googleapis.com/css2?family=Fira+Code:wght@300..700&display=swap"
            ;;
        "JetBrains Mono")
            url="https://fonts.googleapis.com/css2?family=JetBrains+Mono&display=swap"
            ;;
        "Source Code Pro")
            url="https://fonts.googleapis.com/css2?family=Source+Code+Pro&display=swap"
            ;;
        "Ubuntu Mono")
            url="https://fonts.googleapis.com/css2?family=Ubuntu+Mono&display=swap"
            ;;
        *)
            # Default to Fira Code
            url="https://fonts.googleapis.com/css2?family=Fira+Code:wght@300..700&display=swap"
            ;;
    esac
    
    echo "$url"
}
FONTS_URL=$(get_google_fonts_url "$SELECTED_FONT")

# Remove existing Google Fonts links
sed -i '/fonts.googleapis.com/d' "$HTML_FILE"

# Properly escape the URL for sed
ESCAPED_URL=$(echo "$FONTS_URL" | sed 's/&/\\&/g')

# Insert the new font link after the shell.css stylesheet
sed -i '/static\/css\/shell.css/a <link href="'"$ESCAPED_URL"'" rel="stylesheet">' "$HTML_FILE"

# Update the JavaScript file to reflect the font selection
JS_FILE="$INSTALL_DIR/static/js/shell.js"
sed -i "s/fontFamily: 'Fira Code, Courier New, monospace'/fontFamily: '$SELECTED_FONT'/g" "$JS_FILE"

echo "Font selection applied successfully! Using: $SELECTED_FONT with URL: $FONTS_URL"
# Font section
##########

print_yellow "Setting up Python virtual environment..."
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate

print_yellow "Installing dependencies..."
pip install flask flask-socketio python-socketio eventlet

print_yellow "Creating environment configuration..."
cat > env.py << EOL
API_KEY = "$API_KEY"
SHELL_PORT = $PORT
EOL

# Modify shell_server.py to use the current user's home directory
print_yellow "Modifying shell server configuration..."
sed -i "s|SHELL_ENV\['HOME'\] = '/root'|SHELL_ENV['HOME'] = '$USER_HOME'|g" shell_server.py

# Update the shell command based on user selection
USER_SHELL=$(grep "^$CURRENT_USER:" /etc/passwd | cut -d: -f7)
if [ -z "$USER_SHELL" ]; then
    USER_SHELL="/bin/bash"
fi
print_yellow "Setting default shell to: $USER_SHELL"
sed -i "s|SHELL_ENV\['SHELL'\] = '/bin/bash'|SHELL_ENV['SHELL'] = '$USER_SHELL'|g" shell_server.py

# Update shell command based on user's choice
if [ "$SHELL_METHOD" = "1" ]; then
    # Direct shell method
    print_yellow "Setting up direct shell access..."
    sed -i "s|\['/bin/bash', '-c', 'cd ~ && exec /bin/bash -c \"ssh localhost\"'\]|\['$USER_SHELL'\]|g" shell_server.py
    echo "USE_SSH_LOCALHOST = False" >> env.py
    
    # Also update the working directory to home directory
    sed -i "/process = subprocess.Popen(/,/)/c\\        # Start the user's shell directly\\n        process = subprocess.Popen(\\n            ['$USER_SHELL'],\\n            preexec_fn=os.setsid,\\n            stdin=slave,\\n            stdout=slave,\\n            stderr=slave,\\n            universal_newlines=True,\\n            cwd='$USER_HOME',\\n            env=SHELL_ENV\\n        )" shell_server.py
else
    # SSH localhost method (original)
    print_yellow "Setting up SSH localhost connection..."
    echo "USE_SSH_LOCALHOST = True" >> env.py
fi

# Create user systemd directory if it doesn't exist
mkdir -p "$SERVICE_DIR"

# Create systemd service file (user level)
print_yellow "Creating user systemd service..."
cat > "$SERVICE_FILE" << EOL
[Unit]
Description=RPi Web Shell Service (User: $CURRENT_USER)
After=network.target

[Service]
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/shell_server.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=rpi-shell

[Install]
WantedBy=default.target
EOL

# Check if systemd user service is available
if ! systemctl --user --version >/dev/null 2>&1; then
    print_yellow "Warning: systemd user service not available. Service will not be installed."
    print_yellow "You can start the shell server manually with:"
    print_yellow "cd $INSTALL_DIR && source venv/bin/activate && python shell_server.py"
else
    # Enable and start user service
    print_yellow "Enabling and starting RPi Web Shell user service..."
    systemctl --user daemon-reload
    systemctl --user enable --now rpi-shell

    # Enable lingering for the user to keep service running after logout
    print_yellow "Enabling lingering to keep service running after logout..."
    if command -v loginctl >/dev/null 2>&1; then
        loginctl enable-linger "$CURRENT_USER" || print_yellow "Failed to enable lingering. Service may stop after logout."
    else
        print_yellow "loginctl not available. Service may stop after logout."
    fi

    # Check if service started successfully
    if systemctl --user is-active --quiet rpi-shell; then
        print_green "RPi Web Shell service started successfully!"
    else
        print_red "Failed to start RPi Web Shell service. Check logs with 'journalctl --user -u rpi-shell'"
    fi
fi

# Get server IP address
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="localhost"
fi

echo ""
print_green "========================================"
print_green "      Installation Complete!"
print_green "========================================"
echo ""
print_green "RPi Web Shell has been installed successfully for user $CURRENT_USER."
echo ""
print_yellow "Access your web shell at: http://$SERVER_IP:$PORT"
print_yellow "API Key: $API_KEY"
echo ""
print_yellow "Please save this API key securely. You will need it to log in."
echo ""

if systemctl --user --version >/dev/null 2>&1; then
    print_yellow "To check the service status:"
    echo "  systemctl --user status rpi-shell"
    echo ""
    print_yellow "To view logs:"
    echo "  journalctl --user -u rpi-shell -f"
    echo ""
    print_yellow "To change the API key or port in the future:"
    echo "  nano $INSTALL_DIR/env.py"
    echo "  systemctl --user restart rpi-shell"
    echo ""
    print_yellow "To uninstall:"
    echo "  systemctl --user stop rpi-shell"
    echo "  systemctl --user disable rpi-shell"
    echo "  rm -rf $INSTALL_DIR"
    echo "  rm $SERVICE_FILE"
    echo "  systemctl --user daemon-reload"
else
    print_yellow "To start the shell manually:"
    echo "  cd $INSTALL_DIR && source venv/bin/activate && python shell_server.py"
    echo ""
    print_yellow "To change the API key or port in the future:"
    echo "  nano $INSTALL_DIR/env.py"
    echo ""
    print_yellow "To uninstall:"
    echo "  rm -rf $INSTALL_DIR"
    echo "  rm -f $SERVICE_FILE"
fi
echo ""

print_yellow "Command line flags:"
echo "  --help         : Show help message"
echo "  --assume-yes   : Skip all prompts and use default values"
echo "  --api=API_KEY  : Specify a custom API key"
echo "  --port=PORT    : Specify a custom port number (default: 5001)"
echo "  --method=METHOD: Specify shell connection method: 1=Direct shell, 2=SSH localhost (default: 1)"
echo ""

print_green "Thank you for installing RPi Web Shell!"
