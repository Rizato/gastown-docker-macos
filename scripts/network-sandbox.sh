#!/bin/bash
# Network isolation script for gastown sandbox
# This script configures iptables/ip6tables to restrict network access

set -e

# Configuration via environment variables
SANDBOX_MODE="${SANDBOX_MODE:-strict}"
ALLOWED_HOSTS="${ALLOWED_HOSTS:-}"
ALLOW_DNS="${ALLOW_DNS:-true}"
ALLOW_LOCALHOST="${ALLOW_LOCALHOST:-true}"
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"

log() {
    echo "[network-sandbox] $1"
}

error() {
    echo "[network-sandbox] ERROR: $1" >&2
}

# Input validation functions
validate_sandbox_mode() {
    case "$SANDBOX_MODE" in
        strict|permissive|disabled)
            return 0
            ;;
        *)
            error "Invalid SANDBOX_MODE: '$SANDBOX_MODE'. Must be 'strict', 'permissive', or 'disabled'"
            exit 1
            ;;
    esac
}

validate_boolean() {
    local name="$1"
    local value="$2"
    case "$value" in
        true|false)
            return 0
            ;;
        *)
            error "Invalid $name: '$value'. Must be 'true' or 'false'"
            exit 1
            ;;
    esac
}

validate_port() {
    local name="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        error "Invalid $name: '$value'. Must be a port number between 1 and 65535"
        exit 1
    fi
}

# Validate hostname/IP - only allow safe characters
validate_host() {
    local host="$1"
    # Allow: alphanumeric, dots, hyphens, and CIDR notation (/)
    # Reject: shell metacharacters, spaces, quotes, semicolons, etc.
    if [[ ! "$host" =~ ^[a-zA-Z0-9.\-/]+$ ]]; then
        error "Invalid hostname/IP: '$host'. Contains disallowed characters"
        return 1
    fi
    # Additional check: must not start/end with dot or hyphen
    if [[ "$host" =~ ^[.\-] ]] || [[ "$host" =~ [.\-]$ ]]; then
        error "Invalid hostname/IP: '$host'. Cannot start/end with dot or hyphen"
        return 1
    fi
    return 0
}

# Validate all inputs before proceeding
validate_inputs() {
    log "Validating configuration..."
    validate_sandbox_mode
    validate_boolean "ALLOW_DNS" "$ALLOW_DNS"
    validate_boolean "ALLOW_LOCALHOST" "$ALLOW_LOCALHOST"
    validate_port "DASHBOARD_PORT" "$DASHBOARD_PORT"
    log "Configuration validated"
}

setup_ipv6_blocking() {
    log "Blocking all IPv6 traffic..."

    # Check if ip6tables is available
    if ! command -v ip6tables &> /dev/null; then
        log "Warning: ip6tables not available, IPv6 may not be blocked"
        return
    fi

    # Flush existing IPv6 rules
    ip6tables -F OUTPUT 2>/dev/null || true
    ip6tables -F INPUT 2>/dev/null || true

    # Allow localhost IPv6 if enabled
    if [[ "$ALLOW_LOCALHOST" == "true" ]]; then
        ip6tables -A OUTPUT -o lo -j ACCEPT
        ip6tables -A INPUT -i lo -j ACCEPT
    fi

    # Drop all other IPv6 traffic
    ip6tables -P INPUT DROP 2>/dev/null || ip6tables -A INPUT -j DROP
    ip6tables -P OUTPUT DROP 2>/dev/null || ip6tables -A OUTPUT -j DROP
    ip6tables -P FORWARD DROP 2>/dev/null || true

    log "IPv6 traffic blocked"
}

