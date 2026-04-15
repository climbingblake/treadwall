#!/bin/bash
################################################################################
# Simplified USB Fallback Setup for Pi Zero W
#
# This configures the Pi Zero W to:
# 1. Try to connect to home WiFi (wpa_supplicant)
# 2. Fall back to USB ethernet if WiFi unavailable
# 3. Support USB tethering from phone for internet access
#
# No AP mode, no bridging - just simple WiFi client OR USB direct access
################################################################################

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

echo "=========================================="
echo "Pi Zero W USB Fallback Setup"
echo "=========================================="
echo ""

# Get WiFi credentials
read -p "Enter your home WiFi SSID (or press Enter to skip): " HOME_SSID
if [ -n "$HOME_SSID" ]; then
    read -s -p "Enter WiFi password: " HOME_PASSWORD
    echo ""
else
    echo "Skipping WiFi configuration - USB-only mode"
    HOME_PASSWORD=""
fi

echo ""
echo "This will configure:"
echo "  - USB gadget mode (always enabled)"
if [ -n "$HOME_SSID" ]; then
    echo "  - WiFi client: $HOME_SSID (primary)"
    echo "  - USB ethernet: Fallback when WiFi unavailable"
else
    echo "  - USB ethernet: Only access method"
fi
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Detect boot partition location (newer Pi OS uses /boot/firmware)
if [ -f "/boot/firmware/config.txt" ]; then
    BOOT_DIR="/boot/firmware"
    echo "✓ Detected boot partition: /boot/firmware (newer Pi OS)"
else
    BOOT_DIR="/boot"
    echo "✓ Detected boot partition: /boot (older Pi OS)"
fi

BOOT_CONFIG="${BOOT_DIR}/config.txt"
BOOT_CMDLINE="${BOOT_DIR}/cmdline.txt"

# Backup files before modification
if [ ! -f "${BOOT_CONFIG}.backup" ]; then
    echo "✓ Backing up ${BOOT_CONFIG}"
    cp "${BOOT_CONFIG}" "${BOOT_CONFIG}.backup"
fi

if [ ! -f "${BOOT_CMDLINE}.backup" ]; then
    echo "✓ Backing up ${BOOT_CMDLINE}"
    cp "${BOOT_CMDLINE}" "${BOOT_CMDLINE}.backup"
fi

# Step 1: Enable USB gadget mode
echo ""
echo "Step 1: Enabling USB gadget mode..."
if grep -q "^dtoverlay=dwc2" "${BOOT_CONFIG}"; then
    echo "  ℹ USB gadget overlay already enabled"
else
    echo "dtoverlay=dwc2" >> "${BOOT_CONFIG}"
    echo "  ✓ Added dtoverlay=dwc2 to ${BOOT_CONFIG}"
fi

# Step 2: Load USB ethernet gadget module
echo ""
echo "Step 2: Configuring USB ethernet gadget..."
if grep -q "modules-load=dwc2,g_ether" "${BOOT_CMDLINE}"; then
    echo "  ℹ USB ethernet module already configured"
else
    # Add after rootwait
    sed -i 's/rootwait/rootwait modules-load=dwc2,g_ether/' "${BOOT_CMDLINE}"
    echo "  ✓ Added g_ether module to ${BOOT_CMDLINE}"
fi

# Step 3: Install required packages for iOS/Android USB support
echo ""
echo "Step 3: Installing USB tethering packages..."
apt-get update -qq
apt-get install -y libimobiledevice-utils ipheth-utils

echo "  ✓ Installed iOS support (libimobiledevice)"
echo "  ✓ Installed ipheth-utils"

# Step 4: Configure wpa_supplicant for WiFi client (if credentials provided)
if [ -n "$HOME_SSID" ]; then
    echo ""
    echo "Step 4: Configuring WiFi client mode..."
    mkdir -p /etc/wpa_supplicant

    # Generate PSK hash
    PSK=$(wpa_passphrase "$HOME_SSID" "$HOME_PASSWORD" | grep 'psk=' | grep -v '#' | cut -d'=' -f2)

    cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="$HOME_SSID"
    psk=$PSK
}
EOF

    chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
    echo "  ✓ Created wpa_supplicant.conf for: $HOME_SSID"

    # Ensure wpa_supplicant service is enabled
    systemctl unmask wpa_supplicant 2>/dev/null || true
    systemctl enable wpa_supplicant 2>/dev/null || true
    echo "  ✓ wpa_supplicant service enabled"
else
    echo ""
    echo "Step 4: Skipping WiFi configuration (USB-only mode)"
fi

# Step 5: Remove any old AP mode configuration
echo ""
echo "Step 5: Cleaning up old AP mode configuration..."

# Stop and disable AP services if they exist
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true
systemctl stop usb-tethering.service 2>/dev/null || true
systemctl disable usb-tethering.service 2>/dev/null || true

