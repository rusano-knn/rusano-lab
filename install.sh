#!/usr/bin/env bash
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab
# Version: 1.0.0
# Updated: 2026-06-22

set -euo pipefail

# Installation Directories
SYSTEMD_USER_DIR="${HOME}/.config/containers/systemd"
CONFIG_BASE_DIR="${HOME}/config"

# Colors for Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Component Lists & Associated Files
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

# Choices array (1=Selected, 0=Unselected)
CHOICES=(1 1 1 1 1 1 1 1 1)

# Function to display menu
show_menu() {
  clear
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${BLUE}      rusano-lab Quadlet Installer Selector       ${NC}"
  echo -e "${BLUE}===================================================${NC}"
  echo "Toggle services using their numbers, or use the letters below:"
  echo ""
  for i in "${!COMPONENTS[@]}"; do
    local checkbox="[ ]"
    if [ "${CHOICES[$i]}" -eq 1 ]; then
      checkbox="[x]"
    fi
    echo -e "  $((i+1))) ${GREEN}${checkbox}${NC} ${COMPONENTS[$i]}"
  done
  echo ""
  echo "  a) Select ALL"
  echo "  n) Select NONE"
  echo "  c) Confirm and continue"
  echo "  q) Quit"
  echo -e "${BLUE}===================================================${NC}"
  echo -n "Select option: "
}

# Interactive selection loop
while true; do
  show_menu
  read -r opt
  case $opt in
    [1-9])
      idx=$((opt-1))
      if [ "${CHOICES[$idx]}" -eq 1 ]; then
        CHOICES[$idx]=0
      else
        CHOICES[$idx]=1
      fi
      ;;
    [aA])
      for i in "${!CHOICES[@]}"; do CHOICES[$i]=1; done
      ;;
    [nN])
      for i in "${!CHOICES[@]}"; do CHOICES[$i]=0; done
      ;;
    [cC])
      break
      ;;
    [qQ])
      echo "Installation cancelled."
      exit 0
      ;;
    *)
      echo "Invalid option. Press Enter to retry."
      read -r
      ;;
  esac
done

# Create necessary directories
mkdir -p "$SYSTEMD_USER_DIR"
mkdir -p "$CONFIG_BASE_DIR"

echo -e "\n${BLUE}→ Installing configurations & symlinking Quadlets...${NC}"

# Define installer actions
install_quadlet() {
  local src="$1"
  local dest="${SYSTEMD_USER_DIR}/$(basename "$src")"
  ln -sf "$(realpath "$src")" "$dest"
  echo -e "  Symlinked: $(basename "$src") → ~/.config/containers/systemd/"
}

# 1. Shared Network (traefik-net)
if [ "${CHOICES[0]}" -eq 1 ]; then
  echo -e "\n${YELLOW}[+] Installing Shared Network...${NC}"
  install_quadlet "app/network/traefik.network"
fi

