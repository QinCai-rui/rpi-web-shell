#!/usr/bin/env python3
"""
RPi Web Shell - A simple web-based terminal for Raspberry Pi
Run this alongside your main RPi-Metrics server for isolated shell functionality
"""

import os
import pty
import select
import termios
import struct
import fcntl
import signal
import subprocess
import threading
import sys
import time
from flask import Flask, render_template, request, send_from_directory, session
from flask_socketio import SocketIO, emit, join_room, leave_room

# Import API_KEY from env (same as RPi-Metrics)
try:
    sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import env
    API_KEY = env.API_KEY
    PORT = int(env.SHELL_PORT)
except ImportError:
    # Fallback in case env.py doesn't exist
    API_KEY = os.getenv("API_KEY", "change-this-key")
    PORT = int(os.getenv("SHELL_PORT", 5001))

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)

# Enhanced Socket.IO configuration for better stability
socketio = SocketIO(
    app,
    async_mode='threading',
    cors_allowed_origins="*",
    ping_timeout=60,      # Increased ping timeout
    ping_interval=25,     # Adjusted ping interval
    reconnection_attempts=5,
    logger=True,          # Enable logging for debugging
    engineio_logger=True
)

# Store active shells by session ID and terminal ID
shells = {}

# Track authenticated sessions
authenticated_sessions = set()

# Set a complete environment for shell processes
SHELL_ENV = os.environ.copy()

# Standard PATH
SHELL_ENV['PATH'] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
if 'PATH' in os.environ:
    SHELL_ENV['PATH'] = os.environ['PATH'] + ":" + SHELL_ENV['PATH']

# Set HOME environment variable if not already set
if 'HOME' not in SHELL_ENV:
    SHELL_ENV['HOME'] = '/root'

# Set terminal environment variables
SHELL_ENV['TERM'] = 'xterm-256color'
SHELL_ENV['SHELL'] = '/bin/bash'

def store_auth_state(sid, api_key):
    """Store authentication state for reconnection"""
    session['auth_key'] = api_key
    authenticated_sessions.add(sid)
    print(f"Stored authentication state for session {sid}")

def is_authenticated(sid):
    """Check if the session is authenticated"""
    # Check both current session and stored authentication
    return sid in authenticated_sessions or ('auth_key' in session and session['auth_key'] == API_KEY)

@app.route('/')
def index():
    return render_template('shell.html')

@app.route('/static/<path:path>')
def serve_static(path):
    return send_from_directory('static', path)

@socketio.on('connect')
def handle_connect():
    print(f"Client connected: {request.sid}")
    # Check if there's a stored authentication
    if 'auth_key' in session and session['auth_key'] == API_KEY:
        authenticated_sessions.add(request.sid)
        join_room(request.sid)
        emit('authentication_success')

@socketio.on('disconnect')
def handle_disconnect():
    print(f"Client disconnected: {request.sid}")
    
    if request.sid in shells:
        # Clean up shells but maintain authentication state
        terminal_ids = list(shells[request.sid].keys())
        for terminal_id in terminal_ids:
            kill_shell(request.sid, terminal_id)
        del shells[request.sid]
    leave_room(request.sid)

@socketio.on('reconnect')
def handle_reconnect():
    print(f"Client reconnecting: {request.sid}")
    if 'auth_key' in session and session['auth_key'] == API_KEY:
        authenticated_sessions.add(request.sid)
        join_room(request.sid)
        emit('authentication_success')
    else:
        emit('authentication_failed')

@socketio.on('authenticate')
def handle_authenticate(data):
    client_api_key = data.get('apiKey')
    if client_api_key == API_KEY:
        store_auth_state(request.sid, client_api_key)
        join_room(request.sid)
        emit('authentication_success')
    else:
        emit('authentication_failed')

@socketio.on('create_shell')
def handle_create_shell(data):
    print(f"Received create_shell request: {data}")  # Debug logging
    # Check authentication before allowing terminal creation
    if not is_authenticated(request.sid):
        print(f"Authentication failed for session {request.sid}")  # Debug logging
        emit('authentication_failed')
        return
        
    terminal_id = data.get('terminalId')
    cols = data.get('cols', 80)
    rows = data.get('rows', 24)
    
    success = create_shell(request.sid, terminal_id, cols, rows)
    if success:
        print(f"Successfully created shell for terminal {terminal_id}")  # Debug logging
        # Send initial prompt
        socketio.emit('shell_output', {
            'terminalId': terminal_id,
            'output': f"\r\n{os.getenv('USER')}@{os.uname()[1]}:~$ "
        }, room=request.sid)
    else:
        print(f"Failed to create shell for terminal {terminal_id}")  # Debug logging
        socketio.emit('shell_error', {
            'terminalId': terminal_id,
            'error': 'Failed to create shell'
        }, room=request.sid)

@socketio.on('shell_input')
def handle_shell_input(data):
    if not is_authenticated(request.sid):
        emit('authentication_failed')
        return
        
    terminal_id = data.get('terminalId')
    input_text = data.get('input', '')
    
    success = write_to_shell(request.sid, terminal_id, input_text)
    return {'success': success}

@socketio.on('resize_terminal')
def handle_resize_terminal(data):
    if not is_authenticated(request.sid):
        emit('authentication_failed')
        return
        
    terminal_id = data.get('terminalId')
    cols = data.get('cols', 80)
    rows = data.get('rows', 24)
    
    resize_terminal(request.sid, terminal_id, cols, rows)

@socketio.on('close_shell')
def handle_close_shell(data):
    if not is_authenticated(request.sid):
        emit('authentication_failed')
        return
        
    terminal_id = data.get('terminalId')
    kill_shell(request.sid, terminal_id)

