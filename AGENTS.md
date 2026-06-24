# AGENTS.md — rusano-cloudlab

**Podman 6.0 · Rootless Quadlet · Source-IP-Preserving · No-Daemon · GitOps Cloudlab**

> **Version:**  1.0.0\
> **Status:**  Active\
> **Last Updated:**  2026-06-21\
> **Arch:**  `x86_64` · `Fedora 41` · Podman `6.0.0-rc1`\
> **Root:**  Unprivileged user `$(whoami)` — no root daemon, no Docker socket, no `sudo podman`

---

## 0. Core Tenets (Hard Rules — Do NOT Violate)

These are ranked by priority. If two conflict, the higher one wins.

### 0.1 Security (Priority 1)

```properties
; Every container in this lab — no exceptions
NoNewPrivileges=true
DropCapability=ALL
ReadOnly=true
PrivateTmp=true
ProtectSystem=full
UMask=0077
```

### 0.2 Source-IP Preservation (Priority 2)

**All** published ports MUST preserve the original client IP. The `rootlessport` userspace TCP proxy is **forbidden** — it strips all source IPs to `127.0.0.1`.

#### The mechanism

```properties
# In ~/.config/containers/containers.conf.d/00-pasta.conf
[network]
rootless_port_forwarder = "pasta"     # ← Podman 6.0 only
# pkw 2026-06-21: PR #28478 merged, enables pesto user-space forwarder
```

This activates **pesto** — a companion to `passt` that handles port forwarding at the **kernel level** via `splice` (loopback) or `TAP` (external), preserving the original source IP.

**What it replaces:**

| Old (Podman ≤5.x)                                                | New (Podman 6.0 + pasta)                                                  |
| :--------------------------------------------------------------- | :------------------------------------------------------------------------ |
| `rootlessport` — userspace TCP proxy → mangles IP to `127.0.0.1` | `rootless_port_forwarder="pasta"` → pesto/passt — **preserves source IP** |
| Requires `--network bridge` → broken logs                        | Works with **any** `--network` type                                       |
| `podman-compose` → all IPs mangled                               | `Quadlet` + custom networks → **IPs intact**                              |

**When NOT to use:**  Same port, different HostIPs (e.g., `-p 127.0.0.1:8080:80` AND `-p 127.0.0.2:8080:80` on separate containers). This creates conflicting DNAT rules in pasta mode — still a known limit.

**Workaround:**  Use different host ports for different services, or bind the same port to different IPs via `127.0.<service>.x` loopback addresses.

### 0.3 No `0.0.0.0` or `127.0.0.1` for Published Ports (Priority 3)

Every service gets a **dedicated IP** from the IP matrix. This prevents:

- Port conflicts on the host
- `rootlessport` mangling
- Accidental exposure to all interfaces

### 0.4 Traefik is the ONLY Reverse Proxy (Priority 4)

- **File provider only** — `--providers.file=true`
- **No Docker socket** — `--providers.docker=false`
- **No Podman socket** — `--providers.podman=false`
- **Why:**  Rootless Podman has no accessible docker socket. Traefik's Docker provider is broken in rootless mode. File provider is the only reliable path.

### 0.5 No Monolithic Databases (Priority 5)

Each service or pod gets its own:

- **PostgreSQL** instance
- **Valkey/Redis** instance
- **No shared databases** — zero cross-service data coupling

### 0.6 Everything Rootless (Priority 6)

```bash
# Verify: You should NEVER need to run this
sudo podman run ...
sudo systemctl start ...
sudo podman ...
```

If a container needs root — it doesn't. Redesign.

### 0.7 No Hardcoded Secrets (Priority 7)

```properties
# WRONG — never
Environment=POSTGRES_PASSWORD=hunter2

# RIGHT
EnvironmentFile=%h/.config/containers/systemd/secrets.env
```

Podman 6.0 also supports **native Quadlet secrets**:

```properties
[Container]
Secret=postgres-password,type=env  # ← Passed as environment variable
```

### 0.8 AutoUpdate=registry (Priority 8)

```properties
[Container]
AutoUpdate=registry  # ← Every single container
```

And the timer:

```bash
systemctl --user enable --now podman-auto-update.timer
```

