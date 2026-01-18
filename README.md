# Immich Homelab (with ML)

This repo deploys:
- Immich
- Immich Machine Learning
- Postgres
- Cloudflare Tunnel
- Caddy (DNS-01, valid HTTPS on LAN/WAN)

---

## Quick Start

```bash
git clone https://github.com/rustygreen/homelab
cd homelab
./scripts/install.sh
```

The interactive installer will prompt you for:
- Your email (for Let's Encrypt)
- Your domain (e.g., `photos.example.com`)
- Cloudflare API Token
- Cloudflare Tunnel credentials

That's it! The script handles all configuration automatically.

---

## Prerequisites

Before running the installer, you'll need:

1. **A Linux server** (Ubuntu/Debian recommended)
2. **A domain managed by Cloudflare**
3. **Cloudflare API Token** — see [Step 1.1](#11-create-a-cloudflare-api-token-for-caddy-dns-01-challenge)
4. **Cloudflare Tunnel** — see [Step 1.2](#12-create-a-cloudflare-tunnel)

---

## Cloudflare Setup

#### 1.1 Create a Cloudflare API Token (for Caddy DNS-01 challenge)

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Go to **My Profile** → **API Tokens** → **Create Token**
3. Use the **Edit zone DNS** template, or create a custom token with:
   - **Permissions:** `Zone > DNS > Edit`
   - **Zone Resources:** `Include > Specific zone > your-domain.com`
4. Copy the token and save it for your `.env` file as `CF_API_TOKEN`

#### 1.2 Create a Cloudflare Tunnel

1. In Cloudflare Dashboard, go to **Zero Trust** → **Networks** → **Tunnels**
2. Click **Create a tunnel**
3. Name it (e.g., `immich-homelab`) and click **Save tunnel**
4. On the connector setup page, select **Docker** and note the credentials
5. Copy the tunnel credentials JSON:
   ```json
   {
     "AccountTag": "your-account-id",
     "TunnelID": "your-tunnel-id",
     "TunnelSecret": "base64-secret"
   }
   ```
6. Configure the public hostname:
   - **Subdomain:** `photos`
   - **Domain:** `example.com` (your domain)
   - **Service:** `http://immich:3001`
7. Save the tunnel

#### 1.3 Add DNS Record (if not auto-created)

1. Go to **DNS** → **Records** for your domain
2. Add a CNAME record:
   - **Name:** `photos`
   - **Target:** `<tunnel-id>.cfargotunnel.com`
   - **Proxy status:** Proxied (orange cloud)

---

### Step 2: NAS/Storage Setup (Optional NFS)

If using a Synology NAS or other NFS share:

1. Enable NFS on your NAS and create a shared folder (e.g., `/volume1/photos`)
2. Set permissions to allow your server's IP with read/write access
3. Add the mount to `/etc/fstab` on your server:
   ```bash
   sudo nano /etc/fstab
   ```
   Add this line (adjust IP and path):
   ```
   192.168.1.100:/volume1/photos  /mnt/photos  nfs  defaults,_netdev,auto,noatime,nofail,retry=5  0  0
   ```
4. Mount the share:
   ```bash
   sudo mkdir -p /mnt/photos
   sudo mount -a
   ```

> **Local storage?** Skip NFS and set `UPLOAD_LOCATION=./uploads` in your `.env` file.

---

### Step 3: Run the Installer

```bash
git clone <this-repo>
cd immich-homelab
./scripts/install.sh
```

The interactive installer will:
- Prompt for your domain, email, and Cloudflare credentials
- Generate a secure database password automatically
- Configure all files with your settings
- Install Docker and dependencies
- Pull and start all containers

---

### Step 4: Access Immich

- **External (via Cloudflare Tunnel):** `https://photos.yourdomain.com`
- **Local (via Caddy):** Same URL (if DNS resolves locally)

On first visit, create your admin account and start uploading photos!

---

## Useful Commands

```bash
# View logs
docker compose logs -f

# Restart stack
docker compose restart

# Update containers
./scripts/update.sh

# Verify stack health
./scripts/verify.sh

# Stop everything
docker compose down
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Tunnel not connecting | Check `cloudflared/credentials.json` matches your Cloudflare tunnel |
| HTTPS certificate errors | Verify `CF_API_TOKEN` has DNS edit permissions |
| NFS mount fails | Check NAS IP, permissions, and `nfs-common` is installed |
| Photos not appearing | Verify `UPLOAD_LOCATION` path exists and has correct permissions |
| Database connection failed | Check `.env` file was created correctly |
| Need to reconfigure | Delete `.env` and `cloudflared/credentials.json`, then run `git checkout .` and re-run install |
