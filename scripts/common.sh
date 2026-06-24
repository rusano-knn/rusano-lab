# Shared library for rusano-lab services
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab

SYSTEMD_USER_DIR="${HOME}/.config/containers/systemd"
CONFIG_BASE_DIR="${HOME}/config"

# Colors for Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Component Mapping
COMPONENTS=(
  "Shared Network (traefik)"
  "Traefik (ACME Proxy)"
  "Technitium DNS Server"
  "Adguard dnsproxy (DNS Forwarder)"
  "Cloudflare Tunnel (cloudflared)"
  "Authentik IdP"
  "Open WebUI"
  "SillyTavern"
  "SearXNG Search"
)

# App Categories
COMP_CATEGORIES=(
  "Core & Networking"
  "Core & Networking"
  "Core & Networking"
  "Core & Networking"
  "Core & Networking"
  "Identity & Auth"
  "AI & LLM Frontends"
  "AI & LLM Frontends"
  "Privacy & Search"
)

# Files associated with each component (relative to ~/.config/containers/systemd/)
declare -A COMP_FILES
COMP_FILES[0]="traefik.network"
COMP_FILES[1]="traefik.pod traefik.container traefik-letsencrypt.volume traefik-data.volume"
COMP_FILES[2]="technitium.pod technitium.container technitium-config.volume technitium-logs.volume"
COMP_FILES[3]="dnsproxy.container"
COMP_FILES[4]="cloudflared.container"
COMP_FILES[5]="authentik.pod authentik-redis.container authentik-postgresql.container authentik-server.container authentik-worker.container authentik-redis-data.volume authentik-postgres-data.volume authentik-media.volume authentik-templates.volume authentik-blueprints.volume"
COMP_FILES[6]="openwebui.pod openwebui.container openwebui-data.volume"
COMP_FILES[7]="sillytavern.pod sillytavern.container sillytavern-data.volume sillytavern-config.volume sillytavern-plugins.volume sillytavern-extensions.volume"
COMP_FILES[8]="searxng.pod searxng.container searxng-valkey.container searxng-config.volume searxng-data.volume searxng-valkey-data.volume"

# Unit files associated with each component
declare -A COMP_UNITS
COMP_UNITS[0]="traefik-network.service"
COMP_UNITS[1]="traefik-pod.service"
COMP_UNITS[2]="technitium-pod.service"
COMP_UNITS[3]="dnsproxy.service"
COMP_UNITS[4]="cloudflared.service"
COMP_UNITS[5]="authentik-pod.service"
COMP_UNITS[6]="openwebui-pod.service"
COMP_UNITS[7]="sillytavern-pod.service"
COMP_UNITS[8]="searxng-pod.service"

# Config folders associated with each component
declare -A COMP_CONFIGS
COMP_CONFIGS[0]=""
COMP_CONFIGS[1]="traefik"
COMP_CONFIGS[2]=""
COMP_CONFIGS[3]="dnsproxy"
COMP_CONFIGS[4]=""
COMP_CONFIGS[5]=""
COMP_CONFIGS[6]=""
COMP_CONFIGS[7]=""
COMP_CONFIGS[8]="searxng"

# Pod names associated with each component
declare -A COMP_PODS
COMP_PODS[0]=""
COMP_PODS[1]="traefik"
COMP_PODS[2]="technitium"
COMP_PODS[3]=""
COMP_PODS[4]=""
COMP_PODS[5]="authentik"
COMP_PODS[6]="openwebui"
COMP_PODS[7]="sillytavern"
COMP_PODS[8]="searxng"

# Standalone container names associated with each component
declare -A COMP_CONTAINERS
COMP_CONTAINERS[0]=""
COMP_CONTAINERS[1]=""
COMP_CONTAINERS[2]=""
COMP_CONTAINERS[3]="dnsproxy"
COMP_CONTAINERS[4]="cloudflared"
COMP_CONTAINERS[5]=""
COMP_CONTAINERS[6]=""
COMP_CONTAINERS[7]=""
COMP_CONTAINERS[8]=""

# Function to dynamically detect status of a component
# Returns status string: "Not Installed", "Stopped", "Running", "Error"
get_status() {
  local idx="$1"
  local files=(${COMP_FILES[$idx]})
  local first_file="${files[0]}"
  local unit="${COMP_UNITS[$idx]}"

  if [ ! -L "${SYSTEMD_USER_DIR}/${first_file}" ]; then
    echo "Not Installed"
    return 0
  fi

  # Check systemd states
  if systemctl --user is-failed "$unit" --quiet 2>/dev/null; then
    echo "Error"
  elif systemctl --user is-active "$unit" --quiet 2>/dev/null; then
    echo "Running"
  else
    echo "Stopped"
  fi
}

# Safely stop and destroy Podman and systemd resources for a service
clean_service_state() {
  local idx="$1"
  local unit="${COMP_UNITS[$idx]}"
  local pod="${COMP_PODS[$idx]}"
  local container="${COMP_CONTAINERS[$idx]}"

  echo "  Stopping systemd unit: $unit"
  systemctl --user stop "$unit" || true

  if [ -n "$pod" ]; then
    echo "  Ensuring Podman pod is stopped and removed: $pod"
    podman pod rm -f "$pod" 2>/dev/null || true
  fi

  if [ -n "$container" ]; then
    echo "  Ensuring Podman container is stopped and removed: $container"
    podman rm -f "$container" 2>/dev/null || true
  fi

  if [ "$idx" -eq 0 ]; then
    echo "  Removing Podman network: traefik"
    podman network rm -f traefik 2>/dev/null || true
  fi

  systemctl --user reset-failed "$unit" 2>/dev/null || true
}
