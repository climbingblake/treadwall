# USB Tethering - Quick Start Guide

## TL;DR

Transform your Pi Zero W into a portable climbing wall controller with internet from your phone.

## One-Time Setup (5 minutes)

1. **SSH into Pi:**
   ```bash
   ssh pi@treadwall.local
   ```

2. **Run setup script:**
   ```bash
   cd /home/pi/treadwall
   sudo ./scripts/setup_usb_tethering.sh
   ```

3. **Reboot:**
   ```bash
   sudo reboot
   ```

4. **Done!** The Pi is now ready for USB tethering.

## Daily Use

### Step 1: Connect Phone to Pi

**Hardware:**
- Power: Wall adapter/power bank → Pi **PWR** port
- Data: Phone → USB cable → Pi **USB** port (NOT PWR!)

**Phone Settings:**

**iOS:**
```
Settings → Personal Hotspot → Toggle ON
```

**Android:**
```
Settings → Network → Hotspot & Tethering → USB tethering ON
```

### Step 2: Connect Tablet to Pi

**WiFi Settings:**
- SSID: `TreadWall-Touch`
- Password: `yosemite`

### Step 3: Access App

**Open browser:**
```
http://192.168.4.1:4567
```

## Verify It's Working

### On the Pi (via SSH):

```bash
# Check USB interface
ip addr show usb0
# Should show: inet 172.20.10.x/28 (iOS) or 192.168.42.x/24 (Android)

# Check internet
ping -c 4 8.8.8.8

# View tethering logs
sudo tail -f /var/log/usb-tethering.log
```

### On the Tablet:

```bash
# Open browser and visit:
http://192.168.4.1:4567/api/network/status

# Should see:
{
  "usb_tethering": {
    "active": true,
    "ip": "172.20.10.3"
  }
}
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| usb0 interface doesn't exist | Enable tethering on phone, check USB cable |
| usb0 exists but no IP | Run: `sudo dhclient usb0` |
| Pi has internet but tablet doesn't | Restart: `sudo systemctl restart usb-tethering` |
| Can't connect to WiFi | Check SSID/password, restart Pi |

## Network Modes

| Interface | Purpose | IP Address |
|-----------|---------|------------|
| `usb0` | Internet from phone | 172.20.10.x (iOS) or 192.168.42.x (Android) |
| `wlan0` | WiFi AP for tablets | 192.168.4.1 |
| `lo` | Loopback | 127.0.0.1 |

## URLs

- **App**: http://192.168.4.1:4567
- **API Status**: http://192.168.4.1:4567/api/status
- **Network Status**: http://192.168.4.1:4567/api/network/status
- **System Info**: http://192.168.4.1:4567/api/system/info

## Data Flow

```
Phone Cellular → USB → Pi → WiFi AP → Tablet → Web Browser → Sinatra App
```

## Power Setup

```
┌──────────────┐
│ Power Bank   │
│  or Adapter  │
└──────┬───────┘
       │ micro-USB
       ▼
┌──────────────┐      ┌──────────────┐
│  Pi Zero W   │      │    Phone     │
│  PWR port ●─────────┼──USB port    │
│  USB port ●  │      │              │
└──────────────┘      └──────────────┘
       ▲                     ▲
       │ micro-USB           │
       │                     │ Cellular
```

## That's It!

Your climbing wall now has:
- ✅ Internet from phone's cellular
- ✅ Local WiFi AP for control
- ✅ Full Sinatra app access
- ✅ System updates anywhere

For detailed docs, see: **USB_TETHERING_README.md**
