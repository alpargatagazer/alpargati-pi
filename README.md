# alpargati-pi 🥧

Lightweight microservices orchestration for **Raspberry Pi 3B** using Docker Compose.

## 📋 Summary

This project deploys a set of personal productivity and security services on a Raspberry Pi 3B with Raspberry Pi OS Lite (64-bit):

| Service | Description | Access |
|----------|-------------|--------|
| **Homepage** | Customizable dashboard | `http://pi.home` |
| **Vaultwarden** | Password manager (Bitwarden compatible) | `http://vault.pi.home` |
| **AdGuard Home** | DNS with ad blocking + local DNS | `http://adguard.pi.home` |
| **FileBrowser** | Web file manager | `http://files.pi.home` |
| **Dozzle** | Real-time Docker log viewer | `http://logs.pi.home` |
| **WUD** | Container update manager | `http://wud.pi.home` |
| **Caddy** | Reverse proxy (manages subdomains) | - |

## 🚀 Prerequisites

### Hardware
- Raspberry Pi 3B (1GB RAM) with Raspberry Pi OS Lite 64-bit
- microSD card (at least 16GB, 32GB recommended)
- Stable network connection (ethernet preferred)

### Software
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
dockerd-rootless-setuptool.sh install

# Restart session or run
newgrp docker
```

### Swap Configuration (Recommended)
The Pi 3B only has 1GB of RAM. Add swap for better stability:

```bash
# Edit swap configuration
sudo nano /etc/dphys-swapfile

# Change CONF_SWAPSIZE=100 to:
CONF_SWAPSIZE=2048

# Restart service
sudo systemctl restart dphys-swapfile
```

### Free Port 53 (Required for AdGuard)
Raspberry Pi OS might have `systemd-resolved` occupying the DNS port:

```bash
# Check if it's in use
sudo ss -lptn 'sport = :53'

# If occupied by systemd-resolved, disable it:
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved

# Configure manual DNS
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### Rootless Docker and Privileged Ports (Port 53)
If you are using **Rootless Docker**, you cannot bind to ports below 1024 by default. This will cause AdGuard Home to fail when binding to port 53.

To fix this, allow unprivileged users to bind to lower ports:

