# Before Testing USB Tethering - Revert to WiFi Client

## Why This Step?

Before testing USB tethering, you should:
1. Remove the dual-WiFi setup (AP + client)
2. Connect Pi to home WiFi
3. Do system updates
4. Then set up USB tethering fresh

This avoids conflicts between old AP configs and new USB tethering setup.

---

## Quick Steps

### 1. SSH into Pi (current setup)

If dual-WiFi is currently active:
```bash
# Connect to the AP
# SSID: TreadWall-Touch (or whatever is in config.json)
# Then SSH to: 192.168.4.1

ssh pi@192.168.4.1
```

OR if you know the Pi's home network IP:
```bash
ssh pi@<pi-ip-address>
# or
ssh pi@treadwall.local
```

### 2. Run the revert script

```bash
cd /home/pi/treadwall
sudo ./scripts/revert_to_client.sh
```

**You'll be prompted for**:
- Home WiFi SSID (your network name)
- WiFi password

**Script will**:
- Stop AP services (hostapd, dnsmasq)
- Remove AP configuration files
- Configure wlan0 for WiFi client mode
- Connect to your home network

### 3. Note the new IP address

The script will display:
```
Connected to: YourHomeNetwork
IP Address: 192.168.1.xxx

You can now access the device at:
  http://192.168.1.xxx:4567
  http://treadwall.local:4567
```

**Write down this IP!**

### 4. Reboot (recommended)

```bash
sudo reboot
```

### 5. Reconnect after reboot

```bash
ssh pi@<new-ip-address>
# or
ssh pi@treadwall.local
```

### 6. Verify internet connection

```bash
ping -c 4 8.8.8.8
curl -I https://google.com
```

### 7. Do system updates

```bash
# Update package lists
sudo apt-get update

# Upgrade packages
sudo apt-get upgrade -y

# Update git repo (if needed)
cd /home/pi/treadwall
git fetch origin
git status
```

---

## After Updates - Set Up USB Tethering

Once you're on home WiFi and updated:

```bash
cd /home/pi/treadwall

# Switch to usb branch
git checkout usb

# Run USB tethering setup
sudo ./scripts/setup_usb_tethering.sh

# Verify configuration
sudo ./scripts/verify_usb_setup.sh

# Reboot
sudo reboot
```

After this reboot, the Pi will be in **USB tethering mode** (AP + USB internet).

---

## Troubleshooting Revert Script

### Problem: Can't connect to home WiFi

**Try manual connection**:
```bash
# List available networks
sudo nmcli device wifi list

# Connect manually
sudo nmcli device wifi connect "YourSSID" password "YourPassword"

# Or use wpa_cli
sudo wpa_cli -i wlan0 reconfigure
```

### Problem: Still seeing old AP

**Manually disable services**:
```bash
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo systemctl disable hostapd
sudo systemctl disable dnsmasq
sudo reboot
```

### Problem: Can't find the Pi after revert

**Check your router's client list** to find the new IP address, or:

**Connect a monitor** and check:
```bash
ip addr show wlan0
```

---

## Summary

**Before USB tethering setup**:
1. ✅ Revert to WiFi client (removes AP)
2. ✅ Connect to home WiFi
3. ✅ Update system
4. ✅ Then run USB tethering setup

This ensures a clean setup without conflicts.
