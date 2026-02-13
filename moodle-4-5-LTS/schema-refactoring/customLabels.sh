#!/bin/bash
#
# customLabels.sh - Apply custom label changes to Moodle language files
#
# Reads customLabels.json (same directory as this script) and replaces
# strings in the specified Moodle files.
#
# Usage:
#   bash customLabels.sh [moodle_base_dir]
#
#   moodle_base_dir : Directory containing the 'moodle/' folder.
#                     Defaults to current working directory.
#                     If the given directory doesn't contain 'moodle/',
#                     but has a moodle dir inside, it will be detected.

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ── Helpers ───────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC}  $*"; }
error()   { echo -e "${RED}[ERR]${NC}   $*"; }

# ── Dependency check ──────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
    error "'jq' is required but not installed. Install it with: sudo apt install jq"
    exit 1
fi

# ── Resolve paths ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE="${SCRIPT_DIR}/customLabels.json"

if [[ ! -f "$JSON_FILE" ]]; then
    error "customLabels.json not found at: $JSON_FILE"
    exit 1
fi

# Determine the base directory (parent of 'moodle/')
if [[ -n "${1:-}" ]]; then
    BASE_DIR="$1"
else
    echo -ne "${CYAN}Enter the Moodle base directory path${NC} (press Enter for current directory): "
    read -r USER_PATH
    BASE_DIR="${USER_PATH:-.}"
fi
BASE_DIR="$(cd "$BASE_DIR" && pwd)"

# If base dir doesn't directly contain 'moodle/', look for it
if [[ ! -d "${BASE_DIR}/moodle" ]]; then
    # Check if the given dir itself IS the moodle dir
    if [[ -f "${BASE_DIR}/version.php" ]] && grep -q 'MOODLE VERSION' "${BASE_DIR}/version.php" 2>/dev/null; then
        # User pointed directly at the moodle folder
        BASE_DIR="$(dirname "$BASE_DIR")"
    else
        # Search for a moodle directory
        info "Searching for 'moodle/' directory under: $BASE_DIR ..."
        FOUND_MOODLE="$(find "$BASE_DIR" -maxdepth 3 -type d -name 'moodle' 2>/dev/null | head -n1)"
        if [[ -n "$FOUND_MOODLE" ]]; then
            BASE_DIR="$(dirname "$FOUND_MOODLE")"
            info "Found moodle directory at: $FOUND_MOODLE"
        else
            error "Could not find a 'moodle/' directory in or under: $BASE_DIR"
            exit 1
        fi
    fi
fi

info "Base directory : $BASE_DIR"
info "JSON file      : $JSON_FILE"
echo ""

# ── Counters ──────────────────────────────────────────────────────────
total=0; changed=0; skipped=0; errors=0

# ── Process each entry ────────────────────────────────────────────────
ENTRY_COUNT=$(jq '.customLabels | length' "$JSON_FILE")

for (( i=0; i<ENTRY_COUNT; i++ )); do
    rel_path=$(jq -r ".customLabels[$i].path"  "$JSON_FILE")
    line_no=$(jq -r  ".customLabels[$i].line"  "$JSON_FILE")
    from_str=$(jq -r ".customLabels[$i].from"  "$JSON_FILE")
    to_str=$(jq -r   ".customLabels[$i].to"    "$JSON_FILE")

    total=$((total + 1))
    file_path="${BASE_DIR}/${rel_path}"
    label="[$((i+1))/$ENTRY_COUNT] $rel_path"

    # 1. Skip if from == to (no change needed)
    if [[ "$from_str" == "$to_str" ]]; then
        warn "$label — from and to are identical, nothing to change."
        skipped=$((skipped + 1))
        continue
    fi

    # 2. Check file exists
    if [[ ! -f "$file_path" ]]; then
        error "$label — file not found: $file_path"
        errors=$((errors + 1))
        continue
    fi

    # 3. Try the specified line number first
    matched=false
    if [[ -n "$line_no" ]] && [[ "$line_no" =~ ^[0-9]+$ ]]; then
        line_content=$(sed -n "${line_no}p" "$file_path" 2>/dev/null || true)
        if echo "$line_content" | grep -qF "$from_str"; then
            # Replace on the exact line using python for safe literal replacement
            python3 -c "
import sys
path, lno, old, new = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
with open(path, 'r') as f:
    lines = f.readlines()
lines[lno-1] = lines[lno-1].replace(old, new, 1)
with open(path, 'w') as f:
    f.writelines(lines)
" "$file_path" "$line_no" "$from_str" "$to_str"
            success "$label — replaced on line $line_no"
            changed=$((changed + 1))
            matched=true
        fi
    fi

    # 4. Fallback: search entire file
    if [[ "$matched" == false ]]; then
        if grep -qF "$from_str" "$file_path"; then
            found_line=$(grep -nF "$from_str" "$file_path" | head -n1 | cut -d: -f1)
            python3 -c "
import sys
path, lno, old, new = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
with open(path, 'r') as f:
    lines = f.readlines()
lines[lno-1] = lines[lno-1].replace(old, new, 1)
with open(path, 'w') as f:
    f.writelines(lines)
" "$file_path" "$found_line" "$from_str" "$to_str"
            if [[ -n "$line_no" ]] && [[ "$line_no" =~ ^[0-9]+$ ]]; then
                success "$label — string not on line $line_no, found and replaced on line $found_line"
            else
                success "$label — found and replaced on line $found_line"
            fi
            changed=$((changed + 1))
        else
            warn "$label — string not found anywhere in file."
            skipped=$((skipped + 1))
        fi
    fi
done

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════"
info "Total entries : $total"
success "Changed       : $changed"
warn "Skipped       : $skipped"
error "Errors        : $errors"
echo "════════════════════════════════════════════"
