# Configuration updater for rusano-lab
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab

run_update_action() {
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${BLUE}        rusano-lab Quadlet Configuration Updater    ${NC}"
  echo -e "${BLUE}===================================================${NC}"

  # Find currently symlinked files in systemd directory pointing to this repository
  echo "→ Validating existing Quadlet symlinks..."
  local symlinks_found=0
  
  while read -r link; do
    local target
    target=$(readlink "$link" || true)
    if [[ "$target" == *"rusano-lab"* ]]; then
      # Re-link just to ensure it is correct and up to date
      ln -sf "$target" "$link"
      echo "  Updated symlink: $(basename "$link")"
      symlinks_found=$((symlinks_found + 1))
    fi
  done < <(find "$SYSTEMD_USER_DIR" -maxdepth 1 -type l 2>/dev/null || true)

  if [ "$symlinks_found" -eq 0 ]; then
    echo -e "${YELLOW}ℹ No existing rusano-lab Quadlet symlinks detected in ~/.config/containers/systemd/.${NC}"
    echo "Please run the installer first to set up your services."
    return 0
  fi

  # Reload systemd
  echo -e "\n${BLUE}→ Reloading systemd user daemon...${NC}"
  systemctl --user daemon-reload

  # Ask to restart running services
  echo -e "\n${BLUE}===================================================${NC}"
  echo -n "Would you like to restart your running rusano-lab services to apply updates? (y/N): "
  read -r restart_now

  if [[ "$restart_now" =~ ^[yY](es)?$ ]]; then
    echo -e "\n${GREEN}→ Restarting active services...${NC}"
    
    for i in "${!COMPONENTS[@]}"; do
      local unit="${COMP_UNITS[$i]}"
      if systemctl --user is-active --quiet "$unit" 2>/dev/null; then
        echo "  Restarting: $unit"
        systemctl --user restart "$unit" || true
      fi
    done
    
    echo -e "${GREEN}✓ All active services restarted successfully.${NC}"
  else
    echo -e "\n${YELLOW}Updates loaded. Please restart services manually to apply changes.${NC}"
  fi

  echo -e "\n${GREEN}✓ Update complete!${NC}"
}
