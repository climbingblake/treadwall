#!/bin/bash
################################################################################
# TreadWall WiFi Configuration Script
#
# This script configures the Raspberry Pi to connect to a home WiFi network
# while maintaining the Access Point (AP) mode for direct connection.
#
# Usage: ./scripts/configure_wifi.sh "SSID" "PASSWORD"
################################################################################

set -e  # Exit on error

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    exit 1
fi

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 \"SSID\" \"PASSWORD\""
    exit 1
fi

SSID="$1"
PASSWORD="$2"

# Validate inputs
if [ -z "$SSID" ]; then
    echo "Error: SSID cannot be empty"
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    echo "Error: Password cannot be empty"
    exit 1
fi

echo "Configuring WiFi for SSID: $SSID"

# Path to wpa_supplicant configuration
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
WPA_BACKUP="/etc/wpa_supplicant/wpa_supplicant.conf.backup"

# Create wpa_supplicant.conf if it doesn't exist
if [ ! -f "$WPA_CONF" ]; then
    echo "Creating new wpa_supplicant.conf..."
    mkdir -p /etc/wpa_supplicant
    cat > "$WPA_CONF" <<'WPAEOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

WPAEOF
    echo "✓ Created wpa_supplicant.conf"
fi

# Create backup if it doesn't exist
if [ ! -f "$WPA_BACKUP" ]; then
    echo "Creating backup of wpa_supplicant.conf..."
    cp "$WPA_CONF" "$WPA_BACKUP"
fi

# Generate PSK hash for the password (more secure than plain text)
PSK=$(wpa_passphrase "$SSID" "$PASSWORD" | grep -v '#psk' | grep 'psk=' | cut -d'=' -f2)

if [ -z "$PSK" ]; then
    echo "Error: Failed to generate PSK"
    exit 1
fi

# Check if this SSID already exists in the config
if grep -q "ssid=\"$SSID\"" "$WPA_CONF"; then
    echo "SSID already configured. Updating password..."

    # Remove existing network block for this SSID
    # This is complex, so we'll regenerate the entire config

    # Extract the header (country code, etc.)
    HEADER=$(sed -n '1,/^network=/p' "$WPA_CONF" | sed '$d')

    # Remove all network blocks with this SSID
    awk -v ssid="$SSID" '
        BEGIN { in_block=0; skip=0 }
        /^network=/ { in_block=1; skip=0; buffer=$0"\n"; next }
        in_block {
            buffer=buffer$0"\n"
            if (/ssid=/) {
                if ($0 ~ "ssid=\""ssid"\"") {
                    skip=1
                }
            }
            if (/^}/) {
                in_block=0
                if (!skip) {
                    printf "%s", buffer
                }
                buffer=""
            }
            next
        }
        !in_block { print }
    ' "$WPA_CONF" > "${WPA_CONF}.tmp"

    # Use the cleaned config
    cat "${WPA_CONF}.tmp" > "$WPA_CONF"
    rm "${WPA_CONF}.tmp"
fi

# Append new network configuration
cat >> "$WPA_CONF" <<EOF

# Home network configuration - Added by CRIMP
# $(date)
network={
    ssid="$SSID"
    psk=$PSK
    key_mgmt=WPA-PSK
    priority=10
}
EOF

echo "✓ WiFi configuration updated"

# Reconfigure wpa_supplicant to pick up the new settings
echo "Applying configuration..."
wpa_cli -i wlan1 reconfigure > /dev/null 2>&1 || true

# Wait a moment for the connection attempt
sleep 3

# Check if connected
CONNECTED_SSID=$(iwgetid -i wlan1 -r 2>/dev/null || echo "")

if [ "$CONNECTED_SSID" = "$SSID" ]; then
    echo "✓ Successfully connected to $SSID"

    # Get IP address
    IP_ADDR=$(ip -4 addr show wlan1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "unknown")
    echo "✓ IP Address: $IP_ADDR"

    exit 0
else
    echo "⚠ Configuration saved, but not yet connected to $SSID"
    echo "   The device will attempt to connect automatically."
    echo "   This is normal if you're currently connected via the AP."

    # Still return success since the config was updated
    exit 0
fi
