# Pi Zero W Setup - USB Fallback Mode

This guide explains how to configure the Pi Zero W for the TreadWall control system with automatic WiFi/USB fallback.

## Architecture

The Pi Zero W operates in **two simple modes**:

### 1. WiFi Client Mode (Primary)
- Pi connects to your home WiFi network (e.g., "Farmhouse")
- Access the web interface from any device on the same network
- Full internet access for software updates
- Access URL: `http://treadwall.local:4567` or `http://<pi-ip>:4567`

### 2. USB Tethering Mode (Automatic Fallback)
- When WiFi is unavailable, the Pi falls back to USB ethernet
- Connect phone via USB cable to Pi's **USB port** (NOT PWR port)
- Enable USB tethering on your phone:
  - **iOS**: Settings → Personal Hotspot → Allow Others to Join
  - **Android**: Settings → Network → USB tethering
- Access from phone browser: `http://172.20.10.2:4567` (iOS) or `http://192.168.42.129:4567` (Android)
- Phone's cellular data provides internet to Pi (for updates)
- Can update WiFi credentials from the Settings page

## Initial Setup

### 1. Run Setup Script

```bash
sudo ./scripts/setup_usb_fallback.sh
```

**What it does:**
- Enables USB gadget mode (dwc2 + g_ether kernel modules)
- Configures wpa_supplicant for home WiFi (optional)
- Sets up automatic fallback: WiFi → USB
- Removes old AP mode configurations (hostapd, dnsmasq)
- Creates auto-DHCP service for USB interface

**During setup, you'll be asked:**
- Home WiFi SSID (can skip for USB-only mode)
- Home WiFi password

### 2. Reboot

```bash
sudo reboot
```

### 3. Connect

**If you provided WiFi credentials:**
- Pi will attempt to connect to home WiFi automatically
- If successful: access via `http://treadwall.local:4567`
- If WiFi fails: connect via USB (see USB Tethering Mode above)

**If you skipped WiFi setup:**
- Pi will only be accessible via USB
- Connect phone via USB and enable tethering
- Access from phone and configure WiFi in Settings page

## Updating WiFi Credentials

You can update WiFi credentials at any time through the web interface:

1. Access the Settings page (Settings tab)
2. Scroll to **Network Configuration** section
3. Enter new WiFi SSID and password
4. Click **Update WiFi Credentials**
5. Pi will attempt to connect automatically

**Note:** USB access remains available if WiFi connection fails.

## Monitoring

### Check Current Network Mode

The Settings page shows:
- **Mode**: WiFi Client Mode or USB Tethering Mode (fallback)
- **IP Address**: Current IP assigned to Pi
- **Interface**: wlan0 (WiFi) or usb0 (USB)
- **Internet**: Whether Pi has internet connectivity
- **WiFi Details**: Configured SSID, current connection, signal strength

### Check Service Status

```bash
# Check wpa_supplicant (WiFi)
sudo systemctl status wpa_supplicant

# Check USB gadget DHCP service
sudo systemctl status usb-gadget-dhcp

# View network interfaces
ip addr show
```

### Logs

USB DHCP service logs:
```bash
sudo journalctl -u usb-gadget-dhcp -f
```

## Troubleshooting

### WiFi Not Connecting

1. Check WiFi credentials in `/etc/wpa_supplicant/wpa_supplicant.conf`
2. Verify WiFi network is in range: `sudo iwlist wlan0 scan | grep SSID`
3. Restart wpa_supplicant: `sudo systemctl restart wpa_supplicant`
4. Use USB mode to access Settings and update credentials

### USB Mode Not Working

1. Verify you're using the **USB port** (NOT PWR port) on Pi Zero
2. Check if usb0 interface exists: `ip link show usb0`
3. On phone, disable and re-enable USB tethering
4. Try different USB cable (data cable, not power-only)
5. Check USB gadget modules loaded: `lsmod | grep g_ether`

### No Internet Access

**In WiFi Mode:**
- Check router internet connection
- Verify Pi has gateway: `ip route show`
- Test DNS: `ping 8.8.8.8`

**In USB Mode:**
- Ensure phone has cellular data enabled
- Check USB tethering is active on phone
- Verify usb0 has IP: `ip addr show usb0`

## Power Considerations

**IMPORTANT:** Power the Pi Zero W from the **PWR** port, not the USB port!

- **PWR port**: Power input (5V, 2.5A recommended)
- **USB port**: Data connection only (for USB tethering)

When using USB tethering, you need **two connections**:
1. PWR port → power adapter
2. USB port → phone (for data)

## What Changed from Previous Setup

**Removed (no longer needed):**
- ❌ hostapd (WiFi Access Point)
- ❌ dnsmasq (DHCP server)
- ❌ "TreadWall-Touch" WiFi network
- ❌ wlan0 static IP (192.168.4.1)
- ❌ iptables NAT bridging
- ❌ Complex mode switching scripts

**New simplified approach:**
- ✅ wpa_supplicant for home WiFi (always enabled)
- ✅ USB gadget mode (always enabled, harmless when unplugged)
- ✅ Automatic fallback: try WiFi → if fails, USB is available
- ✅ Simple credential updates via web UI
- ✅ No need to create separate AP network

## Files and Locations

### Configuration Files

- `/etc/wpa_supplicant/wpa_supplicant.conf` - WiFi credentials
- `/boot/config.txt` - USB gadget device tree overlay
- `/boot/cmdline.txt` - USB ethernet module loading
- `/etc/systemd/system/usb-gadget-dhcp.service` - Auto-DHCP for USB
- `config.json` - App configuration (WiFi credentials stored here too)

### Scripts

- `scripts/setup_usb_fallback.sh` - Initial setup script (run once)
- `scripts/archived_ap_mode/` - Old AP mode scripts (for reference)

## API Endpoints

### Network Status
```bash
GET /api/network/status
```

Returns:
```json
{
  "success": true,
  "mode": "wifi_client",  // or "usb_fallback" or "disconnected"
  "mode_description": "WiFi Client Mode",
  "interface": "wlan0",   // or "usb0"
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

### Update WiFi Credentials
```bash
POST /api/network/configure
Content-Type: application/json

{
  "ssid": "YourNetworkName",
  "password": "YourPassword"
}
```

## Security Notes

- WiFi passwords are hashed in `wpa_supplicant.conf` using WPA-PSK
- Plain text passwords stored in `config.json` (protect this file!)
- Web interface has no authentication (use firewall if concerned)
- USB gadget mode creates direct network link (no authentication)

## Support

For issues or questions:
1. Check logs: `sudo journalctl -xe`
2. Review service status: `systemctl status`
3. Access Settings page for network diagnostics
4. Use USB mode as emergency access when WiFi fails
