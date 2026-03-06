#!/bin/bash

# Analysis Dashboard — Native (No Docker) Population Script Wrapper
# Copies the PHP script into the Moodle webroot and executes it.
#
# Usage:
#   ./populate-dashboard-native.sh <moodle-base-dir> [password-suffix]
#
# Examples:
#   ./populate-dashboard-native.sh ~/moodle-instances/moodle-instance-8092
#   ./populate-dashboard-native.sh /var/www/moodle-base MyPass99
#
# The <moodle-base-dir> should contain a 'moodle/' folder (the webroot).

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

if [ -z "$1" ]; then
    print_error "Usage: $0 <moodle-base-dir> [password-suffix]"
    echo "  Examples:"
    echo "    $0 ~/moodle-instances/moodle-instance-8092"
    echo "    $0 /var/www/moodle-base MyPass99"
    exit 1
fi

BASE_DIR="$1"

# Resolve the moodle webroot.
if [ -d "$BASE_DIR/moodle" ]; then
    MOODLE_ROOT="$BASE_DIR/moodle"
elif [ -f "$BASE_DIR/config.php" ]; then
    MOODLE_ROOT="$BASE_DIR"
else
    print_error "Cannot find Moodle webroot. Ensure '$BASE_DIR' contains a 'moodle/' folder or is the Moodle root itself."
    exit 1
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

# Detect the PHP binary.
PHP_BIN=$(command -v php 2>/dev/null || true)
if [ -z "$PHP_BIN" ]; then
    print_error "PHP CLI not found. Please install PHP."
    exit 1
fi

print_info "Moodle root: $MOODLE_ROOT"
print_info "Copying dashboard population script into Moodle root..."
cp "$PHP_SCRIPT" "$MOODLE_ROOT/populate_dashboard_data.php"

print_info "Running population script with password suffix: $PASSWORD_SUFFIX"
print_info "This may take a few minutes..."
"$PHP_BIN" "$MOODLE_ROOT/populate_dashboard_data.php" --password-suffix="$PASSWORD_SUFFIX"

print_info "Cleaning up..."
rm -f "$MOODLE_ROOT/populate_dashboard_data.php"

print_success "Done! Dashboard data has been populated with 25 users, 5 courses, and all widget data."
