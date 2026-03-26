# CRIMP Device Inventory

This file tracks all deployed Raspberry Pi devices running the CRIMP (Climbing Routine Interactive Motor Platform) system.

## Device List

| Device ID | Hostname | AP IP | Home Network IP | Location | Last Updated | Notes |
|-----------|----------|-------|-----------------|----------|--------------|-------|
| 001 | treadwall-001 | 192.168.50.1 | TBD | - | Not deployed | - |
| 002 | treadwall-002 | 192.168.50.1 | TBD | - | Not deployed | - |
| 003 | treadwall-003 | 192.168.50.1 | TBD | - | Not deployed | - |
| 004 | treadwall-004 | 192.168.50.1 | TBD | - | Not deployed | - |

## Access Information

**Default Access Point:**
- SSID: `TreadWall-Control` (or `TreadWall-{DEVICE_ID}` if configured)
- Password: Set in device config
- Web Interface: `http://192.168.50.1:4567`

**SSH Access:**
```bash
# Via AP connection
ssh pi@192.168.50.1

# Via home network (once IP is known)
ssh pi@treadwall-001.local
```

**Default Credentials:**
- Username: `pi`
- Password: `raspberry` (change immediately after setup!)

## Setup Checklist

For each new device:

- [ ] Flash Raspberry Pi OS Lite (64-bit) to SD card
- [ ] Create empty `ssh` file in boot partition
- [ ] Create `wpa_supplicant.conf` for initial WiFi (optional)
- [ ] Boot Pi and change default password
- [ ] Clone repository: `git clone <repo-url> /home/pi/treadwall`
- [ ] Copy `config/config.example.json` to `config.json`
- [ ] Edit `config.json` with device-specific settings (device_id, AP credentials)
- [ ] Configure dual-mode WiFi (AP + Client)
- [ ] Install dependencies (Ruby, Python, RPi.GPIO)
- [ ] Set up systemd service
- [ ] Test motor control
- [ ] Update this inventory file with device details

## Maintenance Notes

**Update Procedure:**
1. SSH to device or use web UI update button
2. Run: `cd /home/pi/treadwall && ./scripts/update.sh`
3. Monitor logs: `tail -f /home/pi/treadwall-update.log`

**Rollback Procedure:**
1. SSH to device
2. Stop service: `sudo systemctl stop motor-control.service`
3. Find backup: `ls -lt /home/pi/treadwall-backup-*`
4. Restore: `rm -rf /home/pi/treadwall && mv /home/pi/treadwall-backup-YYYYMMDD-HHMMSS /home/pi/treadwall`
5. Start service: `sudo systemctl start motor-control.service`

**Health Check:**
- Service status: `sudo systemctl status motor-control.service`
- View logs: `sudo journalctl -u motor-control.service -f`
- Current version: `cd /home/pi/treadwall && git log -1 --oneline`

## Hardware Configuration

**Raspberry Pi Zero 2 W:**
- RAM: 512MB
- WiFi: 2.4GHz 802.11n
- GPIO: BCM mode

**Motor Driver Connections:**
- DIR Pin: GPIO 5 (BCM)
- PUL Pin: GPIO 6 (BCM)

## Network Topology

```
[Device] --wlan0_ap--> [Local Devices]
    |                    (192.168.50.0/24)
    |
    +----wlan0----> [Home WiFi Router]
                     (Internet access for updates)
```
