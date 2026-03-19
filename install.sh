#!/bin/bash

# Sjtech Panel - Debian Installation Script with Enhanced Login-Only Authentication
# This script installs and configures the Sjtech Panel with Nginx, SSL, and Bind9 integration
# Features: Login-only access, enhanced security, and improved user experience

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
PANEL_DIR="/opt/sjtech-panel"
FRONTEND_DIR="$PANEL_DIR/frontend"
BACKEND_DIR="$PANEL_DIR/backend"
CONFIG_DIR="$PANEL_DIR/debian-config"
NGINX_DIR="$PANEL_DIR/nginx"
SSL_DIR="$PANEL_DIR/ssl"
BIND9_DIR="$PANEL_DIR/bind9"
DOMAIN="panel.yourdomain.com"
PM2_APP_NAME="sjtech-panel"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get system information
get_system_info() {
    print_info "Gathering system information..."
    
    # Get hostname
    HOSTNAME=$(hostname)
    
    # Get IP address
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    # Get current domain (if any)
    CURRENT_DOMAIN=$(hostname -f)
    
    # Get public IP (for external access)
    PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "unknown")
    
    print_info "System Information:"
    print_info "  Hostname: $HOSTNAME"
    print_info "  IP Address: $IP_ADDRESS"
    print_info "  Public IP: $PUBLIC_IP"
    print_info "  Current Domain: $CURRENT_DOMAIN"
}

# Function to configure hostname
configure_hostname() {
    print_info "Configuring hostname..."
    
    # Backup current hostname
    if [ -f /etc/hostname ]; then
        cp /etc/hostname /etc/hostname.bak
        print_info "  Backup created: /etc/hostname.bak"
    fi
    
    # Set new hostname (can be customized)
    read -p "Enter new hostname (default: sjtech-panel): " NEW_HOSTNAME
    NEW_HOSTNAME=${NEW_HOSTNAME:-sjtech-panel}
    
    echo "$NEW_HOSTNAME" > /etc/hostname
    print_info "  New hostname set: $NEW_HOSTNAME"
    
    # Update hosts file
    if [ -f /etc/hosts ]; then
        cp /etc/hosts /etc/hosts.bak
        print_info "  Backup created: /etc/hosts.bak"
    fi
    
    sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME $NEW_HOSTNAME.local/" /etc/hosts
    print_info "  Hosts file updated"
    
    # Apply hostname changes
    hostnamectl set-hostname "$NEW_HOSTNAME"
    print_success "Hostname configured to: $NEW_HOSTNAME"
}

# Function to configure domain
configure_domain() {
    print_info "Configuring domain..."
    
    # Get current domain or ask for new one
    read -p "Enter domain name (default: panel.yourdomain.com): " DOMAIN
    DOMAIN=${DOMAIN:-panel.yourdomain.com}
    
    print_info "  Domain set to: $DOMAIN"
    
    # Check if domain resolves to this server
    DOMAIN_IP=$(dig +short $DOMAIN)
    if [ "$DOMAIN_IP" != "$IP_ADDRESS" ] && [ "$DOMAIN_IP" != "$PUBLIC_IP" ]; then
        print_warning "  Warning: Domain $DOMAIN doesn't resolve to this server's IP ($IP_ADDRESS/$PUBLIC_IP)"
        read -p "  Continue anyway? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ]; then
            print_error "Installation aborted by user"
            exit 1
        fi
    fi
    
    print_success "Domain configured: $DOMAIN"
}

# Function to install dependencies
install_dependencies() {
    print_info "Installing system dependencies..."
    
    # Check if package manager is available
    if ! command_exists apt; then
        print_error "Package manager 'apt' not found. This script is for Debian/Ubuntu systems."
        exit 1
    fi
    
    # Update package lists
    apt update
    
    # Install required packages
    local packages="nginx certbot python3-certbot-nginx bind9 nodejs npm git curl ufw mariadb-server"
    apt install -y $packages
    
    # Install Node.js if not available
    if ! command_exists node; then
        print_info "Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        apt install -y nodejs
    fi
    
    # Install PM2 globally
    if ! command_exists pm2; then
        print_info "Installing PM2..."
        npm install -g pm2
    fi
    
    print_success "Dependencies installed successfully"
}

