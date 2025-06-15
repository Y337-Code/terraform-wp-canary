#!/bin/bash

# Generate Consul Gossip Encryption Key
# This script generates a base64-encoded 32-byte key for Consul gossip encryption
# Usage: ./generate-gossip-key.sh [options]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
OUTPUT_FILE=""
UPDATE_TFVARS=false
QUIET=false

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Generate a Consul gossip encryption key for testing"
    echo ""
    echo "OPTIONS:"
    echo "  -f, --file FILE       Save the key to specified file"
    echo "  -u, --update-tfvars   Update terraform.tfvars with the generated key"
    echo "  -q, --quiet           Only output the key (no additional text)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    Generate and display key"
    echo "  $0 -f gossip.key      Save key to gossip.key file"
    echo "  $0 -u                 Update terraform.tfvars with new key"
    echo "  $0 -q                 Output only the key (for scripting)"
    echo ""
}

# Function to log messages (unless quiet mode)
log() {
    if [ "$QUIET" = false ]; then
        echo -e "$1" >&2
    fi
}

# Function to generate gossip key
generate_key() {
    local key=""
    
    # Try consul keygen first (if consul is available)
    if command -v consul >/dev/null 2>&1; then
        log "${BLUE}Using 'consul keygen' to generate key...${NC}"
        key=$(consul keygen 2>/dev/null || echo "")
    fi
    
    # Fallback to openssl if consul keygen failed or consul not available
    if [ -z "$key" ]; then
        if command -v openssl >/dev/null 2>&1; then
            log "${BLUE}Using 'openssl' to generate key...${NC}"
            key=$(openssl rand -base64 32 2>/dev/null || echo "")
        fi
    fi
    
    # Fallback to /dev/urandom with base64 (most Unix systems)
    if [ -z "$key" ]; then
        if [ -r /dev/urandom ] && command -v base64 >/dev/null 2>&1; then
            log "${BLUE}Using '/dev/urandom' to generate key...${NC}"
            key=$(head -c 32 /dev/urandom | base64 2>/dev/null || echo "")
        fi
    fi
    
    # Final fallback using dd and base64
    if [ -z "$key" ]; then
        if command -v dd >/dev/null 2>&1 && command -v base64 >/dev/null 2>&1; then
            log "${BLUE}Using 'dd' to generate key...${NC}"
            key=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 2>/dev/null || echo "")
        fi
    fi
    
    if [ -z "$key" ]; then
        log "${RED}Error: Unable to generate gossip key. Please ensure one of the following is available:${NC}"
        log "${RED}  - consul binary${NC}"
        log "${RED}  - openssl binary${NC}"
        log "${RED}  - /dev/urandom and base64${NC}"
        exit 1
    fi
    
    # Clean up the key (remove any whitespace/newlines)
    key=$(echo "$key" | tr -d '[:space:]')
    
    # Validate key format (should be base64 and roughly 44 characters for 32 bytes)
    if ! echo "$key" | grep -qE '^[A-Za-z0-9+/]+=*$' || [ ${#key} -lt 40 ]; then
        log "${RED}Error: Generated key appears to be invalid format${NC}"
        exit 1
    fi
    
    echo "$key"
}

# Function to save key to file
save_to_file() {
    local key="$1"
    local file="$2"
    
    echo "$key" > "$file"
    log "${GREEN}Key saved to: $file${NC}"
}

# Function to update terraform.tfvars
update_tfvars() {
    local key="$1"
    local tfvars_file="terraform.tfvars"
    
    if [ ! -f "$tfvars_file" ]; then
        log "${YELLOW}Warning: $tfvars_file not found. Creating new file...${NC}"
        echo "# Terraform variables for WordPress Canary test" > "$tfvars_file"
        echo "" >> "$tfvars_file"
    fi
    
    # Check if shared_gossip_key already exists
    if grep -q "^shared_gossip_key" "$tfvars_file"; then
        # Update existing key - use safer approach without sed
        grep -v "^shared_gossip_key" "$tfvars_file" > "${tfvars_file}.tmp"
        echo "shared_gossip_key = \"$key\"" >> "${tfvars_file}.tmp"
        mv "${tfvars_file}.tmp" "$tfvars_file"
        log "${GREEN}Updated shared_gossip_key in $tfvars_file${NC}"
    else
        # Add new key
        echo "shared_gossip_key = \"$key\"" >> "$tfvars_file"
        log "${GREEN}Added shared_gossip_key to $tfvars_file${NC}"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -u|--update-tfvars)
            UPDATE_TFVARS=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    if [ "$QUIET" = false ]; then
        log "${BLUE}=== Consul Gossip Key Generator ===${NC}"
        log ""
    fi
    
    # Generate the key
    local gossip_key
    gossip_key=$(generate_key)
    
    if [ "$QUIET" = false ]; then
        log "${GREEN}Generated gossip key:${NC}"
        echo "$gossip_key"
    else
        echo "$gossip_key"
    fi
    
    # Save to file if requested
    if [ -n "$OUTPUT_FILE" ]; then
        save_to_file "$gossip_key" "$OUTPUT_FILE"
    fi
    
    # Update terraform.tfvars if requested
    if [ "$UPDATE_TFVARS" = true ]; then
        update_tfvars "$gossip_key"
    fi
    
    if [ "$QUIET" = false ]; then
        log ""
        log "${YELLOW}Usage Notes:${NC}"
        log "- Use this key for the 'shared_gossip_key' variable in terraform.tfvars"
        log "- The same key must be used across all Consul datacenters for WAN federation"
        log "- Keep this key secure and treat it as a secret"
        log ""
        log "${BLUE}Example terraform.tfvars entry:${NC}"
        log "shared_gossip_key = \"$gossip_key\""
    fi
}

# Run main function
main
