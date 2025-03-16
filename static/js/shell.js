// Global variables
let apiKey = localStorage.getItem('rpi_metrics_shell_api_key');
let socket;
let connected = false;
let terminals = [];
let activeTabIndex = -1;
let contextMenuTarget = null;
let terminalCounter = 0;

// Debounce function to limit frequent executions
function debounce(func, wait) {
    let timeout;
    return function() {
        const context = this;
        const args = arguments;
        clearTimeout(timeout);
        timeout = setTimeout(() => {
            func.apply(context, args);
        }, wait);
    };
}

// Document ready handler
document.addEventListener('DOMContentLoaded', function() {
    // Check if API key exists, otherwise show the modal
    if (!apiKey) {
        showApiKeyModal();
    } else {
        initSocket();
    }
    
    // Set up event listeners
    setupEventListeners();
    
    // Update time display every second
    updateCurrentTime();
    setInterval(updateCurrentTime, 1000);
});

// Set up all event listeners
function setupEventListeners() {
    // Tab click delegation
    document.querySelector('.tab-bar').addEventListener('click', function(event) {
        // Handle tab close button
        if (event.target.classList.contains('tab-close')) {
            const tab = event.target.closest('.tab');
            const terminalId = tab.getAttribute('data-terminal-id');
            closeTerminal(terminalId);
            event.stopPropagation();
            return;
        }
        
        // Handle tab selection
        if (event.target.classList.contains('tab') || event.target.closest('.tab')) {
            const tab = event.target.classList.contains('tab') ? event.target : event.target.closest('.tab');
            const terminalId = tab.getAttribute('data-terminal-id');
            activateTab(terminalId);
        }
    });
    
    // Tab right-click context menu
    document.querySelector('.tab-bar').addEventListener('contextmenu', function(event) {
        if (event.target.classList.contains('tab') || event.target.closest('.tab')) {
            event.preventDefault();
            const tab = event.target.classList.contains('tab') ? event.target : event.target.closest('.tab');
            showTabContextMenu(tab, event.clientX, event.clientY);
        }
    });
    
    // Hide context menu on click outside
    document.addEventListener('click', function() {
        document.getElementById('tab-context-menu').classList.remove('visible');
    });
    
    // Close context menu on escape key
    document.addEventListener('keydown', function(event) {
        if (event.key === 'Escape') {
            document.getElementById('tab-context-menu').classList.remove('visible');
        }
    });
    
    // API key input form handler
    document.getElementById('api-key-input').addEventListener('keydown', function(event) {
        if (event.key === 'Enter') {
            authenticateWithApiKey();
        }
    });

    // Window resize handler for all terminals
    window.addEventListener('resize', debounce(() => {
        resizeAllTerminals();
    }, 100));

    // Visibility change handler
    document.addEventListener('visibilitychange', () => {
        if (!document.hidden && terminals.length > 0) {
            // When returning to the tab, resize all terminals
            setTimeout(resizeAllTerminals, 100);
        }
    });
}


// Initialize socket connection
function initSocket() {
    // Connect to socket.io
    const serverUrl = window.location.protocol + '//' + window.location.host;
    const socketOptions = {
        reconnectionAttempts: Infinity,
        reconnectionDelay: 1000,
        reconnectionDelayMax: 10000,
        timeout: 20000
    };
    socket = io(serverUrl, socketOptions);
    
    // Socket.io event listeners
    socket.on('connect', function() {
        connected = true;
        updateConnectionStatus();
        
        // Send API key for authentication
        socket.emit('authenticate', { apiKey: apiKey });
    });
    
    socket.on('disconnect', function() {
        connected = false;
        updateConnectionStatus();
        terminals.forEach(term => {
            if (term.term) {
                term.term.writeln('\r\nDisconnected from server. Attempting to reconnect...');
            }
        });
    });
    
    socket.on('reconnect', function() {
        connected = true;
        updateConnectionStatus();
        terminals.forEach(term => {
            if (term.term) {
                term.term.writeln('\r\nReconnected to server.');
            }
        });
        
        // Re-authenticate after reconnection
        //socket.emit('authenticate', { apiKey: apiKey });
    });
    
    socket.on('reconnect_failed', function() {
        terminals.forEach(term => {
            if (term.term) {
                term.term.writeln('\r\nFailed to reconnect after multiple attempts. Please refresh the page.');
            }
        });
    });
    
    socket.on('authentication_failed', function() {
    // Clear any existing terminals
    terminals.forEach(term => {
        const terminalId = term.id;
        // Remove from DOM without telling server
        const tab = document.querySelector(`.tab[data-terminal-id="${terminalId}"]`);
        const terminalInstance = document.getElementById(terminalId);
        if (tab) tab.remove();
        if (terminalInstance) terminalInstance.remove();
    });
    
    // Reset terminals array
    terminals = [];
    activeTabIndex = -1;
    
    // Show authentication modal
    showApiKeyModal();
    });
    
    socket.on('authentication_success', function() {
        // Create first tab after authentication
        if (terminals.length === 0) {
            createNewTab();
        }
    });
    
    socket.on('shell_output', function(data) {
        const terminal = terminals.find(t => t.id === data.terminalId);
        if (terminal && terminal.term) {
            terminal.term.write(data.output);
        }
    });
    
    socket.on('shell_error', function(data) {
        const terminal = terminals.find(t => t.id === data.terminalId);
        if (terminal && terminal.term) {
            terminal.term.writeln('\r\nError: ' + data.error);
        }
    });
}