# Function to create directory structure
create_directories() {
    print_info "Creating directory structure..."
    
    mkdir -p "$PANEL_DIR"
    mkdir -p "$FRONTEND_DIR"
    mkdir -p "$BACKEND_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$NGINX_DIR"
    mkdir -p "$SSL_DIR"
    mkdir -p "$BIND9_DIR"
    
    print_success "Directory structure created"
}

# Function to setup frontend with login-only authentication
setup_frontend() {
    print_info "Setting up frontend with login-only authentication..."
    
    # Create frontend files
    cat > "$FRONTEND_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sjtech Panel</title>
    <script src="https://cdn.jsdelivr.net/npm/react@18.0.0/umd/react.development.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/react-dom@18.0.0/umd/react-dom.development.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/@babel/standalone/babel.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.3/css/all.min.css">
    <style>
        body {
            background-color: #0f172a;
            color: white;
            font-family: 'Inter', sans-serif;
            margin: 0;
            padding: 0;
        }
    </style>
</head>
<body>
    <div id="root"></div>

    <script type="text/babel">
        const { useState, useEffect, useRef } = React;

        // Auth Context
        const AuthContext = React.createContext();

        // Auth Provider Component
        const AuthProvider = ({ children }) => {
            const [user, setUser] = useState(null);
            const [loading, setLoading] = useState(true);
            const [authError, setAuthError] = useState('');

            useEffect(() => {
                // Check if user is logged in
                fetch('/api/auth/status')
                    .then(response => response.json())
                    .then(data => {
                        setUser(data.user);
                        setLoading(false);
                    })
                    .catch(error => {
                        console.error('Auth check failed:', error);
                        setUser(null);
                        setLoading(false);
                    });
            }, []);

            const login = async (email, password) => {
                setAuthError('');
                try {
                    const response = await fetch('/api/auth/login', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ email, password })
                    });
                    const data = await response.json();
                    if (data.success) {
                        setUser(data.user);
                        return { success: true };
                    } else {
                        setAuthError(data.message || 'Login failed');
                        return { success: false, message: data.message };
                    }
                } catch (error) {
                    setAuthError('Network error. Please try again.');
                    return { success: false, message: 'Network error' };
                }
            };

            const logout = async () => {
                try {
                    await fetch('/api/auth/logout', { method: 'POST' });
                    setUser(null);
                } catch (error) {
                    console.error('Logout failed:', error);
                }
            };

            return (
                <AuthContext.Provider value={{ user, loading, authError, login, logout }}>
                    {children}
                </AuthContext.Provider>
            );
        };

        // Protected Route Component
        const ProtectedRoute = ({ children }) => {
            const { user, loading, authError } = React.useContext(AuthContext);
            
            if (loading) return <div className="flex items-center justify-center h-screen">Loading...</div>;
            if (!user) return <LoginPage />;
            
            return children;
        };

        // Login Page Component
        const LoginPage = () => {
            const [email, setEmail] = useState('');
            const [password, setPassword] = useState('');
            const { login } = React.useContext(AuthContext);

            const handleSubmit = async (e) => {
                e.preventDefault();
                const result = await login(email, password);
                if (result.success) {
                    window.location.href = '/dashboard';
                }
            };

            return (
                <div className="min-h-screen flex items-center justify-center bg-slate-900">
                    <div className="max-w-md w-full p-8 bg-slate-800 rounded-lg shadow-xl">
                        <div className="text-center mb-8">
                            <h2 className="text-3xl font-bold text-white">Sjtech Panel</h2>
                            <p className="text-gray-400 mt-2">Sign in to your account</p>
                        </div>
                        <form onSubmit={handleSubmit} className="space-y-6">
                            <div>
                                <label className="block text-sm font-medium text-gray-300 mb-2">Email</label>
                                <input
                                    type="email"
                                    value={email}
                                    onChange={(e) => setEmail(e.target.value)}
                                    className="w-full px-4 py-3 bg-slate-700 border border-slate-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                                    placeholder="Enter your email"
                                    required
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-300 mb-2">Password</label>
                                <input
                                    type="password"
                                    value={password}
                                    onChange={(e) => setPassword(e.target.value)}
                                    className="w-full px-4 py-3 bg-slate-700 border border-slate-600 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                                    placeholder="Enter your password"
                                    required
                                />
                            </div>
                            {authError && <div className="text-red-400 text-sm text-center">{authError}</div>}
                            <button
                                type="submit"
                                className="w-full py-3 px-4 bg-blue-600 text-white rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 font-medium transition duration-200"
                            >
                                Sign In
                            </button>
                        </form>
                        <div className="mt-6 text-center text-gray-400 text-sm">
                            Don't have an account? Contact your administrator.
                        </div>
                    </div>
                </div>
            );
        };

        // Dashboard Component
        const Dashboard = () => {
            const [systemStats, setSystemStats] = useState(null);
            const { user, logout } = React.useContext(AuthContext);

            useEffect(() => {
                // Fetch system stats from API
                fetch('/api/system-stats')
                    .then(response => response.json())
                    .then(data => setSystemStats(data));
            }, []);

            return (
                <div className="flex h-screen">
                    <Sidebar />
                    
                    <div className="flex-1 p-8">
                        <div className="flex justify-between items-center mb-8">
                            <h1 className="text-3xl font-bold">Sjtech Panel</h1>
                            <div className="flex items-center space-x-4">
                                <span className="text-sm">{user?.email}</span>
                                <img src="https://placehold.co/40x40/6366f1/ffffff?text=U" alt="User avatar" className="w-10 h-10 rounded-full" />
                                <button 
                                    onClick={logout}
                                    className="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 transition duration-200"
                                >
                                    Logout
                                </button>
                            </div>
                        </div>

                        <h2 className="text-2xl font-semibold mb-6">Dashboard</h2>

                        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                            <StatsCard title="CPU Usage">
                                <Chart
                                    type="line"
                                    data={{
                                        labels: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00', '24:00'],
                                        datasets: [{
                                            data: [20, 35, 42, 30, 38, 40, 42],
                                            borderColor: '#3b82f6',
                                            backgroundColor: 'rgba(59, 130, 246, 0.1)',
                                            tension: 0.4,
                                            fill: true
                                        }]
                                    }}
                                    options={{
                                        responsive: true,
                                        maintainAspectRatio: false,
                                        plugins: { legend: { display: false } },
                                        scales: {
                                            y: { beginAtZero: true, grid: { color: 'rgba(255, 255, 255, 0.1)' }, ticks: { color: 'rgba(255, 255, 255, 0.7)' } },
                                            x: { grid: { color: 'rgba(255, 255, 255, 0.1)' }, ticks: { color: 'rgba(255, 255, 255, 0.7)' } }
                                        }
                                    }}
                                />
                                <div className="text-2xl font-bold text-blue-400 mt-4">42% USAGE</div>
                            </StatsCard>

                            <StatsCard title="Memory Usage">
                                <Chart
                                    type="line"
                                    data={{
                                        labels: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00', '24:00'],
                                        datasets: [{
                                            data: [2, 4, 5, 3, 6, 5, 6.2],
                                            borderColor: '#10b981',
                                            backgroundColor: 'rgba(16, 185, 129, 0.1)',
                                            tension: 0.4,
                                            fill: true
                                        }]
                                    }}
                                    options={{
                                        responsive: true,
                                        maintainAspectRatio: false,
                                        plugins: { legend: { display: false } },
                                        scales: {
                                            y: { beginAtZero: true, grid: { color: 'rgba(255, 255, 255, 0.1)' }, ticks: { color: 'rgba(255, 255, 255, 0.7)' } },
                                            x: { grid: { color: 'rgba(255, 255, 255, 0.1)' }, ticks: { color: 'rgba(255, 255, 255, 0.7)' } }
                                        }
                                    }}
                                />
                                <div className="text-2xl font-bold text-green-400 mt-4">6.2 / 16.0 GB</div>
                            </StatsCard>

                            <StatsCard title="Disk Space">
                                <Chart
                                    type="bar"
                                    data={{
                                        labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul'],
                                        datasets: [{
                                            data: [60, 75, 80, 65, 90, 85, 87],
                                            backgroundColor: '#3b82f6'
                                        }]
                                    }}
                                    options={{
                                        responsive: true,
                                        maintainAspectRatio: false,
                                        plugins: { legend: { display: false } },
                                        scales: {
                                            y: { beginAtZero: true, grid: { color: 'rgba(255, 255, 255, 0.1)' }, ticks: { color: 'rgba(255, 255, 255, 0.7)' } },
                                            x: { grid: { color: 'rgba(255, 255, 255, 0.1)' }, ticks: { color: 'rgba(255, 255, 255, 0.7)' } }
                                        }
                                    }}
                                />
                                <div className="text-2xl font-bold text-blue-400 mt-4">87 / 200 GB</div>
                            </StatsCard>

                            <StatsCard title="Total Websites">
                                <div className="text-5xl font-bold text-white">12</div>
                            </StatsCard>

                            <StatsCard title="Active FTP Sessions">
                                <div className="text-5xl font-bold text-white">3</div>
                            </StatsCard>

                            <StatsCard title="Security Status">
                                <div className="flex items-center">
                                    <div className="text-5xl font-bold text-green-400">Protected</div>
                                    <i className="fas fa-shield-alt text-4xl text-blue-400 ml-4"></i>
                                </div>
                            </StatsCard>
                        </div>
                    </div>
                </div>
            );
        };

        // Sidebar Component
        const Sidebar = () => {
            const [activeItem, setActiveItem] = useState('dashboard');
            const menuItems = [
                { icon: 'fas fa-chart-line', label: 'Dashboard', key: 'dashboard' },
                { icon: 'fas fa-globe', label: 'Websites', key: 'websites' },
                { icon: 'fas fa-network-wired', label: 'Domains', key: 'domains' },
                { icon: 'fas fa-dharmachakra', label: 'DNS Manager', key: 'dns' },
                { icon: 'fas fa-server', label: 'FTP Accounts', key: 'ftp' },
                { icon: 'fas fa-database', label: 'Databases', key: 'databases' },
                { icon: 'fas fa-shield-alt', label: 'Security Center', key: 'security' }
            ];

            return (
                <div className="w-64 bg-slate-900 p-4 h-full">
                    <div className="flex items-center mb-8">
                        <i className="fas fa-th-large text-xl mr-3"></i>
                        <span className="text-xl font-semibold">Dashboard</span>
                    </div>
                    <nav>
                        {menuItems.map((item) => (
                            <div
                                key={item.key}
                                className={`sidebar-item p-3 mb-2 rounded-lg flex items-center cursor-pointer ${
                                    activeItem === item.key ? 'bg-slate-700' : 'hover:bg-slate-800'
                                }`}
                                onClick={() => setActiveItem(item.key)}
                            >
                                <i className={`${item.icon} mr-3`}></i>
                                <span>{item.label}</span>
                            </div>
                        ))}
                    </nav>
                </div>
            );
        };

        // Stats Card Component
        const StatsCard = ({ title, children, className = "" }) => (
            <div className={`card rounded-xl p-6 ${className}`}>
                <h3 className="text-lg font-medium mb-4">{title}</h3>
                {children}
            </div>
        );

        // Chart Component
        const Chart = ({ type, data, options, height = "120px" }) => {
            const canvasRef = useRef(null);

            useEffect(() => {
                const canvas = canvasRef.current;
                const ctx = canvas.getContext('2d');
                new Chart(ctx, {
                    type,
                    data,
                    options
                });
            }, [type, data, options]);

            return <canvas ref={canvasRef} height={height}></canvas>;
        };

        // Main App Component
        const App = () => {
            return (
                <AuthProvider>
                    <ProtectedRoute>
                        <Dashboard />
                    </ProtectedRoute>
                </AuthProvider>
            );
        };

        ReactDOM.render(<App />, document.getElementById('root'));
    </script>
