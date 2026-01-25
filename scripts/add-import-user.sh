#!/usr/bin/env bash
# Add or update a user's API key for the import watcher

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <username> <api_key>"
    echo ""
    echo "Example: $0 rusty xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    echo ""
    echo "Get API keys from Immich: Account Settings → API Keys → New API Key"
    exit 1
fi

USERNAME=$(echo "$1" | tr '[:lower:]' '[:upper:]')
API_KEY="$2"
VAR_NAME="IMPORT_USER_${USERNAME}"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found: $ENV_FILE"
    echo "Run ./scripts/install.sh first or copy .env.example to .env"
    exit 1
fi

# Check if user already exists
if grep -q "^${VAR_NAME}=" "$ENV_FILE"; then
    # Update existing user
    sed -i "s|^${VAR_NAME}=.*|${VAR_NAME}=${API_KEY}|" "$ENV_FILE"
    echo "✅ Updated API key for user: $1"
else
    # Add new user
    echo "" >> "$ENV_FILE"
    echo "${VAR_NAME}=${API_KEY}" >> "$ENV_FILE"
    echo "✅ Added new user: $1"
fi

echo ""
echo "Restart the import watcher to apply changes:"
echo "  cd ~/homelab && docker compose restart import_watch"
