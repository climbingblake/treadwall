#!/bin/bash
#
# USB Tethering Setup Verification Script
# Checks if all configuration is correct before first use
#
# Usage: sudo ./verify_usb_setup.sh
#

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

echo "=========================================="
echo "USB Tethering Configuration Verification"
echo "=========================================="
echo ""

ERRORS=0
WARNINGS=0

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${WARN} Warning: Not running as root. Some checks may fail."
    WARNINGS=$((WARNINGS + 1))
fi

# 1. Check boot configuration
echo "Checking boot configuration..."

if grep -q "^dtoverlay=dwc2" /boot/config.txt; then
    echo -e "  ${PASS} USB gadget overlay enabled in /boot/config.txt"
else
    echo -e "  ${FAIL} USB gadget overlay NOT found in /boot/config.txt"
    ERRORS=$((ERRORS + 1))
fi

if grep -q "modules-load=dwc2,g_ether" /boot/cmdline.txt; then
    echo -e "  ${PASS} USB ethernet module configured in /boot/cmdline.txt"
else
    echo -e "  ${FAIL} USB ethernet module NOT found in /boot/cmdline.txt"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 2. Check installed packages
echo "Checking required packages..."

packages=("libimobiledevice6" "usbmuxd" "dnsmasq" "hostapd")
for pkg in "${packages[@]}"; do
    if dpkg -l | grep -q "^ii.*${pkg}"; then
        echo -e "  ${PASS} ${pkg} installed"
    else
        echo -e "  ${FAIL} ${pkg} NOT installed"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""

# 3. Check IP forwarding
echo "Checking IP forwarding..."

if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo -e "  ${PASS} IP forwarding enabled in /etc/sysctl.conf"
else
    echo -e "  ${FAIL} IP forwarding NOT enabled in /etc/sysctl.conf"
    ERRORS=$((ERRORS + 1))
fi

current_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
if [ "$current_forward" = "1" ]; then
    echo -e "  ${PASS} IP forwarding currently active"
else
    echo -e "  ${WARN} IP forwarding not active (will be after reboot)"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 4. Check hostapd configuration
echo "Checking WiFi AP configuration..."

if [ -f /etc/hostapd/hostapd.conf ]; then
    echo -e "  ${PASS} /etc/hostapd/hostapd.conf exists"

    # Check key settings
    if grep -q "^interface=wlan0" /etc/hostapd/hostapd.conf; then
        echo -e "  ${PASS} AP interface set to wlan0"
    else
        echo -e "  ${FAIL} AP interface NOT set to wlan0"
        ERRORS=$((ERRORS + 1))
    fi

    if grep -q "^ssid=" /etc/hostapd/hostapd.conf; then
        SSID=$(grep "^ssid=" /etc/hostapd/hostapd.conf | cut -d'=' -f2)
        echo -e "  ${PASS} AP SSID: ${SSID}"
    else
        echo -e "  ${FAIL} AP SSID not configured"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "  ${FAIL} /etc/hostapd/hostapd.conf NOT found"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 5. Check dnsmasq configuration
echo "Checking DHCP server configuration..."

if [ -f /etc/dnsmasq.conf ]; then
    echo -e "  ${PASS} /etc/dnsmasq.conf exists"

    if grep -q "^interface=wlan0" /etc/dnsmasq.conf; then
        echo -e "  ${PASS} DHCP interface set to wlan0"
    else
        echo -e "  ${FAIL} DHCP interface NOT set to wlan0"
        ERRORS=$((ERRORS + 1))
    fi

    if grep -q "^dhcp-range=" /etc/dnsmasq.conf; then
        DHCP_RANGE=$(grep "^dhcp-range=" /etc/dnsmasq.conf | cut -d'=' -f2)
        echo -e "  ${PASS} DHCP range: ${DHCP_RANGE}"
    else
        echo -e "  ${FAIL} DHCP range not configured"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "  ${FAIL} /etc/dnsmasq.conf NOT found"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 6. Check static IP for wlan0
echo "Checking wlan0 static IP..."

if grep -q "^interface wlan0" /etc/dhcpcd.conf; then
    echo -e "  ${PASS} wlan0 configured in /etc/dhcpcd.conf"

    if grep -A 2 "^interface wlan0" /etc/dhcpcd.conf | grep -q "static ip_address=192.168.4.1"; then
        echo -e "  ${PASS} Static IP set to 192.168.4.1"
    else
        echo -e "  ${WARN} Static IP may not be 192.168.4.1"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "  ${FAIL} wlan0 NOT configured in /etc/dhcpcd.conf"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# 7. Check systemd service
