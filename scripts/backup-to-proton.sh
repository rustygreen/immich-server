#!/bin/bash
# backup-to-proton.sh - Backup Immich photos to Proton Drive per user
#
# This script syncs each user's photos to their own Proton Drive account.
# Similar to import-watch, users are configured via environment variables:
#
#   PROTON_USER_RUSTY=rusty@proton.me
#   PROTON_USER_LAUREN=lauren@proton.me
#
# Each user needs an rclone remote configured with their name (lowercase):
#   rclone config  ->  name: proton_rusty, proton_lauren, etc.
#
# The script maps Immich user IDs to usernames via the Immich API.
#
# Usage: ./backup-to-proton.sh [--dry-run]

set -euo pipefail

# Configuration
IMMICH_LIBRARY="${IMMICH_LIBRARY:-/srv/immich/library}"
IMMICH_URL="${IMMICH_URL:-http://localhost:2283}"
IMMICH_API_KEY="${IMMICH_API_KEY:-}"  # Admin API key for user lookup
LOG_FILE="${PROTON_LOG_FILE:-/var/log/proton-backup.log}"
PROTON_DEST_FOLDER="${PROTON_DEST_FOLDER:-Photos/Immich}"
DRY_RUN=""

# Parse arguments
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
    echo "DRY RUN MODE - No files will be transferred"
fi

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Get configured users from environment (PROTON_USER_*)
get_proton_users() {
    env | grep "^PROTON_USER_" | while IFS='=' read -r key value; do
        username=$(echo "$key" | sed 's/^PROTON_USER_//' | tr '[:upper:]' '[:lower:]')
        echo "$username:$value"
    done
}

# Get Immich user ID by email using API
get_immich_user_id() {
    local email="$1"
    
    if [[ -z "$IMMICH_API_KEY" ]]; then
        log "ERROR: IMMICH_API_KEY not set - cannot lookup user IDs"
        return 1
    fi
    
    # Call Immich API to search users
    local response
    response=$(curl -s -H "x-api-key: $IMMICH_API_KEY" \
        "${IMMICH_URL}/api/admin/users")
    
    # Extract user ID by email (requires jq)
    echo "$response" | jq -r --arg email "$email" \
        '.[] | select(.email == $email) | .id'
}

# Alternative: Map usernames to Immich user IDs directly via env vars
# PROTON_IMMICH_ID_RUSTY=abc123-def456-...
get_immich_user_id_from_env() {
    local username="$1"
    local var_name="PROTON_IMMICH_ID_${username^^}"
    echo "${!var_name:-}"
}

# Sync a single user's library to Proton Drive
sync_user() {
    local username="$1"
    local proton_email="$2"
    local immich_user_id="$3"
    
    local rclone_remote="proton_${username}"
    local source_path="${IMMICH_LIBRARY}/${immich_user_id}"
    local dest_path="${rclone_remote}:${PROTON_DEST_FOLDER}"
    
    # Check if rclone remote exists
    if ! rclone listremotes | grep -q "^${rclone_remote}:$"; then
        log "WARNING: rclone remote '${rclone_remote}' not configured for ${username}"
        log "  Run: rclone config -> name: ${rclone_remote}, type: protondrive"
        return 1
    fi
    
    # Check if source directory exists
    if [[ ! -d "$source_path" ]]; then
        log "WARNING: No library found for ${username} at ${source_path}"
        return 1
    fi
    
    # Count files to sync
    local file_count
    file_count=$(find "$source_path" -type f | wc -l)
    local size
    size=$(du -sh "$source_path" 2>/dev/null | cut -f1)
    
    log "Syncing ${username}: ${file_count} files (${size}) -> ${dest_path}"
    
    # Perform sync
    rclone sync "$source_path" "$dest_path" \
        $DRY_RUN \
        --progress \
        --transfers 4 \
        --checkers 8 \
        --log-file "$LOG_FILE" \
        --log-level INFO \
        --stats 30s \
        --stats-one-line
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log "SUCCESS: ${username} sync complete"
    else
        log "ERROR: ${username} sync failed with exit code ${exit_code}"
    fi
    
    return $exit_code
}

# Main
main() {
    log "=========================================="
    log "Starting Proton Drive backup"
    log "Library: ${IMMICH_LIBRARY}"
    log "=========================================="
    
    # Check dependencies
    if ! command -v rclone &> /dev/null; then
        log "ERROR: rclone not installed. Run: curl https://rclone.org/install.sh | sudo bash"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log "WARNING: jq not installed - user ID lookup via API won't work"
        log "  Install with: apt install jq"
        log "  Or set PROTON_IMMICH_ID_<USER> variables manually"
    fi
    
    # Get users
    local users
    users=$(get_proton_users)
    
    if [[ -z "$users" ]]; then
        log "ERROR: No users configured!"
        log "Add environment variables like:"
        log "  PROTON_USER_RUSTY=rusty@proton.me"
        log "  PROTON_IMMICH_ID_RUSTY=<immich-user-uuid>"
        exit 1
    fi
    
    local success=0
    local failed=0
    
    # Process each user
    while IFS=':' read -r username proton_email; do
        log "Processing user: ${username} (${proton_email})"
        
        # Get Immich user ID
        local immich_id
        immich_id=$(get_immich_user_id_from_env "$username")
        
        if [[ -z "$immich_id" ]] && [[ -n "$IMMICH_API_KEY" ]]; then
            immich_id=$(get_immich_user_id "$proton_email")
        fi
        
        if [[ -z "$immich_id" ]]; then
            log "ERROR: Cannot determine Immich user ID for ${username}"
            log "  Set PROTON_IMMICH_ID_${username^^}=<uuid> or provide IMMICH_API_KEY"
            ((failed++))
            continue
        fi
        
        log "  Immich user ID: ${immich_id}"
        
        if sync_user "$username" "$proton_email" "$immich_id"; then
            ((success++))
        else
            ((failed++))
        fi
        
    done <<< "$users"
    
    log "=========================================="
    log "Backup complete: ${success} succeeded, ${failed} failed"
    log "=========================================="
    
    [[ $failed -eq 0 ]]
}

main "$@"
