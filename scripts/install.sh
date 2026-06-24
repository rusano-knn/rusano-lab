# Installer logic for rusano-lab
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab

# Function to run the installer
run_install_action() {
  local num_items=${#COMPONENTS[@]}
  local choices=()
  for (( i=0; i<num_items; i++ )); do
    choices+=(1) # Select all by default
  done

  # Run TUI selector
  run_selector choices "install"

  # Validate if anything was selected
  local selected_count=0
  for val in "${choices[@]}"; do
    [[ "$val" -eq 1 ]] && selected_count=$((selected_count + 1))
  done

  if [ "$selected_count" -eq 0 ]; then
    echo -e "${YELLOW}No services selected for installation.${NC}"
    return 0
  fi

  # Show selected services and request confirmation
  echo -e "\n${BLUE}===================================================${NC}"
  echo -e " The following services will be installed:"
  for i in "${!choices[@]}"; do
    if [ "${choices[$i]}" -eq 1 ]; then
      echo -e "  ${GREEN}*${NC} ${COMPONENTS[$i]}"
    fi
  done
  echo -e "${BLUE}===================================================${NC}"
  echo -n "Proceed with installation? (y/N): "
  read -r confirm
  if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
    echo "Installation cancelled."
    return 0
  fi

  # Create directories
  mkdir -p "$SYSTEMD_USER_DIR"
  mkdir -p "$CONFIG_BASE_DIR"

  echo -e "\n${BLUE}→ Installing configurations & symlinking Quadlets...${NC}"

  install_quadlet() {
    local src="$1"
    local dest="${SYSTEMD_USER_DIR}/$(basename "$src")"
    ln -sf "$(realpath "$src")" "$dest"
    echo -e "  Symlinked: $(basename "$src") → ~/.config/containers/systemd/"
  }

  # 1. Shared Network (traefik)
  if [ "${choices[0]}" -eq 1 ]; then
    echo -e "\n${YELLOW}[+] Installing Shared Network...${NC}"
    install_quadlet "app/network/traefik.network"
  fi

  # 2. Traefik
  if [ "${choices[1]}" -eq 1 ]; then
    echo -e "\n${YELLOW}[+] Installing Traefik...${NC}"
    mkdir -p "${CONFIG_BASE_DIR}/traefik"
    for f in traefik-static.yml dynamic-conf.yml; do
      if [ ! -f "${CONFIG_BASE_DIR}/traefik/$f" ]; then
        cp "app/network/traefik/config/$f" "${CONFIG_BASE_DIR}/traefik/"
        echo "  Copied default configuration: ~/config/traefik/$f"
      fi
    done
    if [ ! -f "${SYSTEMD_USER_DIR}/traefik.env" ]; then
      cp "app/network/traefik/traefik.env.example" "${SYSTEMD_USER_DIR}/traefik.env"
      chmod 0600 "${SYSTEMD_USER_DIR}/traefik.env"
      echo "  Created default environment file: ~/.config/containers/systemd/traefik.env"
    fi
    for q in app/network/traefik/*.pod app/network/traefik/*.container app/network/traefik/*.volume; do
      install_quadlet "$q"
    done
  fi

  # 3. Technitium
  if [ "${choices[2]}" -eq 1 ]; then
    echo -e "\n${YELLOW}[+] Installing Technitium...${NC}"
    if [ ! -f "${SYSTEMD_USER_DIR}/technitium.env" ]; then
      cp "app/network/technitium/technitium.env.example" "${SYSTEMD_USER_DIR}/technitium.env"
      chmod 0600 "${SYSTEMD_USER_DIR}/technitium.env"
      echo "  Created default environment file: ~/.config/containers/systemd/technitium.env"
    fi
    for q in app/network/technitium/*.pod app/network/technitium/*.container app/network/technitium/*.volume; do
      install_quadlet "$q"
    done
  fi

  # 4. Adguard dnsproxy
  if [ "${choices[3]}" -eq 1 ]; then
    echo -e "\n${YELLOW}[+] Installing Adguard dnsproxy...${NC}"
    mkdir -p "${CONFIG_BASE_DIR}/dnsproxy"
    if [ ! -f "${CONFIG_BASE_DIR}/dnsproxy/config.yaml" ]; then
      cp "app/network/dnsproxy/config.yaml" "${CONFIG_BASE_DIR}/dnsproxy/"
      echo "  Copied default configuration: ~/config/dnsproxy/config.yaml"
    fi
    install_quadlet "app/network/dnsproxy/dnsproxy.container"
  fi

  # 5. Cloudflare Tunnel
  if [ "${choices[4]}" -eq 1 ]; then
    echo -e "\n${YELLOW}[+] Installing Cloudflare Tunnel...${NC}"
    install_quadlet "app/network/cloudflared/cloudflared.container"
  fi

  # 6. Authentik
  if [ "${choices[5]}" -eq 1 ]; then
    echo -e "\n${YELLOW}[+] Installing Authentik...${NC}"
    for q in app/auth/authentik/*.pod app/auth/authentik/*.container app/auth/authentik/*.volume; do
      install_quadlet "$q"
    done
  fi

  # 7. Open WebUI
  if [ "${choices[6]}" -eq 1 ]; then
    echo -e "\n${YELLOW}[+] Installing Open WebUI...${NC}"
    for q in app/ai/openwebui/*.pod app/ai/openwebui/*.container app/ai/openwebui/*.volume; do
      install_quadlet "$q"
    done
  fi

  # 8. SillyTavern
  if [ "${choices[7]}" -eq 1 ]; then
    echo -e "\n${YELLOW}[+] Installing SillyTavern...${NC}"
    for q in app/ai/sillytavern/*.pod app/ai/sillytavern/*.container app/ai/sillytavern/*.volume; do
      install_quadlet "$q"
    done
  fi

  # 9. SearXNG
  if [ "${choices[8]}" -eq 1 ]; then
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

  # Start Services
  local active_units=()
  for i in "${!choices[@]}"; do
    if [ "${choices[$i]}" -eq 1 ]; then
      active_units+=("${COMP_UNITS[$i]}")
    fi
  done

  echo -e "\n${GREEN}ℹ Note: Boot autostart is managed natively by systemd Quadlet [Install] targets.${NC}"
  echo -e "${BLUE}===================================================${NC}"
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
    echo -e "\n${YELLOW}You can start them later manually using: systemctl --user start <service_name>${NC}"
  fi

  echo -e "\n${GREEN}✓ Setup complete!${NC}"
}
