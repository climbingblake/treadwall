# USB Tethering Mode - Setup Guide

## Overview

This branch configures the Pi Zero W to:
1. **Receive internet** from a phone via USB tethering (iOS or Android)
2. **Share that internet** to devices connected to its WiFi AP
3. **Run the Sinatra app** with full internet connectivity for updates

### Architecture

```
Phone (cellular data)
    ↓ USB cable (micro-USB)
Pi Zero W USB port (usb0 interface)
    ↓ iptables NAT bridge
Pi Zero W WiFi (wlan0 AP at 192.168.4.1)
    ↓ WiFi connection
Tablet/Control Device
    ↓ HTTP
Sinatra App (port 4567)
```

## Why USB Tethering?

**Problem Solved**: Dual-WiFi instability when home network is unavailable

**Alternative to**:
- ❌ Dual WiFi (wlan0 + wlan1 dongle) - unreliable scanning conflicts
- ❌ Bluetooth PAN - iOS doesn't grant entitlements
- ✅ USB tethering - rock solid, works with iOS and Android

**Benefits**:
- No WiFi scanning conflicts (only wlan0 runs as AP)
- Internet access for system updates anywhere
- Works with both iOS and Android phones
- Simple setup, auto-detects and configures

## Hardware Requirements

### Pi Zero W USB Ports
- **PWR port** (micro-USB): Power input - connect to power bank or wall adapter
- **USB port** (micro-USB OTG): Data - connect to phone for tethering

⚠️ **IMPORTANT**: You **must** power the Pi from the **PWR port** when using USB tethering. The USB OTG port cannot provide power while acting as a gadget.

### Cables Needed

**For iOS:**
- Lightning to USB-A cable (comes with iPhone)
- USB-A female to micro-USB male adapter
- OR: USB-C to micro-USB cable (for USB-C iPhones)

**For Android:**
- USB-C to micro-USB cable (most modern Android phones)
- OR: micro-USB to micro-USB cable (older Android phones)

**Recommendation**: Keep a USB-C to micro-USB cable attached to the Pi for universal compatibility.

## Installation

### One-Time Setup on Pi Zero W

1. **SSH into the Pi** or connect a monitor/keyboard

2. **Navigate to the project directory:**
   ```bash
   cd /home/pi/treadwall
   ```

3. **Run the setup script:**
   ```bash
   sudo ./scripts/setup_usb_tethering.sh
   ```

   This script will:
   - ✅ Enable USB gadget mode (dwc2, g_ether)
   - ✅ Install iOS/Android tethering support
   - ✅ Configure WiFi AP on wlan0 (192.168.4.1)
   - ✅ Set up DHCP server (dnsmasq)
   - ✅ Enable IP forwarding
   - ✅ Install auto-bridge service
   - ✅ Create systemd service for monitoring

4. **Reboot the Pi:**
   ```bash
   sudo reboot
   ```

5. **After reboot, the Pi will be ready for USB tethering**

## Usage

### Connecting a Phone

#### iOS (iPhone/iPad)

1. **Connect iPhone to Pi via USB:**
   - Phone Lightning port → USB cable → micro-USB adapter → Pi USB port

2. **Enable Personal Hotspot on iPhone:**
   - Settings → Personal Hotspot → Toggle ON
   - "Allow Others to Join" → ON
   - You'll see "1 Connection" when the Pi connects

3. **Verify connection on Pi:**
   ```bash
   # Check if usb0 interface exists
   ip addr show usb0

   # Should show an IP like 172.20.10.x
   ```

#### Android

1. **Connect Android phone to Pi via USB:**
   - Phone USB-C port → USB cable → micro-USB adapter → Pi USB port

2. **Enable USB tethering on Android:**
   - Settings → Network & Internet → Hotspot & Tethering
   - Toggle "USB tethering" ON

3. **Verify connection on Pi:**
   ```bash
   ip addr show usb0
   # Should show an IP assigned by the phone
   ```

