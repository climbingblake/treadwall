# Pi Zero W Setup - WiFi + USB Tethering

This guide explains the **simplified** setup for Pi Zero W with automatic WiFi/USB fallback.

## Architecture Overview

The Pi Zero W operates in **two simple modes** that work automatically:

### Mode 1: WiFi Client (Primary)
- Pi connects to your home WiFi network
- Access from any device on the same network
- Full internet access for software updates
- **Interface:** `wlan0`
- **Access:** `http://treadwall.local:4567` or `http://<pi-ip>:4567`

### Mode 2: USB Tethering (Automatic Fallback)
- When WiFi is unavailable or you're away from home
- Connect iPhone via USB cable
- Enable Personal Hotspot on iPhone
- Pi gets internet from phone's cellular data
- Access web interface directly from phone
- **Interface:** `eth0` (created automatically by iOS)
- **IP Range:** `172.20.10.x` (iOS) or `192.168.42.x` (Android)
- **Access from phone:** `http://172.20.10.x:4567` (check `ip addr show eth0` for exact IP)

**Both modes can be active simultaneously** - the Pi can be on WiFi AND connected via USB at the same time.

## How It Works (The Simple Truth)

**You don't need USB gadget mode!** The Pi Zero W works as a normal USB host:
- iPhone provides USB tethering just like it does to a laptop
- Pi's USB port acts as a host (default behavior)
- No special kernel modules or gadget configuration needed
- The `ipheth` driver (built into Raspberry Pi OS) handles iPhone connectivity

## Initial Setup

### Prerequisites
- Pi Zero W with Raspberry Pi OS (Bookworm or newer)
- USB cable: micro-USB (Pi) to USB-C or Lightning (phone)
- Access to Pi via keyboard/monitor OR existing network connection

### 1. Configure WiFi (Optional but Recommended)

If you want WiFi as your primary connection:

```bash
# Edit wpa_supplicant configuration
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
```

Add your network:
```
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="YourNetworkName"
    psk="YourPassword"
}
```

Or use `wpa_passphrase` for hashed password:
```bash
wpa_passphrase "YourNetworkName" "YourPassword" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf
```

Restart networking:
```bash
sudo systemctl restart wpa_supplicant
sudo systemctl restart dhcpcd
```

### 2. Install iOS USB Support (Already Included)

Raspberry Pi OS includes `ipheth` support by default. Verify:

```bash
# Check if ipheth module exists
modinfo ipheth

# Install additional iOS tools if needed (optional)
sudo apt-get update
sudo apt-get install -y libimobiledevice-utils ipheth-utils
```

### 3. Verify Configuration

Check that Pi is NOT in USB gadget mode:

```bash
# Check boot config - should have NO dwc2 peripheral settings
grep -i dwc2 /boot/firmware/config.txt

# If you see dtoverlay=dwc2,dr_mode=peripheral - REMOVE it!
# Default (host mode) is what you want
```

**Important:** The Pi Zero W defaults to USB **host mode**, which is exactly what we need for iPhone tethering. Don't add any USB gadget configuration!

### 4. Test Connection

**With iPhone:**

1. Connect USB cable:
   - **Pi Zero:** Use the micro-USB port labeled **"USB"** (NOT "PWR")
   - **iPhone:** Use your normal charging cable (Lightning or USB-C)
   - Use adapters if needed (micro-USB to USB-A to USB-C works fine)

2. On iPhone:
   - Go to **Settings → Personal Hotspot**
   - Turn ON **"Allow Others to Join"**
   - You may see "Trust This Computer?" - tap **Trust**

3. On Pi (via SSH or monitor):
   ```bash
   # Check if eth0 interface appeared
   ip link show eth0

   # Should show UP and have an IP address
   ip addr show eth0

   # Look for: inet 172.20.10.x/28
   ```

4. From iPhone Safari:
   - Find Pi's IP: `ssh pi@treadwall.local "ip -4 addr show eth0 | grep inet"`
   - Or check on Pi: `ip -4 addr show eth0 | grep inet`
   - Open Safari: `http://172.20.10.7:4567` (use your actual IP)

**With Android:**

1. Connect USB cable to Pi's USB port
2. On Android: Settings → Network → USB tethering → Enable
3. Pi should get `usb0` interface with IP `192.168.42.129`
4. Access from phone: `http://192.168.42.129:4567`

## Network Status Monitoring

The web interface Settings page shows:

- **Mode:** WiFi Client, USB Tethering, or Disconnected
- **Interface:** wlan0, eth0, usb0, or None
- **IP Address:** Current assigned IP
- **Internet:** Whether Pi can reach the internet

### Check Status via Command Line

