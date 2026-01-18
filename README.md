# 📸 Immich Homelab

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
                         ▼
          ┌──────────────┴──────────────┐
          ▼                             ▼
    ┌──────────┐                 ┌─────────────┐
    │ Postgres │◄────────────────│  DB Backup  │
    └──────────┘                 └──────┬──────┘
                                        │
                                        ▼
                                 ┌─────────────┐
                                 │  NAS/NFS    │
                                 │  Storage    │
                                 └─────────────┘
```

---

## 🚀 Quick Start

```bash
git clone https://github.com/rustygreen/homelab
cd homelab
./scripts/install.sh
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
3. Name it (e.g., `immich-homelab`) and click **Save tunnel**
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
3. Add to `/etc/fstab`:
   ```
   192.168.1.100:/volume1/photos  /mnt/photos  nfs  defaults,_netdev,auto,noatime,nofail,retry=5  0  0
   ```
4. Mount:
   ```bash
   sudo mkdir -p /mnt/photos
   sudo mount -a
   ```

> 💡 **Using local storage?** Just set `UPLOAD_LOCATION=./uploads` during installation.

</details>

---

## 🛠️ Commands

| Command | Description |
|---------|-------------|
| `docker compose logs -f` | View live logs |
| `docker compose restart` | Restart all services |
| `./scripts/update.sh` | Pull latest images & restart |
| `./scripts/verify.sh` | Check stack health |
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
<summary><strong>NFS mount fails</strong></summary>

- Verify NAS IP and share path
- Check NAS permissions allow your server's IP
- Ensure `nfs-common` is installed: `sudo apt install nfs-common`

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
