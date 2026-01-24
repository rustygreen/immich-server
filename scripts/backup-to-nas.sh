#!/usr/bin/env bash
set -e

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

# Sync library (original photos) - this is the important one
log "Syncing library..."
rsync -av --delete --progress "$LOCAL_DATA/library/" "$BACKUP_DEST/library/" 2>&1 | tee -a "$LOG_FILE"

# Sync database backups
log "Syncing database backups..."
rsync -av --delete --progress "$LOCAL_DATA/backups/" "$BACKUP_DEST/backups/" 2>&1 | tee -a "$LOG_FILE"

# Optional: sync thumbnails (can be regenerated, but saves time)
# log "Syncing thumbnails..."
# rsync -av --delete --progress "$LOCAL_DATA/thumbs/" "$BACKUP_DEST/thumbs/" 2>&1 | tee -a "$LOG_FILE"

log "Backup completed successfully!"
