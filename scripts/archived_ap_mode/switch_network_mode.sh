#!/bin/bash
#
# Network Mode Switcher
# Switches between AP mode (USB tethering) and Client mode (home WiFi)
#
# Usage: sudo ./switch_network_mode.sh [ap|client] [ssid] [password]
#

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: Run with sudo"
    exit 1
fi

MODE="$1"
HOME_SSID="$2"
HOME_PASSWORD="$3"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Detect current mode
detect_current_mode() {
    # Check actual wlan0 IP address (most reliable)
    if ip addr show wlan0 2>/dev/null | grep -q "inet 192.168.4.1"; then
        # Has AP IP - definitely in AP mode
        echo "ap"
    elif ip addr show wlan0 2>/dev/null | grep -qE "inet (10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.[^4])"; then
        # Has a different private IP - definitely in client mode
        echo "client"
    elif iwgetid -r 2>/dev/null | grep -q "."; then
        # Connected to a WiFi network - client mode
        echo "client"
    elif systemctl is-active hostapd >/dev/null 2>&1 && ! pgrep wpa_supplicant >/dev/null; then
        # hostapd active and wpa_supplicant NOT running - probably AP mode
        echo "ap"
    else
        # Default to client mode if unclear
        echo "client"
    fi
}

CURRENT_MODE=$(detect_current_mode)

echo "=========================================="
echo "Network Mode Switcher"
echo "=========================================="
echo ""
echo "Current mode: $CURRENT_MODE"

if [ -z "$MODE" ]; then
    # No mode specified, toggle to opposite
    if [ "$CURRENT_MODE" = "ap" ]; then
        MODE="client"
    else
        MODE="ap"
    fi
    echo "Switching to: $MODE"
else
    echo "Target mode: $MODE"
fi

# Validate mode
if [ "$MODE" != "ap" ] && [ "$MODE" != "client" ]; then
    echo "Error: Mode must be 'ap' or 'client'"
    exit 1
fi

# Check if already in target mode
if [ "$CURRENT_MODE" = "$MODE" ]; then
    echo ""
    echo "Already in $MODE mode. No changes needed."
    exit 0
fi

echo ""

# Switch modes
if [ "$MODE" = "client" ]; then
    echo "Switching to Client Mode (Home WiFi)"
    echo "=========================================="
    echo ""

    # Validate credentials
    if [ -z "$HOME_SSID" ] || [ -z "$HOME_PASSWORD" ]; then
        echo "Error: WiFi credentials required for client mode"
        echo "Usage: sudo ./switch_network_mode.sh client <ssid> <password>"
        exit 1
    fi

    # Use existing revert_to_client.sh script
    if [ -f "${APP_DIR}/scripts/revert_to_client.sh" ]; then
        # Create temporary expect script to automate the prompts
        cat > /tmp/switch_to_client.exp <<EOF
#!/usr/bin/expect -f
set timeout 30
spawn ${APP_DIR}/scripts/revert_to_client.sh
expect "Enter your home WiFi SSID:"
send "${HOME_SSID}\r"
expect "Enter WiFi password:"
send "${HOME_PASSWORD}\r"
expect "Continue? (y/n)"
send "y\r"
expect eof
EOF
        chmod +x /tmp/switch_to_client.exp

        # Run expect script if available
        if command -v expect >/dev/null 2>&1; then
            /tmp/switch_to_client.exp
            rm /tmp/switch_to_client.exp
        else
            # Fallback: Manual configuration
            echo "Configuring WiFi manually..."

            # Stop AP services
            systemctl stop hostapd 2>/dev/null || true
            systemctl stop dnsmasq 2>/dev/null || true
            systemctl disable hostapd 2>/dev/null || true
            systemctl disable dnsmasq 2>/dev/null || true

            # Reset wlan0
            ip link set wlan0 down
            ip addr flush dev wlan0
            ip link set wlan0 up

            # Create wpa_supplicant config
            PSK=$(wpa_passphrase "$HOME_SSID" "$HOME_PASSWORD" | grep 'psk=' | grep -v '#' | cut -d'=' -f2)

            cat > /etc/wpa_supplicant/wpa_supplicant.conf <<WPAEOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="$HOME_SSID"
    psk=$PSK
}
WPAEOF

            chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

            # Restart networking
            systemctl daemon-reload
            systemctl restart dhcpcd
        fi

        echo ""
        echo "✓ Switched to Client Mode"
        echo ""
        echo "IMPORTANT: Reboot required"
        echo "  sudo reboot"
        echo ""
        echo "After reboot, the Pi will connect to: $HOME_SSID"
        echo "Access via: http://treadwall.local:4567"
        echo ""

    else
        echo "Error: revert_to_client.sh script not found"
        exit 1
    fi

elif [ "$MODE" = "ap" ]; then
    echo "Switching to AP Mode (USB Tethering)"
    echo "=========================================="
    echo ""

    # Use existing setup_usb_tethering.sh script
    if [ -f "${APP_DIR}/scripts/setup_usb_tethering.sh" ]; then
        # Run the setup script
        "${APP_DIR}/scripts/setup_usb_tethering.sh"

        echo ""
        echo "✓ Switched to AP Mode"
        echo ""
        echo "IMPORTANT: Reboot required"
        echo "  sudo reboot"
        echo ""
        echo "After reboot:"
        echo "  - Connect to WiFi: TreadWall-Touch"
        echo "  - Access at: http://192.168.4.1:4567"
        echo ""

    else
        echo "Error: setup_usb_tethering.sh script not found"
        exit 1
    fi
fi

exit 0
