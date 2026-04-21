# alpargati-pi 🥧

Lightweight microservices orchestration for **Raspberry Pi 3B** using Docker Compose.

## 📋 Summary

This project deploys a set of personal productivity and security services on a Raspberry Pi 3B with Raspberry Pi OS Lite (64-bit):

| Service | Description | URL |
|---------|-------------|-----|
| **AdGuard Home** | DNS (Encrypted + LAN) | `http://adguard.pi.home` |
| **FreshRSS** | RSS Feed Aggregator | `http://rss.pi.home` or HTTPS via Tailscale |
| **Dozzle** | Real-time Docker logs | `http://logs.pi.home` |
| **Caddy** | Reverse proxy | - |
| **Tailscale** | Mesh VPN & Remote Access | - |
| **init-chown** | Volume permissions helper | - |

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

Fill in:
- `DOMAIN`: Your local domain (e.g., `pi.home`)
- `CADDY_AUTH_USER` / `CADDY_AUTH_PASSWORD`: Credentials for protected services access.
- `VOLUMES_PATH`: Path for persistent data.

### 3. Make scripts executable
```bash
chmod +x bootstrap.sh
```

### 4. Deploy
```bash
./bootstrap.sh
```

## 🌐 Local Network Configuration (DNS)

To access services by name (e.g., `rss.pi.home`), configure AdGuard Home as your network's DNS server.

### Automatic Setup (Recommended)

When you run `./bootstrap.sh` for the first time, the script automatically:
1. Detects your Raspberry Pi's IP address (eth0)
2. Creates an AdGuard Home configuration with:
   - DNS rewrites for `pi.home` and `*.pi.home`
   - Default filters (AdGuard DNS + AdAway) + Custom Filters from template
   - User credentials from `.env` variables

> [!NOTE]
> If `AdGuardHome.yaml` already exists, the template will NOT overwrite it. Delete the existing config to regenerate.

### Manual Setup (If Needed)

If you prefer manual setup or need to reconfigure:

1. Access `http://<YOUR-PI-IP>:3000`
2. Complete the initial setup wizard
3. In AdGuard Home → **Filters** → **DNS rewrites**, add:

| Domain | IP |
|---------|-----|
| `pi.home` | `<YOUR-PI-IP>` |
| `*.pi.home` | `<YOUR-PI-IP>` |

### Configure your Router
In your router's DHCP settings, set the **Pi IP address** as the primary DNS server.

> [!IMPORTANT]
> **IPv6 Interference**: Modern devices prioritize IPv6 DNS. Disable DHCPv6/RA on your router or set IPv6 to "Link-local only".

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

### 🌐 Accessing `pi.home` Remotely (Subnet Routing)
If you want to use your local domains (`*.pi.home`) from your mobile device via Tailscale:

1. **Update the configuration**:
   - The project uses `TS_ROUTES=192.168.0.0/24` in `docker-compose-network.yml` for the `tailscale` service.
