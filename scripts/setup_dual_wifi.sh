#!/bin/bash
################################################################################
# TreadWall Dual-Mode WiFi Setup Script
#
# This script configures a Raspberry Pi to run both:
# - Access Point (AP) on wlan0_ap virtual interface
# - WiFi Client on wlan0 for home network connection
#
# Usage: sudo ./scripts/setup_dual_wifi.sh
################################################################################

set -e  # Exit on error

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    exit 1
fi

echo "=========================================="
echo "TreadWall Dual-Mode WiFi Setup"
echo "=========================================="
echo ""

# Get configuration from user
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
echo "Installing required packages..."
apt-get update
apt-get install -y hostapd dnsmasq iptables-persistent

# Stop services while we configure
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true

echo "✓ Packages installed"

################################################################################
# Configure dhcpcd to ignore wlan0_ap
################################################################################

echo ""
echo "Configuring dhcpcd..."

if ! grep -q "denyinterfaces wlan0_ap" /etc/dhcpcd.conf; then
    cat >> /etc/dhcpcd.conf <<EOF

# Ignore wlan0_ap (managed by hostapd)
denyinterfaces wlan0_ap
EOF
    echo "✓ dhcpcd configured"
else
    echo "✓ dhcpcd already configured"
fi

################################################################################
# Configure virtual interface and static IP
################################################################################

echo ""
echo "Configuring network interfaces..."

cat > /etc/network/interfaces.d/wlan0_ap <<EOF
# Virtual AP interface
allow-hotplug wlan0_ap
iface wlan0_ap inet static
    address $AP_IP
    netmask 255.255.255.0
    network 192.168.50.0
    broadcast 192.168.50.255
EOF

echo "✓ Network interfaces configured"

################################################################################
# Configure hostapd (Access Point)
################################################################################

echo ""
echo "Configuring hostapd..."

cat > /etc/hostapd/hostapd.conf <<EOF
# Interface configuration
interface=wlan0_ap
driver=nl80211

# Network configuration
ssid=$AP_SSID
hw_mode=g
channel=$AP_CHANNEL
ieee80211n=1
wmm_enabled=1
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]

# Security configuration
wpa=2
wpa_passphrase=$AP_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP CCMP
rsn_pairwise=CCMP

# Logging
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2

# Other settings
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
EOF

# Point hostapd to config file
sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# Unmask and enable hostapd
systemctl unmask hostapd
systemctl enable hostapd

echo "✓ hostapd configured"

################################################################################
# Configure dnsmasq (DHCP and DNS)
################################################################################

echo ""
echo "Configuring dnsmasq..."

# Backup original config
cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup 2>/dev/null || true

cat > /etc/dnsmasq.conf <<EOF
# Interface configuration
interface=wlan0_ap
bind-interfaces

# DHCP configuration
dhcp-range=192.168.50.10,192.168.50.50,24h
dhcp-option=3,$AP_IP    # Gateway
dhcp-option=6,$AP_IP    # DNS server

# DNS configuration
domain-needed
bogus-priv
no-resolv
server=8.8.8.8
server=8.8.4.4
EOF

systemctl enable dnsmasq

echo "✓ dnsmasq configured"

################################################################################
# Configure IP forwarding and NAT
################################################################################

echo ""
echo "Configuring routing and NAT..."

# Enable IP forwarding
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

# Set up NAT rules
iptables -t nat -F
iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
iptables -A FORWARD -i wlan0 -o wlan0_ap -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0_ap -o wlan0 -j ACCEPT

# Save iptables rules
netfilter-persistent save

echo "✓ Routing configured"

################################################################################
# Create virtual interface startup script
################################################################################

echo ""
echo "Creating startup script for virtual interface..."

cat > /usr/local/bin/create-ap-interface.sh <<'EOF'
#!/bin/bash
# Create virtual AP interface if it doesn't exist
if ! ip link show wlan0_ap >/dev/null 2>&1; then
    iw dev wlan0 interface add wlan0_ap type __ap
    ip link set wlan0_ap up
fi
EOF

chmod +x /usr/local/bin/create-ap-interface.sh

# Create systemd service to run on boot
cat > /etc/systemd/system/create-ap-interface.service <<EOF
[Unit]
Description=Create virtual AP interface
Before=hostapd.service
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/create-ap-interface.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable create-ap-interface.service

echo "✓ Startup script created"

################################################################################
# Start services
################################################################################

echo ""
echo "Starting services..."

# Create virtual interface now
/usr/local/bin/create-ap-interface.sh

# Start services
systemctl start hostapd
systemctl start dnsmasq

echo "✓ Services started"

################################################################################
# Verify setup
################################################################################

echo ""
echo "=========================================="
echo "Verifying setup..."
echo "=========================================="
echo ""

# Check interface
if ip addr show wlan0_ap >/dev/null 2>&1; then
    echo "✓ Virtual interface wlan0_ap created"
    ip addr show wlan0_ap | grep "inet "
else
    echo "✗ Virtual interface wlan0_ap not found"
fi

# Check services
if systemctl is-active --quiet hostapd; then
    echo "✓ hostapd is running"
else
    echo "✗ hostapd is not running"
    systemctl status hostapd
fi

if systemctl is-active --quiet dnsmasq; then
    echo "✓ dnsmasq is running"
else
    echo "✗ dnsmasq is not running"
    systemctl status dnsmasq
fi

# Check wlan0 status
echo ""
echo "wlan0 (Home network) status:"
CONNECTED_SSID=$(iwgetid -r 2>/dev/null || echo "Not connected")
echo "  Connected to: $CONNECTED_SSID"

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Access Point Details:"
echo "  SSID: $AP_SSID"
echo "  Password: [hidden]"
echo "  IP Address: $AP_IP"
echo "  Web Interface: http://$AP_IP:4567"
echo ""
echo "You can now:"
echo "1. Connect to the '$AP_SSID' WiFi network"
echo "2. Open http://$AP_IP:4567 in your browser"
echo "3. Use the Network Configuration section to add home WiFi"
echo ""
echo "If you need to reboot: sudo reboot"
echo ""
