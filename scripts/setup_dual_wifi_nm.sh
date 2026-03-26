#!/bin/bash
################################################################################
# TreadWall Dual-Mode WiFi Setup Script (NetworkManager version)
#
# This script configures a Raspberry Pi to run both:
# - Access Point (AP) on wlan0_ap virtual interface
# - WiFi Client on wlan0 for home network connection
#
# Compatible with modern Raspberry Pi OS using NetworkManager
#
# Usage: sudo ./scripts/setup_dual_wifi_nm.sh
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
apt-get install -y hostapd dnsmasq iptables-persistent iw

# Stop services while we configure
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true

echo "✓ Packages installed"

################################################################################
# Configure hostapd (Access Point)
################################################################################

echo ""
echo "Configuring hostapd..."

# Create config directory if it doesn't exist
mkdir -p /etc/hostapd

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

# Configure hostapd service
if [ -f /etc/default/hostapd ]; then
    sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
else
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd
fi

# Unmask and enable hostapd
systemctl unmask hostapd
systemctl enable hostapd

echo "✓ hostapd configured"

################################################################################
# Configure dnsmasq (DHCP and DNS)
################################################################################

echo ""
echo "Configuring dnsmasq..."

# Backup original config if it exists
if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
fi

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

# Set up NAT rules
iptables -t nat -F
iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
iptables -A FORWARD -i wlan0 -o wlan0_ap -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0_ap -o wlan0 -j ACCEPT

# Save iptables rules
netfilter-persistent save

echo "✓ Routing configured"

################################################################################
# Create virtual interface and AP startup script
################################################################################

echo ""
echo "Creating AP startup script..."

cat > /usr/local/bin/start-ap.sh <<'EOFSCRIPT'
#!/bin/bash
# Start Access Point
set -e

# Wait for wlan0 to be available
timeout=30
while [ $timeout -gt 0 ]; do
    if ip link show wlan0 >/dev/null 2>&1; then
        break
    fi
    sleep 1
    ((timeout--))
done

if [ $timeout -eq 0 ]; then
    echo "Error: wlan0 not available"
    exit 1
fi

# Create virtual AP interface if it doesn't exist
if ! ip link show wlan0_ap >/dev/null 2>&1; then
    echo "Creating wlan0_ap interface..."
    iw dev wlan0 interface add wlan0_ap type __ap
fi

# Bring up the interface
ip link set wlan0_ap up

# Set static IP
ip addr flush dev wlan0_ap
ip addr add 192.168.50.1/24 dev wlan0_ap

echo "Access Point interface ready"
EOFSCRIPT

chmod +x /usr/local/bin/start-ap.sh

# Update the AP IP in the script if user changed it
sed -i "s|192.168.50.1|$AP_IP|g" /usr/local/bin/start-ap.sh

# Create systemd service
cat > /etc/systemd/system/treadwall-ap.service <<EOF
[Unit]
Description=TreadWall Access Point Interface
After=network.target
Before=hostapd.service dnsmasq.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/start-ap.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable treadwall-ap.service

echo "✓ AP startup script created"

################################################################################
# Start services
################################################################################

echo ""
echo "Starting services..."

# Start AP interface
systemctl start treadwall-ap.service
sleep 2

# Start services
systemctl start hostapd
sleep 2
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
    ip addr show wlan0_ap | grep "inet " || echo "  (IP not yet assigned)"
else
    echo "✗ Virtual interface wlan0_ap not found"
fi

# Check services
if systemctl is-active --quiet hostapd; then
    echo "✓ hostapd is running"
else
    echo "✗ hostapd is not running"
    echo "  Checking logs..."
    journalctl -u hostapd -n 10 --no-pager
fi

if systemctl is-active --quiet dnsmasq; then
    echo "✓ dnsmasq is running"
else
    echo "✗ dnsmasq is not running"
    echo "  Checking logs..."
    journalctl -u dnsmasq -n 10 --no-pager
fi

# Check wlan0 status
echo ""
echo "wlan0 (Home network) status:"
CONNECTED_SSID=$(iwgetid -r 2>/dev/null || echo "Not connected")
WLAN0_IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "No IP")
echo "  Connected to: $CONNECTED_SSID"
echo "  IP Address: $WLAN0_IP"

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
echo "1. Look for the '$AP_SSID' WiFi network on your device"
echo "2. Connect using the password you set"
echo "3. Open http://$AP_IP:4567 in your browser"
echo "4. Use the Network Configuration section to manage WiFi"
echo ""
echo "Note: The AP will start automatically on boot."
echo ""
