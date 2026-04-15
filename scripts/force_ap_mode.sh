#!/bin/bash
#
# Force AP Mode - Emergency fix when setup script didn't work
# This aggressively configures the Pi into AP mode
#

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: Run with sudo"
    exit 1
fi

echo "=========================================="
echo "Forcing AP Mode"
echo "=========================================="
echo ""

# 1. Stop and disable wpa_supplicant
echo "Step 1: Disabling wpa_supplicant..."
systemctl stop wpa_supplicant 2>/dev/null || true
systemctl disable wpa_supplicant 2>/dev/null || true
killall wpa_supplicant 2>/dev/null || true
echo "✓ wpa_supplicant stopped"
echo ""

# 2. Bring down wlan0 and flush addresses
echo "Step 2: Resetting wlan0..."
ip link set wlan0 down
ip addr flush dev wlan0
echo "✓ wlan0 reset"
echo ""

# 3. Configure static IP
echo "Step 3: Setting static IP..."
ip addr add 192.168.4.1/24 dev wlan0
ip link set wlan0 up
echo "✓ wlan0 configured with 192.168.4.1"
echo ""

# 4. Start hostapd
echo "Step 4: Starting hostapd..."
if [ ! -f /etc/hostapd/hostapd.conf ]; then
    echo "✗ Error: /etc/hostapd/hostapd.conf not found"
    echo "  Run: sudo ./scripts/setup_usb_tethering.sh"
    exit 1
fi

systemctl unmask hostapd 2>/dev/null || true
systemctl enable hostapd
systemctl restart hostapd

sleep 2

if systemctl is-active hostapd >/dev/null; then
    echo "✓ hostapd is running"
else
    echo "✗ hostapd failed to start"
    echo "  Check: sudo systemctl status hostapd"
    echo "  Check: sudo journalctl -u hostapd -n 20"
fi
echo ""

# 5. Start dnsmasq
echo "Step 5: Starting dnsmasq..."
if [ ! -f /etc/dnsmasq.conf ]; then
    echo "✗ Error: /etc/dnsmasq.conf not found"
    echo "  Run: sudo ./scripts/setup_usb_tethering.sh"
    exit 1
fi

systemctl enable dnsmasq
systemctl restart dnsmasq

sleep 2

if systemctl is-active dnsmasq >/dev/null; then
    echo "✓ dnsmasq is running"
else
    echo "✗ dnsmasq failed to start"
    echo "  Check: sudo systemctl status dnsmasq"
fi
echo ""

# 6. Verify
echo "=========================================="
echo "Verification:"
echo "=========================================="
echo ""

echo "wlan0 IP:"
ip addr show wlan0 | grep "inet "
echo ""

echo "hostapd status:"
systemctl is-active hostapd && echo "✓ Running" || echo "✗ Not running"
echo ""

echo "dnsmasq status:"
systemctl is-active dnsmasq && echo "✓ Running" || echo "✗ Not running"
echo ""

echo "WiFi networks being broadcast:"
timeout 3 iw dev wlan0 info 2>/dev/null || echo "Could not query (may be normal)"
echo ""

echo "=========================================="
echo "AP Mode should now be active!"
echo "=========================================="
echo ""
echo "Connect to WiFi: TreadWall-Touch"
echo "Access at: http://192.168.4.1:4567"
echo ""
echo "If still not working:"
echo "  sudo reboot"
echo ""
