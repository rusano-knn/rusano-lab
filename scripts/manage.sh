# Service manager loop for rusano-lab
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab

# Function to run the service manager loop
run_manage_action() {
  while true; do
    clear
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${BLUE}            rusano-lab Service Manager             ${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo "Select a service to manage:"
    echo ""

    for i in "${!COMPONENTS[@]}"; do
      local status_str
      status_str=$(get_status "$i")

      local status_color="$YELLOW"
      if [[ "$status_str" == "Running" ]]; then
        status_color="$GREEN"
      elif [[ "$status_str" == "Stopped" ]]; then
        status_color="$RED"
      elif [[ "$status_str" == "Error" ]]; then
        status_color="$RED"
      fi

      echo -e "  $((i+1))) [${status_color}${status_str}${NC}] ${COMPONENTS[$i]}"
    done

    echo ""
    echo "  q) Return to Main Menu"
    echo -e "${BLUE}===================================================${NC}"
    echo -n "Select option: "
    read -r opt

    if [[ "$opt" == "q" ]]; then
      break
    fi

    if [[ "$opt" =~ ^[1-9]$ ]]; then
      local idx=$((opt-1))
      
      while true; do
        clear
        local status_str
        status_str=$(get_status "$idx")

        local status_color="$YELLOW"
        if [[ "$status_str" == "Running" ]]; then
          status_color="$GREEN"
        elif [[ "$status_str" == "Stopped" ]]; then
          status_color="$RED"
        elif [[ "$status_str" == "Error" ]]; then
          status_color="$RED"
        fi

        echo -e "${BLUE}===================================================${NC}"
        echo -e "${CYAN} Service: ${COMPONENTS[$idx]}${NC}"
        echo -e " Status:  [${status_color}${status_str}${NC}]"
        echo -e "${BLUE}===================================================${NC}"
        
        if [[ "$status_str" == "Not Installed" ]]; then
          echo "  1) Install and Start"
          echo "  b) Back to List"
          echo -e "${BLUE}===================================================${NC}"
          echo -n "Select option: "
          read -r subopt
          
          if [[ "$subopt" == "b" ]]; then
            break
          elif [[ "$subopt" == "1" ]]; then
            # Re-install single service
            echo -e "\n${GREEN}→ Installing ${COMPONENTS[$idx]}...${NC}"
            mkdir -p "$SYSTEMD_USER_DIR"
            mkdir -p "$CONFIG_BASE_DIR"

            install_quadlet_local() {
              ln -sf "$(realpath "$1")" "${SYSTEMD_USER_DIR}/$(basename "$1")"
            }

            if [ "$idx" -eq 0 ]; then
              install_quadlet_local "app/network/traefik.network"
            elif [ "$idx" -eq 1 ]; then
              mkdir -p "${CONFIG_BASE_DIR}/traefik"
              for f in traefik-static.yml dynamic-conf.yml; do
                [ ! -f "${CONFIG_BASE_DIR}/traefik/$f" ] && cp "app/network/traefik/config/$f" "${CONFIG_BASE_DIR}/traefik/"
              done
              [ ! -f "${SYSTEMD_USER_DIR}/traefik.env" ] && cp "app/network/traefik/traefik.env.example" "${SYSTEMD_USER_DIR}/traefik.env" && chmod 0600 "${SYSTEMD_USER_DIR}/traefik.env"
              for q in app/network/traefik/*.pod app/network/traefik/*.container app/network/traefik/*.volume; do
                install_quadlet_local "$q"
              done
            elif [ "$idx" -eq 2 ]; then
              [ ! -f "${SYSTEMD_USER_DIR}/technitium.env" ] && cp "app/network/technitium/technitium.env.example" "${SYSTEMD_USER_DIR}/technitium.env" && chmod 0600 "${SYSTEMD_USER_DIR}/technitium.env"
              for q in app/network/technitium/*.pod app/network/technitium/*.container app/network/technitium/*.volume; do
                install_quadlet_local "$q"
              done
            elif [ "$idx" -eq 3 ]; then
              mkdir -p "${CONFIG_BASE_DIR}/dnsproxy"
              [ ! -f "${CONFIG_BASE_DIR}/dnsproxy/config.yaml" ] && cp "app/network/dnsproxy/config.yaml" "${CONFIG_BASE_DIR}/dnsproxy/"
              install_quadlet_local "app/network/dnsproxy/dnsproxy.container"
            elif [ "$idx" -eq 4 ]; then
              install_quadlet_local "app/network/cloudflared/cloudflared.container"
            elif [ "$idx" -eq 5 ]; then
              for q in app/auth/authentik/*.pod app/auth/authentik/*.container app/auth/authentik/*.volume; do
                install_quadlet_local "$q"
              done
            elif [ "$idx" -eq 6 ]; then
              for q in app/ai/openwebui/*.pod app/ai/openwebui/*.container app/ai/openwebui/*.volume; do
                install_quadlet_local "$q"
              done
            elif [ "$idx" -eq 7 ]; then
              for q in app/ai/sillytavern/*.pod app/ai/sillytavern/*.container app/ai/sillytavern/*.volume; do
                install_quadlet_local "$q"
              done
            elif [ "$idx" -eq 8 ]; then
              mkdir -p "${CONFIG_BASE_DIR}/searxng"
              for f in settings.yml limiter.toml favicons.toml; do
                [ ! -f "${CONFIG_BASE_DIR}/searxng/$f" ] && cp "app/privacy/searxng/config/$f" "${CONFIG_BASE_DIR}/searxng/"
              done
              for q in app/privacy/searxng/*.pod app/privacy/searxng/*.container app/privacy/searxng/*.volume; do
                install_quadlet_local "$q"
              done
            fi

            systemctl --user daemon-reload
            systemctl --user start "${COMP_UNITS[$idx]}" || true
            echo -e "${GREEN}✓ Installed and started!${NC}"
            read -p "Press Enter to continue..." -r
            break
          fi
        else
          echo "  1) Start service"
          echo "  2) Stop service (with cleanups)"
          echo "  3) Restart service"
          echo "  4) View logs (last 50 lines)"
          echo "  5) Clean Uninstall / Remove"
          echo "  b) Back to List"
          echo -e "${BLUE}===================================================${NC}"
          echo -n "Select option: "
          read -r subopt
          
          if [[ "$subopt" == "b" ]]; then
            break
          fi
          
          local unit="${COMP_UNITS[$idx]}"
          
          case "$subopt" in
            1)
              echo -e "\n${GREEN}→ Starting $unit...${NC}"
              systemctl --user start "$unit"
              echo -e "${GREEN}✓ Start command sent.${NC}"
              read -p "Press Enter to continue..." -r
              ;;
            2)
              echo -e "\n${RED}→ Stopping $unit...${NC}"
              clean_service_state "$idx"
              echo -e "${GREEN}✓ Stopped and cleared successfully.${NC}"
              read -p "Press Enter to continue..." -r
              ;;
            3)
              echo -e "\n${YELLOW}→ Restarting $unit (with cleanups)...${NC}"
              systemctl --user stop "$unit" || true
              clean_service_state "$idx"
              systemctl --user start "$unit"
              echo -e "${GREEN}✓ Restart completed.${NC}"
              read -p "Press Enter to continue..." -r
              ;;
            4)
              echo -e "\n${CYAN}→ Displaying logs for $unit:${NC}\n"
              journalctl --user -u "$unit" -n 50 --no-pager || true
              echo ""
              read -p "Press Enter to continue..." -r
              ;;
            5)
              echo -e "\n${RED}→ Uninstalling ${COMPONENTS[$idx]}...${NC}"
              echo -n "Are you sure you want to remove this service? (y/N): "
              read -r confirm
              if [[ "$confirm" =~ ^[yY](es)?$ ]]; then
                clean_service_state "$idx"
                
                # Delete symlinks
                local files=(${COMP_FILES[$idx]})
                for file in "${files[@]}"; do
                  rm -f "${SYSTEMD_USER_DIR}/${file}"
                done
                
                systemctl --user daemon-reload
                
                # Option to purge config
                local config_folder="${COMP_CONFIGS[$idx]}"
                if [ -n "$config_folder" ]; then
                  local full_path="${CONFIG_BASE_DIR}/${config_folder}"
                  if [ -d "$full_path" ]; then
                    echo -n "Would you also like to delete local configuration folder ~/config/$config_folder? (y/N): "
                    read -r delete_dir
                    if [[ "$delete_dir" =~ ^[yY](es)?$ ]]; then
                      rm -rf "$full_path"
                      echo "  Deleted configuration directory."
                    fi
                  fi
                fi
                
                echo -e "${GREEN}✓ Service uninstalled successfully!${NC}"
                read -p "Press Enter to continue..." -r
                break
              else
                echo "Uninstall cancelled."
                read -p "Press Enter to continue..." -r
              fi
              ;;
            *)
              echo "Invalid option."
              sleep 1
              ;;
          esac
        fi
      done
    else
      echo "Invalid option."
      sleep 1
    fi
  done
}
