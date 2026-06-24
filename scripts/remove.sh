# Uninstaller logic for rusano-lab
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab

# Function to run the uninstaller
run_remove_action() {
  local num_items=${#COMPONENTS[@]}
  local choices=()
  local installed_count=0

  # Scan which ones are actually installed
  for (( i=0; i<num_items; i++ )); do
    local files=(${COMP_FILES[$i]})
    local first_file="${files[0]}"
    if [ -L "${SYSTEMD_USER_DIR}/${first_file}" ]; then
      choices+=(1)
      installed_count=$((installed_count + 1))
    else
      choices+=(0)
    fi
  done

  if [ "$installed_count" -eq 0 ]; then
    echo -e "${YELLOW}ℹ No installed rusano-lab Quadlet services found in ~/.config/containers/systemd/.${NC}"
    return 0
  fi

  # Run TUI selector
  run_selector choices "remove"

  # Validate if anything was selected for removal
  local selected_count=0
  for val in "${choices[@]}"; do
    [[ "$val" -eq 1 ]] && selected_count=$((selected_count + 1))
  done

  if [ "$selected_count" -eq 0 ]; then
    echo -e "${YELLOW}No services selected for removal.${NC}"
    return 0
  fi

  # Show selected services and request confirmation
  echo -e "\n${BLUE}===================================================${NC}"
  echo -e " ${RED}The following services will be uninstalled:${NC}"
  for i in "${!choices[@]}"; do
    if [ "${choices[$i]}" -eq 1 ]; then
      echo -e "  ${RED}*${NC} ${COMPONENTS[$i]}"
    fi
  done
  echo -e "${BLUE}===================================================${NC}"
  echo -n "Are you sure you want to proceed with uninstallation? (y/N): "
  read -r confirm
  if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
    echo "Removal cancelled."
    return 0
  fi

  echo -e "\n${BLUE}→ Stopping active services and deleting Quadlet symlinks...${NC}"

  for i in "${!choices[@]}"; do
    if [ "${choices[$i]}" -eq 1 ]; then
      echo -e "\n${RED}[-] Removing ${COMPONENTS[$i]}...${NC}"
      
      # Clean up running states, Pods, containers, and processes
      clean_service_state "$i"
      
      # Delete symlinks
      local files=(${COMP_FILES[$i]})
      for file in "${files[@]}"; do
        local link_path="${SYSTEMD_USER_DIR}/${file}"
        if [ -L "$link_path" ]; then
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
  local folders_to_delete=()
  for i in "${!choices[@]}"; do
    if [ "${choices[$i]}" -eq 1 ]; then
      local config_folder="${COMP_CONFIGS[$i]}"
      if [ -n "$config_folder" ]; then
        local full_path="${CONFIG_BASE_DIR}/${config_folder}"
        if [ -d "$full_path" ]; then
          folders_to_delete+=("$config_folder")
        fi
      fi
    fi
  done

  if [ "${#folders_to_delete[@]}" -gt 0 ]; then
    echo -e "\n${BLUE}===================================================${NC}"
    echo " The following local configuration directories can be purged:"
    for folder in "${folders_to_delete[@]}"; do
      echo -e "  ${RED}*${NC} ~/config/${folder}"
    done
    echo -e "${BLUE}===================================================${NC}"
    echo -n "Would you also like to delete these local configuration folders? (y/N): "
    read -r delete_configs

    if [[ "$delete_configs" =~ ^[yY](es)?$ ]]; then
      echo ""
      for folder in "${folders_to_delete[@]}"; do
        rm -rf "${CONFIG_BASE_DIR}/${folder}"
        echo -e "${RED}  Deleted directory: ~/config/$folder${NC}"
      done
    fi
  fi

  echo -e "\n${GREEN}✓ Selected services removed successfully!${NC}"
}