```bash
# Show all network interfaces
ip addr show

# Common interfaces:
# - lo: Loopback (always present)
# - wlan0: WiFi (when connected to home network)
# - eth0: iPhone USB tethering (when iPhone connected)
# - usb0: Android USB tethering (when Android connected)

# Test internet connectivity
ping -c 3 8.8.8.8

# Check which interface has default route
ip route show default
```

## Updating WiFi Credentials

### Via Web Interface (Recommended)

1. Access Settings page in web UI
2. Scroll to **Network Configuration** section
3. Enter new WiFi SSID and password
4. Click **Update WiFi Credentials**
5. Pi will automatically attempt to connect

### Via Command Line

```bash
# Method 1: Edit wpa_supplicant directly
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf

# Method 2: Use wpa_passphrase
wpa_passphrase "NewNetwork" "NewPassword" | sudo tee /etc/wpa_supplicant/wpa_supplicant.conf

# Restart WiFi
sudo systemctl restart wpa_supplicant dhcpcd
```

## Power Considerations

**CRITICAL: Pi Zero W has TWO micro-USB ports!**

- **PWR port:** Power input only (5V, 2.5A recommended)
- **USB port:** Data connection for USB tethering

**Correct setup when using USB tethering:**
```
Power adapter → PWR port (powers the Pi)
iPhone/Android → USB port (provides network + additional power)
```

**Note:** The USB data port also provides some power, but it's not enough to reliably power the Pi Zero W. Always use a proper power supply on the PWR port.

## Troubleshooting

### WiFi Not Connecting

```bash
# Check WiFi status
sudo systemctl status wpa_supplicant

# Scan for networks
sudo iwlist wlan0 scan | grep SSID

# Check WiFi credentials
sudo cat /etc/wpa_supplicant/wpa_supplicant.conf

# Restart WiFi
sudo systemctl restart wpa_supplicant
sudo systemctl restart dhcpcd
```

### USB Tethering Not Working

**Check iPhone connection:**

```bash
# Look for eth0 interface
ip link show eth0

# If it doesn't exist, check:
dmesg | grep -i ipheth

# Should see messages like:
# ipheth 1-1:4.2: Apple iPhone USB Ethernet device attached
```

**Common issues:**

1. **Wrong USB port on Pi:**
   - Must use the port labeled "USB" (data port)
   - NOT the port labeled "PWR" (power only)

2. **Personal Hotspot not enabled on iPhone:**
   - Settings → Personal Hotspot → Turn ON
   - Must show "Allow Others to Join" enabled

3. **Cable issues:**
   - Some cables are power-only, no data
   - Try a different cable or adapter combination
   - Apple's original cables work best

4. **Trust dialog on iPhone:**
   - First time: iPhone asks "Trust This Computer?"
   - Tap "Trust" - required for USB tethering

5. **Check ipheth driver:**
   ```bash
   # Manually load if needed
   sudo modprobe ipheth

   # Check if loaded
   lsmod | grep ipheth
   ```

### No Internet Access

**On WiFi:**
```bash
# Check router connectivity
ping 10.0.0.1  # Your router IP

# Check DNS
ping 8.8.8.8

# Check gateway
ip route show default
```

**On USB:**
```bash
# Check iPhone provided gateway
ip route show

# Should see default via 172.20.10.1 dev eth0
# (or similar iOS IP range)

# Test with DNS
ping 8.8.8.8
```

### Finding Your Pi's IP Address

**When on home WiFi:**
```bash
# Use mDNS (usually works)
ping treadwall.local

# Or check router's DHCP leases
# Or use: hostname -I
```

**When on USB:**
```bash
# From Pi itself (via SSH to WiFi IP or keyboard/monitor):
ip -4 addr show eth0 | grep inet

# Shows: inet 172.20.10.7/28 (example)
# Use this IP from iPhone browser
```

## API Endpoints

The web interface uses these endpoints to show network status:

### Get Network Status
```bash
GET http://<pi-ip>:4567/api/network/status
```

Response:
```json
{
  "success": true,
  "mode": "wifi_client",
  "mode_description": "WiFi Client Mode",
  "interface": "wlan0",
  "ip_address": "10.0.0.42",
  "wifi": {
    "connected": true,
    "ssid": "Farmhouse",
    "signal": "-45",
    "configured_ssid": "Farmhouse"
  },
  "usb": {
    "connected": false,
    "ip": "Not connected"
  },
  "internet": true
}
```

When USB tethering is active (eth0 interface):
```json
{
  "success": true,
  "mode": "usb_fallback",
  "mode_description": "USB Tethering Mode (fallback)",
  "interface": "eth0",
  "ip_address": "172.20.10.7",
  "wifi": {
    "connected": false,
    "ssid": "Not connected",
    "signal": "N/A",
    "configured_ssid": "Farmhouse"
  },
  "usb": {
    "connected": true,
    "ip": "172.20.10.7"
  },
  "internet": true
}
```