</body>
</html>
EOF

    print_success "Frontend setup completed"
}

# Function to setup backend with login-only authentication
setup_backend() {
    print_info "Setting up backend with login-only authentication..."
    
    # Check if MySQL service is running
    if ! systemctl is-active --quiet mysql; then
        print_warning "MySQL service is not running. Attempting to start..."
        systemctl start mysql
        if ! systemctl is-active --quiet mysql; then
            print_error "Failed to start MySQL service. Please check your MySQL installation."
            exit 1
        fi
        print_success "MySQL service started"
    fi

    # Create database and tables
    print_info "Setting up MySQL database..."
    mysql -u root -e "
        CREATE DATABASE IF NOT EXISTS sjtech_panel;
        USE sjtech_panel;
        CREATE TABLE IF NOT EXISTS users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            email VARCHAR(100) UNIQUE NOT NULL,
            password VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_login TIMESTAMP NULL,
            is_active BOOLEAN DEFAULT TRUE,
            failed_attempts INT DEFAULT 0,
            lock_until TIMESTAMP NULL
        );
    "
    print_success "Database and tables created"

    # Create backend server.js with login-only authentication
    cat > "$BACKEND_DIR/server.js" << 'EOF'
const express = require('express');
const os = require('os');
const { exec } = require('child_process');
const bcrypt = require('bcrypt');
const session = require('express-session');
const MySQLStore = require('express-mysql-session')(session);
const mysql = require('mysql2/promise');
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const xss = require('xss-clean');
const cors = require('cors');

