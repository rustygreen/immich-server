#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "============================================"
echo "   Immich Homelab Interactive Setup"
echo "============================================"
echo ""

# Collect user information
read -p "📧 Enter your email (for Let's Encrypt): " USER_EMAIL
read -p "🌐 Enter your domain (e.g., photos.example.com): " USER_DOMAIN
read -p "🔐 Enter your Cloudflare API Token: " CF_API_TOKEN

echo ""
echo "🚇 Cloudflare Tunnel Token"
echo "   (Find this in Cloudflare Zero Trust → Tunnels → Your tunnel → Install connector)"
echo "   Copy the token from: docker run ... --token <YOUR_TOKEN>"
read -p "   Tunnel Token: " TUNNEL_TOKEN

echo ""
read -p "📂 Upload location [/mnt/photos/immich]: " UPLOAD_LOCATION
UPLOAD_LOCATION="${UPLOAD_LOCATION:-/mnt/photos/immich}"

read -p "� Backup location [/mnt/photos/backups]: " BACKUP_LOCATION
BACKUP_LOCATION="${BACKUP_LOCATION:-/mnt/photos/backups}"

read -p "�🕐 Timezone [America/New_York]: " TZ
TZ="${TZ:-America/New_York}"

# Generate a secure random password for the database
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)

echo ""
echo "============================================"
echo "   Configuring your installation..."
echo "============================================"

# Create .env file
cat > .env <<EOF
TZ=$TZ

DB_PASSWORD=$DB_PASSWORD
UPLOAD_LOCATION=$UPLOAD_LOCATION
BACKUP_LOCATION=$BACKUP_LOCATION

CF_API_TOKEN=$CF_API_TOKEN
TUNNEL_TOKEN=$TUNNEL_TOKEN
EOF
echo "✅ Created .env"

# Update Caddyfile with user's domain and email
sed -i "s/you@example.com/$USER_EMAIL/g" caddy/Caddyfile
sed -i "s/photos.example.com/$USER_DOMAIN/g" caddy/Caddyfile
echo "✅ Configured caddy/Caddyfile"

# Update verify script with user's domain
sed -i "s/photos.example.com/$USER_DOMAIN/g" scripts/verify.sh
echo "✅ Configured scripts/verify.sh"

echo ""
echo "============================================"
echo "   Installing system dependencies..."
echo "============================================"

sudo apt update
sudo apt install -y docker.io docker-compose-plugin nfs-common git ufw

echo "🐳 Enabling Docker..."
sudo systemctl enable docker --now
sudo usermod -aG docker $USER

echo "📁 Creating photo mount directory..."
sudo mkdir -p /mnt/photos
sudo chown 1000:1000 /mnt/photos

echo ""
echo "============================================"
echo "   Starting Immich stack..."
echo "============================================"

docker compose pull
docker compose up -d

echo ""
echo "============================================"
echo "   ✅ Installation Complete!"
echo "============================================"
echo ""
echo "🌐 Access Immich at: https://$USER_DOMAIN"
echo "🔑 Database password saved in .env (keep it safe!)"
echo ""
echo "📋 Next steps:"
echo "   1. If using NFS, configure /etc/fstab (see system/fstab.nfs.example)"
echo "   2. Run './scripts/verify.sh' to check your setup"
echo ""
