# Deployment Guide — rusano-lab

This document outlines the requirements and step-by-step procedures to deploy the `rusano-lab` infrastructure using Podman Rootless Quadlets.

---

## 1. Prerequisites & Host Configuration

### 1.1 Podman & System Requirements

- **Podman Version**: Your system must run **Podman 6.0.0** (or later) to support native `pasta` port forwarding and `pesto` source IP preservation.

  ```bash
  podman --version
  ```

- **User Namespaces**: Your user must have valid subuid and subgid ranges mapped (configured by default on Fedora). You can inspect yours with:

  ```bash
  grep $(whoami) /etc/subuid /etc/subgid
  ```

  If empty, configure them using:

  ```bash
  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $(whoami)
  podman system migrate
  ```

### 1.2 Host Sysctl Configuration

Rootless Podman containers binding to host ports below `1024` (such as port `53` for DNS and `80`/`443` for Traefik proxy) will fail with a `Permission denied` error unless host port restrictions are relaxed.

1. **Lower the unprivileged port binding threshold** to allow binding to port 53 and above, and **allow binding to non-local IPs** (needed for dedicated zone loopbacks in the IP Matrix):

   ```bash
   sudo sysctl -w net.ipv4.ip_unprivileged_port_start=53
   sudo sysctl -w net.ipv4.ip_nonlocal_bind=1
   sudo sysctl -w net.ipv6.ip_nonlocal_bind=1
   ```

2. **Make these settings persistent** across system reboots by writing them to sysctl configuration files:

   ```bash
   echo "net.ipv4.ip_unprivileged_port_start=53" | sudo tee /etc/sysctl.d/50-rootless-ports.conf
   echo "net.ipv4.ip_nonlocal_bind=1" | sudo tee /etc/sysctl.d/50-nonlocal-bind.conf
   echo "net.ipv6.ip_nonlocal_bind=1" | sudo tee /etc/sysctl.d/50-nonlocal-bind-ipv6.conf
   sudo sysctl --system
   ```

### 1.3 Pasta Networking Configuration

Define `pasta` as the default port forwarder for rootless containers by creating or editing `~/.config/containers/containers.conf.d/00-pasta.conf`:

```ini
[network]
rootless_port_forwarder = "pasta"
```

### 1.4 Systemd User Lingering

By default, the systemd user manager terminates user services when you log out. To ensure services start automatically at host boot and persist in the background:

```bash
sudo loginctl enable-linger $(whoami)
```

### 1.5 Host Firewall Configuration (firewalld)

If you are running on a host with `firewalld` enabled, allow incoming traffic on public ports (`80`, `443`, and `53` for DNS):

```bash
# Allow Traefik web ports
sudo firewall-cmd --add-service=http --add-service=https --permanent
# Allow Technitium DNS Proxy ports
sudo firewall-cmd --add-port=53/tcp --add-port=53/udp --permanent
# Reload firewall to apply changes
sudo firewall-cmd --reload
```

### 1.6 Host DNS Resolver Integration (systemd-resolved & NetworkManager)

By default, `systemd-resolved` resolves queries by sending them to active interface-specific DNS servers (assigned dynamically via DHCP) in parallel with or in preference to the Global DNS setting. To route host-level DNS resolutions exclusively through the `dnsproxy` container (`127.10.10.12`):

1. **Configure NetworkManager to ignore DHCP-assigned DNS**. You can apply this change persistently to your current active connection, or globally for all networks:

   - **Option A: Connection-Specific (Persistent for a single network profile)**:
     Use this for specific network interfaces (e.g. your primary Wi-Fi or Ethernet network profile). NetworkManager stores this setting persistently in `/etc/NetworkManager/system-connections/`:

     ```bash
     # List active connections to find the Name or UUID of your active interface
     nmcli connection show --active

     # Tell NetworkManager to ignore auto DNS on the connection (replace "YourConnectionName")
     sudo nmcli connection modify "YourConnectionName" ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes

     # Re-activate the connection to apply the changes
     sudo nmcli connection up "YourConnectionName"
     ```

   - **Option B: Global Overrides (Persistent for ALL current and future connections)**:
     Use this for dedicated cloud servers or static environments where you never want DHCP-assigned DNS to register in systemd-resolved:
     Create a global config drop-in file at `/etc/NetworkManager/conf.d/99-ignore-dhcp-dns.conf`:

     ```ini
     [connection]
     ipv4.ignore-auto-dns=yes
     ipv6.ignore-auto-dns=yes
     ```