2. **Deploy**: Run `./bootstrap.sh`. 
3. **Approve the route** in the [Tailscale Admin Console](https://login.tailscale.com/admin/machines):
   - Find `alpargati-pi` -> `...` (three dots) -> **Edit route settings**.
   - Enable the `192.168.0.0/24` checkbox.
3. **Configure DNS**:
   - In Tailscale **DNS** settings, set your Pi's Tailscale IP as a **Global Nameserver** and enable **Override local DNS**.

Now, when your phone asks for `adguard.pi.home`, AdGuard will return the local IP, and Tailscale will know how to route that traffic back to your house.

> [!TIP]
> **Standard Docker Advantage**: In Standard Docker mode, Tailscale and AdGuard Home use `network_mode: host`. This allows Tailscale to route traffic seamlessly and AdGuard to see the real IPs of every device in your home.

## 🎛️ Using the Bootstrap Script

```bash
# Start all services
./bootstrap.sh

# Stop all services
./bootstrap.sh --down

# Start without Dozzle
./bootstrap.sh --no-dozzle

# Start without Tailscale
./bootstrap.sh --no-tailscale

# View help
./bootstrap.sh --help
```

### Available Profiles
- `--no-dozzle`: Disables the log viewer
- `--no-tailscale`: Disables Tailscale service

## 📰 FreshRSS

FreshRSS is a self-hosted RSS feed aggregator. Access it at `http://rss.pi.home` (Local) or securely via Tailscale HTTPS.

### First-time Setup
The first time you access FreshRSS, a user will be automatically created using the credentials in your `.env` file:
- `FRESHRSS_USER`: Default username
- `FRESHRSS_PASSWORD`: Default password

Feeds are automatically refreshed every 30 minutes via cron.

## 🔐 Security

### Services protected by Caddy
- Dozzle (Basic Auth)

### Services with their own auth
- AdGuard Home, FreshRSS

## 📁 Project Structure

```
alpargati-pi/
├── .env.example                    # Configuration template
├── bootstrap.sh                    # Main script
├── docker-compose-core.yml         # init-chown
├── docker-compose-network.yml      # Caddy, Tailscale
├── docker-compose-services.yml     # AdGuard Home, FreshRSS
├── docker-compose-tools.yml        # Dozzle
├── configs/
│   ├── AdGuardHome.template.yaml    # AdGuard config template
│   └── Caddyfile                   # Caddy template
└── README.md
```

## 🔄 Migration from Rootless to Standard Docker

If you previously set up the project in Rootless mode and want to switch to Standard Docker (recommended for better networking/Tailscale):

### Step 1: Uninstall Rootless Docker
```bash
systemctl --user stop docker
dockerd-rootless-setuptool.sh uninstall
unset DOCKER_HOST
```

### Step 2: Install Standard Docker
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and log back in, or run:
newgrp docker
```

### Step 3: Enable Standard Docker Service
```bash
sudo systemctl enable --now docker
```

---

## 🔧 Troubleshooting

### Cannot access via domain name
1. Verify AdGuard Home is set as the DNS on your router.
2. Check DNS Rewrites in AdGuard Home.
3. Test: `nslookup rss.pi.home <YOUR-PI-IP>`.

### Local domain (pi.home) not resolving
If you can access services by IP but not by domain, ensure your devices are using the Pi as their DNS server.

**IPv6 Interference (Common issue):**
Modern OS (macOS, iOS, Android) prioritize IPv6 DNS. If your router announces an IPv6 DNS, your devices will ignore the Pi's IPv4 DNS.
- **Fix**: Disable IPv6 (DHCPv6/RA Service) in your router settings, or set your network interface to "IPv4 Only" / "Link-local only" for IPv6.

> [!IMPORTANT]
> **AdGuard Warning**: Do NOT create DNS rewrites in AdGuard for your `*.ts.net` domain. Let Tailscale's MagicDNS handle it to ensure the SSL certificate matches the tunnel IP and remains valid.

### AdGuard Home showing only one client (172.18.0.1)
In Standard Docker, AdGuard Home runs in `network_mode: host`, which allows it to see the real IPs of your devices.
-   **Fix**: Ensure you have successfully migrated to Standard Docker and that the container is running in host mode.

### Permission Denied (bootstrap.sh)
If `bootstrap.sh` fails with "Permission denied":
- **Fix**: Ensure you run the script with a user that has write permissions to the project directory.

## Technical Lessons: Tailscale HTTPS Integration

During this project, we implemented a robust way to get **real SSL certificates** on a local Raspberry Pi using Tailscale and Caddy.

### 1. The Socket Sharing Challenge
Caddy needs to talk to the `tailscaled.sock` to request certificates. Sharing this socket via Docker volumes is tricky because:
- Tailscale often creates a **symbolic link** (`/var/run/tailscale/tailscaled.sock -> /tmp/tailscaled.sock`).
- Symbolic links break across container boundaries if the target path is not mounted identically.
- **Solution**: Mount the host directory to **both** `/var/run/tailscale` and `/tmp` in the Tailscale container. This ensures the link always points to a valid file on the shared volume.

### 2. DNS Resolution (AdGuard vs. MagicDNS)
- **Problem**: Manually pointing Tailscale domains to local IPs in AdGuard breaks SSL validation and tunnel connectivity.
- **Solution**: Use Tailscale's **MagicDNS**. Caddy must resolve the `*.ts.net` domain to the Tailscale IP (`100.x.x.x`), not the LAN IP, for the certificate to be fetched and used correctly.

### 3. IPv6 and Access Control
- Tailscale often uses IPv6 for mobile devices.
- **Lesson**: Always include the Tailscale IPv6 range (`fd7a:115c:a1e0::/48`) in your Caddy `internal_only` filters, or you will get "Access Denied" errors on your phone.

### 4. Dozzle Memory Consumption not showing
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
