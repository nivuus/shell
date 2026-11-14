#!/usr/bin/env zsh
# =============================================================================
# Network Tools
# =============================================================================
# Simple, lightweight network utilities
# =============================================================================

# =============================================================================
# IP Address Information
# =============================================================================

# Show public IP address
myip() {
    local ip=$(curl -s https://api.ipify.org 2>/dev/null)
    if [[ -n "$ip" ]]; then
        echo "Public IP: $ip"
    else
        echo "✗ Failed to retrieve public IP"
        return 1
    fi
}

# Show local IP addresses
localip() {
    echo "Local IP addresses:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print "  " $2}'
    else
        # Linux
        hostname -I 2>/dev/null || ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print "  " $2}' | cut -d/ -f1
    fi
}

# =============================================================================
# Port Information
# =============================================================================

# List open ports and processes
ports() {
    echo "Open ports and processes:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sudo lsof -iTCP -sTCP:LISTEN -n -P 2>/dev/null
    else
        # Linux
        if command -v ss &>/dev/null; then
            sudo ss -tulpn 2>/dev/null
        elif command -v netstat &>/dev/null; then
            sudo netstat -tulpn 2>/dev/null
        else
            echo "✗ Neither ss nor netstat found"
            return 1
        fi
    fi
}

# =============================================================================
# Weather
# =============================================================================

# Get weather forecast
weather() {
    local city="${1:-}"

    if [[ -z "$city" ]]; then
        # Use geolocation
        curl -s "https://wttr.in/?format=3"
    else
        # Specific city
        curl -s "https://wttr.in/${city}?format=3"
    fi

    echo ""
    echo "For detailed forecast: weather <city>"
    [[ -n "$city" ]] && echo "Detailed: curl wttr.in/${city}"
}

# Detailed weather
weatherfull() {
    local city="${1:-}"
    curl -s "https://wttr.in/${city}"
}

# =============================================================================
# Network Testing
# =============================================================================

# Ping with count, at a terminal only: a script or an agent shell calling
# `ping` gets ping's own behaviour. `-c` is the count option of every ping
# this shell targets (iputils, BSD/macOS, busybox).
if nivuus_has_terminal; then
    alias ping='ping -c 5'
fi

# Fast speed test (if speedtest-cli is installed)
if command -v speedtest-cli &>/dev/null; then
    alias speedtest='speedtest-cli --simple'
fi

# =============================================================================
# DNS Tools
# =============================================================================

# Quick DNS lookup
dns() {
    if [[ -z "$1" ]]; then
        echo "Usage: dns <domain>"
        return 1
    fi

    echo "DNS records for: $1"
    echo "═══════════════════════════"

    if command -v dig &>/dev/null; then
        dig +short "$1"
    elif command -v nslookup &>/dev/null; then
        nslookup "$1" | grep -A2 "Name:"
    else
        echo "✗ Neither dig nor nslookup found"
        return 1
    fi
}

# =============================================================================
# HTTP Tools
# =============================================================================

# Download file with progress
if command -v wget &>/dev/null; then
    alias download='wget -c'
elif command -v curl &>/dev/null; then
    alias download='curl -O -C -'
fi

# Headers of a URL
headers() {
    if [[ -z "$1" ]]; then
        echo "Usage: headers <url>"
        return 1
    fi

    curl -sI "$1"
}