# 2. Traefik
if [ "${CHOICES[1]}" -eq 1 ]; then
  echo -e "\n${YELLOW}[+] Installing Traefik...${NC}"
  mkdir -p "${CONFIG_BASE_DIR}/traefik"
  # Copy configs if they don't exist to prevent overwriting custom changes
  for f in traefik-static.yml dynamic-conf.yml; do
    if [ ! -f "${CONFIG_BASE_DIR}/traefik/$f" ]; then
      cp "app/network/traefik/config/$f" "${CONFIG_BASE_DIR}/traefik/"
      echo "  Copied default configuration: ~/config/traefik/$f"
    fi
  done
  for q in app/network/traefik/*.pod app/network/traefik/*.container app/network/traefik/*.volume; do
    install_quadlet "$q"
  done
fi

# 3. Technitium
if [ "${CHOICES[2]}" -eq 1 ]; then
  echo -e "\n${YELLOW}[+] Installing Technitium...${NC}"
  for q in app/network/technitium/*.pod app/network/technitium/*.container app/network/technitium/*.volume; do
    install_quadlet "$q"
  done
fi

# 4. Adguard dnsproxy
if [ "${CHOICES[3]}" -eq 1 ]; then
  echo -e "\n${YELLOW}[+] Installing Adguard dnsproxy...${NC}"
  mkdir -p "${CONFIG_BASE_DIR}/dnsproxy"
  if [ ! -f "${CONFIG_BASE_DIR}/dnsproxy/config.yaml" ]; then
    cp "app/network/dnsproxy/config.yaml" "${CONFIG_BASE_DIR}/dnsproxy/"
    echo "  Copied default configuration: ~/config/dnsproxy/config.yaml"
  fi
  install_quadlet "app/network/dnsproxy/dnsproxy.container"
fi

# 5. Cloudflare Tunnel
if [ "${CHOICES[4]}" -eq 1 ]; then
  echo -e "\n${YELLOW}[+] Installing Cloudflare Tunnel...${NC}"
  install_quadlet "app/network/cloudflared/cloudflared.container"
fi

# 6. Authentik
if [ "${CHOICES[5]}" -eq 1 ]; then
  echo -e "\n${YELLOW}[+] Installing Authentik...${NC}"
  for q in app/auth/authentik/*.pod app/auth/authentik/*.container app/auth/authentik/*.volume; do
    install_quadlet "$q"
  done
fi

# 7. Open WebUI
if [ "${CHOICES[6]}" -eq 1 ]; then
  echo -e "\n${YELLOW}[+] Installing Open WebUI...${NC}"
  for q in app/ai/openwebui/*.pod app/ai/openwebui/*.container app/ai/openwebui/*.volume; do
    install_quadlet "$q"
  done
fi

# 8. SillyTavern
if [ "${CHOICES[7]}" -eq 1 ]; then
  echo -e "\n${YELLOW}[+] Installing SillyTavern...${NC}"
  for q in app/ai/sillytavern/*.pod app/ai/sillytavern/*.container app/ai/sillytavern/*.volume; do
    install_quadlet "$q"
  done
fi

# 9. SearXNG
if [ "${CHOICES[8]}" -eq 1 ]; then
  echo -e "\n${YELLOW}[+] Installing SearXNG...${NC}"
  mkdir -p "${CONFIG_BASE_DIR}/searxng"
  for f in settings.yml limiter.toml favicons.toml; do
    if [ ! -f "${CONFIG_BASE_DIR}/searxng/$f" ]; then
      cp "app/privacy/searxng/config/$f" "${CONFIG_BASE_DIR}/searxng/"
      echo "  Copied default configuration: ~/config/searxng/$f"
    fi
  done
  for q in app/privacy/searxng/*.pod app/privacy/searxng/*.container app/privacy/searxng/*.volume; do
    install_quadlet "$q"
  done
fi

# Reload systemd
echo -e "\n${BLUE}→ Reloading systemd user daemon...${NC}"
systemctl --user daemon-reload

# Enable & Start
echo -e "\n${BLUE}===================================================${NC}"
echo -n "Would you like to enable the installed services to start automatically on system boot? (y/N): "
read -r enable_boot

# Build list of active units to manage
active_units=()
[ "${CHOICES[0]}" -eq 1 ] && active_units+=("traefik-network.service")
[ "${CHOICES[1]}" -eq 1 ] && active_units+=("traefik-pod.service")
[ "${CHOICES[2]}" -eq 1 ] && active_units+=("technitium-pod.service")
[ "${CHOICES[3]}" -eq 1 ] && active_units+=("dnsproxy.service")
[ "${CHOICES[4]}" -eq 1 ] && active_units+=("cloudflared.service")
[ "${CHOICES[5]}" -eq 1 ] && active_units+=("authentik-pod.service")
[ "${CHOICES[6]}" -eq 1 ] && active_units+=("openwebui-pod.service")
[ "${CHOICES[7]}" -eq 1 ] && active_units+=("sillytavern-pod.service")
[ "${CHOICES[8]}" -eq 1 ] && active_units+=("searxng-pod.service")

if [[ "$enable_boot" =~ ^[yY](es)?$ ]]; then
  echo -e "\n${GREEN}→ Enabling services for system boot...${NC}"
  for unit in "${active_units[@]}"; do
    echo "  Enabling: $unit"
    systemctl --user enable "$unit" || true
  done
  echo -e "${GREEN}✓ Enabled successfully.${NC}"
fi

echo -e "\n${BLUE}===================================================${NC}"
echo -n "Would you like to start the installed services now? (y/N): "
read -r start_now

if [[ "$start_now" =~ ^[yY](es)?$ ]]; then
  echo -e "\n${GREEN}→ Starting services...${NC}"
  for unit in "${active_units[@]}"; do
    echo "  Starting: $unit"
    systemctl --user start "$unit" || true
  done
  echo -e "${GREEN}✓ Started successfully.${NC}"
else
  if [[ "$enable_boot" =~ ^[yY](es)?$ ]]; then
    echo -e "\n${YELLOW}Services are enabled and will start on next boot/login, or you can start them manually using: systemctl --user start <service_name>${NC}"
  else
    echo -e "\n${YELLOW}You can start them later manually using: systemctl --user start <service_name>${NC}"
  fi
fi

echo -e "\n${GREEN}✓ Setup complete!${NC}"