const app = express();
const port = 3001;

// Database connection
const dbConfig = {
    host: 'localhost',
    user: 'root',
    password: '',
    database: 'sjtech_panel'
};

// Security middleware
app.use(helmet());
app.use(xss());
app.use(cors({
    origin: true,
    credentials: true
}));

// Rate limiting
const loginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 5, // Limit each IP to 5 login requests per windowMs
    message: {
        success: false,
        message: 'Too many login attempts. Please try again later.'
    },
    handler: (req, res) => {
        res.status(429).json({
            success: false,
            message: 'Too many login attempts. Please try again after 15 minutes.'
        });
    }
});

// Session configuration with enhanced security
const sessionStore = new MySQLStore({}, dbConfig);
app.use(session({
    key: 'session_cookie_name',
    secret: crypto.randomBytes(64).toString('hex'),
    store: sessionStore,
    resave: false,
    saveUninitialized: false,
    cookie: {
        maxAge: 1000 * 60 * 60 * 24, // 1 day
        secure: false,
        httpOnly: true,
        sameSite: 'lax'
    }
}));

// Middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(express.static('frontend'));

// Database connection pool
const pool = mysql.createPool(dbConfig);

// Authentication middleware
const authenticateToken = async (req, res, next) => {
    if (req.session.userId) {
        try {
            const [rows] = await pool.execute('SELECT id, name, email, is_active FROM users WHERE id = ? AND is_active = TRUE', [req.session.userId]);
            if (rows.length > 0) {
                req.user = rows[0];
                // Update last login
                await pool.execute('UPDATE users SET last_login = NOW() WHERE id = ?', [req.session.userId]);
                next();
            } else {
                req.session.destroy();
                res.status(401).json({ error: 'Unauthorized' });
            }
        } catch (error) {
            res.status(500).json({ error: 'Authentication error' });
        }
    } else {
        res.status(401).json({ error: 'Unauthorized' });
    }
};