setup_strict_isolation() {
    log "Setting up strict network isolation..."

    # Flush existing rules
    iptables -F OUTPUT 2>/dev/null || true
    iptables -F INPUT 2>/dev/null || true

    # Allow established connections
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow localhost if enabled
    if [[ "$ALLOW_LOCALHOST" == "true" ]]; then
        iptables -A OUTPUT -o lo -j ACCEPT
        iptables -A INPUT -i lo -j ACCEPT
        log "Localhost traffic allowed"
    fi

    # Allow inbound connections on dashboard port (for Docker port forwarding)
    if [[ -n "$DASHBOARD_PORT" ]]; then
        iptables -A INPUT -p tcp --dport "$DASHBOARD_PORT" -j ACCEPT
        log "Inbound traffic allowed on port $DASHBOARD_PORT"
    fi

    # Allow DNS if enabled (UDP and TCP port 53)
    if [[ "$ALLOW_DNS" == "true" ]]; then
        iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
        iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
        log "DNS traffic allowed"
    fi

    # Allow specific hosts if configured
    if [[ -n "$ALLOWED_HOSTS" ]]; then
        # Use read with delimiter, avoiding xargs
        while IFS=',' read -ra HOSTS; do
            for host in "${HOSTS[@]}"; do
                # Trim whitespace using parameter expansion (safe, no external commands)
                host="${host#"${host%%[![:space:]]*}"}"
                host="${host%"${host##*[![:space:]]}"}"

                if [[ -z "$host" ]]; then
                    continue
                fi

                # Validate the host before using it
                if ! validate_host "$host"; then
                    log "Skipping invalid host: $host"
                    continue
                fi

                # Check if it's an IP address or CIDR
                if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
                    iptables -A OUTPUT -d "$host" -j ACCEPT
                    log "Allowed IP: $host"
                else
                    # It's a hostname, resolve it
                    resolved_ips=$(dig +short "$host" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
                    if [[ -n "$resolved_ips" ]]; then
                        while IFS= read -r ip; do
                            iptables -A OUTPUT -d "$ip" -j ACCEPT
                            log "Allowed host $host resolved to: $ip"
                        done <<< "$resolved_ips"
                    else
                        log "Warning: Could not resolve hostname: $host"
                    fi
                fi
            done
        done <<< "$ALLOWED_HOSTS"
    fi

    # Drop all other traffic
    iptables -A INPUT -j DROP
    iptables -A OUTPUT -j DROP

    log "Strict network isolation enabled - only whitelisted traffic allowed"
}

setup_permissive_isolation() {
    log "Setting up permissive network isolation..."

    # Flush existing rules
    iptables -F OUTPUT 2>/dev/null || true

    # Block common dangerous ports but allow most traffic
    # Block SMTP (spam prevention)
    iptables -A OUTPUT -p tcp --dport 25 -j DROP
    iptables -A OUTPUT -p tcp --dport 465 -j DROP
    iptables -A OUTPUT -p tcp --dport 587 -j DROP

    # Block SSH outbound (prevent lateral movement)
    iptables -A OUTPUT -p tcp --dport 22 -j DROP

    # Block common database ports
    iptables -A OUTPUT -p tcp --dport 3306 -j DROP   # MySQL
    iptables -A OUTPUT -p tcp --dport 5432 -j DROP   # PostgreSQL
    iptables -A OUTPUT -p tcp --dport 27017 -j DROP  # MongoDB
    iptables -A OUTPUT -p tcp --dport 6379 -j DROP   # Redis

    log "Permissive network isolation enabled - dangerous ports blocked"
}

# Main execution
validate_inputs

# Always block IPv6 unless disabled
if [[ "$SANDBOX_MODE" != "disabled" ]]; then
    setup_ipv6_blocking
fi

case "$SANDBOX_MODE" in
    strict)
        setup_strict_isolation
        ;;
    permissive)
        setup_permissive_isolation
        ;;
    disabled)
        log "Network isolation disabled"
        ;;
esac

# Configure git credentials for node user if GITHUB_TOKEN is present
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    sudo -u node git config --global credential.helper /usr/local/bin/git-credential-github-token
    log "Git credential helper configured for GitHub"
else
    log "Warning: GITHUB_TOKEN not set, git push/pull to GitHub will not work"
fi

# Drop privileges and execute the original command as node user
exec sudo -u node "$@"