```bash
# Allow binding to port 53 and above
echo "net.ipv4.ip_unprivileged_port_start=53" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

## 📦 Installation

### 1. Clone repository
```bash
cd /opt
sudo git clone https://github.com/your-username/alpargati-pi.git
sudo chown -R $USER:$USER alpargati-pi
cd alpargati-pi
```

### 2. Configure Environment Variables
```bash
cp .env.example .env
nano .env
```

Fill in at least:
- `DOMAIN`: Your local domain (e.g., `pi.home`)
- `CADDY_AUTH_USER` / `CADDY_AUTH_PASSWORD`: Credentials to protect services
- `VOLUMES_PATH`: Path for persistent data. If using `/opt/alpargati-pi/volumes`, make sure the user has permissions.

> [!TIP]
> If you get a "Permission denied" error when running the script, you may need to create the volumes directory manually:
> `sudo mkdir -p /opt/alpargati-pi && sudo chown -R $USER:$USER /opt/alpargati-pi`
>
> Alternatively, if you are using **rootless Docker**, it is highly recommended to use a path within your home directory (e.g., `VOLUMES_PATH=~/alpargati-pi/volumes`) to avoid permission issues.

### 3. Make scripts executable
```bash
chmod +x bootstrap.sh
chmod +x configs/entrypoints/*.sh
```

### 4. Deploy
```bash
./bootstrap.sh
```

## 🌐 Local Network Configuration (DNS)

To access services by name (e.g., `vault.pi.home`), you need to configure AdGuard Home as your network's DNS server.

### Step 1: AdGuard Home Initial Setup
1. Access `http://<YOUR-PI-IP>:3000`
2. Complete the initial setup wizard. Set listening interface to "3000".
3. Set a username and password for the dashboard

### Step 2: Configure DNS Rewrites
In AdGuard Home → **Filters** → **DNS rewrites**:

| Domain | IP |
|---------|-----|
| `pi.home` | `<YOUR-PI-IP>` |
| `*.pi.home` | `<YOUR-PI-IP>` |

### Step 3: Configure your Router
In your router's DHCP settings, set the **Pi IP address** as the primary DNS server.

> [!IMPORTANT]
> **AdGuard Home Setup Wizard**: During the initial setup, AdGuard Home might show internal IPs (like `172.x.x.x` or `127.0.0.1`). **Ignore them.** Since we are using Docker port mapping, the correct IP to use for your devices and router is the **physical IP of your Raspberry Pi** (e.g., `192.168.1.X`).

> [!NOTE]
> After this, all devices on your network will resolve `*.pi.home` to the Pi, and Caddy will route them to the correct service.

## 🎛️ Using the Bootstrap Script

```bash
# Start all services
./bootstrap.sh

# Stop all services
./bootstrap.sh --down

# Start without WUD
./bootstrap.sh --no-wud

# Start without Dozzle or FileBrowser
./bootstrap.sh --no-dozzle --no-filebrowser

# View help
./bootstrap.sh --help
```

### Available Profiles
- `--no-wud`: Disables the update manager
- `--no-dozzle`: Disables the log viewer
- `--no-filebrowser`: Disables the file manager

## 🔐 Security

### Dual-Layer Authentication
Sensitive services are protected by:
1. **Caddy Basic Auth**: First layer at the proxy (`CADDY_AUTH_USER`/`CADDY_AUTH_PASSWORD`)
2. **Service Auth**: Each application's own second layer

### Services protected by Caddy
- Vaultwarden
- AdGuard Home
- FileBrowser
- Dozzle

### Services with their own auth only
- WUD (uses its own auth system)

## 📁 Project Structure

```
alpargati-pi/
├── .env.example                    # Configuration template
├── bootstrap.sh                    # Main script
├── docker-compose-core.yml         # Homepage, init-chown
├── docker-compose-network.yml      # Caddy
├── docker-compose-services.yml     # Vaultwarden, AdGuard Home
├── docker-compose-tools.yml        # FileBrowser, Dozzle, WUD
├── configs/
│   ├── Caddyfile                   # Caddy template
│   └── entrypoints/
│       ├── caddy.sh
│       ├── filebrowser.sh
│       └── wud.sh
└── README.md
```

## 🔧 Troubleshooting

### Containers not starting
```bash
# View logs for all services
docker compose -p alpargati-pi logs -f

# View logs for a specific service
docker compose -p alpargati-pi logs -f vaultwarden
```

### AdGuard cannot use port 53
```bash
# Check what process is using the port
sudo lsof -i :53

# If it's systemd-resolved, see "Free Port 53" section above
```

### Pi is running slowly
```bash
# Check memory usage
free -h

# Check active swap
swapon --show

# If swap is full, consider disabling optional services
./bootstrap.sh --no-dozzle --no-filebrowser
```

### Cannot access via domain name
1. Verify AdGuard Home is set as the DNS on your router
2. Check DNS Rewrites in AdGuard Home
3. Test: `nslookup vault.pi.home <YOUR-PI-IP>`

## 📝 Future Services

These services are planned but not included by default (some may require more resources):

- **Stirling-PDF**: PDF tools
- **Tailscale**: Mesh VPN for remote access
- **SilverBullet**: Lightweight Markdown Wiki/Notes (ideal for Pi)
- **Memos**: Fast microblogging-style notes

> ⚠️ **Note**: Services like AFFiNE or Anytype are not viable on a Pi 3B due to >2GB RAM requirements and incompatible MongoDB versions.

## 📄 License

MIT License - See [LICENSE](LICENSE)