// Password validation
const validatePassword = (password) => {
    const minLength = 8;
    const hasUpperCase = /[A-Z]/.test(password);
    const hasLowerCase = /[a-z]/.test(password);
    const hasNumbers = /\d/.test(password);
    const hasSpecialChars = /[!@#$%^&*(),.?":{}|<>]/.test(password);
    
    if (password.length < minLength) {
        return 'Password must be at least 8 characters long';
    }
    if (!hasUpperCase) {
        return 'Password must contain at least one uppercase letter';
    }
    if (!hasLowerCase) {
        return 'Password must contain at least one lowercase letter';
    }
    if (!hasNumbers) {
        return 'Password must contain at least one number';
    }
    if (!hasSpecialChars) {
        return 'Password must contain at least one special character';
    }
    return null;
};

// System stats endpoint
app.get('/api/system-stats', (req, res) => {
    exec('top -bn1 | grep "Cpu(s)"', (error, stdout, stderr) => {
        if (error) {
            return res.status(500).json({ error: 'Failed to get CPU usage' });
        }
        
        const cpuUsage = parseFloat(stdout.split(',')[1].split('%')[0].trim());
        
        exec('free -m | grep Mem', (error, stdout, stderr) => {
            if (error) {
                return res.status(500).json({ error: 'Failed to get memory usage' });
            }
            
            const memInfo = stdout.split(/\s+/);
            const totalMem = parseFloat(memInfo[1]);
            const usedMem = parseFloat(memInfo[2]);
            const memUsage = (usedMem / totalMem * 100).toFixed(1);
            
            exec('df -h | grep "/$" | awk \'{print $3 " " $2}\'', (error, stdout, stderr) => {
                if (error) {
                    return res.status(500).json({ error: 'Failed to get disk usage' });
                }
                
                const diskInfo = stdout.split(' ');
                const usedDisk = diskInfo[0];
                const totalDisk = diskInfo[1];
                
                res.json({
                    cpu: cpuUsage,
                    memory: {
                        used: usedMem,
                        total: totalMem,
                        percentage: memUsage
                    },
                    disk: {
                        used: usedDisk,
                        total: totalDisk
                    },
                    uptime: os.uptime(),
                    loadavg: os.loadavg()
                });
            });
        });
    });
});

// Authentication endpoints
app.post('/api/auth/login', loginLimiter, async (req, res) => {
    try {
        const { email, password } = req.body;
        
        if (!email || !password) {
            return res.status(400).json({ success: false, message: 'Email and password are required' });
        }

        // Find user
        const [users] = await pool.execute('SELECT * FROM users WHERE email = ?', [email]);
        const user = users[0];

        if (!user) {
            return res.status(400).json({ success: false, message: 'Invalid credentials' });
        }

        // Check if account is locked
        if (!user.is_active) {
            return res.status(403).json({ success: false, message: 'Account is locked. Please contact support.' });
        }

        // Check password
        const passwordMatch = await bcrypt.compare(password, user.password);
        if (!passwordMatch) {
            // Increment failed attempts
            await pool.execute(
                'UPDATE users SET failed_attempts = failed_attempts + 1 WHERE id = ?',
                [user.id]
            );
            
            const [updatedUser] = await pool.execute('SELECT failed_attempts FROM users WHERE id = ?', [user.id]);
            const failedAttempts = updatedUser[0].failed_attempts;
            
            if (failedAttempts >= 5) {
                // Lock account for 15 minutes
                const lockUntil = new Date(Date.now() + 15 * 60 * 1000);
                await pool.execute(
                    'UPDATE users SET is_active = FALSE, lock_until = ? WHERE id = ?',
                    [lockUntil, user.id]
                );
                return res.status(403).json({ success: false, message: 'Account locked due to too many failed attempts. Please try again in 15 minutes.' });
            }
            
            return res.status(400).json({ success: false, message: 'Invalid credentials' });
        }

        // Reset failed attempts and set account active
        await pool.execute(
            'UPDATE users SET failed_attempts = 0, is_active = TRUE WHERE id = ?',
            [user.id]
        );

        // Set session
        req.session.userId = user.id;

        res.json({ 
            success: true, 
            message: 'Login successful',
            user: { id: user.id, name: user.name, email: user.email }
        });
    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ success: false, message: 'Login failed' });
    }
});

