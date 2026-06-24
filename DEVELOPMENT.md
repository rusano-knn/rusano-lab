# Development Guide — rusano-lab

This guide details the coding conventions, directory structure rules, security configurations, and validation processes for expanding or maintaining the `rusano-lab` infrastructure.

---

## 1. Directory Layout & Naming Conventions

All services inside `app/` are categorized by function:

- `network/`: Base networking, reverse proxies, and recursive DNS configurations.
- `auth/`: Identity management and access control systems.
- `ai/`: Large Language Model (LLM) client UIs and tooling.
- `privacy/`: Privacy-respecting tools and search engines.
- `database/`: Database administration engines.

### File Naming Matrix

You must adhere to the following Quadlet file naming rules:

| Suffix | Quadlet Target | Example |
| :--- | :--- | :--- |
| `*.network` | Shared network definition | [traefik.network](file:///home/rusano/Projects/Code/rusano/rusano-lab/app/network/traefik.network) |
| `*.pod` | Shared container namespace | [traefik.pod](file:///home/rusano/Projects/Code/rusano/rusano-lab/app/network/traefik/traefik.pod) |
| `*.container` | Main application container spec | [traefik.container](file:///home/rusano/Projects/Code/rusano/rusano-lab/app/network/traefik/traefik.container) |
| `*.volume` | Named persistent data volume | [openwebui-data.volume](file:///home/rusano/Projects/Code/rusano/rusano-lab/app/ai/openwebui/openwebui-data.volume) |
| `*.env.example` | Template environment template | [authelia.env.example](file:///home/rusano/Projects/Code/rusano/rusano-lab/app/network/technitium/.env.example) |

### Header Conventions

Every file must start with the standard tracking header:

```properties
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab
# Version: 1.0.0
# Updated: 2026-06-22
```

---

## 2. Hard Security Constraints

When writing a new `*.container` spec, these security keys under `[Container]` are mandatory:

```properties
[Container]
# Ensure zero privilege escalation
NoNewPrivileges=true

# Drop all Linux capabilities
DropCapability=ALL

# Enable read-only container root filesystems
ReadOnly=true

# Add writeable areas to tmpfs
Tmpfs=/tmp /run /var/tmp

# Standardize system updates
AutoUpdate=registry
```

### Adding Back Capabilities

Only add back essential capabilities when explicitly needed (e.g. binding to standard ports or debugging routes):

- **DNS Servers / Proxies**: `AddCapability=NET_BIND_SERVICE,NET_RAW,NET_ADMIN`
- **Web Routers**: `AddCapability=NET_BIND_SERVICE`

---

## 3. Workflow: Adding a New Service

To introduce a new service into the cloudlab:

### Step 1: Assign a Dedicated Loopback IP

Reference the IP Matrix in [README.md](file:///home/rusano/Projects/Code/rusano/rusano-lab/README.md) and allocate a new dedicated IP from the correct zone.

- `127.0.1.x` — Auth
- `127.0.2.x` — AI Tools
- `127.0.3.x` — Privacy & Search
- `127.10.10.x` — DNS Zone

### Step 2: Define Volumes & Pod

Create `.volume` files for persistent paths, and a `.pod` file connected to `Network=traefik`.

### Step 3: Define Container configurations

Write the `*.container` file. Connect it to the pod using `Pod=yourpod.pod` and bind ports using the assigned loopback IP:

```properties
PublishPort=127.0.x.x:hostPort:containerPort
```

### Step 4: Map Secrets

Do **not** hardcode credentials. Expose them to Podman via `Secret=secret-name,type=env` under `[Container]`.

### Step 5: Add to Reverse Proxy

Add a routing configuration in Traefik's dynamic config [dynamic-conf.yml](file:///home/rusano/Projects/Code/rusano/rusano-lab/app/network/traefik/config/dynamic-conf.yml) pointing to `http://container-name:port` inside the `traefik` bridge network.

---

## 4. Quadlet Syntax Validation & Troubleshooting

You can test that your Quadlet files compile into systemd services without starting them.

### Dry-run Compilation

Podman compiles Quadlets on the host using the `podman-systemd-generator`. You can run this compiler manually to inspect the generated systemd files:

```bash
# Compile and dump generated user service files to console
/usr/lib/systemd/user-generators/podman-user-generator --dryrun

# Or for system-wide service files (if running as root):
/usr/lib/systemd/system-generators/podman-system-generator --dryrun
```

### Checking Generated Files

When services are successfully loaded, systemd compiles them in `/run/user/$(id -u)/systemd/generator/` (or `/run/systemd/generator/` for system services). You can view the output file:

```bash
cat /run/user/$(id -u)/systemd/generator/your-service.service
```

### Common Errors

1. **SELinux Permissions**: Ensure that files have the correct security context. When mounting folders from the host, ensure they use the `:Z` suffix (e.g. `Volume=/path:/mount:Z`).
2. **Restart Loop**: A container with `ReadOnly=true` might crash instantly if it tries to write to a path not mapped to a `Tmpfs` or persistent `Volume`. Check systemd logs using `journalctl --user -u name-server.service` to inspect the error.
