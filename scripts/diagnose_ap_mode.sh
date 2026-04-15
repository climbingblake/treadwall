#!/bin/bash
# Diagnose why AP mode isn't working

echo "=========================================="
echo "AP Mode Diagnostics"
echo "=========================================="
echo ""

echo "1. wlan0 IP address:"
ip addr show wlan0 | grep "inet "
echo ""

echo "2. hostapd service status:"
systemctl is-active hostapd && echo "✓ Active" || echo "✗ Inactive"
systemctl is-enabled hostapd && echo "✓ Enabled" || echo "✗ Disabled"
echo ""

echo "3. dnsmasq service status:"
systemctl is-active dnsmasq && echo "✓ Active" || echo "✗ Inactive"
systemctl is-enabled dnsmasq && echo "✓ Enabled" || echo "✗ Disabled"
echo ""

echo "4. wpa_supplicant processes:"
pgrep -a wpa_supplicant || echo "None running"
echo ""

echo "5. dhcpcd config for wlan0:"
grep -A 3 "^interface wlan0" /etc/dhcpcd.conf || echo "Not configured"
echo ""

echo "6. hostapd config exists:"
ls -la /etc/hostapd/hostapd.conf 2>&1
echo ""

echo "7. Is wlan0 being managed by wpa_supplicant?"
if grep -q "nohook wpa_supplicant" /etc/dhcpcd.conf; then
    echo "✓ wpa_supplicant disabled for wlan0"
else
    echo "✗ wpa_supplicant still managing wlan0"
fi
echo ""

echo "8. Check for wpa_supplicant config:"
if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
    echo "wpa_supplicant.conf exists (may conflict)"
    grep "^network=" /etc/wpa_supplicant/wpa_supplicant.conf -A 3 | head -10
else
    echo "No wpa_supplicant.conf"
fi
echo ""

echo "=========================================="
echo "Quick Fix Suggestions:"
echo "=========================================="
echo ""

if ! systemctl is-active hostapd >/dev/null; then
    echo "hostapd is not running. Try:"
    echo "  sudo systemctl restart hostapd"
    echo "  sudo systemctl status hostapd"
    echo ""
fi

if ip addr show wlan0 | grep -q "10.0.0"; then
    echo "wlan0 has home WiFi IP. The static IP didn't apply."
    echo "Try:"
    echo "  sudo systemctl restart dhcpcd"
    echo "  OR reboot: sudo reboot"
    echo ""
fi

if pgrep wpa_supplicant >/dev/null; then
    echo "wpa_supplicant is running (conflicts with AP mode)."
    echo "Try:"
    echo "  sudo systemctl stop wpa_supplicant"
    echo "  sudo systemctl disable wpa_supplicant"
    echo "  sudo reboot"
    echo ""
fi
