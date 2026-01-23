#!/bin/bash

# Immich Photo Import Script
# Imports photos folder by folder to avoid overwhelming the system

# Load .env file from parent directory (homelab root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
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
# ===========================================

# Count total folders
FOLDERS=($(find "$IMPORT_DIR" -maxdepth 1 -mindepth 1 -type d | sort))
TOTAL=${#FOLDERS[@]}
CURRENT=0

echo "========================================"
echo "Immich Photo Import"
echo "========================================"
echo "Found $TOTAL folders to import"
echo "Delay between folders: ${DELAY_BETWEEN_FOLDERS}s"
echo "Delete folders on success: $DELETE_FOLDER_ON_SUCCESS"
echo "Docker network: $DOCKER_NETWORK"
echo ""

for FOLDER in "${FOLDERS[@]}"; do
    CURRENT=$((CURRENT + 1))
    FOLDER_NAME=$(basename "$FOLDER")
    
    echo "----------------------------------------"
    echo "[$CURRENT/$TOTAL] Importing: $FOLDER_NAME"
    echo "----------------------------------------"
    
    docker run --rm --network "$DOCKER_NETWORK" \
        -v "$FOLDER:/import:ro" \
        -e IMMICH_INSTANCE_URL="$IMMICH_URL" \
        -e IMMICH_API_KEY="$IMMICH_API_KEY" \
        ghcr.io/immich-app/immich-cli:latest \
        upload --recursive /import
    
    if [ $? -eq 0 ]; then
        echo "✓ Completed: $FOLDER_NAME"
        
        if [ "$DELETE_FOLDER_ON_SUCCESS" = true ]; then
            echo "  Deleting folder: $FOLDER"
            rm -rf "$FOLDER"
        fi
    else
        echo "✗ Failed: $FOLDER_NAME (folder preserved)"
    fi
    
    # Delay before next folder (skip on last one)
    if [ $CURRENT -lt $TOTAL ]; then
        echo "  Waiting ${DELAY_BETWEEN_FOLDERS}s before next folder..."
        sleep $DELAY_BETWEEN_FOLDERS
    fi
    
    echo ""
done

echo "========================================"
echo "Import complete! Processed $TOTAL folders."
echo "========================================"