def create_shell(session_id, terminal_id, cols=80, rows=24):
    """Create a new shell process for a session and terminal ID"""
    try:
        # Create a pseudo-terminal
        master, slave = pty.openpty()
        
        # Start bash with a complete environment and change to home directory
        process = subprocess.Popen(
            ['/bin/bash', '-c', 'cd ~ && exec /bin/bash'],
            preexec_fn=os.setsid,
            stdin=slave,
            stdout=slave,
            stderr=slave,
            universal_newlines=True,
            env=SHELL_ENV
        )
        
        # Set terminal size
        fcntl.ioctl(
            master,
            termios.TIOCSWINSZ,
            struct.pack("HHHH", rows, cols, 0, 0)
        )
        
        # Initialize session if needed
        if session_id not in shells:
            shells[session_id] = {}
        
        # Store shell data
        shells[session_id][terminal_id] = {
            'process': process,
            'master': master,
            'slave': slave,
            'thread': None,
            'running': True
        }
        
        # Start output reader thread
        thread = threading.Thread(
            target=read_output,
            args=(session_id, terminal_id, master),
            daemon=True
        )
        thread.start()
        shells[session_id][terminal_id]['thread'] = thread
        
        return True
    except Exception as e:
        print(f"Error creating shell: {e}")
        socketio.emit('shell_error', {'terminalId': terminal_id, 'error': str(e)}, room=session_id)
        return False

def resize_terminal(session_id, terminal_id, cols, rows):
    """Resize the terminal"""
    if session_id in shells and terminal_id in shells[session_id]:
        try:
            fcntl.ioctl(
                shells[session_id][terminal_id]['master'],
                termios.TIOCSWINSZ,
                struct.pack("HHHH", rows, cols, 0, 0)
            )
            return True
        except Exception as e:
            print(f"Error resizing terminal: {e}")
            return False
    return False

def write_to_shell(session_id, terminal_id, data):
    """Write data to the shell"""
    if session_id in shells and terminal_id in shells[session_id]:
        try:
            os.write(shells[session_id][terminal_id]['master'], data.encode('utf-8'))
            return True
        except Exception as e:
            print(f"Error writing to shell: {e}")
            return False
    return False

def read_output(session_id, terminal_id, fd):
    """Read output from the shell and emit it via socketio"""
    max_read_bytes = 1024 * 20
    
    while (session_id in shells and 
           terminal_id in shells[session_id] and 
           shells[session_id][terminal_id]['running']):
        try:
            # Check if process has terminated
            process = shells[session_id][terminal_id]['process']
            if process.poll() is not None:
                print(f"Process terminated for terminal {terminal_id}")
                socketio.emit('shell_exit', {'terminalId': terminal_id}, room=session_id)
                kill_shell(session_id, terminal_id)
                break
                
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                output = os.read(fd, max_read_bytes)
                
                if output:
                    # Convert bytes to string safely
                    text = output.decode('utf-8', errors='replace')
                    print(f"Sending output for terminal {terminal_id}: {repr(text)}")  # Debug logging
                    socketio.emit('shell_output', {
                        'terminalId': terminal_id, 
                        'output': text
                    }, room=session_id)
                    
                    if 'exit' in text.lower() and (
                        'logout' in text.lower() or 
                        'connection closed' in text.lower() or
                        'connection to' in text.lower() and 'closed' in text.lower()
                    ):
                        print(f"Exit detected for terminal {terminal_id}")
                        socketio.emit('shell_exit', {'terminalId': terminal_id}, room=session_id)
                        kill_shell(session_id, terminal_id)
                        break
                else:
                    print(f"EOF received for terminal {terminal_id}")
                    socketio.emit('shell_exit', {'terminalId': terminal_id}, room=session_id)
                    kill_shell(session_id, terminal_id)
                    break
            
            time.sleep(0.01)
        except Exception as e:
            print(f"Error reading from shell {terminal_id}: {e}")
            socketio.emit('shell_error', {'terminalId': terminal_id, 'error': str(e)}, room=session_id)
            kill_shell(session_id, terminal_id)
            break


def kill_shell(session_id, terminal_id):
    """Kill a shell process"""
    if session_id in shells and terminal_id in shells[session_id]:
        print(f"Killing shell {terminal_id} for session {session_id}")
        shells[session_id][terminal_id]['running'] = False
        
        # Kill the process
        try:
            process = shells[session_id][terminal_id]['process']
            if process.poll() is None:  # Only kill if still running
                os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        except Exception as e:
            print(f"Error killing process: {e}")
        
        # Close file descriptors
        for fd_name in ['master', 'slave']:
            try:
                if shells[session_id][terminal_id][fd_name] is not None:
                    os.close(shells[session_id][terminal_id][fd_name])
            except Exception as e:
                print(f"Error closing {fd_name}: {e}")
        
        # Remove terminal from session
        del shells[session_id][terminal_id]
        
        # Only remove session if explicitly requested (not during disconnect)
        if session_id in shells and not shells[session_id]:
            del shells[session_id]
        
        return True
    return False

if __name__ == '__main__':
    # Create required directories if they don't exist
    template_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates')
    static_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'static')
    css_dir = os.path.join(static_dir, 'css')
    js_dir = os.path.join(static_dir, 'js')
    
    for directory in [template_dir, static_dir, css_dir, js_dir]:
        if not os.path.exists(directory):
            os.makedirs(directory)
    
    print(f"Starting RPi Web Shell on port {PORT}")
    socketio.run(app, host='0.0.0.0', port=PORT, debug=False, allow_unsafe_werkzeug=True)
