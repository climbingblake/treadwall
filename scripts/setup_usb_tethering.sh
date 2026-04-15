#!/bin/bash
#
# USB Tethering Setup Script
# One-time configuration to enable USB OTG gadget mode on Pi Zero W
#
# This script configures the Pi Zero W to:
# 1. Act as a USB ethernet gadget (receive internet from phone via USB)
# 2. Run as WiFi AP on wlan0
# 3. Bridge USB internet (usb0) to AP clients
#
# Usage: sudo ./setup_usb_tethering.sh
#

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

echo "=========================================="
echo "USB Tethering Setup for Pi Zero W"
echo "=========================================="
echo ""

# Backup files before modification
BOOT_CONFIG="/boot/config.txt"
BOOT_CMDLINE="/boot/cmdline.txt"

if [ ! -f "${BOOT_CONFIG}.backup" ]; then
    echo "✓ Backing up ${BOOT_CONFIG}"
    cp "${BOOT_CONFIG}" "${BOOT_CONFIG}.backup"
fi

if [ ! -f "${BOOT_CMDLINE}.backup" ]; then
    echo "✓ Backing up ${BOOT_CMDLINE}"
    cp "${BOOT_CMDLINE}" "${BOOT_CMDLINE}.backup"
fi

# 1. Enable USB gadget mode in config.txt
echo ""
echo "Step 1: Enabling USB gadget mode..."
if grep -q "^dtoverlay=dwc2" "${BOOT_CONFIG}"; then
    echo "  ℹ USB gadget overlay already enabled"
else
    echo "dtoverlay=dwc2" >> "${BOOT_CONFIG}"
    echo "  ✓ Added dtoverlay=dwc2 to ${BOOT_CONFIG}"
fi

# 2. Load USB ethernet gadget module in cmdline.txt
echo ""
echo "Step 2: Configuring USB ethernet gadget..."
if grep -q "modules-load=dwc2,g_ether" "${BOOT_CMDLINE}"; then
    echo "  ℹ USB ethernet module already configured"
else
    # Add after rootwait
    sed -i 's/rootwait/rootwait modules-load=dwc2,g_ether/' "${BOOT_CMDLINE}"
    echo "  ✓ Added g_ether module to ${BOOT_CMDLINE}"
fi

# 3. Install required packages
echo ""
echo "Step 3: Installing USB tethering packages..."
apt-get update -qq
apt-get install -y libimobiledevice-utils ipheth-utils dnsmasq hostapd iptables-persistent

echo "  ✓ Installed iOS support (libimobiledevice)"
echo "  ✓ Installed ipheth-utils"
echo "  ✓ Installed dnsmasq, hostapd, iptables-persistent"

# 4. Enable IP forwarding
echo ""
echo "Step 4: Enabling IP forwarding..."
if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "  ℹ IP forwarding already enabled"
else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1
    echo "  ✓ Enabled IP forwarding"
fi

# 5. Configure hostapd for wlan0 AP
echo ""
echo "Step 5: Configuring WiFi Access Point..."

# Read AP credentials from config.json if it exists
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${APP_DIR}/config.json"

if [ -f "${CONFIG_FILE}" ]; then
    AP_SSID=$(grep -oP '"ap_ssid":\s*"\K[^"]+' "${CONFIG_FILE}" || echo "TreadWall-Touch")
    AP_PASSWORD=$(grep -oP '"ap_password":\s*"\K[^"]+' "${CONFIG_FILE}" || echo "yosemite")
    AP_CHANNEL=$(grep -oP '"ap_channel":\s*\K[0-9]+' "${CONFIG_FILE}" || echo "6")
else
    AP_SSID="TreadWall-Touch"
    AP_PASSWORD="yosemite"
    AP_CHANNEL="6"
fi

cat > /etc/hostapd/hostapd.conf <<EOF
# TreadWall AP Configuration (USB Tethering Mode)
interface=wlan0
driver=nl80211

# Network name
ssid=${AP_SSID}

# WiFi channel
channel=${AP_CHANNEL}
hw_mode=g
ieee80211n=1
wmm_enabled=1

# Security
auth_algs=1
wpa=2
wpa_passphrase=${AP_PASSWORD}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

echo "  ✓ Created /etc/hostapd/hostapd.conf"
echo "    SSID: ${AP_SSID}"
echo "    Channel: ${AP_CHANNEL}"

# Tell systemd where to find hostapd config
sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd || true

# 6. Configure dnsmasq for DHCP on wlan0
echo ""
echo "Step 6: Configuring DHCP server..."

# Backup original dnsmasq config
if [ -f /etc/dnsmasq.conf.original ]; then
    echo "  ℹ dnsmasq backup already exists"
else
    mv /etc/dnsmasq.conf /etc/dnsmasq.conf.original
    echo "  ✓ Backed up original dnsmasq.conf"
fi

cat > /etc/dnsmasq.conf <<EOF
# TreadWall DHCP Configuration (USB Tethering Mode)
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h

# Don't read /etc/resolv.conf or /etc/hosts
no-resolv
no-hosts

# Use Google DNS as upstream (will be overridden by usb0 when available)
server=8.8.8.8
server=8.8.4.4
EOF

echo "  ✓ Created /etc/dnsmasq.conf"
echo "    DHCP range: 192.168.4.10 - 192.168.4.50"

# 7. Configure static IP for wlan0
echo ""
echo "Step 7: Configuring static IP for wlan0..."

# Check if dhcpcd is managing wlan0
if ! grep -q "^interface wlan0" /etc/dhcpcd.conf; then
    cat >> /etc/dhcpcd.conf <<EOF

