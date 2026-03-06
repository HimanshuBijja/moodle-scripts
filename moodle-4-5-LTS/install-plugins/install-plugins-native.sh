#!/bin/bash

# Moodle Plugin Installer Script — Native (No Docker)
# Installs plugins from a centralized GitHub repository based on plugins.json
# directly into a local Moodle filesystem.
#
# Usage:
#   ./install-plugins-native.sh --moodle-path /path/to/moodle
#   ./install-plugins-native.sh --moodle-path /path/to/moodle --plugins-file /path/to/plugins.json
#   ./install-plugins-native.sh --base-dir ~/moodle-instances/moodle-instance-8085

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_plugin() { echo -e "${CYAN}[PLUGIN]${NC} $1"; }

# Script directory (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
MOODLE_PATH=""
BASE_DIR=""
PLUGINS_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --moodle-path)
            MOODLE_PATH="$2"
            shift 2
            ;;
        --base-dir)
            BASE_DIR="$2"
            shift 2
            ;;
        --plugins-file)
            PLUGINS_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --moodle-path PATH   Path to the Moodle webroot (containing config.php)"
            echo "  --base-dir PATH      Path to the instance base dir (containing moodle/ folder)"
            echo "  --plugins-file PATH  Path to plugins.json (optional, auto-detected)"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --moodle-path /var/www/html/moodle"
            echo "  $0 --base-dir ~/moodle-instances/moodle-instance-8085"
            echo "  $0 --moodle-path /var/www/html/moodle --plugins-file /path/to/plugins.json"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Resolve Moodle webroot from base-dir if moodle-path not given.
if [ -z "$MOODLE_PATH" ] && [ -n "$BASE_DIR" ]; then
    if [ -d "$BASE_DIR/moodle" ]; then
        MOODLE_PATH="$BASE_DIR/moodle"
    elif [ -f "$BASE_DIR/config.php" ]; then
        MOODLE_PATH="$BASE_DIR"
    fi
fi

# Validate required parameters
if [ -z "$MOODLE_PATH" ]; then
    print_error "Missing required parameters. Provide --moodle-path or --base-dir."
    print_info "Run '$0 --help' for usage information."
    exit 1
fi

# Validate Moodle path exists
if [ ! -d "$MOODLE_PATH" ]; then
    print_error "Moodle path does not exist: $MOODLE_PATH"
    exit 1
fi

# Validate it looks like a Moodle installation
if [ ! -f "$MOODLE_PATH/config.php" ] && [ ! -f "$MOODLE_PATH/version.php" ]; then
    print_warning "Path '$MOODLE_PATH' does not appear to be a Moodle installation (no config.php or version.php found)."
    read -p "Continue anyway? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Find plugins.json - check in order: explicit path, base dir, scripts dir
if [ -n "$PLUGINS_FILE" ]; then
    if [ ! -f "$PLUGINS_FILE" ]; then
        print_error "Plugins file not found: $PLUGINS_FILE"
        exit 1
    fi
elif [ -n "$BASE_DIR" ] && [ -f "$BASE_DIR/plugins.json" ]; then
    PLUGINS_FILE="$BASE_DIR/plugins.json"
elif [ -f "$SCRIPT_DIR/plugins.json" ]; then
    PLUGINS_FILE="$SCRIPT_DIR/plugins.json"
else
    print_warning "No plugins.json found. Nothing to install."
    print_info "Create a plugins.json in $SCRIPT_DIR or provide via --plugins-file"
    exit 0
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed."
    print_info "Install it with: sudo apt install jq"
    exit 1
fi

# Detect PHP binary
PHP_BIN=$(command -v php 2>/dev/null || true)
if [ -z "$PHP_BIN" ]; then
    print_error "PHP CLI not found. Please install PHP."
    exit 1
fi

# Read plugins.json
print_info "Reading plugins from: $PLUGINS_FILE"

REPO_URL=$(jq -r '.repo' "$PLUGINS_FILE")
PLUGIN_COUNT=$(jq -r '.plugins | length' "$PLUGINS_FILE")

if [ "$PLUGIN_COUNT" -eq 0 ]; then
    print_warning "No plugins defined in plugins.json. Skipping."
    exit 0
fi

print_info "Repository: $REPO_URL"
print_info "Moodle path: $MOODLE_PATH"
print_info "Plugins to install: $PLUGIN_COUNT"
echo ""

# Extract owner/repo from URL (e.g., https://github.com/HimanshuBijja/moodle-plugins -> HimanshuBijja/moodle-plugins)
REPO_PATH=$(echo "$REPO_URL" | sed 's|https://github.com/||')

# Create temp directory for downloads
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Track results
INSTALLED=0
FAILED=0