app.get('/api/auth/status', async (req, res) => {
    if (req.session.userId) {
        try {
            const [users] = await pool.execute('SELECT id, name, email FROM users WHERE id = ?', [req.session.userId]);
            const user = users[0];
            res.json({ 
                loggedin: true, 
                user: user || null 
            });
        } catch (error) {
            res.json({ loggedin: false, user: null });
        }
    } else {
        res.json({ loggedin: false, user: null });
    }
});

app.post('/api/auth/logout', (req, res) => {
    req.session.destroy(err => {
        if (err) {
            return res.status(500).json({ success: false, message: 'Logout failed' });
        }
        res.json({ success: true, message: 'Logout successful' });
    });
});

// Websites endpoint
app.get('/api/websites', authenticateToken, (req, res) => {
    exec('ls /var/www/', (error, stdout, stderr) => {
        if (error) {
            return res.status(500).json({ error: 'Failed to get websites' });
        }
        
        const websites = stdout.split('\n').filter(site => site.trim() !== '');
        res.json(websites);
    });
});

// User profile endpoint
app.get('/api/user/profile', authenticateToken, async (req, res) => {
    try {
        const [users] = await pool.execute('SELECT id, name, email, created_at, last_login FROM users WHERE id = ?', [req.user.id]);
        res.json({ success: true, user: users[0] });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Failed to fetch user profile' });
    }
});