### 0.9 Drop Capability = ALL (Priority 9)

```properties
[Container]
DropCapability=ALL
# Add back ONLY what the image explicitly needs
# e.g., net_admin for ping, dac_override for ... no, never dac_override
```

### 0.10 ReadOnly=true (Priority 10)

```properties
[Container]
ReadOnly=true
# Write locations:
Tmpfs=/tmp /run /var/tmp
# Persistent writes via named volumes
Volume=postgres-data:/var/lib/postgresql/data:Z
```

---

## 1. Repository Layout

```plain
rusano-cloudlab/
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD: sync → quadlet-install → reload
├── .githooks/
│   └── pre-push                 # Validate quadlet files before push
├── services/
│   ├── _shared/                  # Shared resources (namespaces, networks, secrets)
│   │   ├── traefik.network       # Shared network definition
│   │   ├── secrets.env           # Centralized secrets (git-crypted)
│   │   └── Makefile              # NO — use `podman quadlet install` instead
│   ├── authentication/
│   │   ├── authelia/
│   │   │   ├── authelia.pod
│   │   │   ├── authelia.container
│   │   │   ├── authelia.volume
│   │   │   └── authelia.env.example
│   │   └── lldap/
│   │       ├── lldap.pod
│   │       ├── lldap.container
│   │       └── lldap.volume
│   ├── dns/
│   │   └── technitium/
│   │       ├── technitium.pod
│   │       ├── technitium.container
│   │       ├── technitium-proxy.container
│   │       └── technitium.volume
│   ├── proxy/
│   │   ├── traefik/
│   │   │   ├── traefik.pod
│   │   │   ├── traefik.container
│   │   │   ├── traefik.volume
│   │   │   ├── config/
│   │   │   │   ├── traefik-static.yml
│   │   │   │   └── dynamic-conf.yml
│   │   │   └── certs/              # SHA256-labelled certs, mounted as secret
│   │   └── cloudflared/
│   │       ├── cloudflared.pod     # Standalone — not in traefik's pod
│   │       └── cloudflared.container
│   ├── search/
│   │   └── searxng/
│   │       ├── searxng.pod
│   │       ├── searxng.container
│   │       ├── searxng.volume
│   │       └── valkey.container
│   ├── monitoring/
│   │   └── ...
│   └── system/                    # Bootstrap services (not yet)
│       └── seed/
│           ├── seed.pod
│           └── seed.container
└── README.md
```

### 1.1 File Naming

| Pattern              | Kind                   | Example                 |
| :------------------- | :--------------------- | :---------------------- |
| `*.pod`              | Pod definition (group) | `traefik.pod`           |
| `*.<role>.container` | Container in a pod     | `traefik.container`     |
| `*.container`        | Standalone container   | `cloudflared.container` |
| `*.volume`           | Named volume           | `postgres.volume`       |
| `*.network`          | Network definition     | `traefik.network`       |
| `*.env.example`      | Environment template   | `authelia.env.example`  |
| `*.yml`              | Configuration files    | `traefik-static.yml`    |
| `*.yaml`             | Configuration files    | `dynamic-conf.yaml`     |

### 1.2 File Conventions (All Files)

```properties
; Header (every file)
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-cloudlab
# Version: 1.0.0
# Podman: 6.0.0-rc1
# Updated: 2026-06-21

[Unit]
Description=<role> — <service> — <lab>

[Container]
Image=docker.io/<org>/<image>:<tag>
```

---

## 2. IP Matrix

This is the **single source of truth** for all published ports. No exceptions.

### 2.1 Base Rules

1. **Every container** gets a dedicated loopback IP
2. **No** `0.0.0.0` — always `127.0.<zone>.<id>`
3. **No** `127.0.0.1` — reserved for the host itself
4. **Proxy IPs** are `10.0.0.x` — accessible from the host only
5. **Admin IPs** are `127.0.0.x` — loopback-only, no external access

### 2.2 The Matrix

