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
from flask import Flask, render_template, request, send_from_directory
from flask_socketio import SocketIO, emit, join_room, leave_room

# Import API_KEY from env (same as RPi-Metrics)
try:
    sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import env
    API_KEY = env.API_KEY
    PORT = env.SHELL_PORT
except ImportError:
    # Fallback in case env.py doesn't exist
    API_KEY = os.getenv("API_KEY", "change-this-key")
    SHELL_PORT = os.getenv("SHELL_PORT", 5001)

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)
socketio = SocketIO(app, async_mode='threading', cors_allowed_origins="*")

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

def is_authenticated(sid):
    """Check if the session is authenticated"""
    return sid in authenticated_sessions

@app.route('/')
def index():
    return render_template('shell.html')

@app.route('/static/<path:path>')
def serve_static(path):
    return send_from_directory('static', path)

@socketio.on('connect')
def handle_connect():
    print(f"Client connected: {request.sid}")

@socketio.on('disconnect')
def handle_disconnect():
    print(f"Client disconnected: {request.sid}")
    # Remove from authenticated sessions
    if request.sid in authenticated_sessions:
        authenticated_sessions.remove(request.sid)
        
    if request.sid in shells:
        # Clean up all shells for this session
        terminal_ids = list(shells[request.sid].keys())
        for terminal_id in terminal_ids:
            kill_shell(request.sid, terminal_id)
        # Remove session entry
        del shells[request.sid]
    leave_room(request.sid)

@socketio.on('authenticate')
def handle_authenticate(data):
    client_api_key = data.get('apiKey')
    if client_api_key == API_KEY:
        # Store the session ID as authenticated
        authenticated_sessions.add(request.sid)
        join_room(request.sid)
        emit('authentication_success')
    else:
        emit('authentication_failed')

@socketio.on('create_shell')
def handle_create_shell(data):
    # Check authentication before allowing terminal creation
    if not is_authenticated(request.sid):
        emit('authentication_failed')
        return
        
    terminal_id = data.get('terminalId')
    cols = data.get('cols', 80)
    rows = data.get('rows', 24)
    create_shell(request.sid, terminal_id, cols, rows)

@socketio.on('shell_input')
def handle_shell_input(data):
    # Check authentication before allowing shell input
    if not is_authenticated(request.sid):
        emit('authentication_failed')
        return
        
    terminal_id = data.get('terminalId')
    input_text = data.get('input', '')
    
    success = write_to_shell(request.sid, terminal_id, input_text)
    return {'success': success}

@socketio.on('resize_terminal')
def handle_resize_terminal(data):
    # Check authentication before allowing terminal resize
    if not is_authenticated(request.sid):
        emit('authentication_failed')
        return
        
    terminal_id = data.get('terminalId')
    cols = data.get('cols', 80)
    rows = data.get('rows', 24)
    
    resize_terminal(request.sid, terminal_id, cols, rows)

@socketio.on('close_shell')
def handle_close_shell(data):
    # Check authentication before allowing shell closure
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
        fcntl.ioctl(
            shells[session_id][terminal_id]['master'],
            termios.TIOCSWINSZ,
            struct.pack("HHHH", rows, cols, 0, 0)
        )
        return True
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
                # Process has exited
                socketio.emit('shell_exit', {'terminalId': terminal_id}, room=session_id)
                kill_shell(session_id, terminal_id)
                break
                
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                output = os.read(fd, max_read_bytes)
                
                if output:
                    # Convert bytes to string safely
                    text = output.decode('utf-8', errors='replace')
                    socketio.emit('shell_output', {'terminalId': terminal_id, 'output': text}, room=session_id)
                    
                    # Check for exit command in output
                    if 'exit' in text.lower() and (
                        'logout' in text.lower() or 
                        'connection closed' in text.lower() or
                        'connection to' in text.lower() and 'closed' in text.lower()
                    ):
                        # Signal that the shell has exited
                        socketio.emit('shell_exit', {'terminalId': terminal_id}, room=session_id)
                        kill_shell(session_id, terminal_id)
                        break
                else:
                    # EOF on the file descriptor
                    socketio.emit('shell_exit', {'terminalId': terminal_id}, room=session_id)
                    kill_shell(session_id, terminal_id)
                    break
            
            # Short sleep to prevent high CPU usage
            time.sleep(0.01)
        except Exception as e:
            print(f"Error reading from shell: {e}")
            socketio.emit('shell_error', {'terminalId': terminal_id, 'error': str(e)}, room=session_id)
            kill_shell(session_id, terminal_id)
            break

def kill_shell(session_id, terminal_id):
    """Kill a shell process"""
    if session_id in shells and terminal_id in shells[session_id]:
        shells[session_id][terminal_id]['running'] = False
        
        # Kill the process
        try:
            os.killpg(os.getpgid(shells[session_id][terminal_id]['process'].pid), signal.SIGTERM)
        except:
            pass
        
        # Close file descriptors
        try:
            os.close(shells[session_id][terminal_id]['master'])
        except:
            pass
        
        try:
            os.close(shells[session_id][terminal_id]['slave'])
        except:
            pass
        
        # Remove from shells dictionary
        del shells[session_id][terminal_id]
        
        # Clean up session if this was the last terminal
        if not shells[session_id]:
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
    
    # Run on port 5001 by default so it doesn't conflict with RPi-Metrics
    print(f"Starting RPi Web Shell on port {PORT}")
    
    socketio.run(app, host='0.0.0.0', port=PORT, debug=False, allow_unsafe_werkzeug=True)
