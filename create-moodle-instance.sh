#!/bin/bash

# Moodle Instance Creator Script
# Creates a new Moodle instance with Docker Compose
# Fully automated - just enter IP and port

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

# Base directory for all moodle instances (uses user's home directory for portability)
BASE_DIR="$HOME/moodle-instances"

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

# Check if port is already in use
if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    print_error "Port $PORT is already in use. Please choose a different port."
    exit 1
fi

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

print_info "Creating Moodle instance: $INSTANCE_NAME"
print_info "Location: $INSTANCE_PATH"
print_info "URL will be: http://$IP_ADDRESS:$PORT"

# Create instance folder
mkdir -p "$INSTANCE_PATH"
cd "$INSTANCE_PATH"

# Create docker-compose.yml with unique container names
print_info "Creating docker-compose.yml..."
cat > docker-compose.yml << EOF
services:
  db:
    image: mariadb:10.11.6
    container_name: moodle-db-$PORT
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: moodle
      MYSQL_USER: moodleuser
      MYSQL_PASSWORD: moodlepass
    volumes:
      - db_data:/var/lib/mysql

  redis:
    image: redis:7
    container_name: moodle-redis-$PORT
    restart: always

  moodle:
    image: moodlehq/moodle-php-apache:8.2
    container_name: moodle-web-$PORT
    depends_on:
      - db
      - redis
    restart: always
    ports:
      - "$IP_ADDRESS:$PORT:80"
    volumes:
      - ./moodle:/var/www/html
      - moodledata:/var/www/moodledata

  moodle-cron:
    image: moodlehq/moodle-php-apache:8.2
    container_name: moodle-cron-$PORT
    depends_on:
      - moodle
    restart: always
    volumes:
      - ./moodle:/var/www/html
      - moodledata:/var/www/moodledata
    entrypoint: >
      sh -c "while true; do
      php /var/www/html/admin/cli/cron.php >/dev/null;
      sleep 60;
      done"

volumes:
  db_data:
  moodledata:
EOF

print_success "docker-compose.yml created"

# Clone Moodle source code
print_info "Downloading Moodle v5.1.2 source code from GitHub..."
print_info "This may take a few minutes depending on your internet connection..."

if command -v git &> /dev/null; then
    # Use git clone with shallow clone for faster download
    git clone --depth 1 --branch v5.1.2 https://github.com/moodle/moodle.git moodle
    print_success "Moodle source code downloaded successfully"
else
    # Fallback to wget/curl if git is not available
    print_warning "Git not found. Downloading source code as archive..."
    
    if command -v wget &> /dev/null; then
        wget -q --show-progress -O moodle.zip https://github.com/moodle/moodle/archive/refs/tags/v5.1.2.zip
    elif command -v curl &> /dev/null; then
        curl -L -o moodle.zip https://github.com/moodle/moodle/archive/refs/tags/v5.1.2.zip
    else
        print_error "Neither git, wget, nor curl found. Please install one of them."
        exit 1
    fi
    
    print_info "Extracting Moodle source code..."
    unzip -q moodle.zip
    mv moodle-5.1.2 moodle
    rm moodle.zip
    print_success "Moodle source code extracted successfully"
fi

# Set proper permissions for moodle folder BEFORE starting containers
print_info "Setting file permissions..."
chmod -R 755 moodle
# Make all PHP files readable
find moodle -type f -name "*.php" -exec chmod 644 {} \;

# Start Docker Compose
print_info "Starting Docker containers..."
docker compose up -d

# Wait for containers to be ready
print_info "Waiting for containers to start..."
sleep 10

# Check if containers are running
if docker compose ps | grep -q "Up"; then
    print_success "All containers are running!"
else
    print_warning "Some containers may not have started properly. Check with 'docker compose ps'"
    exit 1
fi

# Fix ownership inside container - CRITICAL for Moodle to work
print_info "Setting proper ownership inside container..."
docker exec moodle-web-$PORT chown -R www-data:www-data /var/www/html
docker exec moodle-web-$PORT chown -R www-data:www-data /var/www/moodledata

# Wait for database to be ready
print_info "Waiting for database to be ready..."
MAX_RETRIES=60
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Check if mysqladmin ping works AND the moodle database is accessible
    if docker exec moodle-db-$PORT mysqladmin ping -h localhost -u root -prootpass --silent 2>/dev/null && \
       docker exec moodle-db-$PORT mysql -u moodleuser -pmoodlepass -e "SELECT 1" moodle >/dev/null 2>&1; then
        print_success "Database is ready!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -n "."
    sleep 2
done
echo ""

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    print_error "Database did not become ready in time. Please check the containers."
    exit 1
fi

# Additional wait for database to fully initialize
sleep 5

# Define admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin@123456"
ADMIN_EMAIL="admin@example.com"
SITE_NAME="Moodle Instance $PORT"

# Run Moodle CLI installation
print_info "Running Moodle installation (this may take 2-3 minutes)..."

docker exec moodle-web-$PORT php /var/www/html/admin/cli/install.php \
    --wwwroot="http://$IP_ADDRESS:$PORT" \
    --dataroot="/var/www/moodledata" \
    --dbtype="mariadb" \
    --dbhost="db" \
    --dbname="moodle" \
    --dbuser="moodleuser" \
    --dbpass="moodlepass" \
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
    print_error "Moodle installation failed. Please check the logs."
    exit 1
fi

# Ensure config.php has correct permissions
print_info "Finalizing permissions..."
docker exec moodle-web-$PORT chmod 644 /var/www/html/config.php
docker exec moodle-web-$PORT chown www-data:www-data /var/www/html/config.php

# Install plugins if plugins.json exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_FILE=""
if [ -f "$INSTANCE_PATH/plugins.json" ]; then
    PLUGINS_FILE="$INSTANCE_PATH/plugins.json"
elif [ -f "$SCRIPT_DIR/plugins.json" ]; then
    PLUGINS_FILE="$SCRIPT_DIR/plugins.json"
fi

if [ -n "$PLUGINS_FILE" ]; then
    print_info "Found plugins.json at $PLUGINS_FILE. Installing plugins..."
    bash "$SCRIPT_DIR/install-plugins.sh" --instance-path "$INSTANCE_PATH" --plugins-file "$PLUGINS_FILE" --container "moodle-web-$PORT"
else
    print_info "No plugins.json found. Installing default Moodle without extra plugins."
fi

echo ""
echo "=========================================="
print_success "Moodle instance is READY TO USE!"
echo "=========================================="
echo ""
echo "Instance Details:"
echo "  - Name: $INSTANCE_NAME"
echo "  - Path: $INSTANCE_PATH"
echo "  - URL: http://$IP_ADDRESS:$PORT"
echo ""
echo "Admin Login Credentials:"
echo "  - Username: $ADMIN_USER"
echo "  - Password: $ADMIN_PASS"
echo "  - Email: $ADMIN_EMAIL"
echo ""
echo "Container Names:"
echo "  - Web: moodle-web-$PORT"
echo "  - Database: moodle-db-$PORT"
echo "  - Redis: moodle-redis-$PORT"
echo "  - Cron: moodle-cron-$PORT"
echo ""
echo "Database Credentials:"
echo "  - Database: moodle"
echo "  - Username: moodleuser"
echo "  - Password: moodlepass"
echo "  - Host: db"
echo ""
print_success "You can now login at http://$IP_ADDRESS:$PORT"
echo ""
