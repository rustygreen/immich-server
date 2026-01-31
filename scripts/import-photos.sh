#!/bin/bash

# Immich Photo Import Script
# Imports photos folder by folder to avoid overwhelming the system
# Supports zip files and Google Takeout exports

set -o pipefail  # Catch errors in pipelines

# Load .env file from parent directory (homelab root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' "$ENV_FILE" | grep -v '^\s*$' | xargs)
else
    echo "Warning: .env file not found at $ENV_FILE"
    echo "Using default values (set IMMICH_API_KEY in .env)"
fi

# ============== CONFIGURATION ==============
# All values can be overridden in .env file
IMPORT_DIR="${IMPORT_DIR:-/mnt/photos/temp}"
IMMICH_URL="${IMPORT_IMMICH_URL:-http://immich:2283}"
IMMICH_API_KEY="${IMMICH_API_KEY:-your_immich_api_key_here}"
DELAY_BETWEEN_FOLDERS="${IMPORT_DELAY:-30}"
DELETE_FOLDER_ON_SUCCESS="${IMPORT_DELETE_ON_SUCCESS:-true}"
DOCKER_NETWORK="${IMPORT_DOCKER_NETWORK:-homelab_default}"
EXTRACT_DIR="${IMPORT_EXTRACT_DIR:-${IMPORT_DIR}/extracted}"
CLEANUP_GOOGLE_TAKEOUT="${IMPORT_CLEANUP_GOOGLE_TAKEOUT:-true}"
LOCK_FILE="${IMPORT_LOCK_FILE:-/tmp/immich-import.lock}"
LOCK_TIMEOUT="${IMPORT_LOCK_TIMEOUT:-86400}"  # 24 hours max runtime before stale lock
LOG_FILE="${IMPORT_LOG_FILE:-}"  # Optional log file path
# ===========================================

# ============== LOGGING ====================
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$message"
    if [ -n "$LOG_FILE" ]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

log_error() {
    log "ERROR: $*" >&2
}
# ===========================================

# ============== LOCK MECHANISM ==============
# Prevent multiple instances from running simultaneously

cleanup_lock() {
    rm -f "$LOCK_FILE"
}

check_stale_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        local lock_age=0
        
        # Validate PID is a number
        if ! [[ "$lock_pid" =~ ^[0-9]+$ ]]; then
            log "Invalid lock file content. Removing..."
            cleanup_lock
            return 0
        fi
        
        # Check if the process is still running
        if kill -0 "$lock_pid" 2>/dev/null; then
            # Process exists, check lock age
            if [ -f "$LOCK_FILE" ]; then
                local lock_time
                lock_time=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || stat -f %m "$LOCK_FILE" 2>/dev/null)
                local current_time
                current_time=$(date +%s)
                if [ -n "$lock_time" ]; then
                    lock_age=$((current_time - lock_time))
                fi
            fi
            
            if [ "$lock_age" -gt "$LOCK_TIMEOUT" ]; then
                log "Warning: Stale lock detected (age: ${lock_age}s, PID: $lock_pid). Removing..."
                cleanup_lock
                return 0
            else
                return 1  # Valid lock exists
            fi
        else
            # Process no longer exists, remove stale lock
            log "Removing stale lock file (process $lock_pid no longer exists)"
            cleanup_lock
            return 0
        fi
    fi
    return 0  # No lock file
}

acquire_lock() {
    # Create lock directory if it doesn't exist
    local lock_dir
    lock_dir=$(dirname "$LOCK_FILE")
    mkdir -p "$lock_dir" 2>/dev/null
    
    if ! check_stale_lock; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        log "Another import is already running (PID: $lock_pid). Exiting."
        exit 0
    fi
    
    # Create lock file with current PID
    echo $$ > "$LOCK_FILE"
    
    # Verify we got the lock (handle race condition)
    sleep 0.2
    local stored_pid
    stored_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ "$stored_pid" != "$$" ]; then
        log "Failed to acquire lock (race condition). Exiting."
        exit 0
    fi
    
    # Set trap to clean up lock on exit
    trap cleanup_lock EXIT INT TERM HUP
    log "Lock acquired (PID: $$)"
}

# Acquire lock before proceeding
acquire_lock
# ============================================

