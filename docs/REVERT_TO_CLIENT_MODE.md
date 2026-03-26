# Reverting to WiFi Client Mode

This guide shows how to remove the Access Point configuration and restore the Pi to normal WiFi client mode (connecting to home network only).

## When to Use This

- You don't have a USB WiFi adapter yet
- You need the Pi on your home network for updates
- You want to simplify the setup temporarily
- Testing/development on home network

## Quick Revert Script

Save this as `/home/pi/revert_to_client.sh` on your Pi:

```bash
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

cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="$HOME_SSID"
    psk=$(wpa_passphrase "$HOME_SSID" "$HOME_PASSWORD" | grep 'psk=' | grep -v '#' | cut -d'=' -f2)
}
EOF

chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
echo "✓ wpa_supplicant configured"

echo ""
echo "Step 6: Starting WiFi client..."
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
    echo "You may need to reboot and check NetworkManager"
    echo ""
    echo "To debug:"
    echo "  sudo systemctl status NetworkManager"
    echo "  nmcli device wifi list"
    echo "  nmcli device wifi connect '$HOME_SSID' password '$HOME_PASSWORD'"
fi

echo ""
echo "Reboot recommended: sudo reboot"
echo ""
```

## Manual Revert Steps

If you prefer to do it manually, SSH into the Pi via the AP (while you still can!) and run:

### 1. Stop Services

```bash
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo systemctl disable hostapd
sudo systemctl disable dnsmasq
sudo systemctl stop treadwall-ap.service 2>/dev/null || true
sudo systemctl disable treadwall-ap.service 2>/dev/null || true
```

### 2. Remove Configuration Files

```bash
sudo rm -f /etc/hostapd/hostapd.conf
sudo rm -f /etc/dnsmasq.conf
sudo rm -f /etc/systemd/network/08-wlan0.network
sudo rm -f /etc/NetworkManager/conf.d/unmanaged-wlan0.conf
sudo rm -f /etc/systemd/system/treadwall-ap.service
sudo rm -f /usr/local/bin/start-ap.sh
```

### 3. Remove Virtual Interface

```bash
sudo ip link delete wlan0_ap 2>/dev/null || true
```

### 4. Reset wlan0

```bash
sudo ip link set wlan0 down
sudo ip addr flush dev wlan0
sudo ip link set wlan0 up
```

### 5. Configure WiFi Client

```bash
# Create wpa_supplicant config
sudo mkdir -p /etc/wpa_supplicant

sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="YourHomeSSID"
    psk="YourPassword"
}
EOF

sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
```

### 6. Restart Network Services

```bash
sudo systemctl restart NetworkManager
# OR
sudo systemctl restart systemd-networkd
```

### 7. Connect to WiFi

**Using NetworkManager (modern Pi OS):**
```bash
nmcli device wifi list
nmcli device wifi connect "YourSSID" password "YourPassword"
```

**Using wpa_supplicant (older method):**
```bash
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
sudo dhclient wlan0
```

### 8. Verify Connection

```bash
iwgetid -r  # Should show your SSID
ip addr show wlan0  # Should show IP address
ping -c 3 8.8.8.8  # Test internet
```

### 9. Reboot (Recommended)

```bash
sudo reboot
```

After reboot, the Pi should automatically connect to your home WiFi.

## Accessing CRIMP After Revert

Once connected to home WiFi, access via:

**By hostname (easiest):**
```
http://treadwall.local:4567
```

**By IP address:**
```bash
# Find the IP
ping treadwall.local
# Or check your router's DHCP leases
```

Then open `http://<ip-address>:4567` in your browser.

## Checking Connection Status

```bash
# Check WiFi connection
iwgetid -r

# Check IP address
ip addr show wlan0

# Check route
ip route

# Test internet
ping -c 3 google.com
```

## Troubleshooting

### Can't Connect to WiFi

**Check WiFi is enabled:**
```bash
sudo rfkill list
# If blocked, unblock:
sudo rfkill unblock wifi
```

**Scan for networks:**
```bash
sudo iwlist wlan0 scan | grep SSID
```

**Check wpa_supplicant:**
```bash
sudo wpa_cli status
sudo journalctl -u wpa_supplicant
```

### NetworkManager Not Working

**Check status:**
```bash
sudo systemctl status NetworkManager
```

**Restart:**
```bash
sudo systemctl restart NetworkManager
```

**Use nmcli:**
```bash
nmcli device status
nmcli device wifi list
nmcli device wifi connect "YourSSID" password "YourPassword"
```

### Still Can't Get Online

**Check if you have an IP:**
```bash
ip addr show wlan0
```

**If no IP, request one:**
```bash
sudo dhclient wlan0
```

**Check DNS:**
```bash
cat /etc/resolv.conf
# Should have nameserver entries like 8.8.8.8
```

## Re-enabling AP Mode Later

When you get a USB WiFi adapter, see `docs/DUAL_WIFI_SETUP.md` for complete setup instructions.

The scripts are preserved in `scripts/`:
- `setup_dual_wifi_usb.sh` (for USB adapter - recommended)
- `setup_ap_only.sh` (for AP-only mode)
- `configure_wifi.sh` (for web UI WiFi config)

All the AP setup code is safely stored and documented!