echo "Checking USB tethering service..."

if [ -f /etc/systemd/system/usb-tethering.service ]; then
    echo -e "  ${PASS} /etc/systemd/system/usb-tethering.service exists"
else
    echo -e "  ${FAIL} USB tethering service NOT found"
    ERRORS=$((ERRORS + 1))
fi

if [ -f /usr/local/bin/usb-tethering-bridge.sh ]; then
    echo -e "  ${PASS} /usr/local/bin/usb-tethering-bridge.sh exists"
    if [ -x /usr/local/bin/usb-tethering-bridge.sh ]; then
        echo -e "  ${PASS} Bridge script is executable"
    else
        echo -e "  ${FAIL} Bridge script is NOT executable"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "  ${FAIL} USB tethering bridge script NOT found"
    ERRORS=$((ERRORS + 1))
fi

# Check if service is enabled
if systemctl is-enabled usb-tethering >/dev/null 2>&1; then
    echo -e "  ${PASS} USB tethering service is enabled"
else
    echo -e "  ${WARN} USB tethering service is NOT enabled"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 8. Check if services are enabled
echo "Checking service enablement..."

services=("hostapd" "dnsmasq" "usb-tethering")
for svc in "${services[@]}"; do
    if systemctl is-enabled "$svc" >/dev/null 2>&1; then
        echo -e "  ${PASS} ${svc} is enabled"
    else
        echo -e "  ${WARN} ${svc} is NOT enabled"
        WARNINGS=$((WARNINGS + 1))
    fi
done

echo ""

# 9. Check for required kernel modules (if already rebooted)
echo "Checking kernel modules (if already rebooted)..."

if lsmod | grep -q dwc2; then
    echo -e "  ${PASS} dwc2 module loaded"
else
    echo -e "  ${WARN} dwc2 module not loaded (normal before first reboot)"
    WARNINGS=$((WARNINGS + 1))
fi

if lsmod | grep -q g_ether; then
    echo -e "  ${PASS} g_ether module loaded"
else
    echo -e "  ${WARN} g_ether module not loaded (normal before first reboot)"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 10. Check current network interfaces
echo "Checking network interfaces..."

if ip link show wlan0 >/dev/null 2>&1; then
    echo -e "  ${PASS} wlan0 interface exists"

    WLAN_IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")
    if [ -n "$WLAN_IP" ]; then
        echo -e "  ${PASS} wlan0 IP: ${WLAN_IP}"
    else
        echo -e "  ${WARN} wlan0 has no IP (normal if not started yet)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "  ${FAIL} wlan0 interface NOT found"
    ERRORS=$((ERRORS + 1))
fi

if ip link show usb0 >/dev/null 2>&1; then
    echo -e "  ${PASS} usb0 interface exists (phone connected!)"

    USB_IP=$(ip -4 addr show usb0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")
    if [ -n "$USB_IP" ]; then
        echo -e "  ${PASS} usb0 IP: ${USB_IP}"
    else
        echo -e "  ${WARN} usb0 exists but no IP (enable tethering on phone)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "  ${WARN} usb0 interface not found (normal if phone not connected)"
fi

echo ""

# 11. Check iptables-persistent
echo "Checking iptables persistence..."

if dpkg -l | grep -q "^ii.*iptables-persistent"; then
    echo -e "  ${PASS} iptables-persistent installed"
else
    echo -e "  ${WARN} iptables-persistent not installed (rules won't persist)"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# Summary
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Your Pi is ready for USB tethering."
    echo ""
    echo "Next steps:"
    echo "  1. Reboot: sudo reboot"
    echo "  2. Connect phone via USB"
    echo "  3. Enable tethering on phone"
    echo "  4. Connect tablet to WiFi AP"
    echo ""
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Configuration complete with ${WARNINGS} warning(s)${NC}"
    echo ""
    echo "Warnings are typically normal before the first reboot."
    echo "If this is your first time setting up, proceed with reboot."
    echo ""
    echo "Next steps:"
    echo "  1. Reboot: sudo reboot"
    echo "  2. Run this script again to verify all services started"
    echo ""
else
    echo -e "${RED}✗ Configuration has ${ERRORS} error(s) and ${WARNINGS} warning(s)${NC}"
    echo ""
    echo "Please run the setup script again:"
    echo "  sudo ./scripts/setup_usb_tethering.sh"
    echo ""
    exit 1
fi

exit 0