### Update WiFi Credentials
```bash
POST http://<pi-ip>:4567/api/network/configure
Content-Type: application/json

{
  "ssid": "YourNetworkName",
  "password": "YourPassword"
}
```

## Files and Locations

### Configuration Files

- `/etc/wpa_supplicant/wpa_supplicant.conf` - WiFi credentials
- `/boot/firmware/config.txt` - Boot configuration (should NOT have dwc2 gadget settings)
- `/boot/firmware/cmdline.txt` - Kernel boot parameters
- `config.json` - App configuration (WiFi credentials also stored here)

### Network Detection Script

The Ruby app (`crimp_app.rb`) detects network mode:

```ruby
def detect_network_mode
  # Check if wlan0 has an IP (connected to WiFi)
  wlan0_ip = `ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'`.strip
  wlan0_connected = !wlan0_ip.empty?

  # Check if usb0 or eth0 interface exists and has IP
  usb0_exists = system('ip link show usb0 >/dev/null 2>&1')
  eth0_exists = system('ip link show eth0 >/dev/null 2>&1')

  usb0_ip = `ip -4 addr show usb0 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'`.strip if usb0_exists
  eth0_ip = `ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'`.strip if eth0_exists

  usb_connected = (usb0_exists && !usb0_ip.to_s.empty?) || (eth0_exists && !eth0_ip.to_s.empty?)

  if wlan0_connected
    { mode: 'wifi_client', interface: 'wlan0', ip: wlan0_ip }
  elsif usb_connected
    interface = usb0_exists && !usb0_ip.to_s.empty? ? 'usb0' : 'eth0'
    ip = usb0_ip.to_s.empty? ? eth0_ip : usb0_ip
    { mode: 'usb_fallback', interface: interface, ip: ip }
  else
    { mode: 'disconnected', interface: nil, ip: nil }
  end
end
```

## What NOT to Do

❌ **Do NOT configure USB gadget mode** - The Pi should be a USB host, not a gadget
❌ **Do NOT add `dtoverlay=dwc2,dr_mode=peripheral`** - This breaks iPhone tethering
❌ **Do NOT load `g_ether` or `g_cdc` modules** - Not needed for iPhone tethering
❌ **Do NOT configure hostapd or dnsmasq** - No Access Point needed
❌ **Do NOT try to create a virtual `usb0` interface** - iOS creates `eth0` automatically

## What Changed from Original Plan

**Original (overly complex) plan:**
- USB gadget mode with `g_ether` module
- Pi acts as USB device providing ethernet to phone
- Phone had to connect to Pi's network AND use USB
- Required configfs, libcomposite, complex setup

**Actual working solution (simple):**
- Default USB host mode (no special configuration)
- iPhone provides USB tethering to Pi (like to a laptop)
- Built-in `ipheth` driver handles everything automatically
- Works out of the box with Raspberry Pi OS

**Lesson learned:** Sometimes the default configuration is exactly what you need!

## Support and Diagnostics

### Full Network Diagnostic

```bash
#!/bin/bash
echo "=== Network Diagnostic ==="
echo ""
echo "All interfaces:"
ip addr show
echo ""
echo "Default route:"
ip route show default
echo ""
echo "WiFi status:"
iwgetid -r
echo ""
echo "Internet connectivity:"
ping -c 3 8.8.8.8
echo ""
echo "iPhone USB (eth0):"
ip addr show eth0 2>/dev/null || echo "Not connected"
echo ""
echo "Android USB (usb0):"
ip addr show usb0 2>/dev/null || echo "Not connected"
```

Save as `network-diagnostic.sh`, make executable, and run:
```bash
chmod +x network-diagnostic.sh
./network-diagnostic.sh
```

### Check iOS USB Connection

```bash
# Check if iOS device is detected
lsusb | grep -i apple

# Check ipheth driver logs
dmesg | grep -i ipheth | tail -10

# Check eth0 interface details
ip addr show eth0
ethtool eth0 2>/dev/null
```

## Summary

The Pi Zero W USB tethering setup is **remarkably simple**:

1. ✅ No special USB gadget configuration needed
2. ✅ Default USB host mode works perfectly
3. ✅ iPhone/Android provide network just like to a laptop
4. ✅ WiFi and USB can work simultaneously
5. ✅ Automatic fallback from WiFi to USB when needed

**That's it!** The complexity we initially planned was completely unnecessary. The Pi Zero W's default configuration handles iPhone USB tethering natively.