2. **Configure `systemd-resolved`** to use the local dnsproxy IP as the global DNS server. Open `/etc/systemd/resolved.conf` in an editor:

   ```ini
   [Resolve]
   DNS=127.10.10.12
   Domains=~.
   ```

   *Note: The `Domains=~.` directive tells systemd-resolved to use this server as the default router for all query domains.*

3. **Restart the services** to apply the configuration:

   ```bash
   sudo systemctl restart NetworkManager
   sudo systemctl restart systemd-resolved
   ```

4. **Verify the active resolver configuration**:

   ```bash
   resolvectl status
   # The Global Current DNS Server should be 127.10.10.12.
   # Active link interfaces (like wlp61s0 or enp0s31f6) should no longer list any active DHCP DNS servers.
   ```

---

## 2. Secrets Management

All security credentials and environment tokens must be stored in Podman's native secret storage. Running containers will consume them directly as environment variables (`Secret=secret-name,type=env`).

Execute the following commands to create the required secrets on the host:

```bash
# 1. Cloudflare DNS API Token for Traefik ACME challenge
podman secret create traefik-secrets - <<EOF
CF_DNS_API_TOKEN=your_cloudflare_dns_api_token
EOF

# 2. Cloudflare Tunnel Token for cloudflared
podman secret create cloudflared-secrets - <<EOF
TUNNEL_TOKEN=your_cloudflare_tunnel_token
EOF

# 3. PostgreSQL Database secrets for Authentik
podman secret create authentik-postgres-secrets - <<EOF
POSTGRES_DB=authentik
POSTGRES_USER=authentik
POSTGRES_PASSWORD=your_secure_db_password
EOF

# 4. Authentik Application secrets
# Note: generate a strong secret key: openssl rand -base64 36
podman secret create authentik-app-secrets - <<EOF
AUTHENTIK_SECRET_KEY=your_authentik_secret_key
AUTHENTIK_POSTGRESQL__PASSWORD=your_secure_db_password
EOF

# 5. Open WebUI secrets
# Note: generate a strong secret key: openssl rand -base64 36
podman secret create openwebui-secrets - <<EOF
WEBUI_SECRET_KEY=your_open_webui_secret_key
EOF

# 6. SearXNG Secrets
# Note: generate a strong secret key: openssl rand -base64 32
podman secret create searxng-secrets - <<EOF
SEARXNG_SECRET=your_searxng_secret_key
EOF
```

### 2.2 Server-Specific Bindings (Environment Files)

For services like Traefik and the Technitium DNS Server, public or host-routed IP addresses for port bindings are required at the host/systemd service level. To prevent committing these IP addresses to the git repository:

The installation script `install.sh` automatically copies the environment templates (`traefik.env.example` and `technitium.env.example`) to your server under the Quadlet configuration directory (`~/.config/containers/systemd/`) with secure permissions (`0600`) if they do not exist:

- `~/.config/containers/systemd/traefik.env`
- `~/.config/containers/systemd/technitium.env`

After running `./install.sh`, edit these files directly on your server to define the correct IP addresses:

```bash
# Example configuration for ~/.config/containers/systemd/traefik.env:
TRAEFIK_BIND_IPV4=10.0.0.100

# Example configuration for ~/.config/containers/systemd/technitium.env:
TECHNITIUM_BIND_IPV4=10.0.100.100
TECHNITIUM_BIND_IPV6=fd7a:115c:a1e0::c338:1e06
```