# ============== VALIDATION ==================
validate_environment() {
    local errors=0
    
    # Check if import directory exists
    if [ ! -d "$IMPORT_DIR" ]; then
        log_error "Import directory does not exist: $IMPORT_DIR"
        errors=$((errors + 1))
    fi
    
    # Check if API key is set
    if [ "$IMMICH_API_KEY" = "your_immich_api_key_here" ] || [ -z "$IMMICH_API_KEY" ]; then
        log_error "IMMICH_API_KEY is not configured"
        errors=$((errors + 1))
    fi
    
    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        errors=$((errors + 1))
    fi
    
    # Check if unzip is available (for zip support)
    if ! command -v unzip &> /dev/null; then
        log "Warning: 'unzip' is not installed. ZIP file extraction will be skipped."
    fi
    
    if [ $errors -gt 0 ]; then
        log_error "Validation failed with $errors error(s). Exiting."
        exit 1
    fi
}

validate_environment
# ============================================

# Function to check if a directory is a Google Takeout export
is_google_takeout() {
    local dir="$1"
    
    # Safety check
    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        return 1
    fi
    
    # Google Takeout typically has "Takeout" folder or .json metadata files
    if [ -d "$dir/Takeout" ] || [ -d "$dir/Google Photos" ]; then
        return 0
    fi
    
    # Check for .json metadata files alongside photos (Google Takeout pattern)
    # Google Takeout JSON files have specific naming patterns like "IMG_1234.jpg.json"
    if find "$dir" -maxdepth 3 -type f -name "*.json" 2>/dev/null | head -1 | grep -q .; then
        if find "$dir" -maxdepth 3 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.mp4" \) 2>/dev/null | head -1 | grep -q .; then
            return 0
        fi
    fi
    return 1
}