// Create a new terminal tab
function createNewTab(title = null) {
    const terminalId = 'terminal-' + terminalCounter++;
    const tabTitle = title || 'Terminal ' + terminalCounter;
    
    // Create tab element
    const tabBar = document.querySelector('.tab-bar');
    const tab = document.createElement('div');
    tab.className = 'tab';
    tab.setAttribute('data-terminal-id', terminalId);
    tab.innerHTML = `
        <span class="tab-title">${tabTitle}</span>
        <span class="tab-close">×</span>
    `;
    tabBar.insertBefore(tab, document.querySelector('.new-tab-button'));
    
    // Create terminal container
    const terminalsContainer = document.getElementById('terminals');
    const terminalInstance = document.createElement('div');
    terminalInstance.className = 'terminal-instance';
    terminalInstance.id = terminalId;
    
    const terminalElement = document.createElement('div');
    terminalElement.className = 'terminal';
    
    terminalInstance.appendChild(terminalElement);
    terminalsContainer.appendChild(terminalInstance);
    
    // Initialize terminal
    const term = new Terminal({
        cursorBlink: true,
        theme: {
            background: '#2d2d2d',
            foreground: '#f8f8f8',
            cursor: '#ffffff'
        },
        fontFamily: 'Courier New, monospace',
        fontSize: 14,
        allowProposedApi: true,
        convertEol: true,
        rendererType: 'canvas',
        allowTransparency: true,
        cursorStyle: 'block',
        scrollback: 10000,
        termName: 'xterm-256color'
    });
    
    const fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);
    term.open(terminalElement);
    //fitAddon.fit();

    setTimeout(() => {
        // Force a resize calculation
        fitAddon.fit();
    
        // Apply a second fit after a brief delay to handle any DOM adjustments
        setTimeout(() => {
            fitAddon.fit();
            // Send terminal size to server
            const dimensions = { cols: term.cols, rows: term.rows };
            socket.emit('resize_terminal', { 
                terminalId: terminalId,
                ...dimensions 
            });
        }, 100);
    }, 50);

    
    // Handle terminal resize
    const resizeObserver = new ResizeObserver(() => {
        try {
            fitAddon.fit();
            
            // Send terminal size to server
            const dimensions = { cols: term.cols, rows: term.rows };
            socket.emit('resize_terminal', { 
                terminalId: terminalId,
                ...dimensions 
            });
        } catch (err) {
            console.error('Error resizing terminal:', err);
        }
    });
    
    resizeObserver.observe(terminalElement);
    
    // Store terminal object
    terminals.push({
        id: terminalId,
        term: term,
        title: tabTitle,
        fitAddon: fitAddon,
        resizeObserver: resizeObserver
    });
    
    // Create shell on server
    socket.emit('create_shell', {
        terminalId: terminalId,
        cols: term.cols,
        rows: term.rows
    });
    
    // Handle terminal input
    term.onData(data => {
        if (connected) {
            socket.emit('shell_input', {
                terminalId: terminalId,
                input: data
            });
        }
    });
    
    // Activate this tab
    activateTab(terminalId);
    
    return terminalId;
}

// Activate a tab by terminal ID
function activateTab(terminalId) {
    // Deactivate all tabs first
    document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
    document.querySelectorAll('.terminal-instance').forEach(term => term.classList.remove('active'));
    
    // Activate selected tab
    const tab = document.querySelector(`.tab[data-terminal-id="${terminalId}"]`);
    const terminalInstance = document.getElementById(terminalId);
    
    if (tab && terminalInstance) {
        tab.classList.add('active');
        terminalInstance.classList.add('active');
        
        // Find terminal index
        const index = terminals.findIndex(t => t.id === terminalId);
        if (index !== -1) {
            activeTabIndex = index;
            const terminal = terminals[index];
            
            // IMPROVED: More reliable terminal resizing on tab activation
        setTimeout(() => {
            if (terminal.fitAddon) {
                terminal.fitAddon.fit();
        
                // Force a second fit to ensure proper dimensions
                setTimeout(() => {
                    terminal.fitAddon.fit();
                    socket.emit('resize_terminal', {
                        terminalId: terminalId,
                        cols: terminal.term.cols,
                        rows: terminal.term.rows
                    });
                    terminal.term.focus();
                }, 50);
            }
        }, 0);
        }
    }
}

// Resize all terminals function
function resizeAllTerminals() {
    terminals.forEach(terminal => {
        if (terminal.fitAddon) {
            terminal.fitAddon.fit();
            socket.emit('resize_terminal', {
                terminalId: terminal.id,
                cols: terminal.term.cols,
                rows: terminal.term.rows
            });
        }
    });
}

