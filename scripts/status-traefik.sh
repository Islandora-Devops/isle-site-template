#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

print_traefik_make_helpers() {
    printf "\tThere are some make commands you can run to get traefik configured correctly\n"
    make help | grep traefik | sed 's/^/\t/'
    echo
}

echo_e "${BLUE}--- Traefik Status ---${RESET}"

# --- Port Binding ---
echo ""
HTTP_PORT=$(find_port 80)
HTTPS_PORT=$(find_port 443)
echo_e "HTTP port: ${GREEN}${HTTP_PORT}${RESET}"
echo_e "HTTPS port: ${GREEN}${HTTPS_PORT}${RESET}"
if is_using_non_standard_ports; then
    echo_e "(${BLUE}Default ports 80/443 were occupied, so the next available ports were chosen.${RESET})"
fi

echo_e "DOMAIN: ${GREEN}${DOMAIN}${RESET}"
echo_e "URL: ${GREEN}${URI_SCHEME}://${DOMAIN}${RESET}"
echo_e "TLS_PROVIDER: ${GREEN}${TLS_PROVIDER}${RESET}"
if is_acme_enabled; then
    color=$GREEN
    if is_acme_using_default_email; then
      color=$RED
    fi
    echo_e "ACME_EMAIL: ${color}${ACME_EMAIL}${RESET}"
fi

# Check 1: Traefik Container Status
if ! docker compose ps traefik | grep -q "traefik"; then
    echo_e "${RED}Traefik container is not running.${RESET}"
else
    TRAEFIK_STATUS=
    if command -v jq &> /dev/null; then
      HEALTH=$(docker compose ps traefik --format=json | jq -r .Health)
      color=$RED
      if [ "$HEALTH" = "healthy" ]; then
        color=$GREEN
      fi
      TRAEFIK_STATUS=" and ${color}healthy${RESET}"
    fi
    echo_e "${GREEN}Traefik container is running${RESET}${TRAEFIK_STATUS}"

fi

# Check 2: DNS Resolution
RESOLVED_IP="not_found"
if command -v dig &> /dev/null; then
    RESOLVED_IP=$(dig +short "$DOMAIN" | tail -n1)
elif command -v nslookup &> /dev/null; then
    RESOLVED_IP=$(nslookup "$DOMAIN" | awk '/^Address: / { print $2 }' | tail -n1)
fi

if [ -z "$RESOLVED_IP" ]; then
    RESOLVED_IP="not_found"
fi

if [ "$RESOLVED_IP" = "not_found" ]; then
    echo_e "${RED}Domain: Could not resolve domain '$DOMAIN'.${RESET}"
else
    echo_e "Domain ${BLUE}$DOMAIN${RESET} resolves to: ${GREEN}${RESOLVED_IP}${RESET}"
fi

if is_dev_mode && [ "$RESOLVED_IP" != "127.0.0.1" ] && [ "$RESOLVED_IP" != "not_found" ]; then
    echo_e "\t${YELLOW}DNS Mismatch${RESET}: ${RED}DEVELOPMENT_ENVIRONMENT=true${RESET}, but ${RED}DOMAIN=$DOMAIN${RESET} does not resolve to 127.0.0.1"
    echo_e "\tThis is expected if you are developing on a remote VM."
    echo_e "\tIf this is a local setup, your DNS or DOMAIN may be misconfigured\n"
fi

if is_prod_mode && [ "$RESOLVED_IP" = "127.0.0.1" ]; then
    print_warning_header
    echo_e "\t${YELLOW}DNS Misconfiguration${RESET}: ${RED}DEVELOPMENT_ENVIRONMENT=false${RESET}, but ${RED}DOMAIN=$DOMAIN${RESET} resolves to 127.0.0.1"
    echo_e "\tProduction environments should not use localhost/127.0.0.1."
    echo_e "\tUpdate DOMAIN in .env to your actual production domain name\n"
fi

# Check 1: Mismatched HTTPS/URI Scheme
if is_tls_http_uri_mismatch; then
    print_warning_header
    echo_e "\t${YELLOW}Mismatched Configuration${RESET}: ENABLE_HTTPS=${RED}true${RESET}, but URI_SCHEME=${RED}http${RESET}"
    print_traefik_make_helpers
fi

