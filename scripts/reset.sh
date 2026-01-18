#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "⚠️  This will:"
echo "   - Stop and remove all containers"
echo "   - Delete Docker volumes (including database)"
echo "   - Remove .env and cloudflared/credentials.json"
echo "   - Reset config files to placeholders"
echo ""
echo "   Photos on NFS (/mnt/photos) will NOT be deleted."
echo ""
read -p "Are you sure? (y/N): " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "🛑 Stopping containers..."
docker compose down -v 2>/dev/null || true

echo "🗑️  Removing generated files..."
rm -f .env

echo "♻️  Resetting config files to placeholders..."
git checkout -- caddy/Caddyfile scripts/verify.sh 2>/dev/null || true

echo ""
echo "✅ Reset complete! Run './scripts/install.sh' to start fresh."
