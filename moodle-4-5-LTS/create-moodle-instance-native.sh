#!/bin/bash

# Moodle 4.5 LTS Instance Creator Script — Native (No Docker)
# Creates a new Moodle 4.5 LTS instance directly on the host system.
# Requires: PHP, MariaDB/MySQL, Apache/Nginx already installed.
# Uses the MOODLE_405_STABLE branch from GitHub.
# Fully automated — just enter IP, port, and DB credentials.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Moodle version config
MOODLE_BRANCH="MOODLE_405_STABLE"
MOODLE_VERSION="4.5 LTS"

# ── Pre-flight checks ────────────────────────────────────────────────
print_info "Checking prerequisites..."

# Check PHP
PHP_BIN=$(command -v php 2>/dev/null || true)
if [ -z "$PHP_BIN" ]; then
    print_error "PHP CLI not found. Please install PHP (8.1+ recommended)."
    exit 1
fi
PHP_VERSION=$("$PHP_BIN" -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
print_success "PHP $PHP_VERSION found at $PHP_BIN"

# Check MySQL/MariaDB client
MYSQL_BIN=$(command -v mysql 2>/dev/null || true)
if [ -z "$MYSQL_BIN" ]; then
    print_error "MySQL/MariaDB client not found. Please install MariaDB or MySQL."
    exit 1
fi
print_success "MySQL client found at $MYSQL_BIN"

# Check git or wget/curl
if ! command -v git &> /dev/null && ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
    print_error "Neither git, wget, nor curl found. Please install one of them."
    exit 1
fi

echo ""

# ── User input ────────────────────────────────────────────────────────
# Get IP address from user
read -p "Enter the IP address for this Moodle instance (default: localhost): " IP_ADDRESS
IP_ADDRESS=${IP_ADDRESS:-localhost}

# Get port number from user
read -p "Enter the port number for this Moodle instance (e.g., 8082): " PORT

# Validate port number
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
    print_error "Invalid port number. Please enter a number between 1024 and 65535."
    exit 1
fi

# Get password suffix for role accounts
read -p "Enter password suffix for all accounts (default: 123456): " ROLE_PASS_SUFFIX
ROLE_PASS_SUFFIX=${ROLE_PASS_SUFFIX:-123456}

# Get base directory
read -p "Enter base directory for Moodle instances (default: \$HOME/moodle-instances): " BASE_DIR
BASE_DIR=${BASE_DIR:-$HOME/moodle-instances}

# ── Database credentials ──────────────────────────────────────────────
echo ""
print_info "Database configuration:"
read -p "  DB host (default: localhost): " DB_HOST
DB_HOST=${DB_HOST:-localhost}

read -p "  DB port (default: 3306): " DB_PORT
DB_PORT=${DB_PORT:-3306}

read -p "  DB root password (to create database + user): " -s DB_ROOT_PASS
echo ""

DB_NAME="moodle_${PORT}"
DB_USER="moodleuser_${PORT}"
DB_PASS="moodlepass_${PORT}"

# ── Moodle data directory ────────────────────────────────────────────
read -p "Enter moodledata directory (default: \$HOME/moodledata-$PORT): " MOODLEDATA_DIR
MOODLEDATA_DIR=${MOODLEDATA_DIR:-$HOME/moodledata-$PORT}

# Define instance folder name and path
INSTANCE_NAME="moodle-instance-$PORT"
INSTANCE_PATH="$BASE_DIR/$INSTANCE_NAME"

# Create base directory if it doesn't exist
mkdir -p "$BASE_DIR"

# Check if folder already exists
if [ -d "$INSTANCE_PATH" ]; then
    print_error "Folder $INSTANCE_PATH already exists. Please choose a different port or remove the existing folder."
    exit 1
fi

echo ""
print_info "Creating Moodle $MOODLE_VERSION instance: $INSTANCE_NAME"
print_info "Location: $INSTANCE_PATH"
print_info "URL will be: http://$IP_ADDRESS:$PORT"
print_info "Database: $DB_NAME on $DB_HOST:$DB_PORT"
print_info "Moodledata: $MOODLEDATA_DIR"
echo ""

# Confirm
read -p "Proceed with installation? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_info "Installation cancelled."
    exit 0
fi

# Create instance folder
mkdir -p "$INSTANCE_PATH"

# ── Clone Moodle source code ─────────────────────────────────────────
print_info "Downloading Moodle $MOODLE_VERSION source code from GitHub (branch: $MOODLE_BRANCH)..."
print_info "This may take a few minutes depending on your internet connection..."

cd "$INSTANCE_PATH"

if command -v git &> /dev/null; then
    git clone --depth 1 --branch "$MOODLE_BRANCH" https://github.com/moodle/moodle.git moodle
    print_success "Moodle source code downloaded successfully"
else
    print_warning "Git not found. Downloading source code as archive..."

    if command -v wget &> /dev/null; then
        wget -q --show-progress -O moodle.zip "https://github.com/moodle/moodle/archive/refs/heads/${MOODLE_BRANCH}.zip"
    elif command -v curl &> /dev/null; then
        curl -L -o moodle.zip "https://github.com/moodle/moodle/archive/refs/heads/${MOODLE_BRANCH}.zip"
    fi

    print_info "Extracting Moodle source code..."
    unzip -q moodle.zip
    mv "moodle-${MOODLE_BRANCH}" moodle
    rm moodle.zip
    print_success "Moodle source code extracted successfully"
fi

MOODLE_ROOT="$INSTANCE_PATH/moodle"

# ── Set permissions ──────────────────────────────────────────────────
print_info "Setting file permissions..."
chmod -R 755 "$MOODLE_ROOT"
find "$MOODLE_ROOT" -type f -name "*.php" -exec chmod 644 {} \;

# Create moodledata directory
mkdir -p "$MOODLEDATA_DIR"
chmod 777 "$MOODLEDATA_DIR"

# ── Create database ──────────────────────────────────────────────────
print_info "Creating database and user..."

"$MYSQL_BIN" -h "$DB_HOST" -P "$DB_PORT" -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

if [ $? -eq 0 ]; then
    print_success "Database '$DB_NAME' and user '$DB_USER' created successfully!"
else
    print_error "Failed to create database. Check your root credentials."
    exit 1
fi

# ── Install Moodle ───────────────────────────────────────────────────
ADMIN_USER="admin"
ADMIN_PASS="Admin@${ROLE_PASS_SUFFIX}"
ADMIN_EMAIL="admin@example.com"
SITE_NAME="Moodle $MOODLE_VERSION - Instance $PORT"

print_info "Running Moodle installation (this may take 2-3 minutes)..."

"$PHP_BIN" "$MOODLE_ROOT/admin/cli/install.php" \
    --wwwroot="http://$IP_ADDRESS:$PORT" \
    --dataroot="$MOODLEDATA_DIR" \
    --dbtype="mariadb" \
    --dbhost="$DB_HOST" \
    --dbport="$DB_PORT" \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASS" \
    --fullname="$SITE_NAME" \
    --shortname="moodle$PORT" \
    --adminuser="$ADMIN_USER" \
    --adminpass="$ADMIN_PASS" \
    --adminemail="$ADMIN_EMAIL" \
    --agree-license \
    --non-interactive

if [ $? -eq 0 ]; then
    print_success "Moodle installation completed successfully!"
else
    print_error "Moodle installation failed. Please check the output above."
    exit 1
fi

# Ensure config.php has correct permissions
chmod 644 "$MOODLE_ROOT/config.php"

# ── Install plugins if plugins.json exists ───────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_FILE=""
if [ -f "$INSTANCE_PATH/plugins.json" ]; then
    PLUGINS_FILE="$INSTANCE_PATH/plugins.json"
elif [ -f "$SCRIPT_DIR/plugins.json" ]; then
    PLUGINS_FILE="$SCRIPT_DIR/plugins.json"
elif [ -f "$SCRIPT_DIR/install-plugins/plugins.json" ]; then
    PLUGINS_FILE="$SCRIPT_DIR/install-plugins/plugins.json"
fi

NATIVE_PLUGIN_SCRIPT=""
if [ -f "$SCRIPT_DIR/install-plugins-native.sh" ]; then
    NATIVE_PLUGIN_SCRIPT="$SCRIPT_DIR/install-plugins-native.sh"
elif [ -f "$SCRIPT_DIR/install-plugins/install-plugins-native.sh" ]; then
    NATIVE_PLUGIN_SCRIPT="$SCRIPT_DIR/install-plugins/install-plugins-native.sh"
fi

if [ -n "$PLUGINS_FILE" ] && [ -n "$NATIVE_PLUGIN_SCRIPT" ]; then
    print_info "Found plugins.json at $PLUGINS_FILE. Installing plugins..."
    bash "$NATIVE_PLUGIN_SCRIPT" --moodle-path "$MOODLE_ROOT" --plugins-file "$PLUGINS_FILE"
elif [ -n "$PLUGINS_FILE" ]; then
    print_warning "Found plugins.json but install-plugins-native.sh not found. Skipping plugin installation."
else
    print_info "No plugins.json found. Installing default Moodle without extra plugins."
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=========================================="
print_success "Moodle $MOODLE_VERSION instance is READY!"
echo "=========================================="
echo ""
echo "Instance Details:"
echo "  - Name: $INSTANCE_NAME"
echo "  - Path: $INSTANCE_PATH"
echo "  - Moodle Root: $MOODLE_ROOT"
echo "  - Moodledata: $MOODLEDATA_DIR"
echo "  - Moodle Version: $MOODLE_VERSION (branch: $MOODLE_BRANCH)"
echo "  - URL: http://$IP_ADDRESS:$PORT"
echo "  - Password Suffix: $ROLE_PASS_SUFFIX"
echo ""
echo "Admin Login Credentials:"
echo "  - Username: $ADMIN_USER"
echo "  - Password: $ADMIN_PASS"
echo "  - Email: $ADMIN_EMAIL"
echo ""
echo "Role Account Passwords (suffix: $ROLE_PASS_SUFFIX):"
echo "  - manager            / Manager@$ROLE_PASS_SUFFIX"
echo "  - coursecreator      / Coursecreator@$ROLE_PASS_SUFFIX"
echo "  - teacher            / Teacher@$ROLE_PASS_SUFFIX"
echo "  - noneditingteacher  / Noneditingteacher@$ROLE_PASS_SUFFIX"
echo "  - student            / Student@$ROLE_PASS_SUFFIX"
echo ""
echo "Database Credentials:"
echo "  - Database: $DB_NAME"
echo "  - Username: $DB_USER"
echo "  - Password: $DB_PASS"
echo "  - Host: $DB_HOST:$DB_PORT"
echo ""
echo "IMPORTANT: You need to configure your web server (Apache/Nginx)"
echo "to serve $MOODLE_ROOT on port $PORT."
echo ""
echo "Apache example (add to sites-available):"
echo "  <VirtualHost *:$PORT>"
echo "      DocumentRoot $MOODLE_ROOT"
echo "      <Directory $MOODLE_ROOT>"
echo "          AllowOverride All"
echo "          Require all granted"
echo "      </Directory>"
echo "  </VirtualHost>"
echo ""
print_success "You can login at http://$IP_ADDRESS:$PORT after configuring your web server."
echo ""
