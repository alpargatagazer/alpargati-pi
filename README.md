# alpargati-pi 🥧

Lightweight microservices orchestration for **Raspberry Pi 3B** using Docker Compose.

## 📋 Summary

This project deploys a set of personal productivity and security services on a Raspberry Pi 3B with Raspberry Pi OS Lite (64-bit):

| **Homepage** | Customizable dashboard | `http://pi.home` |
| **Vaultwarden** | Password manager (HTTPS) | `https://vault.pi.home` |
| **AdGuard Home** | DNS (Encrypted + LAN) | `http://adguard.pi.home` |
| **SilverBullet** | Markdown Knowledge Base | `http://notes.pi.home` |
| **Memos** | Lightweight Note-taking | `http://memos.pi.home` |
| **Tailscale** | Mesh VPN & Remote Access | - |
| **FileBrowser** | Web file manager | `http://files.pi.home` |
| **Dozzle** | Real-time Docker logs | `http://logs.pi.home` |
| **WUD** | Container update manager | `http://wud.pi.home` |
| **Caddy** | Reverse proxy | - |

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

# Enable persistence (lingering) for Rootless Docker
# Important: This ensures containers start automatically on boot
sudo loginctl enable-linger $USER
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

## 🛡️ Tailscale Configuration (Remote Access)

Tailscale allows you to access your services securely from anywhere without opening ports on your router.

1. **Get an Auth Key**:
   - Log in to your [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).
   - Go to **Settings** → **Keys**.
   - Generate a new **Auth Key**. (Recommended: "Ephemeral" and "Reusable" for this setup).
2. **Configure `.env`**:
   - Add the key to your `.env` file: `TS_AUTHKEY=tskey-auth-xxxxxx`
   - Add your Tailscale domain: `TS_DOMAIN=alpargati-pi.yourname.ts.net`
3. **Deploy**:
   - Run `./bootstrap.sh`. The Pi will show up in your Tailscale machine list as `alpargati-pi`.
4. **Access**:
   - You can now access your Pi using its Tailscale IP or MagicDNS name from any device connected to your Tailnet.
   - Example: `https://adguard.your-tailnet-name.ts.net`

> [!IMPORTANT]
> **HTTPS on Tailscale**: Caddy is configured with `tls internal` to provide HTTPS on `.ts.net` domains. Your browser will warn about a self-signed certificate unless you trust the Caddy Root CA or enable Tailscale's native HTTPS feature.

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
│   ├── entrypoints/
│   │   ├── caddy.sh
│   │   ├── filebrowser.sh
│   │   └── wud.sh
│   └── homepage/                   # Homepage dashboard config
│       ├── services.yaml
│       ├── settings.yaml
│       ├── widgets.yaml
│       └── bookmarks.yaml
└── README.md
```

## 🔧 Troubleshooting

### Cannot access via domain name
1. Verify AdGuard Home is set as the DNS on your router
2. Check DNS Rewrites in AdGuard Home
3. Test: `nslookup vault.pi.home <YOUR-PI-IP>`

### Local domain (pi.home) not resolving
If you can access services by IP but not by domain, ensure your devices are using the Pi as their DNS server.

**IPv6 Interference (Common issue):**
Modern OS (macOS, iOS, Android) prioritize IPv6 DNS. If your router announces an IPv6 DNS, your devices will ignore the Pi's IPv4 DNS.
- **Fix**: Disable IPv6 (DHCPv6/RA Service) in your router settings, or set your network interface to "IPv4 Only" / "Link-local only" for IPv6.
- **ZTE H3600 (Hyperoptic)**: Go to *Local Network* -> *LAN* -> *IPv6* and set *DHCPv6 Server* and *RA Service* to **Off**.

### AdGuard Home showing only one client (172.18.0.1)
In Rootless Docker, all inbound traffic goes through a proxy (RootlessKit/slirp4netns), which masks individual device IPs.
- **Limitation**: Due to the way Rootless Docker handles networking namespaces, traditional "host mode" connectivity is restricted. For stability on the Pi 3B, AdGuard runs in Bridge mode, and transactions will appear as coming from the Docker gateway.

### AdGuard Home Advanced Ports
The following ports are exposed for encrypted DNS:
- **853 (TCP/UDP)**: DNS-over-TLS (DoT) and DNS-over-QUIC (DoQ).
- **5443 (TCP/UDP)**: DNSCrypt.
- **784/8853 (UDP)**: Additional DoQ ports.

### Dozzle Memory Consumption not showing
On ARM devices, edit `/boot/firmware/cmdline.txt` and add:
`cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1`
Then reboot.

## 📝 Future Services

These services are planned or viable but not included by default:

- **Stirling-PDF**: Comprehensive PDF manipulation tools.
- **Navidrome**: Personal music streaming server (Subsonic compatible).

> ⚠️ **Note**: High-resource applications (like AFFiNE, Anytype, or Bitwarden Official) are NOT viable on a Pi 3B due to RAM and database constraints.

## 📄 License

MIT License - See [LICENSE](LICENSE)