---

## 3. Deployment Helper Scripts

We provide interactive scripts to install, update, and remove the Quadlet services automatically. These scripts will create the configuration directories under `~/config/`, copy initial configuration templates, and symlink the Quadlet files to `~/.config/containers/systemd/`.

### Installation

Run the interactive installation script from the root of the repository:

```bash
./install.sh
```

This script allows you to choose exactly which services to install via a text menu, copies configuration templates, reloads systemd, and prompts you to enable and start the selected services.

### Updating Services

To sync any configuration changes from the repository and trigger a systemd daemon-reload (and optional service restarts), run:

```bash
./update.sh
```

### Removing Services

To cleanly stop running services, delete all symlinks in your systemd folder, reload the systemd daemon, and optionally purge the custom configuration directories under `~/config/`, run:

```bash
./remove.sh
```

---

## 4. Operations & Logs

### Checking Services Status

Use the standard systemd commands inside user space:

```bash
# List all running user-level services
systemctl --user list-units --type=service

# View status of a specific pod or container service
systemctl --user status traefik.pod
systemctl --user status searxng.service
```

### Reviewing Logs

All logs are routed directly into the systemd journal database.

```bash
# Follow logs for Traefik
journalctl --user -u traefik.pod -f

# Read the last 50 log lines for Authentik
journalctl --user -u authentik-server.service -n 50 --no-pager
```

---

## 5. Stack Bootstrapping & Initial Configuration

### Traefik Domain Adaption

Before starting, update the domain rules in [dynamic-conf.yml](file:///home/rusano/Projects/Code/rusano/rusano-lab/app/network/traefik/config/dynamic-conf.yml) and [traefik-static.yml](file:///home/rusano/Projects/Code/rusano/rusano-lab/app/network/traefik/config/traefik-static.yml) by replacing `example.com` with your own domain name registered on Cloudflare.

### DNS Setup (Private Resolvers)

1. Log into your Cloudflare dashboard and create a DNS A/AAAA record pointing to your cloud host IP.
2. In the Tunnel settings, set `dns.yourdomain.com` to point to `https://10.0.0.100:443` (Traefik).
3. Configure your host's local DNS resolver (e.g. `systemd-resolved`) to route queries through the DNS Proxy (`127.10.10.12`) on port `53`. The proxy will cache and forward queries to the Technitium DNS Server at `127.10.10.10`.
4. **Generate and Install an SSL/TLS Certificate** for the Web Console and the DNS Server (DoT/DoH):
   - Run the interactive certificate generation utility from the repository root:
     ```bash
     ./lab.sh cert
     ```
   - Follow the prompts to enter your Let's Encrypt email address, your Technitium DNS domain (e.g., `dns.yourdomain.com`), your Cloudflare DNS API Token, and a secure password for the PFX bundle.
   - The script will run ephemeral ACME and conversion containers to issue the certificate, bundle it into a PKCS#12 `.pfx` file, copy it directly to `/etc/dns/certs/dns.pfx` in the Technitium configuration volume, and cleanly remove all temporary containers and downloaded images.
   - Log into the Technitium Web Console (by default at `http://127.100.100.100:5380`).
   - Navigate to **Settings** > **Web Service**.
   - Set **TLS Certificate File Path** to `/etc/dns/certs/dns.pfx`.
   - Enter your chosen password in the **TLS Certificate Password** field and save the settings. Technitium will immediately read and apply the certificate without requiring a service restart.

### Authentik Setup

1. Navigate to `https://auth.yourdomain.com/if/flow/initial-setup/` to set the admin password.
2. Configure applications and outposts as needed.

### AI Client Tools

- **Open WebUI**: Navigate to `https://ai.yourdomain.com` and register your first account (the first registered account automatically becomes the administrator).
- **SillyTavern**: Navigate to `https://tavern.yourdomain.com` to customize your user settings. Access is pre-proxied and secured by Traefik/Authentik middleware filters.
