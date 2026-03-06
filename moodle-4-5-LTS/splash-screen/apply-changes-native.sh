#!/bin/bash

# Moodle Splash Screen — Native (No Docker) Apply/Revert Changes
# Reads manifest.json and lets the user interactively apply or revert
# file and folder changes directly on the local Moodle filesystem.
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

# ── Prompt for Moodle base directory ────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Moodle Splash Screen Manager (Native)      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

if [ -n "$1" ]; then
    BASE_DIR="$1"
else
    read -p "  Enter path to Moodle base directory: " BASE_DIR
fi

if [ -z "$BASE_DIR" ]; then
    print_error "No path provided."
    exit 1
fi

# Resolve the moodle webroot.
if [ -d "$BASE_DIR/moodle" ]; then
    MOODLE_ROOT="$BASE_DIR/moodle"
elif [ -f "$BASE_DIR/config.php" ]; then
    MOODLE_ROOT="$BASE_DIR"
else
    print_error "Cannot find Moodle webroot. Ensure '$BASE_DIR' contains a 'moodle/' folder or is the Moodle root itself."
    exit 1
fi

# ── Read manifest ──────────────────────────────────────────────────
CHANGE_COUNT=$(jq -r '.file_changes | length' "$MANIFEST")

if [ "$CHANGE_COUNT" -eq 0 ]; then
    print_warning "No file changes defined in manifest.json."
    exit 0
fi

echo ""
echo -e "  Moodle root: ${CYAN}$MOODLE_ROOT${NC}"
echo -e "  Changes:     ${CYAN}$CHANGE_COUNT entry/entries${NC}"
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
    # Strip the leading "moodle/" to get the relative path inside the webroot.
    TARGET_PATH="$MOODLE_ROOT/${FILE_PATH#moodle/}"

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

        # Ensure parent directory exists.
        mkdir -p "$(dirname "$TARGET_PATH")"

        print_info "  Copying $TARGET_CHOICE version to $TARGET_PATH ..."
        if cp "$SOURCE_FILE" "$TARGET_PATH"; then
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
        echo -e "    ${GREEN}1)${NC} Apply — copy folder contents into Moodle"
        echo -e "    ${YELLOW}2)${NC} Revert — remove copied contents from Moodle"
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
            # Apply: copy each item inside the local_path into the target path.
            print_info "  Copying directory contents to $TARGET_PATH ..."

            # Ensure the destination directory exists.
            mkdir -p "$TARGET_PATH"

            COPY_FAILED=false
            for item in "$LOCAL_DIR"/*; do
                ITEM_NAME=$(basename "$item")
                if cp -r "$item" "$TARGET_PATH/$ITEM_NAME"; then
                    print_info "    Copied $ITEM_NAME"
                else
                    print_error "    Failed to copy $ITEM_NAME"
                    COPY_FAILED=true
                fi
            done

            if [ "$COPY_FAILED" = false ]; then
                jq ".file_changes[$i].choice = \"new\"" "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
                print_success "  Directory contents applied ✓"
                CHANGES_MADE=$((CHANGES_MADE + 1))
            else
                print_error "  Some files failed to copy."
            fi
        else
            # Revert: remove the items we copied.
            print_warning "  Reverting will remove the following from Moodle:"
            for item in "$LOCAL_DIR"/*; do
                ITEM_NAME=$(basename "$item")
                echo -e "    ${RED}✗${NC} $TARGET_PATH/$ITEM_NAME"
            done
            echo ""
            read -p "  Are you sure? (y/N): " CONFIRM
            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                for item in "$LOCAL_DIR"/*; do
                    ITEM_NAME=$(basename "$item")
                    rm -rf "$TARGET_PATH/$ITEM_NAME" 2>/dev/null || true
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
