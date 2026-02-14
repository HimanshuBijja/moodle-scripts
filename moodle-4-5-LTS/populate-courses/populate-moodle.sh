#!/bin/bash

# Moodle Population Script — Wrapper
# Copies the PHP population script into a running Moodle container and executes it.
#
# Usage:
#   ./populate-moodle.sh <port-or-container-name> [password-suffix]
#
# Examples:
#   ./populate-moodle.sh 8088
#   ./populate-moodle.sh 8088 MyPass99
#   ./populate-moodle.sh moodle-web-8088 MyPass99

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
    echo "    $0 8088"
    echo "    $0 8088 MyPass99"
    echo "    $0 moodle-web-8088 MyPass99"
    exit 1
fi

# Determine container name.
if [[ "$1" =~ ^[0-9]+$ ]]; then
    CONTAINER="moodle-web-$1"
else
    CONTAINER="$1"
fi

# Get password suffix from second argument or prompt interactively.
if [ -n "$2" ]; then
    PASSWORD_SUFFIX="$2"
else
    read -p "Enter password suffix for all accounts (default: 123456): " PASSWORD_SUFFIX
    PASSWORD_SUFFIX=${PASSWORD_SUFFIX:-123456}
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_SCRIPT="$SCRIPT_DIR/populate_courses.php"

if [ ! -f "$PHP_SCRIPT" ]; then
    print_error "populate_courses.php not found at $SCRIPT_DIR"
    exit 1
fi

# Verify container is running.
if ! docker inspect "$CONTAINER" > /dev/null 2>&1; then
    print_error "Container '$CONTAINER' not found. Is the instance running?"
    exit 1
fi

print_info "Copying population script into container '$CONTAINER'..."
docker cp "$PHP_SCRIPT" "$CONTAINER:/var/www/html/populate_courses.php"

print_info "Running population script with password suffix: $PASSWORD_SUFFIX"
print_info "This may take a few minutes..."
docker exec "$CONTAINER" php /var/www/html/populate_courses.php --password-suffix="$PASSWORD_SUFFIX"

print_info "Cleaning up..."
docker exec "$CONTAINER" rm -f /var/www/html/populate_courses.php

print_success "Done! Your Moodle instance is now populated with courses, users, and activity."
