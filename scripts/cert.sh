#!/bin/bash
# Certificate generator for Technitium DNS Server
# Managed by rusano-cloudlab
# Source: https://github.com/rusano-knn/rusano-lab
# Version: 1.0.0
# Updated: 2026-06-25

# Ensure variables from common.sh are available if run directly
if [ -z "${BLUE:-}" ]; then
  # Find script directory
  CERT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${CERT_SCRIPT_DIR}/common.sh"
fi

run_cert_action() {
  clear
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${GREEN}      Technitium DNS ACME Certificate Generator    ${NC}"
  echo -e "${BLUE}===================================================${NC}"
  echo -e "This utility will request or renew an SSL/TLS certificate"
  echo -e "using the Let's Encrypt ACME DNS-01 challenge via Cloudflare,"
  echo -e "convert it to PFX format, copy it to the Technitium volume,"
  echo -e "and clean up any pulled container images when finished."
  echo -e "${BLUE}===================================================${NC}"
  echo ""

  # Prompt for Email
  echo -n "Enter your Let's Encrypt Account Email: "
  read -r acme_email
  if [ -z "$acme_email" ]; then
    echo -e "${RED}Error: Email cannot be empty.${NC}"
    read -p "Press Enter to return..." -r || true
    return 1
  fi

  # Prompt for Domain
  echo -n "Enter your Technitium DNS Domain (e.g., dns.example.com): "
  read -r acme_domain
  if [ -z "$acme_domain" ]; then
    echo -e "${RED}Error: Domain cannot be empty.${NC}"
    read -p "Press Enter to return..." -r || true
    return 1
  fi

  # Prompt for Cloudflare Token
  echo -n "Enter your Cloudflare DNS API Token: "
  read -rs acme_cf_token
  echo ""
  if [ -z "$acme_cf_token" ]; then
    echo -e "${RED}Error: Cloudflare Token cannot be empty.${NC}"
    read -p "Press Enter to return..." -r || true
    return 1
  fi

  # Prompt for PFX Password
  echo -n "Enter PFX Password (for importing into Technitium): "
  read -rs pfx_password
  echo ""
  if [ -z "$pfx_password" ]; then
    echo -e "${RED}Error: PFX password cannot be empty.${NC}"
    read -p "Press Enter to return..." -r || true
    return 1
  fi

  echo -e "\n${BLUE}→ Validating Podman installation and network...${NC}"
  if ! command -v podman &>/dev/null; then
    echo -e "${RED}Error: Podman command not found.${NC}"
    read -p "Press Enter to return..." -r || true
    return 1
  fi

  # Ensure technitium-config volume exists
  if ! podman volume inspect technitium-config &>/dev/null; then
    echo -e "${RED}Error: Technitium volume 'technitium-config' does not exist.${NC}"
    echo -e "Please install the Technitium DNS service first.${NC}"
    read -p "Press Enter to return..." -r || true
    return 1
  fi

  echo -e "\n${BLUE}→ Running Let's Encrypt ACME DNS-01 challenge via lego...${NC}"

  # Run lego run (lego v5+ automatically handles both generation and renewal)
  if ! podman run --rm \
    -v technitium-config:/etc/dns:Z \
    -e CF_DNS_API_TOKEN="$acme_cf_token" \
    docker.io/goacme/lego:latest \
    run \
    --email "$acme_email" \
    --dns cloudflare \
    --domains "$acme_domain" \
    --path "/etc/dns/certs/lego" \
    --accept-tos \
    --dns.resolvers "1.1.1.1:53" \
    --dns.resolvers "1.0.0.1:53"; then
      echo -e "${RED}Error: Certificate generation/renewal failed. Please check your token and inputs.${NC}"
      # Cleanup pulled images on failure
      echo -e "${BLUE}→ Cleaning up pulled images...${NC}"
      podman rmi docker.io/goacme/lego:latest 2>/dev/null || true
      read -p "Press Enter to return..." -r || true
      return 1
  fi

  echo -e "\n${BLUE}→ Converting PEM certificate to PFX format...${NC}"
  if ! podman run --rm \
    -v technitium-config:/etc/dns:Z \
    docker.io/library/alpine:latest \
    sh -c 'apk add --no-cache openssl && mkdir -p /etc/dns/certs && openssl pkcs12 -export -out /etc/dns/certs/dns.pfx -inkey /etc/dns/certs/lego/certificates/'"$acme_domain"'.key -in /etc/dns/certs/lego/certificates/'"$acme_domain"'.crt -certfile /etc/dns/certs/lego/certificates/'"$acme_domain"'.issuer.crt -passout pass:"'"$pfx_password"'" && chmod 600 /etc/dns/certs/dns.pfx'; then
      echo -e "${RED}Error: Failed to convert certificate to PFX.${NC}"
      # Cleanup pulled images on failure
      echo -e "${BLUE}→ Cleaning up pulled images...${NC}"
      podman rmi docker.io/goacme/lego:latest docker.io/library/alpine:latest 2>/dev/null || true
      read -p "Press Enter to return..." -r || true
      return 1
  fi

  # Post-execution image cleanup
  echo -e "\n${BLUE}→ Cleaning up downloaded container images...${NC}"
  podman rmi docker.io/goacme/lego:latest docker.io/library/alpine:latest 2>/dev/null || true
  echo -e "${GREEN}✓ Local system cleaned of temporary images.${NC}"

  echo -e "\n${GREEN}✓ Certificate successfully created and updated in the Technitium volume!${NC}"
  echo -e "File inside container: ${YELLOW}/etc/dns/certs/dns.pfx${NC}"
  echo -e "File password:        ${YELLOW}(your chosen password)${NC}"
  echo ""
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${CYAN}What you need to do next in the Technitium Web Console:${NC}"
  echo -e "  1. Log into your Web Console (normally at http://127.100.100.100:5380)"
  echo -e "  2. Go to Settings -> Web Service"
  echo -e "  3. Set TLS Certificate File Path to /etc/dns/certs/dns.pfx"
  echo -e "  4. Set TLS Certificate Password to the password you entered above"
  echo -e "  5. Save settings (Technitium will load and apply it automatically)"
  echo -e "${BLUE}===================================================${NC}"

  # Optionally check if Technitium container is running and prompt to restart it
  if systemctl --user is-active --quiet technitium-pod.service 2>/dev/null; then
    echo -e "\nTechnitium is currently running."
    echo -n "Would you like to restart Technitium to force immediate application of the cert? (y/N): "
    read -r restart_tech
    if [[ "$restart_tech" =~ ^[yY](es)?$ ]]; then
      echo -e "${BLUE}→ Restarting Technitium service...${NC}"
      systemctl --user restart technitium-pod.service
      echo -e "${GREEN}✓ Technitium service restarted.${NC}"
    fi
  fi

  read -p "Press Enter to continue..." -r || true
}