### Connecting a Tablet/Control Device

1. **Connect to the Pi's WiFi AP:**
   - SSID: `TreadWall-Touch` (or whatever is in config.json)
   - Password: `yosemite` (or whatever is in config.json)
   - IP: 192.168.4.1

2. **Access the Sinatra app:**
   - Open browser: `http://192.168.4.1:4567`

3. **The tablet now has internet** via: Tablet → Pi WiFi → Pi USB → Phone cellular

## Monitoring & Troubleshooting

### Check USB Tethering Status

```bash
# Check if usb-tethering service is running
sudo systemctl status usb-tethering

# View real-time logs
sudo tail -f /var/log/usb-tethering.log

# Check all network interfaces
ip addr show
```

### Expected Interface Layout

When everything is working:

```bash
$ ip addr show

# Loopback
1: lo: <LOOPBACK,UP,LOWER_UP>
    inet 127.0.0.1/8

# WiFi AP (for tablets to connect)
2: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP>
    inet 192.168.4.1/24

# USB tethering (internet from phone)
3: usb0: <BROADCAST,MULTICAST,UP,LOWER_UP>
    inet 172.20.10.3/28  # iOS example
    # OR
    inet 192.168.42.129/24  # Android example
```

### Check Internet Connectivity

From the Pi:
```bash
# Ping Google via USB internet
ping -c 4 8.8.8.8

# Check DNS resolution
nslookup google.com
```

From a connected tablet:
```bash
# Ping Google via bridged connection
ping 8.8.8.8
```

### Check iptables NAT Rules

```bash
# View NAT rules
sudo iptables -t nat -L -v

# Should see MASQUERADE rule for usb0
sudo iptables -L FORWARD -v

# Should see ACCEPT rules for wlan0 ↔ usb0
```

## Troubleshooting

### Problem: usb0 interface doesn't appear

**Cause**: USB gadget mode not enabled or phone not in tethering mode

**Solution**:
```bash
# Check if dwc2 module is loaded
lsmod | grep dwc2

# Check boot config
grep dwc2 /boot/config.txt
grep g_ether /boot/cmdline.txt

# If missing, re-run setup script
sudo ./scripts/setup_usb_tethering.sh
sudo reboot
```

### Problem: usb0 exists but no IP

**iOS**: Make sure "Personal Hotspot" is enabled
**Android**: Make sure "USB tethering" is enabled

**Force DHCP request**:
```bash
sudo dhclient -v usb0
```

### Problem: Pi has internet but tablet doesn't

**Cause**: iptables bridge not configured or IP forwarding disabled

**Solution**:
```bash
# Check IP forwarding
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1

# Manually configure bridge
sudo iptables -t nat -A POSTROUTING -o usb0 -j MASQUERADE
sudo iptables -A FORWARD -i wlan0 -o usb0 -j ACCEPT
sudo iptables -A FORWARD -i usb0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save rules
sudo netfilter-persistent save

# Restart service
sudo systemctl restart usb-tethering
```

### Problem: iOS device won't connect

**Cause**: Missing libimobiledevice or ipheth modules

**Solution**:
```bash
# Install iOS support
sudo apt-get update
sudo apt-get install libimobiledevice-utils ipheth-utils

# Load ipheth module
sudo modprobe ipheth

# Restart
sudo reboot
```

### Problem: Everything works but internet is slow

**Expected Performance**:
- USB 2.0 max: ~480 Mbps
- Phone USB tethering: 100-300 Mbps typical
- Pi Zero W WiFi: ~40 Mbps typical
- **Bottleneck**: Pi Zero W WiFi (this is the limiting factor)

**Reality**: Your tablet will get 20-40 Mbps, which is more than enough for the Sinatra app and system updates.

## Auto-Start Behavior

After installation, the system automatically:

1. **On boot**:
   - WiFi AP starts on wlan0 (192.168.4.1)
   - DHCP server ready for tablets
   - usb-tethering service monitors for USB connections

