#!/bin/bash
################################################################################
# TreadWall Dual-Mode WiFi Setup with USB Adapter
#
# This script configures:
# - wlan0 (built-in): Access Point for direct device control
# - wlan1 (USB adapter): WiFi client for home network/internet
#
# Requirements: USB WiFi adapter plugged in and detected as wlan1
#
# Usage: sudo ./scripts/setup_dual_wifi_usb.sh
################################################################################

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    exit 1
fi

echo "=========================================="
echo "TreadWall Dual-WiFi USB Setup"
echo "=========================================="
echo ""

# Check if wlan1 exists
if ! ip link show wlan1 >/dev/null 2>&1; then
    echo "Error: wlan1 (USB WiFi adapter) not detected"
    echo ""
    echo "Please:"
    echo "  1. Plug in USB WiFi adapter"
    echo "  2. Wait 10 seconds"
    echo "  3. Run: ip link show"
    echo "  4. Verify wlan1 appears in the list"
    echo ""
    exit 1
fi

echo "✓ USB WiFi adapter detected (wlan1)"
echo ""

# Get configuration
read -p "Enter AP SSID [TreadWall-Control]: " AP_SSID
AP_SSID=${AP_SSID:-TreadWall-Control}

read -s -p "Enter AP Password (min 8 chars): " AP_PASSWORD
echo ""

