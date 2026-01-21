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

echo "DNS:"
nslookup "$DOMAIN"

echo "Containers:"
docker ps

echo "Mount:"
df -h | grep "${MOUNT_PATH%/*}"
