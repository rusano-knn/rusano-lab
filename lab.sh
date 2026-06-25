#!/usr/bin/env bash
# rusano-lab Service Control Manager
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab
# Version: 1.0.0
# Updated: 2026-06-24

set -euo pipefail

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/scripts/common.sh"
source "${SCRIPT_DIR}/scripts/ui.sh"

show_utilities_menu() {
  while true; do
    clear
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${BLUE}            rusano-lab Utilities Menu              ${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo "Select a utility action to perform:"
    echo ""
    echo "  1) Generate/Renew Technitium TLS Certificate"
    echo ""
    echo "  b) Back to Main Menu"
    echo -e "${BLUE}===================================================${NC}"
    echo -n "Select option: "
    read -r util_opt

    case "$util_opt" in
      1)
        source "${SCRIPT_DIR}/scripts/cert.sh"
        run_cert_action
        ;;
      b|[bB])
        break
        ;;
      *)
        echo "Invalid option."
        sleep 1
        ;;
    esac
  done
}

show_main_menu() {
  clear
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${BLUE}            rusano-lab Control Panel               ${NC}"
  echo -e "${BLUE}===================================================${NC}"
  echo "Select an action to perform:"
  echo ""
  echo "  1) Install Services"
  echo "  2) Manage Services (Start/Stop/Restart/Logs)"
  echo "  3) Update Configuration Links & Reload"
  echo "  4) Uninstall Services"
  echo "  5) Utilities (Certificate Management, etc.)"
  echo ""
  echo "  q) Quit"
  echo -e "${BLUE}===================================================${NC}"
  echo -n "Select option: "
  read -r action_opt

  case "$action_opt" in
    1)
      source "${SCRIPT_DIR}/scripts/install.sh"
      run_install_action
      ;;
    2)
      source "${SCRIPT_DIR}/scripts/manage.sh"
      run_manage_action
      ;;
    3)
      source "${SCRIPT_DIR}/scripts/update.sh"
      run_update_action
      ;;
    4)
      source "${SCRIPT_DIR}/scripts/remove.sh"
      run_remove_action
      ;;
    5)
      show_utilities_menu
      ;;
    q|[qQ])
      echo "Goodbye."
      exit 0
      ;;
    *)
      echo "Invalid option."
      sleep 1
      ;;
  esac
}

# Main routing
action="${1:-""}"

if [ -z "$action" ]; then
  # Interactive mode if no argument is provided
  while true; do
    show_main_menu
    echo ""
    read -p "Press Enter to return to Main Menu..." -r || true
  done
else
  # Direct argument routing
  case "$action" in
    install)
      source "${SCRIPT_DIR}/scripts/install.sh"
      run_install_action
      ;;
    remove|uninstall)
      source "${SCRIPT_DIR}/scripts/remove.sh"
      run_remove_action
      ;;
    manage)
      source "${SCRIPT_DIR}/scripts/manage.sh"
      run_manage_action
      ;;
    update)
      source "${SCRIPT_DIR}/scripts/update.sh"
      run_update_action
      ;;
    cert)
      source "${SCRIPT_DIR}/scripts/cert.sh"
      run_cert_action
      ;;
    utilities)
      subaction="${2:-""}"
      if [ "$subaction" = "cert" ]; then
        source "${SCRIPT_DIR}/scripts/cert.sh"
        run_cert_action
      else
        show_utilities_menu
      fi
      ;;
    *)
      echo "Unknown action: $action"
      echo "Usage: $0 [install|remove|manage|update|cert|utilities]"
      exit 1
      ;;
  esac
fi