// Update user profile endpoint
app.put('/api/user/profile', authenticateToken, async (req, res) => {
    try {
        const { name } = req.body;
        if (!name) {
            return res.status(400).json({ success: false, message: 'Name is required' });
        }

        await pool.execute(
            'UPDATE users SET name = ? WHERE id = ?',
            [name, req.user.id]
        );

        res.json({ success: true, message: 'Profile updated successfully' });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Failed to update profile' });
    }
});

// Change password endpoint
app.put('/api/user/password', authenticateToken, async (req, res) => {
    try {
        const { currentPassword, newPassword } = req.body;
        if (!currentPassword || !newPassword) {
            return res.status(400).json({ success: false, message: 'Current and new password are required' });
        }

        // Validate new password
        const passwordError = validatePassword(newPassword);
        if (passwordError) {
            return res.status(400).json({ success: false, message: passwordError });
        }

        // Get current user
        const [users] = await pool.execute('SELECT password FROM users WHERE id = ?', [req.user.id]);
        const user = users[0];

        // Verify current password
        const passwordMatch = await bcrypt.compare(currentPassword, user.password);
        if (!passwordMatch) {
            return res.status(400).json({ success: false, message: 'Current password is incorrect' });
        }

        // Hash new password
        const hashedPassword = await bcrypt.hash(newPassword, 12);

        // Update password
        await pool.execute(
            'UPDATE users SET password = ? WHERE id = ?',
            [hashedPassword, req.user.id]
        );

        res.json({ success: true, message: 'Password changed successfully' });
    } catch (error) {
        res.status(500).json({ success: false, message: 'Failed to change password' });
    }
});

