#!/bin/bash
# Network isolation script for gastown sandbox
# This script configures iptables to restrict network access

set -e

# Configuration via environment variables
SANDBOX_MODE="${SANDBOX_MODE:-strict}"  # strict, permissive, or disabled
ALLOWED_HOSTS="${ALLOWED_HOSTS:-}"       # Comma-separated list of allowed hosts/IPs
ALLOW_DNS="${ALLOW_DNS:-true}"           # Allow DNS lookups
ALLOW_LOCALHOST="${ALLOW_LOCALHOST:-true}"  # Allow localhost traffic
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"    # Port for inbound dashboard access

log() {
    echo "[network-sandbox] $1"
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
        IFS=',' read -ra HOSTS <<< "$ALLOWED_HOSTS"
        for host in "${HOSTS[@]}"; do
            host=$(echo "$host" | xargs)  # trim whitespace
            if [[ -n "$host" ]]; then
                # Resolve hostname to IP if needed
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
            fi
        done
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
    *)
        log "Unknown SANDBOX_MODE: $SANDBOX_MODE (using strict)"
        setup_strict_isolation
        ;;
esac

# Drop privileges and execute the original command as node user
exec sudo -u node "$@"
