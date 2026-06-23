#!/usr/bin/env bash
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab
# Version: 1.0.0
# Updated: 2026-06-22

set -euo pipefail

SYSTEMD_USER_DIR="${HOME}/.config/containers/systemd"
CONFIG_BASE_DIR="${HOME}/config"

# Colors for Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Component Mapping
COMPONENTS=(
  "Shared Network (traefik-net)"
  "Traefik (ACME Proxy)"
  "Technitium DNS Server"
  "Adguard dnsproxy (DNS Forwarder)"
  "Cloudflare Tunnel (cloudflared)"
  "Authentik IdP"
  "Open WebUI"
  "SillyTavern"
  "SearXNG Search"
)

# Files associated with each component (relative to ~/.config/containers/systemd/)
declare -A COMP_FILES
COMP_FILES[0]="traefik.network"
COMP_FILES[1]="traefik.pod traefik.container traefik-letsencrypt.volume traefik-data.volume"
COMP_FILES[2]="technitium.pod technitium-server.container technitium-config.volume technitium-logs.volume"
COMP_FILES[3]="dnsproxy.container"
COMP_FILES[4]="cloudflared.container"
COMP_FILES[5]="authentik.pod authentik-redis.container authentik-postgresql.container authentik-server.container authentik-worker.container authentik-redis-data.volume authentik-postgres-data.volume authentik-media.volume authentik-templates.volume authentik-blueprints.volume"
COMP_FILES[6]="openwebui.pod openwebui.container openwebui-data.volume"
COMP_FILES[7]="sillytavern.pod sillytavern.container sillytavern-data.volume sillytavern-config.volume sillytavern-plugins.volume sillytavern-extensions.volume"
COMP_FILES[8]="searxng.pod searxng.container searxng-valkey.container searxng-config.volume searxng-data.volume searxng-valkey-data.volume"

# Unit files associated with each component (for disabling and stopping services)
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

# Choices array for removal (1=Selected, 0=Unselected)
CHOICES=(0 0 0 0 0 0 0 0 0)

# Check which components are actually installed (meaning the symlink exists)
check_installed() {
  local installed_count=0
  for i in "${!COMPONENTS[@]}"; do
    local files=(${COMP_FILES[$i]})
    local first_file="${files[0]}"
    if [ -l "${SYSTEMD_USER_DIR}/${first_file}" ]; then
      CHOICES[$i]=1
      installed_count=$((installed_count+1))
    fi
  done
  return "$installed_count"
}

# Scan installed services
check_installed || installed_count=$?

if [ "$installed_count" -eq 0 ]; then
  echo -e "${YELLOW}ℹ No installed rusano-lab Quadlet services found in ~/.config/containers/systemd/.${NC}"
  exit 0
fi

# Function to display menu
show_menu() {
  clear
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${BLUE}       rusano-lab Quadlet Removal Selector         ${NC}"
  echo -e "${BLUE}===================================================${NC}"
  echo "Toggle services to remove using their numbers, or use the letters below:"
  echo ""
  for i in "${!COMPONENTS[@]}"; do
    # Only show if currently installed
    local files=(${COMP_FILES[$i]})
    local first_file="${files[0]}"
    if [ -l "${SYSTEMD_USER_DIR}/${first_file}" ]; then
      local checkbox="[ ]"
      if [ "${CHOICES[$i]}" -eq 1 ]; then
        checkbox="[x]"
      fi
      echo -e "  $((i+1))) ${RED}${checkbox}${NC} ${COMPONENTS[$i]}"
    else
      echo -e "  $((i+1))) ${YELLOW}[Not Installed]${NC} ${COMPONENTS[$i]}"
    fi
  done
  echo ""
  echo "  a) Select ALL Installed"
  echo "  n) Select NONE"
  echo "  c) Confirm and remove"
  echo "  q) Quit"
  echo -e "${BLUE}===================================================${NC}"
  echo -n "Select option: "
}

# Selection loop
while true; do
  show_menu
  read -r opt
  case $opt in
    [1-9])
      idx=$((opt-1))
      local files=(${COMP_FILES[$idx]})
      local first_file="${files[0]}"
      if [ -l "${SYSTEMD_USER_DIR}/${first_file}" ]; then
        if [ "${CHOICES[$idx]}" -eq 1 ]; then
          CHOICES[$idx]=0
        else
          CHOICES[$idx]=1
        fi
      else
        echo "Option $((idx+1)) is not installed. Press Enter."
        read -r
      fi
      ;;
    [aA])
      for i in "${!CHOICES[@]}"; do
        local files=(${COMP_FILES[$i]})
        local first_file="${files[0]}"
        if [ -l "${SYSTEMD_USER_DIR}/${first_file}" ]; then
          CHOICES[$i]=1
        fi
      done
      ;;
    [nN])
      for i in "${!CHOICES[@]}"; do CHOICES[$i]=0; done
      ;;
    [cC])
      break
      ;;
    [qQ])
      echo "Removal cancelled."
      exit 0
      ;;
    *)
      echo "Invalid option. Press Enter to retry."
      read -r
      ;;
  esac
done

# Check if anything was selected
selected_any=0
for val in "${CHOICES[@]}"; do
  if [ "$val" -eq 1 ]; then selected_any=1; break; fi
done

if [ "$selected_any" -eq 0 ]; then
  echo "No services selected for removal."
  exit 0
fi

echo -e "\n${BLUE}→ Stopping active services and deleting Quadlet symlinks...${NC}"

for i in "${!CHOICES[@]}"; do
  if [ "${CHOICES[$i]}" -eq 1 ]; then
    echo -e "\n${RED}[-] Removing ${COMPONENTS[$i]}...${NC}"
    
    # 1. Disable and Stop service/pod unit
    local unit="${COMP_UNITS[$i]}"
    echo "  Disabling systemd unit: $unit"
    systemctl --user disable "$unit" || true
    if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
      echo "  Stopping systemd unit: $unit"
      systemctl --user stop "$unit" || true
    fi
    
    # 2. Delete symlinks
    local files=(${COMP_FILES[$i]})
    for file in "${files[@]}"; do
      local link_path="${SYSTEMD_USER_DIR}/${file}"
      if [ -l "$link_path" ]; then
        rm -f "$link_path"
        echo "  Deleted symlink: $file"
      fi
    done
  fi
done

# Reload systemd
echo -e "\n${BLUE}→ Reloading systemd user daemon...${NC}"
systemctl --user daemon-reload

# Ask to clean up config folders
echo -e "\n${BLUE}===================================================${NC}"
echo -n "Would you also like to delete the local configuration folders (e.g. ~/config/) for removed services? (y/N): "
read -r delete_configs

if [[ "$delete_configs" =~ ^[yY](es)?$ ]]; then
  echo ""
  for i in "${!CHOICES[@]}"; do
    if [ "${CHOICES[$i]}" -eq 1 ]; then
      local config_folder="${COMP_CONFIGS[$i]}"
      if [ -n "$config_folder" ]; then
        local full_path="${CONFIG_BASE_DIR}/${config_folder}"
        if [ -d "$full_path" ]; then
          rm -rf "$full_path"
          echo -e "${RED}  Deleted directory: ~/config/$config_folder${NC}"
        fi
      fi
    fi
  done
fi

echo -e "\n${GREEN}✓ Selected services removed successfully!${NC}"