// Start server
app.listen(port, () => {
    console.log(\`Backend server running on port \${port}\`);
});
EOF

    print_success "Backend setup completed"
}

# Function to setup Nginx configuration
setup_nginx() {
    print_info "Setting up Nginx configuration..."
    
    # Create Nginx configuration
    cat > "$NGINX_DIR/sjtech-panel.conf" << EOF
server {
    listen 80;
    server_name $DOMAIN;
    root $FRONTEND_DIR;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api/ {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=auth:10m rate=10r/s;
    
    # Block common attack patterns
    location ~* \.(git|env|ini|log|sh|sql|bak|backup|old|tmp)$ {
        deny all;
    }
}
EOF

    # Copy to Nginx sites-available
    cp "$NGINX_DIR/sjtech-panel.conf" /etc/nginx/sites-available/
    
    # Create symlink
    ln -sf /etc/nginx/sites-available/sjtech-panel.conf /etc/nginx/sites-enabled/
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    # Test Nginx configuration
    nginx -t
    
    # Restart Nginx
    systemctl restart nginx
    
    print_success "Nginx configuration completed"
}

# Function to setup SSL with Let's Encrypt
setup_ssl() {
    print_info "Setting up SSL with Let's Encrypt..."
    
    # Obtain SSL certificate
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
    
    # Create SSL configuration
    cat > "$SSL_DIR/ssl.conf" << EOF
server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN/chain.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets off;
    
    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https:; object-src 'none';" always;
    
    root $FRONTEND_DIR;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location /api/ {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=auth:10m rate=10r/s;
    
    # Block common attack patterns
    location ~* \.(git|env|ini|log|sh|sql|bak|backup|old|tmp)$ {
        deny all;
    }
}
EOF

    # Update Nginx configuration
    cp "$SSL_DIR/ssl.conf" /etc/nginx/sites-available/sjtech-panel.conf
    ln -sf /etc/nginx/sites-available/sjtech-panel.conf /etc/nginx/sites-enabled/
    
    # Test and restart Nginx
    nginx -t && systemctl restart nginx
    
    print_success "SSL configuration completed"
}

# Function to setup Bind9 DNS
setup_bind9() {
    print_info "Setting up Bind9 DNS..."
    
    # Create Bind9 configuration
    cat > "$BIND9_DIR/named.conf.local" << EOF
zone "$DOMAIN" {
    type master;
    file "/etc/bind/db.$DOMAIN";
};

zone "1.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192.168.1";
};
EOF

    # Create zone file
    cat > "$BIND9_DIR/db.$DOMAIN" << EOF
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN. admin.$DOMAIN. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMAIN.
@       IN      A       $IP_ADDRESS
ns1     IN      A       $IP_ADDRESS
www     IN      A       $IP_ADDRESS
panel   IN      A       $IP_ADDRESS
EOF

    # Create reverse zone file
    cat > "$BIND9_DIR/db.192.168.1" << EOF
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN. admin.$DOMAIN. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMAIN.
1       IN      PTR     $DOMAIN.
EOF

    # Copy configuration files
    cp "$BIND9_DIR/named.conf.local" /etc/bind/
    cp "$BIND9_DIR/db.$DOMAIN" /etc/bind/
    cp "$BIND9_DIR/db.192.168.1" /etc/bind/
    
    # Restart Bind9
    systemctl restart bind9
    
    print_success "Bind9 configuration completed"
}

# Function to setup PM2 process management
setup_pm2() {
    print_info "Setting up PM2 process management..."
    
    # Create ecosystem file
    cat > "$CONFIG_DIR/ecosystem.config.js" << EOF
module.exports = {
  apps: [{
    name: '$PM2_APP_NAME',
    script: '$BACKEND_DIR/server.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production'
    },
    error_file: '/var/log/pm2/error.log',
    out_file: '/var/log/pm2/out.log',
    log_file: '/var/log/pm2/combined.log',
    time: true,
    // Auto-restart on failure
    autorestart: true,
    // Restart delay
    restart_delay: 5000
  }]
};
EOF

    # Start application with PM2
    pm2 start "$CONFIG_DIR/ecosystem.config.js"
    
    # Save PM2 configuration
    pm2 save
    
    # Setup PM2 to start on boot
    pm2 startup systemd
    
    print_success "PM2 setup completed"
}

# Function to configure firewall
setup_firewall() {
    print_info "Configuring firewall..."
    
    # Reset firewall
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow DNS
    ufw allow 53/tcp
    ufw allow 53/udp
    
    # Allow PM2 port
    ufw allow 3001/tcp
    
    # Allow MySQL (for backend)
    ufw allow 3306/tcp
    
    # Enable firewall
    ufw --force enable
    
    print_success "Firewall configuration completed"
}

# Function to create startup script
create_startup_script() {
    print_info "Creating startup script..."
    
    cat > "/etc/systemd/system/sjtech-panel.service" << EOF
[Unit]
Description=Sjtech Panel Service
After=network.target

[Service]
User=root
WorkingDirectory=$PANEL_DIR
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable sjtech-panel.service
    
    print_success "Startup script created"
}

# Function to display installation summary
display_summary() {
    print_info "Installation Summary:"
    print_info "===================="
    print_info "Hostname: $(hostname)"
    print_info "IP Address: $IP_ADDRESS"
    print_info "Domain: $DOMAIN"
    print_info "Panel URL: https://$DOMAIN"
    print_info "Backend Port: 3001"
    print_info "Database: MySQL (sjtech_panel)"
    print_info "===================="
    print_info "Installation completed successfully!"
    print_info "Please reboot the system for all changes to take effect."
    print_info "Security features enabled:"
    print_info "  - Login-only access (registration disabled)"
    print_info "  - Password complexity requirements"
    print_info "  - Account lockout after 5 failed attempts"
    print_info "  - Rate limiting for authentication"
    print_info "  - HTTPS with Let's Encrypt"
    print_info "  - Security headers"
    print_info "  - Input validation and sanitization"
    print_info "===================="
    print_info "Note: Users must be created manually in the database."
    print_info "Contact your administrator for account access."
}

# Main installation function
main() {
    print_info "Starting Sjtech Panel installation with login-only authentication..."
    print_info "This script will install all necessary components."
    
    # Get system information
    get_system_info
    
    # Configure hostname and domain
    configure_hostname
    configure_domain
    
    # Install dependencies
    install_dependencies
    
    # Create directory structure
    create_directories
    
    # Setup frontend and backend
    setup_frontend
    setup_backend
    
    # Setup services
    setup_nginx
    setup_ssl
    setup_bind9
    setup_pm2
    setup_firewall
    create_startup_script
    
    # Display summary
    display_summary
}

# Run main function
main
