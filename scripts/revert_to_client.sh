#!/bin/bash
################################################################################
# Revert CRIMP to WiFi Client Mode
#
# This removes AP configuration and restores normal WiFi client operation
################################################################################

if [ "$EUID" -ne 0 ]; then
    echo "Error: Run with sudo"
    exit 1
fi

echo "=========================================="
echo "Reverting to WiFi Client Mode"
echo "=========================================="
echo ""

# Get home WiFi credentials
read -p "Enter your home WiFi SSID: " HOME_SSID
read -s -p "Enter WiFi password: " HOME_PASSWORD
echo ""

if [ -z "$HOME_SSID" ] || [ -z "$HOME_PASSWORD" ]; then
    echo "Error: SSID and password required"
    exit 1
fi

echo ""
echo "This will:"
echo "  1. Stop and disable Access Point services"
echo "  2. Restore wlan0 to WiFi client mode"
echo "  3. Connect to: $HOME_SSID"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "Step 1: Stopping AP services..."
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true
systemctl stop treadwall-ap.service 2>/dev/null || true
systemctl disable treadwall-ap.service 2>/dev/null || true
echo "✓ AP services stopped"

echo ""
echo "Step 2: Removing AP configuration files..."
rm -f /etc/hostapd/hostapd.conf
rm -f /etc/dnsmasq.conf
rm -f /etc/systemd/network/08-wlan0.network
rm -f /etc/NetworkManager/conf.d/unmanaged-wlan0.conf
rm -f /etc/systemd/system/treadwall-ap.service
rm -f /usr/local/bin/start-ap.sh
echo "✓ Configuration files removed"

echo ""
echo "Step 3: Removing virtual interface..."
ip link delete wlan0_ap 2>/dev/null || true
echo "✓ Virtual interface removed"

echo ""
echo "Step 4: Resetting wlan0..."
ip link set wlan0 down
ip addr flush dev wlan0
ip link set wlan0 up
echo "✓ wlan0 reset"

echo ""
echo "Step 5: Creating wpa_supplicant configuration..."
mkdir -p /etc/wpa_supplicant

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
echo "✓ wpa_supplicant configured"

echo ""
echo "Step 6: Starting WiFi client..."
systemctl daemon-reload
systemctl restart NetworkManager 2>/dev/null || true
systemctl restart systemd-networkd 2>/dev/null || true

# Wait for connection
echo "Waiting for connection..."
sleep 10

# Check connection
CONNECTED=$(iwgetid -r 2>/dev/null || echo "")
if [ "$CONNECTED" = "$HOME_SSID" ]; then
    IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "unknown")
    echo ""
    echo "=========================================="
    echo "✓ Success!"
    echo "=========================================="
    echo ""
    echo "Connected to: $HOME_SSID"
    echo "IP Address: $IP"
    echo ""
    echo "You can now access the device at:"
    echo "  http://$IP:4567"
    echo "  http://treadwall.local:4567"
    echo ""
else
    echo ""
    echo "⚠ Could not connect automatically"
    echo "Rebooting may help. Run: sudo reboot"
    echo ""
    echo "After reboot, to debug:"
    echo "  sudo systemctl status NetworkManager"
    echo "  nmcli device wifi list"
    echo "  nmcli device wifi connect '$HOME_SSID' password '[password]'"
fi

echo ""
echo "Reboot recommended: sudo reboot"
echo ""
