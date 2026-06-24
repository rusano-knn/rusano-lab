# TUI and UI components for rusano-lab
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab

# Function to run an interactive multi-selection menu
# Arguments:
#   $1: name of choices array (nameref)
#   $2: action ("install" or "remove")
run_selector() {
  local -n __choices_ref="$1"
  local action="$2"
  local num_items=${#COMPONENTS[@]}
  local page_size=10
  local total_pages=$(( (num_items + page_size - 1) / page_size ))
  local current_page=0

  while true; do
    clear
    local title="rusano-lab Quadlet Installer Selector"
    local theme_color="$GREEN"
    if [[ "$action" == "remove" ]]; then
      title="rusano-lab Quadlet Removal Selector"
      theme_color="$RED"
    fi

    echo -e "${BLUE}===================================================${NC}"
    echo -e "${theme_color}      ${title}       ${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo "Toggle services using their numbers, or use the commands below:"
    
    local start_idx=$((current_page * page_size))
    local end_idx=$((start_idx + page_size - 1))
    if [ "$end_idx" -ge "$num_items" ]; then
      end_idx=$((num_items - 1))
    fi

    local last_cat=""
    for (( i=start_idx; i<=end_idx; i++ )); do
      local cat="${COMP_CATEGORIES[$i]}"
      if [[ "$cat" != "$last_cat" ]]; then
        echo -e "\n  ${CYAN}[$cat]${NC}"
        last_cat="$cat"
      fi

      local local_idx=$((i - start_idx))
      local checkbox="[ ]"
      if [ "${__choices_ref[$i]}" -eq 1 ]; then
        checkbox="[x]"
      fi

      # Detect dynamic status
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

      if [[ "$action" == "remove" ]]; then
        # For removal, mark if not installed
        if [[ "$status_str" == "Not Installed" ]]; then
          echo -e "    ${local_idx}) ${YELLOW}[Not Installed]${NC} ${COMPONENTS[$i]}"
        else
          echo -e "    ${local_idx}) ${theme_color}${checkbox}${NC} [${status_color}${status_str}${NC}] ${COMPONENTS[$i]}"
        fi
      else
        echo -e "    ${local_idx}) ${theme_color}${checkbox}${NC} [${status_color}${status_str}${NC}] ${COMPONENTS[$i]}"
      fi
    done

    echo -e "\n${BLUE}---------------------------------------------------${NC}"
    echo -e " Page $((current_page + 1))/${total_pages}   (Use ${CYAN}Left/Right Arrow${NC} keys to change pages)"
    echo -e " Commands:  ${CYAN}[0-9]${NC} Toggle item  ·  ${CYAN}[a]${NC} Select All  ·  ${CYAN}[n]${NC} Select None"
    echo -e "            ${CYAN}[q]${NC} Quit         ·  ${CYAN}[Enter]${NC} Confirm and continue"
    echo -e "${BLUE}===================================================${NC}"
    echo -n "Action: "

    # Read exactly 1 character silently
    local key
    read -s -n 1 key

    # Handle Escape Sequences (Arrow Keys)
    if [[ "$key" == $'\e' ]]; then
      local next_keys
      read -s -n 2 -t 0.1 next_keys || continue
      if [[ "$next_keys" == "[C" ]]; then
        # Right Arrow -> Next Page
        current_page=$(( (current_page + 1) % total_pages ))
      elif [[ "$next_keys" == "[D" ]]; then
        # Left Arrow -> Previous Page
        current_page=$(( (current_page - 1 + total_pages) % total_pages ))
      fi
    # Enter key (empty string)
    elif [[ "$key" == "" ]]; then
      break
    elif [[ "$key" == "q" ]]; then
      echo -e "\nCancelled."
      exit 0
    elif [[ "$key" == "a" ]]; then
      for (( k=0; k<num_items; k++ )); do
        if [[ "$action" == "remove" ]]; then
          # For removal, only select what is actually installed
          local status_str
          status_str=$(get_status "$k")
          if [[ "$status_str" != "Not Installed" ]]; then
            __choices_ref[$k]=1
          else
            __choices_ref[$k]=0
          fi
        else
          __choices_ref[$k]=1
        fi
      done
    elif [[ "$key" == "n" ]]; then
      for (( k=0; k<num_items; k++ )); do
        __choices_ref[$k]=0
      done
    elif [[ "$key" =~ ^[0-9]$ ]]; then
      local pressed_val="$key"
      local target_idx=$((current_page * page_size + pressed_val))
      if [ "$target_idx" -lt "$num_items" ]; then
        if [[ "$action" == "remove" ]]; then
          # If removing, only allow selection of installed apps
          local status_str
          status_str=$(get_status "$target_idx")
          if [[ "$status_str" == "Not Installed" ]]; then
            continue
          fi
        fi
        __choices_ref[$target_idx]=$(( 1 - __choices_ref[$target_idx] ))
      fi
    fi
  done
}
