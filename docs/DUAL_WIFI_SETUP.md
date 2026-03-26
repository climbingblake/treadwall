# Dual-Mode WiFi Setup (Future Implementation)

This document describes how to set up the CRIMP system with simultaneous Access Point and WiFi client capabilities using a USB WiFi adapter.

## Why USB WiFi Adapter?

The Raspberry Pi Zero 2 W has only one WiFi radio (wlan0), which cannot reliably run both Access Point and WiFi client modes simultaneously using virtual interfaces. The solution is to use a USB WiFi adapter:

- **wlan0** (built-in): Access Point for direct device control
- **wlan1** (USB adapter): WiFi client for home network/internet

## Hardware Requirements

### Recommended USB WiFi Adapters

**Budget Options (~$10-15):**
- TP-Link TL-WN725N (Realtek RTL8188EU)
- Edimax EW-7811Un (Realtek RTL8188CUS)
- Panda Wireless PAU05 (Ralink RT5370)

**Better Performance (~$20-30):**
- TP-Link Archer T2U Nano (Realtek RTL8811AU)
- ASUS USB-AC53 Nano (MediaTek MT7610U)

**Requirements:**
- USB 2.0 or better
- Linux driver support (most adapters work out-of-the-box on Raspberry Pi OS)
- Low power consumption (Pi Zero has limited USB power)

### Verifying Adapter Support

After plugging in the adapter:

```bash
# Check if adapter is detected
lsusb

# Check if wlan1 interface appeared
ip link show

# Check driver info
dmesg | tail -n 50
```

You should see `wlan1` listed.

## Setup Scripts

The repository includes setup scripts in `scripts/`:

### For USB WiFi Adapter Setup (Recommended)

**`scripts/setup_dual_wifi_usb.sh`** (to be created)
- Sets up wlan0 as Access Point
- Configures wlan1 (USB) as WiFi client
- Both work simultaneously

### For Single WiFi Radio (Not Recommended)

**`scripts/setup_dual_wifi_nm.sh`**
- Attempts virtual interface on single radio
- Works on some Pi models but unreliable on Pi Zero 2 W

**`scripts/setup_ap_only.sh`**
- Configures wlan0 as AP only
- No internet connectivity without ethernet

## Configuration Steps (With USB Adapter)

### 1. Install USB WiFi Adapter

```bash
# Plug in USB WiFi adapter
# Wait a few seconds

# Verify it's detected
ip link show wlan1
```

### 2. Run Setup Script

```bash
cd ~/treadwall
sudo ./scripts/setup_dual_wifi_usb.sh
```

The script will:
1. Configure wlan0 as Access Point
2. Configure wlan1 for home WiFi
3. Set up routing between interfaces
4. Enable DHCP on the AP
5. Configure NAT for internet sharing

### 3. Configure Home WiFi via Web UI

1. Connect to the Access Point (e.g., "TreadWall-Control")
2. Open `http://192.168.50.1:4567`
3. Scroll to **Network Configuration** section
4. Enter your home WiFi credentials
5. Click "Connect to Network"

The script will configure wlan1 to connect to your home network while keeping the AP running on wlan0.

## Network Configuration Feature

The web UI includes a **Network Configuration** section that allows users to:

- View AP status and IP
- View home network connection status
- Configure home WiFi credentials without SSH
- Reconnect to different networks as needed

### API Endpoints

**Get network status:**
```bash
curl http://192.168.50.1:4567/api/network/status
```

**Configure WiFi (requires sudo privileges):**
```bash
curl -X POST http://192.168.50.1:4567/api/network/configure \
  -H "Content-Type: application/json" \
  -d '{"ssid":"YourNetwork","password":"YourPassword"}'
```

### Backend Script

**`scripts/configure_wifi.sh`**
- Updates `/etc/wpa_supplicant/wpa_supplicant.conf`
- Stores encrypted PSK (not plaintext password)
- Applies configuration to wlan1
- Maintains AP on wlan0

**Required sudoers permission:**
```bash
sudo visudo
# Add:
pi ALL=(ALL) NOPASSWD: /home/pi/treadwall/scripts/configure_wifi.sh
```

## Network Topology

```
┌─────────────────┐
│   CRIMP Device  │
│                 │
│  ┌──────────┐   │
│  │  wlan0   │───┼───► Access Point (192.168.50.1)
│  │   (AP)   │   │     - Users connect here for control
│  └──────────┘   │     - SSID: TreadWall-Control
│                 │     - DHCP: 192.168.50.10-50
│  ┌──────────┐   │
│  │  wlan1   │───┼───► Home WiFi Network
│  │ (Client) │   │     - Internet access
│  └──────────┘   │     - Software updates
│                 │
└─────────────────┘
```

## Advantages

✅ **Always Accessible**: AP never goes down, even if home WiFi changes
✅ **No Reconfiguration**: Users can update WiFi via web UI
✅ **Internet Access**: Automatic updates and remote monitoring
✅ **Multi-Location**: Same device works anywhere
✅ **Zero-Touch Deployment**: Ship pre-configured, users add their WiFi

## Reverting to Single WiFi Mode

If you need to remove dual-mode and use wlan0 for WiFi client only:

See `docs/REVERT_TO_CLIENT_MODE.md`

## Troubleshooting

### AP Not Broadcasting

```bash
sudo systemctl status hostapd
sudo journalctl -u hostapd -n 50
```

**Common issues:**
- Interface not ready when hostapd starts
- Config file errors
- Conflicting network manager

### DHCP Not Working

```bash
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -n 50
```

**Common issues:**
- Interface doesn't exist when dnsmasq starts
- Port 53 already in use
- Incorrect interface binding

### WiFi Client Not Connecting (wlan1)

```bash
# Check wpa_supplicant status
sudo wpa_cli -i wlan1 status

# View available networks
sudo wpa_cli -i wlan1 scan
sudo wpa_cli -i wlan1 scan_results

# Check logs
sudo journalctl -u wpa_supplicant -n 50
```

### No Internet on Client Devices

```bash
# Check IP forwarding
cat /proc/sys/net/ipv4/ip_forward
# Should be: 1

# Check NAT rules
sudo iptables -t nat -L -n

# Test internet from Pi
ping -c 3 8.8.8.8
```

## Performance Considerations

**Expected Performance:**
- **wlan0 (AP)**: 802.11n, 2.4GHz, ~50Mbps
- **wlan1 (USB)**: Depends on adapter (802.11n/ac)
- **Latency**: <10ms for local control (AP)

**For motor control application:**
- Control commands are <1KB each
- Low bandwidth requirements
- AP performance is more than adequate

## Cost Analysis

**Single Device:**
- Raspberry Pi Zero 2 W: $15
- USB WiFi Adapter: $10-15
- SD Card (32GB): $10
- Case/Power: $10
- **Total: ~$45-50**

**vs. Ethernet-Only:**
- Requires ethernet cable at install location
- No portable/remote operation
- User can't reconfigure WiFi

**Dual-mode WiFi is worth the extra $10-15 for USB adapter!**

## Security Considerations

- AP password should be unique per device
- Home WiFi credentials stored encrypted (PSK)
- Web UI runs on private AP network
- Consider adding HTTPS for production
- Firewall rules limit exposure

## Future Enhancements

- [ ] Automatic USB adapter detection and configuration
- [ ] WiFi network scanning via web UI
- [ ] Signal strength indicators
- [ ] Fallback to AP-only if USB adapter removed
- [ ] Multiple saved WiFi networks with auto-connect
- [ ] VPN support for remote access
- [ ] HTTPS with self-signed certificates
- [ ] Web UI authentication/password protection