if [ ${#AP_PASSWORD} -lt 8 ]; then
    echo "Error: Password must be at least 8 characters"
    exit 1
fi

read -p "Enter AP IP Address [192.168.50.1]: " AP_IP
AP_IP=${AP_IP:-192.168.50.1}

read -p "Enter AP Channel (1-11) [6]: " AP_CHANNEL
AP_CHANNEL=${AP_CHANNEL:-6}

echo ""
echo "Configuration:"
echo "  wlan0 (built-in) will be Access Point"
echo "  - SSID: $AP_SSID"
echo "  - IP: $AP_IP"
echo "  - Channel: $AP_CHANNEL"
echo ""
echo "  wlan1 (USB) will remain as WiFi client"
echo "  - Configure via web UI after setup"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled"
    exit 0
fi

echo ""
echo "Installing packages..."
apt-get update
apt-get install -y hostapd dnsmasq iptables-persistent

# Stop services
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true

echo "✓ Packages installed"

################################################################################
# Configure NetworkManager to ignore wlan0 (but NOT wlan1)
################################################################################

echo ""
echo "Configuring NetworkManager..."

mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/unmanaged-wlan0.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF

systemctl restart NetworkManager 2>/dev/null || true

echo "✓ NetworkManager configured (wlan0 unmanaged, wlan1 managed)"

################################################################################
# Configure static IP for wlan0
################################################################################

echo ""
echo "Configuring wlan0 static IP..."

cat > /etc/systemd/network/08-wlan0.network <<EOF
[Match]
Name=wlan0

[Network]
Address=$AP_IP/24
DHCPServer=no
EOF

systemctl enable systemd-networkd
systemctl restart systemd-networkd

echo "✓ Static IP configured on wlan0"

################################################################################
# Configure hostapd (Access Point on wlan0)
################################################################################

echo ""
echo "Configuring hostapd..."

mkdir -p /etc/hostapd

cat > /etc/hostapd/hostapd.conf <<EOF
# Interface
interface=wlan0
driver=nl80211

# Network
ssid=$AP_SSID
hw_mode=g
channel=$AP_CHANNEL
ieee80211n=1
wmm_enabled=1

# Security
wpa=2
wpa_passphrase=$AP_PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP

# Other
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
EOF

if [ -f /etc/default/hostapd ]; then
    sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
else
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd
fi

systemctl unmask hostapd
systemctl enable hostapd

echo "✓ hostapd configured on wlan0"

################################################################################
# Configure dnsmasq (DHCP on wlan0)
################################################################################

echo ""
echo "Configuring dnsmasq..."

if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
fi

cat > /etc/dnsmasq.conf <<EOF
# Listen only on wlan0 (AP interface)
interface=wlan0
bind-interfaces

# DHCP configuration
dhcp-range=192.168.50.10,192.168.50.50,24h
dhcp-option=3,$AP_IP
dhcp-option=6,$AP_IP

# DNS configuration
domain-needed
bogus-priv
no-resolv
server=8.8.8.8
server=8.8.4.4
EOF

systemctl enable dnsmasq

echo "✓ dnsmasq configured on wlan0"

################################################################################
# Configure IP forwarding and NAT (route AP traffic through wlan1)
################################################################################

echo ""
echo "Configuring routing and NAT..."

# Enable IP forwarding
if [ -f /etc/sysctl.conf ]; then
    if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
        sed -i 's/#*net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    else
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
else
    mkdir -p /etc/sysctl.d
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ip-forward.conf
fi

sysctl -w net.ipv4.ip_forward=1

# Set up NAT rules (route AP traffic through wlan1 to internet)
iptables -t nat -F
iptables -t nat -A POSTROUTING -o wlan1 -j MASQUERADE
iptables -A FORWARD -i wlan1 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o wlan1 -j ACCEPT

# Save iptables rules
netfilter-persistent save

echo "✓ Routing configured (wlan0 → wlan1 → internet)"

################################################################################
# Configure wpa_supplicant for wlan1 (if not already configured)
################################################################################

echo ""
echo "Checking wlan1 configuration..."

# Create wpa_supplicant config if it doesn't exist
if [ ! -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
    echo "Creating wpa_supplicant.conf template..."
    mkdir -p /etc/wpa_supplicant
    cat > /etc/wpa_supplicant/wpa_supplicant.conf <<'WPAEOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

# Add your home WiFi network via the web UI
# Or manually add here:
# network={
#     ssid="YourHomeNetwork"
#     psk="YourPassword"
# }
WPAEOF
    chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
    echo "✓ Created wpa_supplicant.conf template"
    echo "  Configure WiFi via web UI after setup"
else
    echo "✓ wpa_supplicant.conf already exists"
    CURRENT_SSID=$(iwgetid -i wlan1 -r 2>/dev/null || echo "")
    if [ -n "$CURRENT_SSID" ]; then
        echo "  wlan1 currently connected to: $CURRENT_SSID"
    fi
fi

################################################################################
# Start services
################################################################################

echo ""
echo "Starting services..."

# Bring up wlan0 with static IP
ip link set wlan0 down
sleep 1
ip link set wlan0 up
ip addr flush dev wlan0
ip addr add $AP_IP/24 dev wlan0
sleep 2

# Start services
systemctl start hostapd
sleep 2
systemctl start dnsmasq

echo "✓ Services started"

################################################################################
# Verify
################################################################################

echo ""
echo "=========================================="
echo "Verifying setup..."
echo "=========================================="
echo ""

# Check wlan0 (AP)
echo "wlan0 (Access Point):"
if systemctl is-active --quiet hostapd; then
    echo "  ✓ hostapd is running"
else
    echo "  ✗ hostapd failed"
    journalctl -u hostapd -n 10 --no-pager
fi

if systemctl is-active --quiet dnsmasq; then
    echo "  ✓ dnsmasq is running"
else
    echo "  ✗ dnsmasq failed"
    journalctl -u dnsmasq -n 10 --no-pager
fi

WLAN0_IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "No IP")
echo "  IP Address: $WLAN0_IP"

# Check wlan1 (Client)
echo ""
echo "wlan1 (Home WiFi Client):"
WLAN1_SSID=$(iwgetid -i wlan1 -r 2>/dev/null || echo "Not connected")
WLAN1_IP=$(ip -4 addr show wlan1 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "No IP")
echo "  Connected to: $WLAN1_SSID"
echo "  IP Address: $WLAN1_IP"

# Check routing
echo ""
echo "Routing:"
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
    echo "  ✓ IP forwarding enabled"
else
    echo "  ✗ IP forwarding disabled"
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Access Point (wlan0):"
echo "  SSID: $AP_SSID"
echo "  IP: $AP_IP"
echo "  Web Interface: http://$AP_IP:4567"
echo ""
echo "Home WiFi (wlan1):"
if [ "$WLAN1_SSID" != "Not connected" ]; then
    echo "  Connected to: $WLAN1_SSID"
    echo "  IP: $WLAN1_IP"
else
    echo "  Not configured yet"
    echo "  Configure via web UI: http://$AP_IP:4567"
fi
echo ""
echo "Next steps:"
echo "1. Connect to '$AP_SSID' WiFi network from your device"
echo "2. Open http://$AP_IP:4567 in your browser"
if [ "$WLAN1_SSID" = "Not connected" ]; then
    echo "3. Scroll to 'Network Configuration' section"
    echo "4. Enter your home WiFi credentials"
    echo "5. Click 'Connect to Network'"
fi
echo ""
echo "Both networks will work simultaneously!"
echo "Reboot recommended: sudo reboot"
echo ""