# Function to clean up Google Takeout metadata and organize files
cleanup_google_takeout() {
    local dir="$1"
    
    # Safety check
    if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        log_error "Invalid directory for Google Takeout cleanup: $dir"
        return 1
    fi
    
    log "  Cleaning up Google Takeout export..."
    
    # Find the actual photos directory (could be nested)
    local photos_dir="$dir"
    if [ -d "$dir/Takeout/Google Photos" ]; then
        photos_dir="$dir/Takeout/Google Photos"
    elif [ -d "$dir/Takeout" ]; then
        photos_dir="$dir/Takeout"
    elif [ -d "$dir/Google Photos" ]; then
        photos_dir="$dir/Google Photos"
    fi
    
    # Remove JSON metadata files (Immich doesn't need them and handles EXIF directly)
    log "  Removing Google Takeout JSON metadata files..."
    local json_count
    json_count=$(find "$photos_dir" -name "*.json" -type f 2>/dev/null | wc -l)
    find "$photos_dir" -name "*.json" -type f -delete 2>/dev/null
    log "  Removed $json_count JSON metadata files"
    
    # Remove archive browser files that Google includes
    find "$dir" -name "archive_browser.html" -type f -delete 2>/dev/null
    
    # Remove print order files
    find "$dir" -name "print-subscriptions.json" -type f -delete 2>/dev/null
    find "$dir" -name "shared_album_comments.json" -type f -delete 2>/dev/null
    find "$dir" -name "user-generated-memory-titles.json" -type f -delete 2>/dev/null
    
    # Move all media files to a flat structure if deeply nested
    # This helps with the import process
    local temp_media_dir="$dir/_media_files_$$"
    mkdir -p "$temp_media_dir"
    
    # Move all media files to temp directory (handle spaces in filenames)
    find "$photos_dir" -type f \( \
        -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \
        -o -iname "*.heic" -o -iname "*.heif" -o -iname "*.webp" -o -iname "*.bmp" \
        -o -iname "*.tiff" -o -iname "*.tif" -o -iname "*.raw" -o -iname "*.cr2" \
        -o -iname "*.nef" -o -iname "*.arw" -o -iname "*.dng" \
        -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" \
        -o -iname "*.3gp" -o -iname "*.m4v" -o -iname "*.webm" -o -iname "*.mts" \
        -o -iname "*.m2ts" -o -iname "*.mpg" -o -iname "*.mpeg" \
    \) -print0 2>/dev/null | while IFS= read -r -d '' file; do
        local basename
        basename=$(basename "$file")
        local target="$temp_media_dir/$basename"
        
        # Handle duplicate filenames by adding a counter
        if [ -e "$target" ]; then
            local counter=1
            local name="${basename%.*}"
            local ext="${basename##*.}"
            while [ -e "$temp_media_dir/${name}_${counter}.${ext}" ]; do
                counter=$((counter + 1))
            done
            target="$temp_media_dir/${name}_${counter}.${ext}"
        fi
        mv "$file" "$target" 2>/dev/null
    done
    
    # Clean up old directory structure (be careful not to delete the main dir)
    if [ "$photos_dir" != "$dir" ] && [ -d "$photos_dir" ]; then
        rm -rf "$photos_dir" 2>/dev/null
    fi
    
    # Also remove the Takeout directory if it exists and is now empty or just contains empty dirs
    if [ -d "$dir/Takeout" ]; then
        find "$dir/Takeout" -type d -empty -delete 2>/dev/null
        rmdir "$dir/Takeout" 2>/dev/null
    fi
    
    # Move media files back to main directory
    if [ -d "$temp_media_dir" ]; then
        local file_count
        file_count=$(find "$temp_media_dir" -type f 2>/dev/null | wc -l)
        if [ "$file_count" -gt 0 ]; then
            mv "$temp_media_dir"/* "$dir/" 2>/dev/null
        fi
        rm -rf "$temp_media_dir" 2>/dev/null
    fi
    
    # Remove any remaining empty directories
    find "$dir" -mindepth 1 -type d -empty -delete 2>/dev/null
    
    local final_count
    final_count=$(find "$dir" -type f 2>/dev/null | wc -l)
    log "  Google Takeout cleanup complete. $final_count files ready for import."
}

# Function to extract zip files
extract_zip_files() {
    # Check if unzip is available
    if ! command -v unzip &> /dev/null; then
        log "Skipping ZIP extraction (unzip not installed)"
        return 0
    fi
    
    # Find zip files safely (handle spaces in filenames)
    local zip_files=()
    while IFS= read -r -d '' file; do
        zip_files+=("$file")
    done < <(find "$IMPORT_DIR" -maxdepth 1 -name "*.zip" -type f -print0 2>/dev/null | sort -z)
    
    local zip_count=${#zip_files[@]}
    
    if [ "$zip_count" -eq 0 ]; then
        return 0
    fi
    
    log "========================================"
    log "Extracting ZIP Files"
    log "========================================"
    log "Found $zip_count zip file(s) to extract"
    log ""
    
    mkdir -p "$EXTRACT_DIR"
    
    for zip_file in "${zip_files[@]}"; do
        local zip_name
        zip_name=$(basename "$zip_file" .zip)
        local extract_path="$EXTRACT_DIR/$zip_name"
        
        # Skip if zip file is still being written (check if file is growing)
        local size1 size2
        size1=$(stat -c %s "$zip_file" 2>/dev/null || stat -f %z "$zip_file" 2>/dev/null)
        sleep 2
        size2=$(stat -c %s "$zip_file" 2>/dev/null || stat -f %z "$zip_file" 2>/dev/null)
        
        if [ "$size1" != "$size2" ]; then
            log "Skipping $zip_name.zip (file still being written)"
            continue
        fi
        
        # Check if zip file is valid
        if ! unzip -t -q "$zip_file" &>/dev/null; then
            log_error "Invalid or corrupted zip file: $zip_name.zip (skipping)"
            continue
        fi
        
        log "Extracting: $zip_name.zip ($(numfmt --to=iec-i --suffix=B "$size2" 2>/dev/null || echo "${size2} bytes"))"
        
        # Create extraction directory
        mkdir -p "$extract_path"
        
        # Extract the zip file with progress indication for large files
        if unzip -q -o "$zip_file" -d "$extract_path" 2>&1; then
            log "✓ Extracted: $zip_name"
            
            # Check if it's a Google Takeout export and clean it up
            if [ "$CLEANUP_GOOGLE_TAKEOUT" = "true" ] && is_google_takeout "$extract_path"; then
                log "  Detected Google Takeout export"
                cleanup_google_takeout "$extract_path"
            fi
            
            # Delete the original zip file after successful extraction
            if [ "$DELETE_FOLDER_ON_SUCCESS" = "true" ]; then
                log "  Deleting zip file: $zip_file"
                rm -f "$zip_file"
            fi
        else
            log_error "Failed to extract: $zip_name.zip"
            # Clean up partial extraction
            rm -rf "$extract_path" 2>/dev/null
        fi
        log ""
    done
    
    log "ZIP extraction complete!"
    log ""
}

# Extract any zip files first
extract_zip_files

# Function to check if folder contains media files
folder_has_media() {
    local folder="$1"
    find "$folder" -maxdepth 1 -type f \( \
        -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \
        -o -iname "*.heic" -o -iname "*.heif" -o -iname "*.webp" -o -iname "*.bmp" \
        -o -iname "*.tiff" -o -iname "*.tif" -o -iname "*.raw" -o -iname "*.cr2" \
        -o -iname "*.nef" -o -iname "*.arw" -o -iname "*.dng" \
        -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" \
        -o -iname "*.3gp" -o -iname "*.m4v" -o -iname "*.webm" -o -iname "*.mts" \
        -o -iname "*.m2ts" -o -iname "*.mpg" -o -iname "*.mpeg" \
    \) 2>/dev/null | head -1 | grep -q .
}

# Count total folders (including newly extracted ones)
# Use process substitution to handle spaces in paths
FOLDERS=()
while IFS= read -r -d '' folder; do
    FOLDERS+=("$folder")
done < <(find "$IMPORT_DIR" -maxdepth 2 -mindepth 1 -type d ! -empty -print0 2>/dev/null | sort -z)

# Filter to only include folders with actual media files
MEDIA_FOLDERS=()
for folder in "${FOLDERS[@]}"; do
    if folder_has_media "$folder"; then
        MEDIA_FOLDERS+=("$folder")
    fi
done
FOLDERS=("${MEDIA_FOLDERS[@]}")
TOTAL=${#FOLDERS[@]}
CURRENT=0

# Exit early if nothing to import
if [ "$TOTAL" -eq 0 ]; then
    log "No folders with media files found. Nothing to import."
    exit 0
fi

log "========================================"
log "Immich Photo Import"
log "========================================"
log "Found $TOTAL folders to import"
log "Delay between folders: ${DELAY_BETWEEN_FOLDERS}s"
log "Delete folders on success: $DELETE_FOLDER_ON_SUCCESS"
log "Docker network: $DOCKER_NETWORK"
log ""

for FOLDER in "${FOLDERS[@]}"; do
    CURRENT=$((CURRENT + 1))
    FOLDER_NAME=$(basename "$FOLDER")
    
    log "----------------------------------------"
    log "[$CURRENT/$TOTAL] Importing: $FOLDER_NAME"
    log "----------------------------------------"
    
    # Count files in folder for progress info
    file_count=$(find "$FOLDER" -type f 2>/dev/null | wc -l)
    log "  Files to import: $file_count"
    
    # Run docker upload
    upload_output=$(docker run --rm --network "$DOCKER_NETWORK" \
        -v "$FOLDER:/import:ro" \
        -e IMMICH_INSTANCE_URL="$IMMICH_URL" \
        -e IMMICH_API_KEY="$IMMICH_API_KEY" \
        ghcr.io/immich-app/immich-cli:latest \
        upload --recursive /import 2>&1)
    upload_exit_code=$?
    
    if [ $upload_exit_code -eq 0 ]; then
        log "✓ Completed: $FOLDER_NAME"
        
        # Log upload summary if available (extract numbers from output)
        uploaded_count=$(echo "$upload_output" | grep -E '[0-9]+ uploaded' | sed 's/.*\([0-9]\+\) uploaded.*/\1/' 2>/dev/null || echo "")
        skipped_count=$(echo "$upload_output" | grep -E '[0-9]+ skipped' | sed 's/.*\([0-9]\+\) skipped.*/\1/' 2>/dev/null || echo "")
        if [ -n "$uploaded_count" ] || [ -n "$skipped_count" ]; then
            log "  Summary: ${uploaded_count:-0} uploaded, ${skipped_count:-0} skipped (duplicates)"
        fi
        
        if [ "$DELETE_FOLDER_ON_SUCCESS" = "true" ]; then
            log "  Deleting folder: $FOLDER"
            rm -rf "$FOLDER"
        fi
    else
        log_error "Failed: $FOLDER_NAME (exit code: $upload_exit_code)"
        log_error "  Output: $upload_output"
        log "  Folder preserved for retry"
    fi
    
    # Delay before next folder (skip on last one)
    if [ "$CURRENT" -lt "$TOTAL" ]; then
        log "  Waiting ${DELAY_BETWEEN_FOLDERS}s before next folder..."
        sleep "$DELAY_BETWEEN_FOLDERS"
    fi
    
    log ""
done

# Clean up empty extracted directory
if [ -d "$EXTRACT_DIR" ]; then
    find "$EXTRACT_DIR" -type d -empty -delete 2>/dev/null
    rmdir "$EXTRACT_DIR" 2>/dev/null
fi

log "========================================"
log "Import complete! Processed $TOTAL folders."
log "========================================"