| Service                 | Host IP        | Container IP   | Ports          | Zone                   |
| :---------------------- | :------------- | :------------- | :------------- | :--------------------- |
| **Traefik (admin)**     | `10.0.0.100`   | `10.0.0.100`   | `:80`, `:443`  | `10.0.0` — host-routed |
| **Technitium (proxy)**  | `10.0.0.111`   | `10.0.0.111`   | `:53`          | `10.0.0` — host-routed |
| **Technitium (server)** | `127.10.10.10` | `127.10.10.10` | `:53`, `:5380` | `127.10.10` — loopback |
| **Authelia**            | `127.0.1.10`   | `127.0.1.10`   | `:9091`        | `127.0.1` — loopback   |
| **LLDAP**               | `127.0.1.11`   | `127.0.1.11`   | `:636`         | `127.0.1` — loopback   |
| **SearXNG**             | `127.0.3.10`   | `127.0.3.10`   | `:8080`        | `127.0.3` — loopback   |
| **Valkey**              | `127.0.3.11`   | `127.0.3.11`   | `:6379`        | `127.0.3` — loopback   |
| **Reserved**            | `10.0.0.xxx`   | `10.0.0.xxx`   | —              | `10.0.0` — future      |
| **Reserved**            | `127.0.99.xx`  | `127.0.99.xx`  | —              | `127.0.99` — future    |

### 2.3 Why These Ranges

