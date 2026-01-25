#!/usr/bin/env bash
set -euo pipefail

# Backup Immich data from local SSD to NAS
# Run this via cron: 0 3 * * * /home/rusty/homelab/scripts/backup-to-nas.sh

NAS_MOUNT="/mnt/photos"
LOCAL_DATA="/srv/immich"
BACKUP_DEST="$NAS_MOUNT/immich-backup"
LOG_FILE="/var/log/immich-backup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if NAS is mounted
if ! mountpoint -q "$NAS_MOUNT"; then
    log "ERROR: NAS not mounted at $NAS_MOUNT. Attempting to mount..."
    sudo mount -a
    sleep 5
    if ! mountpoint -q "$NAS_MOUNT"; then
        log "ERROR: Failed to mount NAS. Backup aborted."
        exit 1
    fi
fi

log "Starting backup to NAS..."

# Create backup directory on NAS if it doesn't exist
mkdir -p "$BACKUP_DEST"

# Rsync options:
#   --no-group --no-perms: Don't try to set permissions (NFS doesn't allow)
#   --times: Preserve modification times
#   --delete: Remove files from dest that don't exist in source
#   --timeout=300: 5 minute timeout for stalled transfers
RSYNC_OPTS="-av --no-group --no-perms --times --delete --timeout=300"

# Sync library (original photos) - this is the important one
log "Syncing library..."
if ! rsync $RSYNC_OPTS "$LOCAL_DATA/library/" "$BACKUP_DEST/library/" 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Library sync failed!"
    exit 1
fi

# Sync database backups
log "Syncing database backups..."
if ! rsync $RSYNC_OPTS "$LOCAL_DATA/backups/" "$BACKUP_DEST/backups/" 2>&1 | tee -a "$LOG_FILE"; then
    log "ERROR: Database backup sync failed!"
    exit 1
fi

# Optional: sync thumbnails (can be regenerated, but saves time)
# log "Syncing thumbnails..."
# rsync $RSYNC_OPTS "$LOCAL_DATA/thumbs/" "$BACKUP_DEST/thumbs/" 2>&1 | tee -a "$LOG_FILE"

log "Backup completed successfully!"