# Remove AP configuration files
rm -f /etc/hostapd/hostapd.conf
rm -f /etc/dnsmasq.conf
rm -f /etc/systemd/network/08-wlan0.network
rm -f /etc/NetworkManager/conf.d/unmanaged-wlan0.conf
rm -f /etc/systemd/system/usb-tethering.service
rm -f /etc/systemd/system/treadwall-ap.service
rm -f /usr/local/bin/start-ap.sh
rm -f /usr/local/bin/usb-tethering-bridge.sh

# Remove static IP from dhcpcd.conf if present
if [ -f /etc/dhcpcd.conf ]; then
    sed -i '/# Static IP for TreadWall AP/,/nohook wpa_supplicant/d' /etc/dhcpcd.conf
    sed -i '/interface wlan0/,/nohook wpa_supplicant/d' /etc/dhcpcd.conf
fi

# Restore original dnsmasq config if it was backed up
if [ -f /etc/dnsmasq.conf.original ]; then
    mv /etc/dnsmasq.conf.original /etc/dnsmasq.conf 2>/dev/null || true
fi

echo "  ✓ Removed old AP mode configuration"

# Step 6: Create USB tethering helper service (optional, for auto-dhcp on usb0)
echo ""
echo "Step 6: Creating USB tethering auto-config service..."

cat > /etc/systemd/system/usb-gadget-dhcp.service <<'EOF'
[Unit]
Description=USB Gadget DHCP Client
After=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'sleep 5; if ip link show usb0 >/dev/null 2>&1; then dhclient usb0; fi'

[Install]
WantedBy=multi-user.target
EOF

systemctl enable usb-gadget-dhcp.service
echo "  ✓ Created usb-gadget-dhcp service (auto-requests IP from phone when USB connected)"

# Step 7: Save WiFi credentials to config.json for web UI
echo ""
echo "Step 7: Saving configuration..."

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${APP_DIR}/config.json"

if [ -f "${CONFIG_FILE}" ]; then
    # Update existing config
    if [ -n "$HOME_SSID" ]; then
        # Use jq if available, otherwise manual sed
        if command -v jq >/dev/null 2>&1; then
            tmp=$(mktemp)
            jq --arg ssid "$HOME_SSID" --arg pass "$HOME_PASSWORD" \
                '.wifi_ssid = $ssid | .wifi_password = $pass' \
                "${CONFIG_FILE}" > "$tmp" && mv "$tmp" "${CONFIG_FILE}"
        else
            # Manual JSON update (basic, assumes fields exist)
            sed -i "s/\"wifi_ssid\":.*/\"wifi_ssid\": \"$HOME_SSID\",/" "${CONFIG_FILE}"
            sed -i "s/\"wifi_password\":.*/\"wifi_password\": \"$HOME_PASSWORD\",/" "${CONFIG_FILE}"
        fi
    fi
    echo "  ✓ Updated ${CONFIG_FILE}"
else
    # Create new config with WiFi credentials
    if [ -n "$HOME_SSID" ]; then
        cat > "${CONFIG_FILE}" <<EOF
{
  "wifi_ssid": "$HOME_SSID",
  "wifi_password": "$HOME_PASSWORD",
  "network_mode": "auto"
}
EOF
        echo "  ✓ Created ${CONFIG_FILE}"
    fi
fi

# Step 8: Reload systemd
echo ""
echo "Step 8: Reloading systemd..."
systemctl daemon-reload
echo "  ✓ Systemd reloaded"

# Summary
echo ""
echo "=========================================="
echo "✓ USB Fallback Setup Complete!"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  - USB gadget mode: Enabled"
if [ -n "$HOME_SSID" ]; then
    echo "  - WiFi client: $HOME_SSID"
    echo "  - Mode: Auto (WiFi primary, USB fallback)"
else
    echo "  - Mode: USB-only"
fi
echo ""
echo "Next steps:"
echo "  1. REBOOT: sudo reboot"
echo ""
if [ -n "$HOME_SSID" ]; then
    echo "  2. Pi will try to connect to: $HOME_SSID"
    echo "     - If successful: Access via http://treadwall.local:4567"
    echo "     - If WiFi unavailable: Connect phone via USB"
else
    echo "  2. Connect phone via USB to the 'USB' port (NOT 'PWR')"
fi
echo ""
echo "USB Access (when phone connected):"
echo "  - Connect USB cable to Pi's 'USB' port"
echo "  - Enable USB tethering on phone:"
echo "    • iOS: Settings → Personal Hotspot → Allow Others to Join"
echo "    • Android: Settings → Network → USB tethering"
echo "  - Access Pi at: http://172.20.10.2:4567 (iOS) or http://192.168.42.129:4567 (Android)"
echo ""
echo "To update WiFi credentials later:"
echo "  - Access the Settings page in the web UI"
echo "  - Or run this script again"
echo ""
echo "IMPORTANT: Power the Pi from the 'PWR' port!"
echo "  The 'USB' port is for data connection only."
echo ""