- `10.0.0.x` — Host-routed via `--network pasta` (pasta's implicit TAP → host bridge). Used for proxies that need to reach the host's network.
- `127.x.x.x` — Loopback addresses via `--network=host` with `-p 127.x.x.x:port:containerPort`. These are **NOT** forwarded through `rootlessport` — they use **pasta's direct TAP** → the host's kernel-level forwarding, preserving source IP.
- **Why not** `127.0.0.1`**?**  — `127.0.0.1` is ambiguous. It's the host's own loopback, and port binding there means the container sees ALL traffic as `127.0.0.1`. Using `127.x.x.x` gives each service its own loopback identity — useful for logging, auditing, and debugging.

### 2.4 The `pasta` Port Forwarding Rule

```properties
# In ~/.config/containers/containers.conf.d/00-pasta.conf
[network]
rootless_port_forwarder = "pasta"
# No rootlessport — ever
```

This is the **critical** setting. Without it, every published port loses its source IP.

---

## 3. Quadlet Conventions

### 3.1 Pods

```properties
# services/traefik/traefik.pod
[Pod]
PodName=traefik
Network=pasta              # ← Default network — passes through pasta
# No PublishPort here — containers handle their own
```

**Why** `Network=pasta` **on the pod, not the container?**

- Pod-level `Network=pasta` means all containers in the pod share the same network namespace
- This enables **inter-container communication** via `127.0.0.1`
- The reverse proxy (traefik) can reach any container in the pod

### 3.2 Containers

```properties
# services/traefik/traefik.container
[Container]
ContainerName=traefik
Image=docker.io/traefik:v3
Pod=traefik.pod               # ← Attaches to the pod
Network=pasta                  # ← Inherited from the pod

# Ports — published via the pod's network
PublishPort=10.0.0.100:80:80          # ← Host-routed: external → 10.0.0.100 → pasta → container
PublishPort=10.0.0.100:443:443

# Security
NoNewPrivileges=true
DropCapability=ALL
ReadOnly=true
PrivateTmp=true
ProtectSystem=full

# Volumes
Volume=%h/config/traefik/traefik-static.yml:/etc/traefik/traefik-static.yml:ro,Z
Volume=%h/config/traefik/dynamic-conf.yml:/etc/traefik/dynamic-conf.yml:ro,Z
Volume=traefik-data:/var/lib/traefik:Z         # Write volume for logs

# Environment
EnvironmentFile=%h/.config/containers/systemd/traefik.env

# Auto-update
AutoUpdate=registry

[Install]
WantedBy=traefik.pod           # ← Start the container when the pod starts

[Service]
Restart=always
```

### 3.3 Standalone Containers

```properties
# services/cloudflared/cloudflared.container
[Container]
ContainerName=cloudflared
Image=docker.io/cloudflared/cloudflared:latest
# NO Pod — this is a standalone container

Network=host                  # ← Host networking for cloudflared
# cloudflared needs to reach the host's network directly
# for tunnel connections

# Security
NoNewPrivileges=true
DropCapability=ALL
ReadOnly=true

# Environment
EnvironmentFile=%h/.config/containers/systemd/cloudflared.env

[Install]
WantedBy=default.target        # ← Standalone — starts on boot

[Service]
Restart=always
```

### 3.4 Volumes

```properties
# services/postgres/postgres.volume
[Volume]
VolumeName=postgres-data
Driver=local
# No Label here — it's a volume
```

### 3.5 Networks

```properties
# services/_shared/traefik.network
[Network]
# Not used in Quadlet — Podman creates networks via 'podman network create'
# But you CAN define a network in a .network file for Quadlet
# Example:
NetworkName=traefik
# driver=bridge
# Subnet=10.0.0.0/24
# Gateway=10.0.0.1
```

---

## 4. Environment & Secrets

### 4.1 Secret Storage

```bash
# Secrets live in:
~/.config/containers/systemd/secrets.env
# Permissions: 0600 — readable by the user only
```

### 4.2 Secret Format

```bash
# secrets.env
# Format: KEY=VALUE
# No quotes — shell-parsed
# No spaces around '='

POSTGRES_PASSWORD=my-secure-password
AUTHELIA_JWT_SECRET=another-secret
TRAEFIK_ACME_EMAIL=admin@example.com
```

### 4.3 Podman 6.0 Native Secrets

```bash
# Create a secret
podman secret create postgres-password ~/.config/containers/systemd/secrets.env

# Use in Quadlet
# In postgres.container:
[Container]
Secret=postgres-password,type=env
# → Postman reads the secret and passes it as POSTGRES_PASSWORD=... to the container
```

### 4.4 Environment File Convention

```bash
# services/authelia/authelia.env.example
# Copy to ~/.config/containers/systemd/authelia.env
# Then edit — never commit the real env

AUTHELIA_JWT_SECRET=change-me
AUTHELIA_SESSION_SECRET=change-me
AUTHELIA_STORAGE_ENCRYPTION_KEY=change-me
```

---

## 5. CI/CD Pipeline

> **Goal:**  `git push` → Podman reloads → Services update. No `make`, no `docker-compose`, no `ansible` (unless you want it).

### 5.1 The Pipeline

```plain
graph LR
    A[git push] --> B[GitHub Actions]
    B --> C[rsync to host]
    C --> D[podman quadlet install]
    D --> E[systemctl --user daemon-reload]
    E --> F[systemctl --user restart]
    F --> G[Services updated]
```

### 5.2 The Workflow

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: self-hosted  # ← Your cloudlab host
    steps:
      - uses: actions/checkout@v4
      
      - name: Sync quadlet files
        run: |
          # Step 1: Copy all .pod, .container, .volume, .network files
          # Exclude .env.example — those are templates for the user
          # Exclude .github/, README.md
          
          # We use 'podman quadlet install' to handle this
          podman quadlet install ./services/  # ← Globbing not yet supported, use explicit paths
      
      - name: Install
        run: |
          # Step 2: Install all quadlet files
          # This generates systemd service files from the .container and .pod files
          systemctl --user daemon-reload
      
      - name: Restart
        run: |
          # Step 3: Restart changed services
          systemctl --user restart traefik.pod
          systemctl --user restart authelia.pod
          # etc.
```

### 5.3 Better: `podman-quadlet-install` Shell Script

```bash
#!/bin/bash
# install-quadlets.sh
# Called by GitHub Actions
# Usage: bash install-quadlets.sh

set -euo pipefail

# Source directory
QUADLET_DIR="${HOME}/.config/containers/systemd"

# Step 1: Install all quadlet files
echo "→ Installing quadlet files..."
for f in $(find services/ -name '*.pod' -o -name '*.container' -o -name '*.volume' -o -name '*.network'); do
  # Symlink to systemd directory
  ln -sf "$(realpath "$f")" "${QUADLET_DIR}/$(basename "$f")"
done

# Step 2: Reload
echo "→ Reloading systemd..."
systemctl --user daemon-reload

# Step 3: Restart
echo "→ Restarting services..."
for pod in $(find services/ -name '*.pod'); do
  pod_name=$(basename "$pod" .pod)
  systemctl --user restart "${pod_name}.pod" || true
done

# Step 4: Check
echo "→ Checking..."
systemctl --user --failed
```

---

## 6. Security Hardening

### 6.1 Capabilities

```bash
# Every container — base
DropCapability=ALL

# Then add back ONLY what's needed
# For ping:
Capability=NET_RAW
# For DNS (technitium):
Capability=NET_RAW,NET_ADMIN
# For traefik (ACME):
Capability=NET_BIND_SERVICE  # ← For ports <1024
```

### 6.2 Seccomp

```properties
[Container]
SeccompProfile=/etc/containers/seccomp.json
# Default seccomp profile — blocks ~44 syscalls
# Use 'default.json' for most containers
```

### 6.3 AppArmor

```properties
# AppArmor is not enabled on Fedora by default
# But if it were:
SecurityLabel=type:spc_t
```

### 6.4 SELinux

```properties
# All mounts MUST be :Z — for SELinux context
Volume=traefik-data:/var/lib/traefik:Z

# :Z ensures the volume is labeled for the container's context
# :z is for shared volumes — use :Z for service-specific
```

### 6.5 Rootless

```bash
# Verify rootless
id=$(id -u)
if [ "$id" -eq 0 ]; then
  echo "ERROR: Running as root — this lab MUST be rootless."
  exit 1
fi
```

### 6.6 User Namespaces

```properties
# All containers
[Container]
# Already rootless — no extra user namespace needed
# But for extra isolation:
UserNS=private
```

### 6.7 Cgroups

```properties
# All containers
[Container]
# Use systemd cgroups — v2
Cgroups=systemd
```

---

## 7. Troubleshooting

### 7.1 Source IP Lost?

```bash
# Check if pasta mode is enabled
podman info --format '{{.Host.Security.RootlessPortForwarder}}'
# → Should be 'pasta'

# If not:
# 1. Check ~/.config/containers/containers.conf.d/00-pasta.conf
# 2. Verify Podman 6.0
podman --version
# → Should be 6.0.0-rc1 or later

# Check pasta
pasta --version  # → Should be a recent version
```

### 7.2 Port Conflict?

```bash
# Check the IP matrix
# All ports are bound to specific IPs
# If you see 0.0.0.0:port — it's a mistake

# Check what's listening
ss -tlnp | grep -E '10\.0\.0|127\.'
# → Should show only the IPs from the matrix
```

### 7.3 Service Not Starting?

```bash
# Check journal
journalctl --user -u traefik.pod --no-pager -n 50

# Check podman
podman ps --all
podman logs traefik

# Check network
podman network ls
```

### 7.4 CI/CD Failure?

```bash
# 1. Check the install script
bash -x install-quadlets.sh

# 2. Check systemd
systemctl --user --failed

# 3. Check file permissions
ls -la ~/.config/containers/systemd/
# → All should be symlinks to the repo
```

---

## 8. Future Directions

### 8.1 Podman 6.x

- **Rootless port forwarder** → `pasta` mode (default in Podman 6.1)
- **Better network management** — `podman network create` → Quadlet

### 8.2 Migration from Docker Compose

```bash
# Convert docker-compose.yml → Quadlet
podman compose generate --format=quadlet
# → Generates .pod + .container files
```

### 8.3 Native Quadlet Secrets

```bash
# Secret format
# In .container files:
[Container]
Secret=postgres-password,type=env
```

---

## 9. References

- [Podman 6.0 PR #28478 — Rootless bridge: preserve source IPs via pesto/pasta](https://github.com/containers/podman/pull/28478)
- [Podman 6.0 — Source IP Mangled to 127.0.0.1 Issue](https://github.com/containers/podman/issues/8193)
- [Traefik + Podman — No Docker Socket, File Provider](https://community.traefik.io/t/how-can-i-make-traefik-v3-work-with-podman/26738)
- [Podman Quadlet — systemd.unit(5) ](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Podman Networking Docs](https://github.com/eriksjolund/podman-networking-docs)
- [Fedora 41 — Podman 6](https://fedoraproject.org/wiki/Changes/Podman6)
- [This Repo](https://github.com/rusano-knn/rusano-cloudlab)

---

## 10. License

MIT — but this is a configuration, not a library. Do what you want.
