#!/bin/bash

# Moodle UI Simplification — Native (No Docker) Apply/Revert Changes
# Reads manifest.json and lets the user interactively apply or revert file changes
# directly on the local Moodle filesystem.
#
# Usage:
#   ./apply-changes-native.sh <moodle-base-dir>
#
# Examples:
#   ./apply-changes-native.sh ~/moodle-instances/moodle-instance-8088
#   ./apply-changes-native.sh /var/www/moodle-base
#
# The <moodle-base-dir> should contain a 'moodle/' folder (the webroot).

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

if [ -z "$1" ]; then
    print_error "Usage: $0 <moodle-base-dir>"
    echo "  Examples:"
    echo "    $0 ~/moodle-instances/moodle-instance-8088"
    echo "    $0 /var/www/moodle-base"
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

# Check for jq.
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed."
    print_info "Install it with: sudo apt install jq"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"

if [ ! -f "$MANIFEST" ]; then
    print_error "manifest.json not found at $SCRIPT_DIR"
    exit 1
fi

# Convert a Moodle path to the folder name convention.
# e.g., moodle/user/editlib.php -> moodle_user_editlib-php
path_to_folder() {
    echo "$1" | sed 's|/|_|g' | sed 's|\\.|-|g'
}

CHANGE_COUNT=$(jq -r '.file_changes | length' "$MANIFEST")

if [ "$CHANGE_COUNT" -eq 0 ]; then
    print_warning "No file changes defined in manifest.json."
    exit 0
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Moodle UI Simplification Manager (Native)    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Moodle root: ${CYAN}$MOODLE_ROOT${NC}"
echo -e "  Changes:     ${CYAN}$CHANGE_COUNT file(s)${NC}"
echo ""
echo "────────────────────────────────────────────────────"
echo ""

# Track if any changes were made.
CHANGES_MADE=0

for i in $(seq 0 $((CHANGE_COUNT - 1))); do
    FILE_PATH=$(jq -r ".file_changes[$i].path" "$MANIFEST")
    CURRENT_CHOICE=$(jq -r ".file_changes[$i].choice // \"default\"" "$MANIFEST")

    FOLDER_NAME=$(path_to_folder "$FILE_PATH")
    FOLDER_PATH="$SCRIPT_DIR/$FOLDER_NAME"

    echo -e "  ${BOLD}File:${NC}    $FILE_PATH"

    # Check if the folder with default/new files exists.
    if [ ! -d "$FOLDER_PATH" ]; then
        print_warning "  Folder '$FOLDER_NAME' not found. Skipping."
        echo ""
        continue
    fi

    if [ ! -f "$FOLDER_PATH/default.php" ] || [ ! -f "$FOLDER_PATH/new.php" ]; then
        print_warning "  Missing default.php or new.php in '$FOLDER_NAME'. Skipping."
        echo ""
        continue
    fi

    # Show current state.
    if [ "$CURRENT_CHOICE" = "new" ]; then
        echo -e "  ${BOLD}Current:${NC} ${GREEN}new (modified)${NC}"
    else
        echo -e "  ${BOLD}Current:${NC} ${YELLOW}default (original)${NC}"
    fi

    # Ask user what they want.
    echo ""
    echo "  Choose an option:"
    echo -e "    ${GREEN}1)${NC} Apply ${GREEN}new${NC} (modified version)"
    echo -e "    ${YELLOW}2)${NC} Revert to ${YELLOW}default${NC} (original version)"
    echo -e "    ${BLUE}3)${NC} Skip (keep current)"
    echo ""
    read -p "  Enter choice [1/2/3] (default: 3): " USER_CHOICE
    USER_CHOICE=${USER_CHOICE:-3}

    case "$USER_CHOICE" in
        1)
            TARGET_CHOICE="new"
            SOURCE_FILE="$FOLDER_PATH/new.php"
            ;;
        2)
            TARGET_CHOICE="default"
            SOURCE_FILE="$FOLDER_PATH/default.php"
            ;;
        3)
            print_info "  Skipped."
            echo "────────────────────────────────────────────────────"
            echo ""
            continue
            ;;
        *)
            print_warning "  Invalid choice. Skipping."
            echo "────────────────────────────────────────────────────"
            echo ""
            continue
            ;;
    esac

    # Skip if already in desired state.
    if [ "$TARGET_CHOICE" = "$CURRENT_CHOICE" ]; then
        print_info "  Already set to '$TARGET_CHOICE'. No change needed."
        echo "────────────────────────────────────────────────────"
        echo ""
        continue
    fi

    # The path in manifest is like "moodle/user/editlib.php".
    # Strip the leading "moodle/" to get the relative path inside the webroot.
    TARGET_PATH="$MOODLE_ROOT/${FILE_PATH#moodle/}"

    # Ensure the parent directory exists.
    mkdir -p "$(dirname "$TARGET_PATH")"

    print_info "  Copying $TARGET_CHOICE version to $TARGET_PATH ..."
    if cp "$SOURCE_FILE" "$TARGET_PATH"; then
        # Fix permissions.
        chmod 644 "$TARGET_PATH"

        # Update manifest.json with the new choice.
        jq ".file_changes[$i].choice = \"$TARGET_CHOICE\"" "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

        if [ "$TARGET_CHOICE" = "new" ]; then
            print_success "  Applied ${GREEN}new${NC} version ✓"
        else
            print_success "  Reverted to ${YELLOW}default${NC} version ✓"
        fi
        CHANGES_MADE=$((CHANGES_MADE + 1))
    else
        print_error "  Failed to copy file."
    fi

    echo "────────────────────────────────────────────────────"
    echo ""
done

# Purge Moodle caches if any changes were made.
if [ "$CHANGES_MADE" -gt 0 ]; then
    PHP_BIN=$(command -v php 2>/dev/null || true)
    if [ -n "$PHP_BIN" ] && [ -f "$MOODLE_ROOT/admin/cli/purge_caches.php" ]; then
        print_info "Purging Moodle caches..."
        if "$PHP_BIN" "$MOODLE_ROOT/admin/cli/purge_caches.php" 2>/dev/null; then
            print_success "Caches purged."
        else
            print_warning "Could not purge caches. You may need to do this manually."
        fi
    else
        print_warning "PHP not found or cache script missing. Purge caches manually."
    fi
fi

echo ""
echo "════════════════════════════════════════════════════"
echo -e "${GREEN}Done!${NC} $CHANGES_MADE change(s) applied."
echo "════════════════════════════════════════════════════"
echo ""