// Close terminal by ID
function closeTerminal(terminalId) {
    const index = terminals.findIndex(t => t.id === terminalId);
    if (index === -1) return;
    
    const terminal = terminals[index];
    
    // Clean up resources
    if (terminal.resizeObserver) {
        terminal.resizeObserver.disconnect();
    }
    
    // Remove from DOM
    const tab = document.querySelector(`.tab[data-terminal-id="${terminalId}"]`);
    const terminalInstance = document.getElementById(terminalId);
    
    if (tab) tab.remove();
    if (terminalInstance) terminalInstance.remove();
    
    // Tell server to close this terminal
    socket.emit('close_shell', { terminalId: terminalId });
    
    // Remove from terminals array
    terminals.splice(index, 1);
    
    // Activate another tab if this was the active one
    if (activeTabIndex === index) {
        if (terminals.length > 0) {
            // Activate the previous tab, or the next if there is no previous
            const newIndex = Math.min(index, terminals.length - 1);
            activateTab(terminals[newIndex].id);
        } else {
            activeTabIndex = -1;
            // Create a new tab if this was the last one
            createNewTab();
        }
    } else if (activeTabIndex > index) {
        // Adjust active index if we removed a tab before it
        activeTabIndex--;
    }
}

// Show tab context menu
function showTabContextMenu(tab, x, y) {
    const terminalId = tab.getAttribute('data-terminal-id');
    contextMenuTarget = terminalId;
    
    const contextMenu = document.getElementById('tab-context-menu');
    contextMenu.style.left = x + 'px';
    contextMenu.style.top = y + 'px';
    contextMenu.classList.add('visible');
}

// Rename current tab
function renameTab() {
    if (!contextMenuTarget) return;
    
    const tab = document.querySelector(`.tab[data-terminal-id="${contextMenuTarget}"]`);
    if (!tab) return;
    
    const tabTitleElement = tab.querySelector('.tab-title');
    const currentTitle = tabTitleElement.textContent;
    
    const newTitle = prompt('Enter new tab name:', currentTitle);
    if (newTitle !== null && newTitle.trim() !== '') {
        tabTitleElement.textContent = newTitle;
        
        // Update title in terminals array
        const index = terminals.findIndex(t => t.id === contextMenuTarget);
        if (index !== -1) {
            terminals[index].title = newTitle;
        }
    }
    
    // Hide context menu
    document.getElementById('tab-context-menu').classList.remove('visible');
}

// Duplicate current tab
function duplicateTab() {
    if (!contextMenuTarget) return;
    
    const index = terminals.findIndex(t => t.id === contextMenuTarget);
    if (index !== -1) {
        const terminal = terminals[index];
        const newTitle = terminal.title + ' (Copy)';
        createNewTab(newTitle);
    }
    
    // Hide context menu
    document.getElementById('tab-context-menu').classList.remove('visible');
}

// Close current tab
function closeTab() {
    if (!contextMenuTarget) return;
    closeTerminal(contextMenuTarget);
    
    // Hide context menu
    document.getElementById('tab-context-menu').classList.remove('visible');
}

// Close other tabs
function closeOtherTabs() {
    if (!contextMenuTarget) return;
    
    // Get all terminal IDs except the current one
    const idsToClose = terminals
        .filter(t => t.id !== contextMenuTarget)
        .map(t => t.id);
        
    // Close each terminal
    idsToClose.forEach(id => closeTerminal(id));
    
    // Hide context menu
    document.getElementById('tab-context-menu').classList.remove('visible');
}

// Show API key modal
function showApiKeyModal() {
    const modal = document.getElementById('api-key-modal');
    modal.style.display = 'flex';
    document.getElementById('api-key-input').value = '';
    document.getElementById('api-key-input').focus();
}

// Hide API key modal
function hideApiKeyModal() {
    const modal = document.getElementById('api-key-modal');
    modal.style.display = 'none';
}

// Authenticate with API key
function authenticateWithApiKey() {
    const inputApiKey = document.getElementById('api-key-input').value.trim();
    if (!inputApiKey) return;
    
    apiKey = inputApiKey;
    localStorage.setItem('rpi_metrics_shell_api_key', apiKey);
    
    hideApiKeyModal();
    
    // Initialize or reconnect socket with new API key
    if (socket && socket.connected) {
        socket.emit('authenticate', { apiKey: apiKey });
    } else {
        initSocket();
    }
}

// Update connection status display
function updateConnectionStatus() {
    const statusElement = document.getElementById('connection-status');
    if (connected) {
        statusElement.innerHTML = '<span class="status-indicator status-connected"></span><span class="status-text">Connected</span>';
    } else {
        statusElement.innerHTML = '<span class="status-indicator status-disconnected"></span><span class="status-text">Disconnected</span>';
    }
}

// Update current time
function updateCurrentTime() {
    const now = new Date();
    const options = { 
        weekday: 'short',
        year: 'numeric', 
        month: 'short', 
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    };
    document.getElementById('current-time').textContent = now.toLocaleDateString('en-US', options);
}

// Logout function
function logout() {
    localStorage.removeItem('rpi_metrics_shell_api_key');
    window.location.reload();
}
