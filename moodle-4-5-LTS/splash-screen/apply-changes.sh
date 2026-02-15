#!/bin/bash

# Moodle Splash Screen — Apply/Revert Changes
# Reads manifest.json and lets the user interactively apply or revert
# file and folder changes in a running Moodle Docker container.
#
# Usage:
#   ./apply-changes.sh
#   (The script will prompt you for the port or container name.)

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

# ── Check for jq ────────────────────────────────────────────────────
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

# ── Prompt for port or container name ───────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         Moodle Splash Screen Manager            ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
read -p "  Enter port number or container name: " USER_INPUT

if [ -z "$USER_INPUT" ]; then
    print_error "No port or container name provided."
    exit 1
fi

# Determine container name.
if [[ "$USER_INPUT" =~ ^[0-9]+$ ]]; then
    CONTAINER="moodle-web-$USER_INPUT"
else
    CONTAINER="$USER_INPUT"
fi

# Verify container is running.
if ! docker inspect "$CONTAINER" > /dev/null 2>&1; then
    print_error "Container '$CONTAINER' not found. Is the instance running?"
    exit 1
fi

# ── Read manifest ──────────────────────────────────────────────────
CHANGE_COUNT=$(jq -r '.file_changes | length' "$MANIFEST")

if [ "$CHANGE_COUNT" -eq 0 ]; then
    print_warning "No file changes defined in manifest.json."
    exit 0
fi

echo ""
echo -e "  Container: ${CYAN}$CONTAINER${NC}"
echo -e "  Changes:   ${CYAN}$CHANGE_COUNT entry/entries${NC}"
echo ""
echo "────────────────────────────────────────────────────"
echo ""

# Track if any changes were made.
CHANGES_MADE=0

for i in $(seq 0 $((CHANGE_COUNT - 1))); do
    FILE_PATH=$(jq -r ".file_changes[$i].path" "$MANIFEST")
    LOCAL_PATH=$(jq -r ".file_changes[$i].local_path" "$MANIFEST")
    CURRENT_CHOICE=$(jq -r ".file_changes[$i].choice // \"default\"" "$MANIFEST")

    LOCAL_DIR="$SCRIPT_DIR/$LOCAL_PATH"

    echo -e "  ${BOLD}Path:${NC}    $FILE_PATH"
    echo -e "  ${BOLD}Source:${NC}  $LOCAL_PATH/"

    # Check if the local directory exists.
    if [ ! -d "$LOCAL_DIR" ]; then
        print_warning "  Folder '$LOCAL_PATH' not found. Skipping."
        echo ""
        continue
    fi

    # ── Detect entry type: file (has default.*/new.*) or directory ──
    IS_FILE_ENTRY=false
    FILE_EXT=""

    # Look for default.* and new.* files to determine if this is a file entry.
    for f in "$LOCAL_DIR"/default.*; do
        if [ -f "$f" ]; then
            FILE_EXT="${f##*.}"
            if [ -f "$LOCAL_DIR/new.$FILE_EXT" ]; then
                IS_FILE_ENTRY=true
            fi
        fi
        break
    done

    # The path in manifest is like "moodle/theme/boost_union/pix".
    # Inside the container, "moodle/" maps to "/var/www/html/".
    CONTAINER_PATH="/var/www/html/${FILE_PATH#moodle/}"

    if [ "$IS_FILE_ENTRY" = true ]; then
        # ── FILE ENTRY ─────────────────────────────────────────────
        echo -e "  ${BOLD}Type:${NC}    File (.$FILE_EXT)"

        if [ "$CURRENT_CHOICE" = "new" ]; then
            echo -e "  ${BOLD}Current:${NC} ${GREEN}new (modified)${NC}"
        else
            echo -e "  ${BOLD}Current:${NC} ${YELLOW}default (original)${NC}"
        fi

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
                SOURCE_FILE="$LOCAL_DIR/new.$FILE_EXT"
                ;;
            2)
                TARGET_CHOICE="default"
                SOURCE_FILE="$LOCAL_DIR/default.$FILE_EXT"
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

    else
        # ── DIRECTORY ENTRY ────────────────────────────────────────
        echo -e "  ${BOLD}Type:${NC}    Directory"

        if [ "$CURRENT_CHOICE" = "new" ]; then
            echo -e "  ${BOLD}Current:${NC} ${GREEN}new (applied)${NC}"
        else
            echo -e "  ${BOLD}Current:${NC} ${YELLOW}default (not applied)${NC}"
        fi

        echo ""
        echo "  Choose an option:"
        echo -e "    ${GREEN}1)${NC} Apply — copy folder contents into container"
        echo -e "    ${YELLOW}2)${NC} Revert — remove copied contents from container"
        echo -e "    ${BLUE}3)${NC} Skip (keep current)"
        echo ""
        read -p "  Enter choice [1/2/3] (default: 3): " USER_CHOICE
        USER_CHOICE=${USER_CHOICE:-3}

        case "$USER_CHOICE" in
            1)  TARGET_CHOICE="new" ;;
            2)  TARGET_CHOICE="default" ;;
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

        if [ "$TARGET_CHOICE" = "new" ]; then
            # Apply: copy each item inside the local_path into the container path.
            print_info "  Copying directory contents to $CONTAINER_PATH ..."

            # Ensure the destination directory exists in the container.
            docker exec "$CONTAINER" mkdir -p "$CONTAINER_PATH"

            COPY_FAILED=false
            for item in "$LOCAL_DIR"/*; do
                ITEM_NAME=$(basename "$item")
                if docker cp "$item" "$CONTAINER:$CONTAINER_PATH/$ITEM_NAME"; then
                    print_info "    Copied $ITEM_NAME"
                else
                    print_error "    Failed to copy $ITEM_NAME"
                    COPY_FAILED=true
                fi
            done

            if [ "$COPY_FAILED" = false ]; then
                # Fix ownership recursively.
                docker exec "$CONTAINER" chown -R www-data:www-data "$CONTAINER_PATH"

                jq ".file_changes[$i].choice = \"new\"" "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
                print_success "  Directory contents applied ✓"
                CHANGES_MADE=$((CHANGES_MADE + 1))
            else
                print_error "  Some files failed to copy."
            fi
        else
            # Revert: remove the items we copied into the container.
            print_warning "  Reverting will remove the following from the container:"
            for item in "$LOCAL_DIR"/*; do
                ITEM_NAME=$(basename "$item")
                echo -e "    ${RED}✗${NC} $CONTAINER_PATH/$ITEM_NAME"
            done
            echo ""
            read -p "  Are you sure? (y/N): " CONFIRM
            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                for item in "$LOCAL_DIR"/*; do
                    ITEM_NAME=$(basename "$item")
                    docker exec "$CONTAINER" rm -rf "$CONTAINER_PATH/$ITEM_NAME" 2>/dev/null || true
                    print_info "    Removed $ITEM_NAME"
                done

                jq ".file_changes[$i].choice = \"default\"" "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
                print_success "  Directory contents reverted ✓"
                CHANGES_MADE=$((CHANGES_MADE + 1))
            else
                print_info "  Revert cancelled."
            fi
        fi
    fi

    echo "────────────────────────────────────────────────────"
    echo ""
done

# ── Purge Moodle caches if any changes were made ───────────────────
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
