#!/bin/bash

# Moodle Plugin Installer Script
# Installs plugins from a centralized GitHub repository based on plugins.json
# Can be used standalone or called from create-moodle-instance.sh
#
# Usage (standalone):
#   ./install-plugins.sh --instance-path /path/to/moodle-instance --container moodle-web-PORT
#   ./install-plugins.sh --instance-path /path/to/moodle-instance --container moodle-web-PORT --plugins-file /path/to/plugins.json
#
# Usage (auto-detect from port):
#   ./install-plugins.sh --port 8085
#   ./install-plugins.sh --port 8085 --plugins-file /path/to/plugins.json

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
INSTANCE_PATH=""
CONTAINER_NAME=""
PLUGINS_FILE=""
PORT=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --instance-path)
            INSTANCE_PATH="$2"
            shift 2
            ;;
        --container)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --plugins-file)
            PLUGINS_FILE="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --instance-path PATH   Path to the Moodle instance directory"
            echo "  --container NAME       Docker container name (e.g., moodle-web-8085)"
            echo "  --plugins-file PATH    Path to plugins.json (optional, auto-detected)"
            echo "  --port PORT            Port number (auto-detects instance-path and container)"
            echo "  -h, --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --port 8085"
            echo "  $0 --instance-path ~/moodle-instances/moodle-instance-8085 --container moodle-web-8085"
            echo "  $0 --port 8085 --plugins-file /path/to/plugins.json"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Auto-detect from port if provided
if [ -n "$PORT" ]; then
    INSTANCE_PATH="${INSTANCE_PATH:-$HOME/moodle-instances/moodle-instance-$PORT}"
    CONTAINER_NAME="${CONTAINER_NAME:-moodle-web-$PORT}"
fi

# Validate required parameters
if [ -z "$INSTANCE_PATH" ] || [ -z "$CONTAINER_NAME" ]; then
    print_error "Missing required parameters. Use --port or provide --instance-path and --container."
    print_info "Run '$0 --help' for usage information."
    exit 1
fi

# Validate instance path exists
if [ ! -d "$INSTANCE_PATH" ]; then
    print_error "Instance path does not exist: $INSTANCE_PATH"
    exit 1
fi

# Validate container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_error "Container '$CONTAINER_NAME' is not running."
    print_info "Start the instance first with: cd $INSTANCE_PATH && docker compose up -d"
    exit 1
fi

# Find plugins.json - check in order: explicit path, instance dir, scripts dir
if [ -n "$PLUGINS_FILE" ]; then
    if [ ! -f "$PLUGINS_FILE" ]; then
        print_error "Plugins file not found: $PLUGINS_FILE"
        exit 1
    fi
elif [ -f "$INSTANCE_PATH/plugins.json" ]; then
    PLUGINS_FILE="$INSTANCE_PATH/plugins.json"
elif [ -f "$SCRIPT_DIR/plugins.json" ]; then
    PLUGINS_FILE="$SCRIPT_DIR/plugins.json"
else
    print_warning "No plugins.json found. Nothing to install."
    print_info "Create a plugins.json in $SCRIPT_DIR or $INSTANCE_PATH"
    exit 0
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed."
    print_info "Install it with: sudo apt install jq"
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
    # URL format: https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{zip_file}
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

    # Determine target path inside the container
    CONTAINER_PLUGIN_PATH="/var/www/html/$PLUGIN_TYPE/$PLUGIN_INSTALL_DIR"

    # Remove existing plugin directory if it exists (for updates)
    docker exec "$CONTAINER_NAME" bash -c "rm -rf $CONTAINER_PLUGIN_PATH" 2>/dev/null || true

    # Create parent directory
    docker exec "$CONTAINER_NAME" mkdir -p "/var/www/html/$PLUGIN_TYPE"

    # Copy plugin files into the container
    print_info "  Copying to container: $CONTAINER_PLUGIN_PATH"
    if ! docker cp "$SOURCE_DIR" "${CONTAINER_NAME}:${CONTAINER_PLUGIN_PATH}"; then
        print_error "  Failed to copy $PLUGIN_NAME to container"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Fix ownership
    docker exec "$CONTAINER_NAME" chown -R www-data:www-data "$CONTAINER_PLUGIN_PATH"
    docker exec "$CONTAINER_NAME" chmod -R 755 "$CONTAINER_PLUGIN_PATH"

    print_success "  $PLUGIN_NAME installed to $CONTAINER_PLUGIN_PATH"
    INSTALLED=$((INSTALLED + 1))

    # Cleanup extracted files
    rm -rf "$EXTRACT_DIR" "$ZIP_PATH"
done

echo ""
echo "────────────────────────────────────────────────"

# Run Moodle upgrade to register new plugins
if [ "$INSTALLED" -gt 0 ]; then
    print_info "Running Moodle upgrade to register plugins..."

    if docker exec -u www-data "$CONTAINER_NAME" php /var/www/html/admin/cli/upgrade.php --non-interactive; then
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