# Static IP for TreadWall AP (USB Tethering Mode)
interface wlan0
static ip_address=192.168.4.1/24
nohook wpa_supplicant
EOF
    echo "  ✓ Added static IP configuration to /etc/dhcpcd.conf"
else
    echo "  ℹ wlan0 static IP already configured"
fi

# 8. Install systemd service for USB tethering
echo ""
echo "Step 8: Installing USB tethering service..."

cat > /etc/systemd/system/usb-tethering.service <<'EOF'
[Unit]
Description=USB Tethering Bridge Service
After=network.target dhcpcd.service
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/usb-tethering-bridge.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "  ✓ Created /etc/systemd/system/usb-tethering.service"

# 9. Copy bridge script to /usr/local/bin
echo ""
echo "Step 9: Installing USB tethering bridge script..."

BRIDGE_SCRIPT="/usr/local/bin/usb-tethering-bridge.sh"
cat > "${BRIDGE_SCRIPT}" <<'BRIDGE_EOF'
#!/bin/bash
#
# USB Tethering Bridge Service
# Monitors for USB tethering connections and bridges internet to AP clients
#

LOG_FILE="/var/log/usb-tethering.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

configure_bridge() {
    log "USB tethering detected on usb0"

    # Request IP from phone via DHCP
    log "Requesting DHCP from phone..."
    dhclient -v usb0 2>&1 | tee -a "${LOG_FILE}"

    # Wait for IP assignment
    sleep 3

    USB_IP=$(ip -4 addr show usb0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -z "${USB_IP}" ]; then
        log "ERROR: Failed to get IP from phone"
        return 1
    fi

    log "✓ USB interface configured: ${USB_IP}"

    # Get DNS servers from usb0
    USB_DNS=$(grep nameserver /etc/resolv.conf | head -n 2 | awk '{print $2}' | tr '\n' ' ')
    log "✓ DNS servers: ${USB_DNS}"

    # Configure iptables to bridge usb0 → wlan0
    log "Configuring iptables NAT..."

    # Flush existing NAT rules
    iptables -t nat -F POSTROUTING
    iptables -F FORWARD

    # Enable masquerading from wlan0 to usb0
    iptables -t nat -A POSTROUTING -o usb0 -j MASQUERADE

    # Allow forwarding
    iptables -A FORWARD -i wlan0 -o usb0 -j ACCEPT
    iptables -A FORWARD -i usb0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Save iptables rules
    netfilter-persistent save 2>&1 | tee -a "${LOG_FILE}"

    log "✓ USB tethering bridge active"
    log "  Internet: Phone (usb0) → Pi → AP clients (wlan0)"
}

cleanup_bridge() {
    log "USB tethering disconnected"

    # Release DHCP lease
    dhclient -r usb0 2>/dev/null || true

    # Clear iptables rules
    iptables -t nat -F POSTROUTING
    iptables -F FORWARD

    log "✓ Bridge cleaned up"
}

# Main monitoring loop
log "=========================================="
log "USB Tethering Bridge Service Started"
log "=========================================="

PREVIOUS_STATE="down"

while true; do
    # Check if usb0 interface exists and is up
    if ip link show usb0 &>/dev/null; then
        CURRENT_STATE="up"

        if [ "${PREVIOUS_STATE}" = "down" ]; then
            configure_bridge
            PREVIOUS_STATE="up"
        fi

        # Check if we still have IP
        USB_IP=$(ip -4 addr show usb0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        if [ -z "${USB_IP}" ]; then
            log "WARNING: usb0 lost IP address, reconfiguring..."
            configure_bridge
        fi

    else
        CURRENT_STATE="down"

        if [ "${PREVIOUS_STATE}" = "up" ]; then
            cleanup_bridge
            PREVIOUS_STATE="down"
        fi
    fi

    # Check every 5 seconds
    sleep 5
done
BRIDGE_EOF

chmod +x "${BRIDGE_SCRIPT}"
echo "  ✓ Installed ${BRIDGE_SCRIPT}"

# 10. Enable services
echo ""
echo "Step 10: Enabling services..."

systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq
systemctl enable usb-tethering.service

echo "  ✓ Enabled hostapd"
echo "  ✓ Enabled dnsmasq"
echo "  ✓ Enabled usb-tethering service"

# 11. Summary
echo ""
echo "=========================================="
echo "✓ USB Tethering Setup Complete!"
echo "=========================================="
echo ""
echo "Configuration summary:"
echo "  - WiFi AP: ${AP_SSID} (192.168.4.1)"
echo "  - USB Gadget Mode: Enabled"
echo "  - IP Forwarding: Enabled"
echo "  - Auto-bridge: usb0 → wlan0"
echo ""
echo "Next steps:"
echo "  1. REBOOT the Pi: sudo reboot"
echo "  2. Connect phone via USB to the 'USB' port (NOT 'PWR')"
echo "  3. Enable USB tethering on phone:"
echo "     - iOS: Settings → Personal Hotspot → Allow Others to Join"
echo "     - Android: Settings → Network → Hotspot & Tethering → USB tethering"
echo "  4. Connect tablet/device to '${AP_SSID}' WiFi"
echo "  5. Tablet will have internet from phone's cellular data"
echo ""
echo "Monitoring:"
echo "  - Check USB bridge status: sudo systemctl status usb-tethering"
echo "  - View logs: sudo tail -f /var/log/usb-tethering.log"
echo "  - Check interfaces: ip addr show"
echo ""
echo "IMPORTANT: Power the Pi from the 'PWR' port!"
echo "  The 'USB' port is for tethering only, not power."
echo ""