# Install each plugin
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
    PLUGIN_NAME=$(jq -r ".plugins[$i].name" "$PLUGINS_FILE")
    PLUGIN_BRANCH=$(jq -r ".plugins[$i].branch" "$PLUGINS_FILE")
    PLUGIN_TAG=$(jq -r ".plugins[$i].tag" "$PLUGINS_FILE")
    PLUGIN_ZIP=$(jq -r ".plugins[$i].zip_file" "$PLUGINS_FILE")
    PLUGIN_TYPE=$(jq -r ".plugins[$i].type" "$PLUGINS_FILE")
    PLUGIN_INSTALL_DIR=$(jq -r ".plugins[$i].install_dir // empty" "$PLUGINS_FILE")

    # Default install_dir to name if not provided
    if [ -z "$PLUGIN_INSTALL_DIR" ]; then
        PLUGIN_INSTALL_DIR="$PLUGIN_NAME"
    fi

    echo "────────────────────────────────────────────────"
    print_plugin "Installing: $PLUGIN_NAME"
    print_info "  Branch: $PLUGIN_BRANCH | Tag: $PLUGIN_TAG"
    print_info "  Type: $PLUGIN_TYPE | Install dir: $PLUGIN_TYPE/$PLUGIN_INSTALL_DIR"
    print_info "  Zip: $PLUGIN_ZIP"

    # Download the zip file from GitHub
    DOWNLOAD_URL="https://raw.githubusercontent.com/${REPO_PATH}/${PLUGIN_BRANCH}/${PLUGIN_ZIP}"
    ZIP_PATH="$TEMP_DIR/${PLUGIN_ZIP}"

    print_info "  Downloading from: $DOWNLOAD_URL"

    if command -v curl &> /dev/null; then
        if ! curl -fsSL -o "$ZIP_PATH" "$DOWNLOAD_URL"; then
            print_error "  Failed to download $PLUGIN_NAME"
            FAILED=$((FAILED + 1))
            continue
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -q -O "$ZIP_PATH" "$DOWNLOAD_URL"; then
            print_error "  Failed to download $PLUGIN_NAME"
            FAILED=$((FAILED + 1))
            continue
        fi
    else
        print_error "  Neither curl nor wget found. Cannot download."
        FAILED=$((FAILED + 1))
        continue
    fi

    # Verify the download is actually a zip file
    if ! file "$ZIP_PATH" | grep -qi "zip"; then
        print_error "  Downloaded file is not a valid zip: $ZIP_PATH"
        FAILED=$((FAILED + 1))
        continue
    fi

    print_success "  Downloaded successfully"

    # Extract to temp directory
    EXTRACT_DIR="$TEMP_DIR/extract_${PLUGIN_NAME}"
    mkdir -p "$EXTRACT_DIR"

    if ! unzip -q -o "$ZIP_PATH" -d "$EXTRACT_DIR"; then
        print_error "  Failed to extract $PLUGIN_ZIP"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Find the extracted plugin directory (usually a single top-level directory)
    EXTRACTED_CONTENTS=$(ls "$EXTRACT_DIR")
    EXTRACTED_COUNT=$(echo "$EXTRACTED_CONTENTS" | wc -l)

    if [ "$EXTRACTED_COUNT" -eq 1 ] && [ -d "$EXTRACT_DIR/$EXTRACTED_CONTENTS" ]; then
        SOURCE_DIR="$EXTRACT_DIR/$EXTRACTED_CONTENTS"
    else
        SOURCE_DIR="$EXTRACT_DIR"
    fi

    # Determine target path on the filesystem
    PLUGIN_TARGET_PATH="$MOODLE_PATH/$PLUGIN_TYPE/$PLUGIN_INSTALL_DIR"

    # Remove existing plugin directory if it exists (for updates)
    rm -rf "$PLUGIN_TARGET_PATH" 2>/dev/null || true

    # Create parent directory
    mkdir -p "$MOODLE_PATH/$PLUGIN_TYPE"

    # Copy plugin files
    print_info "  Copying to: $PLUGIN_TARGET_PATH"
    if cp -r "$SOURCE_DIR" "$PLUGIN_TARGET_PATH"; then
        # Fix permissions
        chmod -R 755 "$PLUGIN_TARGET_PATH"

        print_success "  $PLUGIN_NAME installed to $PLUGIN_TARGET_PATH"
        INSTALLED=$((INSTALLED + 1))
    else
        print_error "  Failed to copy $PLUGIN_NAME"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Cleanup extracted files
    rm -rf "$EXTRACT_DIR" "$ZIP_PATH"
done

echo ""
echo "────────────────────────────────────────────────"

# Run Moodle upgrade to register new plugins
if [ "$INSTALLED" -gt 0 ]; then
    print_info "Running Moodle upgrade to register plugins..."

    if "$PHP_BIN" "$MOODLE_PATH/admin/cli/upgrade.php" --non-interactive; then
        print_success "Moodle upgrade completed successfully!"
    else
        print_warning "Moodle upgrade returned a non-zero exit code."
        print_info "You may need to complete the upgrade manually via the web interface."
    fi
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Plugin Installation Summary${NC}"
echo "=========================================="
echo "  Installed: $INSTALLED"
echo "  Failed:    $FAILED"
echo "  Total:     $PLUGIN_COUNT"
echo ""

if [ "$FAILED" -gt 0 ]; then
    print_warning "Some plugins failed to install. Check the output above for details."
    exit 1
else
    print_success "All plugins installed successfully!"
fi
