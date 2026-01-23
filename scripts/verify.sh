#!/usr/bin/env bash

# Load .env file from parent directory (homelab root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# Use env vars with defaults
DOMAIN="${DOMAIN:-photos.example.com}"
MOUNT_PATH="${UPLOAD_LOCATION:-/mnt/photos}"
LOCAL_CACHE="/srv/immich"

echo "DNS:"
nslookup "$DOMAIN"

echo ""
echo "Containers:"
docker ps

echo ""
echo "NAS Mount:"
df -h | grep "${MOUNT_PATH%/*}" || echo "⚠️  NAS not mounted at ${MOUNT_PATH%/*}"

echo ""
echo "Local SSD Cache:"
if [ -d "$LOCAL_CACHE" ]; then
    du -sh $LOCAL_CACHE/*/ 2>/dev/null || echo "  (empty)"
else
    echo "⚠️  Local cache directory not found: $LOCAL_CACHE"
fi
