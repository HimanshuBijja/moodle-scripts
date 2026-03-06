#!/bin/bash

# Moodle Population Script — Native (No Docker) Wrapper
# Copies the PHP population script into the Moodle webroot and executes it.
#
# Usage:
#   ./populate-moodle-native.sh <moodle-base-dir> [num-courses] [password-suffix]
#
# Examples:
#   ./populate-moodle-native.sh ~/moodle-instances/moodle-instance-8088
#   ./populate-moodle-native.sh /var/www/moodle-base 1
#   ./populate-moodle-native.sh /var/www/moodle-base 3 MyPass99
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
    print_error "Usage: $0 <moodle-base-dir> [num-courses] [password-suffix]"
    echo "  Examples:"
    echo "    $0 ~/moodle-instances/moodle-instance-8088"
    echo "    $0 /var/www/moodle-base 1"
    echo "    $0 /var/www/moodle-base 3 MyPass99"
    exit 1
fi

BASE_DIR="$1"

# Resolve the moodle webroot.
if [ -d "$BASE_DIR/moodle" ]; then
    MOODLE_ROOT="$BASE_DIR/moodle"
elif [ -f "$BASE_DIR/config.php" ]; then
    # User pointed directly at the moodle folder
    MOODLE_ROOT="$BASE_DIR"
else
    print_error "Cannot find Moodle webroot. Ensure '$BASE_DIR' contains a 'moodle/' folder or is the Moodle root itself."
    exit 1
fi

# Get number of courses.
NUM_COURSES_ARG=""
if [ -n "$2" ]; then
    NUM_COURSES_ARG="--num-courses=$2"
fi

# Get password suffix.
if [ -n "$3" ]; then
    PASSWORD_SUFFIX="$3"
else
    PASSWORD_SUFFIX="123456"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_SCRIPT="$SCRIPT_DIR/populate_courses.php"

if [ ! -f "$PHP_SCRIPT" ]; then
    print_error "populate_courses.php not found at $SCRIPT_DIR"
    exit 1
fi

# Detect the PHP binary.
PHP_BIN=$(command -v php 2>/dev/null || true)
if [ -z "$PHP_BIN" ]; then
    print_error "PHP CLI not found. Please install PHP."
    exit 1
fi

print_info "Moodle root: $MOODLE_ROOT"
print_info "Copying population script into Moodle root..."
cp "$PHP_SCRIPT" "$MOODLE_ROOT/populate_courses.php"

print_info "Running population script with password suffix: $PASSWORD_SUFFIX"
print_info "This may take a few minutes..."
"$PHP_BIN" "$MOODLE_ROOT/populate_courses.php" --password-suffix="$PASSWORD_SUFFIX" $NUM_COURSES_ARG

print_info "Cleaning up..."
rm -f "$MOODLE_ROOT/populate_courses.php"

print_success "Done! Your Moodle instance is now populated with courses, users, and activity."