2. **When phone is connected via USB**:
   - Auto-detects usb0 interface
   - Requests IP via DHCP from phone
   - Configures iptables NAT bridge
   - Logs event to `/var/log/usb-tethering.log`

3. **When phone is disconnected**:
   - Auto-cleans up iptables rules
   - Releases DHCP lease
   - WiFi AP continues running (no internet to clients)

4. **Sinatra app**:
   - Continues running regardless of USB state
   - Accessible at 192.168.4.1:4567 from AP clients
   - Can perform system updates when USB internet is available

## Network Topology Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Your Phone                            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Cellular Connection (LTE/5G)                         │  │
│  └─────────────────────┬─────────────────────────────────┘  │
│                        │                                     │
│  ┌─────────────────────▼─────────────────────────────────┐  │
│  │  USB Tethering (Personal Hotspot / USB Tethering)    │  │
│  └─────────────────────┬─────────────────────────────────┘  │
└────────────────────────┼─────────────────────────────────────┘
                         │ USB cable (micro-USB)
                         │
┌────────────────────────▼─────────────────────────────────────┐
│                    Pi Zero W                                  │
│  ┌───────────────────────────────────────────────────────┐   │
│  │  usb0 interface (172.20.10.x or 192.168.42.x)        │   │
│  └─────────────────────┬─────────────────────────────────┘   │
│                        │                                      │
│  ┌─────────────────────▼─────────────────────────────────┐   │
│  │  iptables NAT (IP forwarding + MASQUERADE)           │   │
│  └─────────────────────┬─────────────────────────────────┘   │
│                        │                                      │
│  ┌─────────────────────▼─────────────────────────────────┐   │
│  │  wlan0 interface (192.168.4.1) - WiFi AP             │   │
│  │  SSID: TreadWall-Touch                               │   │
│  │  DHCP: 192.168.4.10 - 192.168.4.50                   │   │
│  └─────────────────────┬─────────────────────────────────┘   │
│                        │                                      │
│  ┌─────────────────────▼─────────────────────────────────┐   │
│  │  Sinatra App (crimp_app.rb)                          │   │
│  │  Port: 4567                                           │   │
│  │  Access: http://192.168.4.1:4567                     │   │
│  └───────────────────────────────────────────────────────┘   │
└────────────────────────┬─────────────────────────────────────┘
                         │ WiFi broadcast
                         │
