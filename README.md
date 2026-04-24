# 📸 Immich Server

> **Self-hosted Google Photos alternative with machine learning, automated backups, and secure remote access.**

[![Immich](https://img.shields.io/badge/Immich-Latest-blue?logo=docker)](https://immich.app)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-orange?logo=cloudflare)](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

<p align="center">
  <img src="https://immich.app/_app/immutable/assets/immich-logo-inline-dark.C4PioLn8.svg" width="150" alt="Immich Logo">
</p>

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🖼️ **Photo Management** | Upload, organize, and browse your photos with a beautiful UI |
| 🤖 **Machine Learning** | Facial recognition, object detection, and smart search |
| 🔒 **Secure Access** | HTTPS everywhere via Cloudflare Tunnel + Caddy |
| 💾 **Auto Backups** | Scheduled PostgreSQL backups to NAS (7 daily, 4 weekly, 6 monthly) |
| 🚀 **One-Command Setup** | Interactive installer handles all configuration |
| ☁️ **Cloud Backup** | Per-user backups to Proton Drive via rclone |

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  Cloudflare Tunnel                          │
└─────────────────────────┬───────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
     ┌─────────┐    ┌──────────┐    ┌──────────┐
     │  Caddy  │    │  Immich  │◄───│ Immich   │
     │  (TLS)  │───►│  Server  │    │    ML    │
     └─────────┘    └────┬─────┘    └──────────┘
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
   ┌──────────┐   ┌─────────────┐  ┌─────────────┐
   │ Postgres │   │ Local SSD   │  │  NAS/NFS    │
   └──────────┘   │ /srv/immich │  │ /mnt/photos │
                  │ (thumbnails,│  │ (originals, │
                  │  transcodes)│  │  backups)   │
                  └─────────────┘  └──────┬──────┘
                                          │
                                   ┌──────┴──────┐
                                   │  DB Backup  │
                                   └─────────────┘
```

### Storage Layout

| Data | Location | Why |
|------|----------|-----|
| **Originals** (library) | NAS `/mnt/photos/immich/library` | Large files, accessed less frequently |
| **DB Backups** | NAS `/mnt/photos/immich/backups` | Safe off-server backup |
| **Thumbnails** | Local SSD `/srv/immich/thumbs` | Fast access, regenerable |
| **Transcoded Videos** | Local SSD `/srv/immich/encoded-video` | Fast access, regenerable |
| **Upload Buffer** | Local SSD `/srv/immich/upload` | Fast writes during upload |
| **Profiles** | Local SSD `/srv/immich/profile` | Small files |

---

## 🚀 Quick Start

```bash
git clone https://github.com/rustygreen/immich-server
cd immich-server
./scripts/install.sh
```

If you see `Permission denied` when running a script, either make scripts executable:

```bash
chmod +x scripts/*.sh
```

or run them via bash:

```bash
bash ./scripts/install.sh
```

The interactive installer prompts for your:
- 📧 Email (for Let's Encrypt certificates)
- 🌐 Domain (e.g., `photos.example.com`)
- 🔑 Cloudflare API Token & Tunnel token
- 📂 Storage locations

**That's it!** The script handles everything else automatically.

---

## 📋 Prerequisites

Before running the installer, you'll need:

| Requirement | Details |
|-------------|---------|
| 🖥️ **Linux Server** | Ubuntu/Debian recommended |
| 🌐 **Domain** | Managed by Cloudflare |
| 🔑 **Cloudflare API Token** | [Create one →](#-cloudflare-api-token) |
| 🚇 **Cloudflare Tunnel** | [Create one →](#-cloudflare-tunnel) |

---

## ☁️ Cloudflare Setup

<details>
<summary><strong>🔑 Cloudflare API Token</strong></summary>

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Go to **My Profile** → **API Tokens** → **Create Token**
3. Use the **Edit zone DNS** template, or create a custom token with:
   - **Permissions:** `Zone > DNS > Edit`
   - **Zone Resources:** `Include > Specific zone > your-domain.com`
4. Copy the token — you'll need it during installation

</details>

<details>
<summary><strong>🚇 Cloudflare Tunnel</strong></summary>

1. In Cloudflare Dashboard, go to **Zero Trust** → **Networks** → **Tunnels**
2. Click **Create a tunnel** → Select **Cloudflared**
3. Name it (e.g., `immich-server`) and click **Save tunnel**
4. On the connector setup page, select **Docker** and copy the **token** from the command:
   ```
   docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJhIjoiYWJj...
   ```
   Copy just the token part (the long string after `--token`)
5. Configure the public hostname:
   - **Subdomain:** `photos`
   - **Domain:** your domain
   - **Service:** `http://immich:3001`
6. Save the tunnel

</details>

<details>
<summary><strong>📡 DNS Record (if not auto-created)</strong></summary>

1. Go to **DNS** → **Records** for your domain
2. Add a CNAME record:
   - **Name:** `photos`
   - **Target:** `<tunnel-id>.cfargotunnel.com`
   - **Proxy status:** Proxied (orange cloud)

</details>

---

## 💾 Storage Setup (Optional NFS)

<details>
<summary><strong>Configure NAS/NFS Mount</strong></summary>

If using a Synology NAS or other NFS share:

1. Enable NFS on your NAS and create a shared folder (e.g., `/volume1/photos`)
2. Set permissions to allow your server's IP with read/write access
3. On your Linux server, edit the filesystem table:
   ```bash
   sudo nano /etc/fstab
   ```
4. Add this line at the end (replace the IP and path with your NAS details):
   ```
   192.168.1.100:/volume1/photos  /mnt/photos  nfs  defaults,_netdev,nofail,soft,timeo=30,retrans=3,noatime  0  0
   ```
   > ⚠️ The `soft,timeo=30,retrans=3` options are important - they prevent system hangs if the NAS disconnects.
5. Save and exit (`Ctrl+X`, then `Y`, then `Enter`)
6. Mount the share:
   ```bash
   sudo mkdir -p /mnt/photos
   sudo mount -a
   ```

> 💡 **Using local storage only?** Set `UPLOAD_LOCATION=/srv/immich` to keep everything on local SSD.

</details>

---

## 🗄️ Storage Architecture

This setup uses **split storage** for optimal performance and reliability:

- **NAS (network)**: Original photos and backups — large files, accessed infrequently
- **Local SSD**: Thumbnails and transcodes — frequently accessed, regenerable if lost

This prevents NAS connectivity issues from breaking the UI, while keeping your originals safely on network storage.

**Local cache location:** `/srv/immich/` (created automatically by installer)

---

## ⚙️ Configuration

All configuration is done through the `.env` file. No need to modify any other files.

| Variable | Description |
|----------|-------------|
| `TZ` | Timezone (e.g., `America/New_York`) |
| `DB_PASSWORD` | PostgreSQL password (auto-generated) |
| `UPLOAD_LOCATION` | Where original photos are stored (NAS) |
| `BACKUP_LOCATION` | Where database backups go (NAS) |
| `ACME_EMAIL` | Email for Let's Encrypt certificates |
| `DOMAIN` | Your photos domain (e.g., `photos.example.com`) |
| `CF_API_TOKEN` | Cloudflare API token for DNS challenges |
| `TUNNEL_TOKEN` | Cloudflare Tunnel token |
| `ML_URL` | Machine Learning URL (leave unset for local ML) |
| `ML_PORT` | Port to expose ML service (default: `3003`) |
| `ML_MEMORY` | Memory limit for ML container (default: `4G`) |

<details>
<summary><strong>🖥️ Multi-Node Setup (Optional)</strong></summary>

You can offload the ML container to a second machine to reduce load on your main server.

**On Main Node (NUC 1):**

1. Edit `.env` and set ML_URL to point to your second node:
   ```bash
   ML_URL=http://192.168.1.101:3003
   ```

2. Start only the main services:
   ```bash
   docker compose --profile main up -d
   ```

**On ML Node (NUC 2):**

1. Clone the repo:
   ```bash
   git clone https://github.com/rustygreen/immich-server
   cd immich-server
   ```

2. Create a minimal `.env`:
   ```bash
   echo "ML_PORT=3003" > .env
   echo "ML_MEMORY=4G" >> .env
   ```

3. Start only the ML service:
   ```bash
   docker compose --profile ml up -d
   ```

**Architecture with 2 nodes:**
```
┌─────────────────────┐         ┌─────────────────────┐
│      NUC 1          │         │      NUC 2          │
│  ┌───────────────┐  │         │  ┌───────────────┐  │
│  │ Immich Server │──┼────────►│  │  Immich ML    │  │
│  │ Postgres      │  │  HTTP   │  │  (port 3003)  │  │
│  │ Redis         │  │         │  └───────────────┘  │
│  │ Caddy         │  │         └─────────────────────┘
│  │ Cloudflared   │  │
│  └───────────────┘  │
└─────────────────────┘
```

</details>

<details>
<summary><strong>Import Script Settings (Optional)</strong></summary>

If you want to use the bulk import script (`./scripts/import-photos.sh`), add these to your `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `IMMICH_API_KEY` | (required) | Your Immich API key |
| `IMPORT_DIR` | `/mnt/photos/upload` | Source folder for imports |
| `IMPORT_IMMICH_URL` | `http://immich:2283` | Immich server URL |
| `IMPORT_DELAY` | `30` | Seconds between folder imports |
| `IMPORT_DELETE_ON_SUCCESS` | `true` | Delete source after import |

Get your API key from Immich: **Account Settings → API Keys → New API Key**

</details>

<details>
<summary><strong>📁 Import Watch Folders (Multi-User)</strong></summary>

The **Import Watch** service monitors folders and automatically imports photos/videos to the correct user's Immich library.

**Setup:**

1. Get API keys for each user from Immich: **Account Settings → API Keys → New API Key**

2. Add users to your `.env` file:
   ```bash
   ./scripts/add-import-user.sh rusty "your-api-key-here"
   ./scripts/add-import-user.sh lauren "laurens-api-key"
   ```
   
   Or manually add to `.env`:
   ```bash
   IMPORT_USER_RUSTY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   IMPORT_USER_LAUREN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```

3. Build and start:
   ```bash
   docker compose up -d --build import_watch
   ```

4. Share the import folder on your network (optional):
   - The default location is `/srv/immich/import`
   - Share via Samba for Windows access

**Folder structure:**
```
/srv/immich/import/
├── rusty/      # Drop files here → imports to Rusty's library
├── lauren/     # Drop files here → imports to Lauren's library
├── miller/
├── hunter/
└── harper/
```

**Optional settings in `.env`:**
| Variable | Default | Description |
|----------|---------|-------------|
| `IMPORT_WATCH_DIR` | `/srv/immich/import` | Watch folder location |
| `IMPORT_SCAN_INTERVAL` | `30` | Seconds between scans |
| `IMPORT_DELETE_AFTER` | `true` | Delete files after import |

</details>

<details>
<summary><strong>☁️ Proton Drive Backup (Multi-User)</strong></summary>

Backup each user's photos to their own Proton Drive account automatically.

**Prerequisites:**

1. Install rclone:
   ```bash
   curl https://rclone.org/install.sh | sudo bash
   apt install jq  # For user ID lookup
   ```

2. Configure a Proton Drive remote for each user:
   ```bash
   rclone config
   # Name: proton_rusty  (lowercase, matches PROTON_USER_RUSTY)
   # Storage: protondrive
   # Follow prompts to authenticate with Rusty's Proton account
   
   # Repeat for each user:
   # proton_lauren, proton_miller, etc.
   ```

3. Get Immich user IDs:
   - Go to **Immich → Administration → Users**
   - Click on a user
   - Copy the UUID from the URL: `/admin/users/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

4. Add to your `.env`:
   ```bash
   # Proton emails (determines rclone remote name)
   PROTON_USER_RUSTY=rusty@proton.me
   PROTON_USER_LAUREN=lauren@protonmail.com
   
   # Immich user IDs (maps username to library folder)
   PROTON_IMMICH_ID_RUSTY=abc12345-6789-...
   PROTON_IMMICH_ID_LAUREN=def98765-4321-...
   ```

5. Test with a dry run:
   ```bash
   ./scripts/backup-to-proton.sh --dry-run
   ```

6. Schedule daily backups (add to crontab):
   ```bash
   crontab -e
   # Add this line:
   0 3 * * * /path/to/homelab/scripts/backup-to-proton.sh
   ```

**How it works:**
```
/srv/immich/library/
├── abc12345-.../     → proton_rusty:Photos/Immich/
├── def98765-.../     → proton_lauren:Photos/Immich/
└── ...
```

Each user's Immich library syncs to their personal Proton Drive with incremental updates.

**Optional settings in `.env`:**
| Variable | Default | Description |
|----------|---------|-------------|
| `IMMICH_LIBRARY` | `/srv/immich/library` | Immich library location |
| `PROTON_DEST_FOLDER` | `Photos/Immich` | Folder in Proton Drive |
| `PROTON_LOG_FILE` | `/var/log/proton-backup.log` | Log file location |

</details>

---

## 🛠️ Commands

| Command | Description |
|---------|-------------|
| `docker compose logs -f` | View live logs |
| `docker compose restart` | Restart all services |
| `./scripts/update.sh` | Pull latest images & restart |
| `./scripts/verify.sh` | Check stack health |
| `./scripts/import-photos.sh` | Bulk import photos (requires API key in .env) |
| `./scripts/backup-to-proton.sh` | Backup photos to Proton Drive |
| `./scripts/reset.sh` | Reset to fresh state |
| `docker compose down` | Stop everything |

---

## 🔧 Troubleshooting

<details>
<summary><strong>Tunnel not connecting</strong></summary>

Verify your `TUNNEL_TOKEN` in `.env` matches the token from Cloudflare Zero Trust → Tunnels.

</details>

<details>
<summary><strong>HTTPS certificate errors</strong></summary>

Verify your `CF_API_TOKEN` has DNS edit permissions for your zone.

</details>

<details>
<summary><strong>NFS mount fails or system hangs</strong></summary>

- Verify NAS IP and share path with `showmount -e <NAS_IP>`
- Check NAS permissions allow your server's IP
- Ensure `nfs-common` is installed: `sudo apt install nfs-common`
- Use `soft` mount option to prevent hangs: add `soft,timeo=30,retrans=3` to fstab

</details>

<details>
<summary><strong>Photos not appearing</strong></summary>

Verify `UPLOAD_LOCATION` exists and has correct permissions:
```bash
ls -la /mnt/photos
```

</details>

<details>
<summary><strong>Need to start over?</strong></summary>

```bash
./scripts/reset.sh
```

This removes all config and lets you re-run the installer fresh.

</details>

---

## 📄 License

MIT © [Rusty Green](https://github.com/rustygreen)
