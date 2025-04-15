# RPi Web Shell

A lightweight web-based terminal interface for servers that provides secure shell access through your browser.

![RPi Web Shell Screenshot](https://github.com/user-attachments/assets/df8aee59-95c7-4bf6-a862-46ac0c5112ae)

## Features

- Secure web-based terminal access to your server
- API key authentication
- Real-time updating terminal with full-colour support
- Responsive design that works on desktop and mobile devices
- Compatible with all terminal commands and CLI applications
- Multi-tabbed

## Requirements

- Python 3.7+
- Flask and Flask-SocketIO
- Modern web browser with WebSocket support

## Installation

```bash
bash <(curl -sSL https://raw.githubusercontent.com/QinCai-rui/rpi-web-shell/refs/heads/main/universal-installer.bash)
```

And then follow the instructions.

## Usage

1. Start the server using instructions above
2. Open a browser and navigate to `http://your-server-ip:5001`
3. Enter your API key when prompted
4. Use the terminal as you would a regular SSH session

## Security Considerations

- This tool provides full shell access - only use it on secure networks or behind a VPN
- Always use a strong API key (default is randomly generated)
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
sudo apt update
sudo apt install -y locales

# Generate the C.UTF-8 locale
sudo locale-gen C.UTF-8
sudo update-locale LC_ALL=C.UTF-8
```

### Socket Connection Issues

If you experience connection issues:

1. Check that the server is running: `systemctl --user status rpi-shell`
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