┌────────────────────────▼─────────────────────────────────────┐
│                Tablet / Control Device                        │
│  ┌───────────────────────────────────────────────────────┐   │
│  │  WiFi: Connected to TreadWall-Touch                   │   │
│  │  IP: 192.168.4.x (via DHCP)                           │   │
│  │  Gateway: 192.168.4.1                                 │   │
│  │  Internet: ✅ (via phone's cellular)                  │   │
│  └─────────────────────┬─────────────────────────────────┘   │
│                        │                                      │
│  ┌─────────────────────▼─────────────────────────────────┐   │
│  │  Web Browser: http://192.168.4.1:4567                │   │
│  └───────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

## Configuration Files

### Modified by Setup Script

- `/boot/config.txt` - Added `dtoverlay=dwc2`
- `/boot/cmdline.txt` - Added `modules-load=dwc2,g_ether`
- `/etc/dhcpcd.conf` - Static IP for wlan0 (192.168.4.1)
- `/etc/hostapd/hostapd.conf` - WiFi AP configuration
- `/etc/dnsmasq.conf` - DHCP server configuration
- `/etc/sysctl.conf` - IP forwarding enabled
- `/etc/systemd/system/usb-tethering.service` - Auto-bridge service
- `/usr/local/bin/usb-tethering-bridge.sh` - Bridge monitoring script

### Backups Created

The setup script creates backups before modifying:
- `/boot/config.txt.backup`
- `/boot/cmdline.txt.backup`
- `/etc/dnsmasq.conf.original`

### Restore to Original State

If you need to undo USB tethering mode:

```bash
# Restore boot config
sudo cp /boot/config.txt.backup /boot/config.txt
sudo cp /boot/cmdline.txt.backup /boot/cmdline.txt

# Disable services
sudo systemctl disable usb-tethering
sudo systemctl disable hostapd
sudo systemctl disable dnsmasq

# Reboot
sudo reboot
```

## Compatibility with Other Branches

### Main Branch (Original Sinatra)
- **Compatible**: USB tethering works with existing Sinatra app
- **No changes needed**: crimp_app.rb runs unchanged

### Bluetooth Branch
- **Can coexist**: BLE GATT server can run alongside WiFi AP
- **Use case**: BLE for control, USB tethering for internet

## Performance Characteristics

### Throughput
- **Cellular → USB**: 100-300 Mbps (depends on phone and carrier)
- **USB → Pi**: ~200 Mbps (USB 2.0 limit on Pi Zero)
- **Pi → WiFi AP**: ~40 Mbps (Pi Zero W WiFi limit)
- **Effective tablet speed**: 20-40 Mbps

**Verdict**: More than enough for the Sinatra app and system updates

### Latency
- Additional hop adds ~5-10ms
- Total latency to internet: depends on cellular connection
- Local app access (192.168.4.1:4567): <5ms

### Power Consumption
- USB tethering: ~100-200mA additional draw on phone
- Pi Zero W: ~120-150mA (same as before)
- **Impact on phone battery**: Minimal (similar to normal hotspot use)

## Security Considerations

### WiFi AP Security
- WPA2-PSK encryption
- Password from config.json (default: "yosemite")
- **Recommendation**: Change default password in `config.json`

### USB Tethering Security
- USB connection is point-to-point (phone ↔ Pi)
- No security risk beyond physical access
- Phone controls internet access via tethering toggle

### Access Control
- Only devices with WiFi password can connect to AP
- Sinatra app has no authentication (assumes trusted network)
- **Recommendation**: Add HTTP basic auth if needed

## Cost Analysis

### Hardware Cost
- Pi Zero W: $10-15 (you already have)
- USB-C to micro-USB cable: $5-10
- Power bank (optional): $15-30

**Total additional cost**: $5-10 for the cable

### Data Cost
- Uses phone's cellular data plan
- Typical app usage: <10 MB/hour
- System updates: 50-200 MB (occasional)

**Total data usage**: Minimal impact on phone plan

## FAQ

**Q: Can I use WiFi and USB tethering at the same time?**
A: Yes! The Pi can have internet via USB (usb0) while providing AP service (wlan0). They don't conflict.

**Q: What happens if I disconnect the phone?**
A: The WiFi AP continues running, but clients lose internet. Local app access still works at 192.168.4.1:4567.

**Q: Can I switch between iOS and Android phones?**
A: Yes, the bridge automatically detects and configures either. Just plug in and enable tethering.

**Q: Does this drain my phone battery faster?**
A: Slightly, similar to running a normal WiFi hotspot. Keep phone charged during long sessions.

**Q: Can I use a USB hub to connect multiple devices?**
A: No, USB gadget mode only supports one host (phone) at a time.

**Q: Will this work with iPad tethering?**
A: Yes, iPads with cellular can tether via USB just like iPhones.

**Q: Can I access the internet from the Pi itself?**
A: Yes! The Pi can perform system updates, git pulls, apt installs, etc. via the USB tethering connection.

**Q: Does this affect the Sinatra app?**
A: No changes to the app. It continues running normally on port 4567.

## Summary

USB tethering mode provides a **rock-solid, simple solution** to the dual-WiFi instability problem:

✅ **Pros:**
- No WiFi scanning conflicts
- Works with iOS and Android
- Internet access anywhere with cellular coverage
- Simple setup, auto-configures
- Sinatra app unchanged

❌ **Cons:**
- Requires USB cable connection
- Drains phone battery slightly
- Adds one more cable to manage

**Recommendation**: This is the most reliable option for portable treadwall use with internet access.