if is_http_tls_uri_mismatch; then
    print_warning_header
    echo_e "\t${YELLOW}Mismatched Configuration${RESET}: ENABLE_HTTPS=${RED}false${RESET}, but URI_SCHEME=${RED}https${RESET}"
    print_traefik_make_helpers
fi

# Check 2: ACME in Development
if is_dev_mode && is_https_enabled && is_acme_enabled; then
    print_warning_header
    echo_e "\t${YELLOW}Insecure Configuration${RESET}: DEVELOPMENT_ENVIRONMENT=${RED}true${RESET} and TLS_PROVIDER=${RED}letsencrypt${RESET}"
    echo_e "\tThis is unusual for local development unless you are on a remote VM"
    echo_e "\tYou should not set DEVELOPMENT_ENVIRONMENT=true on production VMs to ensure the container filesystem is read only\n"
fi

# Check 3: HTTP in Production
if is_prod_mode && ! is_https_enabled; then
    print_warning_header
    echo_e "\t${YELLOW}Insecure Configuration: You are in production mode with traffic accepted over HTTP${RESET}"
    echo_e "\tThis should only be done if ISLE is behind a secure reverse proxy."
    echo_e "\tTo configure a reverse proxy, set REVERSE_PROXY=on and define FRONTEND_IP variables in your .env file."
    echo_e "\tThe network between your site and the frontend should be encrypted in transit.\n"
fi

# --- Helper Text Logic ---
if is_prod_mode && is_https_enabled; then
    if is_acme_enabled; then
        if is_acme_using_default_email; then
            print_warning_header
            echo_e "\t${YELLOW}Bad default setting{$RESET}: ${RED}ACME_EMAIL=postmaster@example.com${RESET}"
            echo_e "\tUpdate it to a real email for certificate issuance\n"
        fi
    else
        print_warning_header
        echo_e "\t${YELLOW}ACME is disabled${RESET} To get valid certificates, you should either:"
        echo_e "\t1. Enable ACME (make traefik-https-letsencrypt) and configure ACME_EMAIL in .env"
        echo_e "\t2. Place your public (cert.pem) and private (privkey.pem) certificates in the ./certs/ directory and set TLS_PROVIDER=self-managed in .env"
    fi
fi

# Check 4: Certificate validation
if is_https_enabled && [ -f certs/cert.pem ]; then
    if command -v openssl &> /dev/null; then
        # Check certificate expiration
        if ! openssl x509 -noout -checkend 0 -in certs/cert.pem &>/dev/null; then
            print_warning_header
            echo_e "\t${RED}Certificate Expired${RESET}: The SSL certificate in certs/cert.pem has expired"
            EXPIRY_DATE=$(openssl x509 -noout -enddate -in certs/cert.pem 2>/dev/null | cut -d= -f2)
            echo_e "\tExpired on: $EXPIRY_DATE"
            echo_e "\tRegenerate the certificate or obtain a new one.\n"
        elif ! openssl x509 -noout -checkend 604800 -in certs/cert.pem &>/dev/null; then
            # Certificate expires within 7 days (604800 seconds)
            print_warning_header
            EXPIRY_DATE=$(openssl x509 -noout -enddate -in certs/cert.pem 2>/dev/null | cut -d= -f2)
            echo_e "\t${YELLOW}Certificate Expiring Soon${RESET}: The SSL certificate will expire within 7 days"
            echo_e "\tExpires on: $EXPIRY_DATE"
            echo_e "\tConsider renewing the certificate soon.\n"
        fi

        # Extract SANs from certificate
        CERT_SANS=$(openssl x509 -noout -text -in certs/cert.pem 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -n1 || echo "")

        if [ -n "$CERT_SANS" ]; then
            # Check if DOMAIN appears in the SANs (accounting for DNS: prefix)
            if ! echo "$CERT_SANS" | grep -q "DNS:$DOMAIN" && ! echo "$CERT_SANS" | grep -q " $DOMAIN"; then
                print_warning_header
                echo_e "\t${YELLOW}Certificate Domain Mismatch${RESET}: ${RED}DOMAIN=$DOMAIN${RESET} is not in certificate SANs"
                echo_e "\tCertificate is valid for: ${CERT_SANS//DNS:/}"
                echo_e "\tEither update DOMAIN in .env to match the certificate, or regenerate the certificate.\n"
            fi
        fi
    fi
fi

echo
