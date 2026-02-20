#!/bin/bash

# Analysis Dashboard — Population Script Wrapper
# Copies the PHP script into a running Moodle container and executes it.
#
# Usage:
#   ./populate-dashboard.sh <port-or-container-name> [password-suffix]
#
# Examples:
#   ./populate-dashboard.sh 8092
#   ./populate-dashboard.sh 8092 MyPass99
#   ./populate-dashboard.sh moodle-web-8092

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

if [ -z "$1" ]; then
    print_error "Usage: $0 <port-or-container-name> [password-suffix]"
    echo "  Examples:"
    echo "    $0 8092"
    echo "    $0 8092 MyPass99"
    echo "    $0 moodle-web-8092"
    exit 1
fi

# Determine container name.
if [[ "$1" =~ ^[0-9]+$ ]]; then
    CONTAINER="moodle-web-$1"
else
    CONTAINER="$1"
fi

# Get password suffix.
if [ -n "$2" ]; then
    PASSWORD_SUFFIX="$2"
else
    read -p "Enter password suffix for all accounts (default: 123456): " PASSWORD_SUFFIX
    PASSWORD_SUFFIX=${PASSWORD_SUFFIX:-123456}
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_SCRIPT="$SCRIPT_DIR/populate_dashboard_data.php"

if [ ! -f "$PHP_SCRIPT" ]; then
    print_error "populate_dashboard_data.php not found at $SCRIPT_DIR"
    exit 1
fi

# Verify container is running.
if ! docker inspect "$CONTAINER" > /dev/null 2>&1; then
    print_error "Container '$CONTAINER' not found. Is the instance running?"
    exit 1
fi

print_info "Copying dashboard population script into container '$CONTAINER'..."
docker cp "$PHP_SCRIPT" "$CONTAINER:/var/www/html/populate_dashboard_data.php"

print_info "Running population script with password suffix: $PASSWORD_SUFFIX"
print_info "This may take a few minutes..."
docker exec "$CONTAINER" php /var/www/html/populate_dashboard_data.php --password-suffix="$PASSWORD_SUFFIX"

print_info "Cleaning up..."
docker exec "$CONTAINER" rm -f /var/www/html/populate_dashboard_data.php

print_success "Done! Dashboard data has been populated with 25 users, 5 courses, and all widget data."
