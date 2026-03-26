#!/bin/bash
################################################################################
# TreadWall Access Point Only Setup
#
# This script configures wlan0 as an Access Point directly.
# Simpler and more compatible with Pi Zero 2 W.
#
# Note: This disables WiFi client mode on wlan0. If you need internet,
# use ethernet or configure home WiFi via the web UI after setup.
#
# Usage: sudo ./scripts/setup_ap_only.sh
################################################################################

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    exit 1
fi

echo "=========================================="
echo "TreadWall Access Point Setup (Simple)"
echo "=========================================="
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
echo "  SSID: $AP_SSID"
echo "  IP: $AP_IP"
echo "  Channel: $AP_CHANNEL"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled"
    exit 1
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
# Block NetworkManager from managing wlan0
################################################################################

echo ""
echo "Configuring NetworkManager..."

mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/unmanaged-wlan0.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF

systemctl restart NetworkManager 2>/dev/null || true

echo "✓ NetworkManager configured to ignore wlan0"

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

echo "✓ Static IP configured"

################################################################################
# Configure hostapd
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

echo "✓ hostapd configured"

################################################################################
# Configure dnsmasq
################################################################################

echo ""
echo "Configuring dnsmasq..."

if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
fi

cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
bind-interfaces
dhcp-range=192.168.50.10,192.168.50.50,24h
dhcp-option=3,$AP_IP
dhcp-option=6,$AP_IP
domain-needed
bogus-priv
no-resolv
server=8.8.8.8
server=8.8.4.4
EOF

systemctl enable dnsmasq

echo "✓ dnsmasq configured"

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

if systemctl is-active --quiet hostapd; then
    echo "✓ hostapd is running"
else
    echo "✗ hostapd failed"
    journalctl -u hostapd -n 10 --no-pager
fi

if systemctl is-active --quiet dnsmasq; then
    echo "✓ dnsmasq is running"
else
    echo "✗ dnsmasq failed"
    journalctl -u dnsmasq -n 10 --no-pager
fi

ip addr show wlan0 | grep "inet "

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Access Point:"
echo "  SSID: $AP_SSID"
echo "  IP: $AP_IP"
echo "  Web Interface: http://$AP_IP:4567"
echo ""
echo "Connect to the WiFi network and open the web interface!"
echo ""
echo "Note: wlan0 is now dedicated to the AP."
echo "To connect to home WiFi, you'll need to use ethernet"
echo "or a USB WiFi adapter."
echo ""
