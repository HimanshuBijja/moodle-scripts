#!/bin/bash

# Moodle UI Simplification — Apply/Revert Changes
# Reads manifest.json and lets the user interactively apply or revert file changes
# in a running Moodle Docker container.
#
# Usage:
#   ./apply-changes.sh <port-or-container-name>
#
# Examples:
#   ./apply-changes.sh 8088
#   ./apply-changes.sh moodle-web-8088

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
    print_error "Usage: $0 <port-or-container-name>"
    echo "  Examples:"
    echo "    $0 8088"
    echo "    $0 moodle-web-8088"
    exit 1
fi

# Determine container name.
if [[ "$1" =~ ^[0-9]+$ ]]; then
    CONTAINER="moodle-web-$1"
else
    CONTAINER="$1"
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

# Verify container is running.
if ! docker inspect "$CONTAINER" > /dev/null 2>&1; then
    print_error "Container '$CONTAINER' not found. Is the instance running?"
    exit 1
fi

# Convert a Moodle path to the folder name convention.
# e.g., moodle/user/editlib.php -> moodle_user_editlib-php
path_to_folder() {
    echo "$1" | sed 's|/|_|g' | sed 's|\.|-|g'
}

CHANGE_COUNT=$(jq -r '.file_changes | length' "$MANIFEST")

if [ "$CHANGE_COUNT" -eq 0 ]; then
    print_warning "No file changes defined in manifest.json."
    exit 0
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       Moodle UI Simplification Manager          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Container: ${CYAN}$CONTAINER${NC}"
echo -e "  Changes:   ${CYAN}$CHANGE_COUNT file(s)${NC}"
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
    # Inside the container, "moodle/" maps to "/var/www/html/".
    CONTAINER_PATH="/var/www/html/${FILE_PATH#moodle/}"

    print_info "  Copying $TARGET_CHOICE version to $CONTAINER_PATH ..."
    if docker cp "$SOURCE_FILE" "$CONTAINER:$CONTAINER_PATH"; then
        # Fix ownership and permissions.
        docker exec "$CONTAINER" chown www-data:www-data "$CONTAINER_PATH"
        docker exec "$CONTAINER" chmod 644 "$CONTAINER_PATH"

        # Update manifest.json with the new choice.
        jq ".file_changes[$i].choice = \"$TARGET_CHOICE\"" "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

        if [ "$TARGET_CHOICE" = "new" ]; then
            print_success "  Applied ${GREEN}new${NC} version ✓"
        else
            print_success "  Reverted to ${YELLOW}default${NC} version ✓"
        fi
        CHANGES_MADE=$((CHANGES_MADE + 1))
    else
        print_error "  Failed to copy file to container."
    fi

    echo "────────────────────────────────────────────────────"
    echo ""
done

# Purge Moodle caches if any changes were made.
if [ "$CHANGES_MADE" -gt 0 ]; then
    print_info "Purging Moodle caches..."
    if docker exec -u www-data "$CONTAINER" php /var/www/html/admin/cli/purge_caches.php 2>/dev/null; then
        print_success "Caches purged."
    else
        print_warning "Could not purge caches. You may need to do this manually."
    fi
fi

echo ""
echo "════════════════════════════════════════════════════"
echo -e "${GREEN}Done!${NC} $CHANGES_MADE change(s) applied."
echo "════════════════════════════════════════════════════"
echo ""
