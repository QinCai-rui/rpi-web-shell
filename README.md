# RPi Web Shell

A lightweight web-based terminal interface for Raspberry Pi devices that provides secure shell access through your browser.

![RPi Web Shell Screenshot](https://github.com/user-attachments/assets/7dfa7dba-85f4-45b4-8e2f-a98ca0db98e1)

## Features

- Secure web-based terminal access to your Raspberry Pi
- API key authentication
- Real-time terminal with full-colour support
- Responsive design that works on desktop and mobile devices
- Automatic reconnection if connection is lost
- Compatible with standard terminal commands and applications
- Multi-tabbed

## Requirements

- Python 3.7+
- Flask and Flask-SocketIO
- Modern web browser with WebSocket support

## Installation

### Quick Install

```bash
sudo su -
```

```bash
cd /usr/share/

# Clone the repository
git clone https://github.com/QinCai-rui/rpi-web-shell.git
cd rpi-web-shell

# Create and activate virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create environment file with a random API key
echo "API_KEY=\"$(openssl rand -hex 16)\"" > env.py

# Run the server
python shell_server.py
```

### Installing as a Service

To run RPi Web Shell as a system service:

```bash
# Copy the service file
sudo cp rpi-shell.service /etc/systemd/system/

# Edit the service file paths if necessary
sudo nano /etc/systemd/system/rpi-shell.service

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable rpi-shell
sudo systemctl start rpi-shell
```

## Configuration

### API Key

The shell requires an API key for authentication. Create an `env.py` file with:

```python
API_KEY = "your-secure-api-key"
```

Or set the environment variable:

```bash
export API_KEY="your-secure-api-key"
```

### Port Configuration

By default, the shell runs on port 5001. To change the port:

```bash
# In env.py
SHELL_PORT = 8080
```

Or set the environment variable:

```bash
export SHELL_PORT=8080
```

## Usage

1. Start the server using instructions above
2. Open a browser and navigate to `http://your-raspberry-pi-ip:5001`
3. Enter your API key when prompted
4. Use the terminal as you would a regular SSH session

## Security Considerations

- This tool provides full shell access - only use it on secure networks or behind a VPN
- Always use a strong API key
- Consider setting up HTTPS using a reverse proxy like Nginx
- The service runs as the user that starts it - be careful about running as root

## Integrating with RPi-Metrics

This project works well alongside [RPi-Metrics](https://github.com/QinCai-rui/RPi-Metrics) for a complete Raspberry Pi monitoring and management solution.

To integrate:

1. Install both projects
2. Use the same API key in both projects
3. Set up RPi-Metrics to run on port 5000 and RPi Web Shell on port 5001
4. Access your metrics dashboard and shell from the same domain

## Troubleshooting

### UTF-8 Locale Issues

If you see errors related to UTF-8 locales:

```bash
# Install locales package
sudo apt-get update
sudo apt-get install -y locales

# Generate the C.UTF-8 locale
sudo locale-gen C.UTF-8
sudo update-locale LC_ALL=C.UTF-8
```

### Socket Connection Issues

If you experience connection issues:

1. Check that the server is running: `sudo systemctl status rpi-shell`
2. Verify port is open: `sudo netstat -tuln | grep 5001`
3. Ensure your firewall allows connections to the port: `sudo ufw allow 5001/tcp`

## License

This project is licensed under the GPLv3 License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Acknowledgements

- [GitHub Copilot](https://github.com/copilot)
- [Flask](https://flask.palletsprojects.com/)
- [Flask-SocketIO](https://flask-socketio.readthedocs.io/)
- [Xterm.js](https://xtermjs.org/)
