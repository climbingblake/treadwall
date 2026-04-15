# Network Mode Switcher - Usage Guide

## Overview

You now have a **web UI button** to switch between network modes without needing SSH access!

### The Problem It Solves

When the Pi boots into **AP mode** (192.168.4.1), you lose the ability to SSH from your home network. This new feature lets you switch modes from the web interface before losing access.

---

## Network Modes

### AP Mode (Access Point)
- **WiFi**: Pi creates "TreadWall-Touch" access point
- **IP**: 192.168.4.1
- **Internet**: Via USB phone tethering
- **Use case**: Portable, no home WiFi needed
- **Access**: http://192.168.4.1:4567

### Client Mode (Home WiFi)
- **WiFi**: Pi connects to your home network
- **IP**: Assigned by your router (e.g., 10.0.0.42)
- **Internet**: Via home WiFi
- **Use case**: At home, development/testing
- **Access**: http://treadwall.local:4567 or http://10.0.0.42:4567

---

## How to Use

### Accessing the Switcher

1. Open the web app
2. Navigate to **Settings** page
3. Scroll to **Network Configuration** section
4. Find **Network Mode** subsection

---

## Switching Between Modes

### From AP Mode → Client Mode

**When to use**: You're in AP mode and want to connect to home WiFi

**Steps**:
1. Click **"Switch to Client Mode"** button
2. Enter your home WiFi SSID when prompted
3. Enter your WiFi password when prompted
4. Confirm the switch
5. System will reboot automatically (30 seconds)
6. After reboot, Pi will be on your home network

**After reboot**:
- Connect your device to home WiFi
- Access at: http://treadwall.local:4567
- SSH available: `ssh pi@treadwall.local`

---

### From Client Mode → AP Mode

**When to use**: You're on home WiFi and want to create an access point

**Steps**:
1. Click **"Switch to AP Mode"** button
2. Confirm the switch
3. System will reboot automatically (30 seconds)
4. After reboot, connect to WiFi: "TreadWall-Touch"

**After reboot**:
- Connect to WiFi: "TreadWall-Touch" (password: yosemite)
- Access at: http://192.168.4.1:4567
- SSH available: `ssh pi@192.168.4.1`

---

## UI Indicators

### Current Mode Display

The settings page shows your current mode:

**AP Mode (WiFi Access Point)**
- Color: Blue
- Shows: "Switch to Client Mode" button

**Client Mode (Home WiFi)**
- Color: Green
- Shows: "Switch to AP Mode" button

---

## What Happens During Switch

### Behind the Scenes

1. **User clicks button** → Web UI sends API request
2. **API endpoint** → Calls shell script in background
3. **Script runs** → Configures network settings
4. **Auto-reboot** → System restarts with new mode
5. **User reconnects** → Access via new network

### Files Modified

The switcher script modifies:
- `/etc/hostapd/hostapd.conf` (AP config)
- `/etc/dnsmasq.conf` (DHCP server)
- `/etc/wpa_supplicant/wpa_supplicant.conf` (WiFi client)
- `/etc/dhcpcd.conf` (Network interfaces)
- Systemd services (hostapd, dnsmasq)

---

## Technical Details

### API Endpoint

```
POST /api/network/switch-mode
Content-Type: application/json

Body:
{
  "mode": "ap" | "client",
  "ssid": "your-network-name",  // Required for client mode
  "password": "your-password"    // Required for client mode
}

Response:
{
  "success": true,
  "mode": "client",
  "message": "Switching to client mode. System will reboot in a few seconds...",
  "note": "After reboot, connect to WiFi: YourNetwork and access via treadwall.local:4567"
}
```

### Shell Script

Located at: `scripts/switch_network_mode.sh`

**Usage**:
```bash
# Switch to AP mode
sudo ./scripts/switch_network_mode.sh ap

# Switch to client mode
sudo ./scripts/switch_network_mode.sh client "YourSSID" "YourPassword"

# Auto-detect and toggle
sudo ./scripts/switch_network_mode.sh
```

### Mode Detection Logic

The system detects current mode by checking:
1. If wlan0 has IP 192.168.4.1 → AP mode
2. If hostapd service is active → AP mode
3. Otherwise → Client mode

---

## Safety Features

### Validation

- **Client mode**: Requires SSID and password (cannot be empty)
- **AP mode**: No credentials needed
- **Mode validation**: Only accepts "ap" or "client"

### Error Handling

- Invalid mode → Returns 400 error
- Missing credentials → Returns 400 error
- Script not found → Returns 500 error
- Network errors → Shows error message in UI

### Reboot Safety

- Script runs in background thread (doesn't block response)
- User gets confirmation before reboot
- 1-second delay to ensure response is sent
- Clear instructions shown before and after reboot

---

## Troubleshooting

### Problem: Can't Access After Switch

**Cause**: Wrong network or IP changed

**Solution**:
- **AP mode**: Connect to "TreadWall-Touch" WiFi, access http://192.168.4.1:4567
- **Client mode**: Connect to home WiFi, access http://treadwall.local:4567

### Problem: Switch Button Doesn't Work

**Cause**: Script missing or permission error

**Solution**:
```bash
# Check if script exists
ls -la /home/pi/treadwall/scripts/switch_network_mode.sh

# Make sure it's executable
chmod +x /home/pi/treadwall/scripts/switch_network_mode.sh

# Check sudoers permissions (crimp-app service needs sudo)
```

### Problem: System Doesn't Reboot

**Cause**: Script failed to execute

**Solution**:
```bash
# Check systemd logs
sudo journalctl -u crimp-app -n 50

# Check script manually
sudo /home/pi/treadwall/scripts/switch_network_mode.sh ap
```

### Problem: Wrong WiFi Credentials in Client Mode

**If you entered wrong SSID/password**:

1. Connect monitor/keyboard to Pi
2. OR Connect to known network if Pi falls back
3. Run setup script again:
   ```bash
   cd /home/pi/treadwall
   sudo ./scripts/revert_to_client.sh
   ```
4. Enter correct credentials

---

## Use Cases

### Scenario 1: Development at Home

**Setup**: Client mode
- Pi on home WiFi
- Easy SSH access
- Can update code via git
- All devices on same network

**When leaving home**:
- Use web UI to switch to AP mode
- Take Pi with you
- Connect phone via USB for internet

---

### Scenario 2: Portable Climbing Wall

**Setup**: AP mode
- Pi creates WiFi AP
- Phone provides internet via USB
- Tablet connects to Pi's WiFi
- Works anywhere

**When returning home**:
- Use web UI to switch to client mode
- Pi joins home network
- Development/testing easier

---

### Scenario 3: Field Testing → Bug Fixing

**Problem**: Found bug while using in AP mode at gym

**Solution**:
1. At gym: Note the bug
2. Return home
3. Switch to client mode via web UI
4. SSH in and fix the bug
5. Test on home network
6. Switch back to AP mode via web UI
7. Return to gym with fixed version

---

## Configuration

### Customizing AP Credentials

Edit `config.json`:
```json
{
  "network": {
    "ap_ssid": "TreadWall-Touch",
    "ap_password": "yosemite",
    "ap_channel": 6
  }
}
```

Then switch to AP mode - it will use the new credentials.

---

## Files Created

1. **scripts/switch_network_mode.sh**
   - Main mode switching script
   - Calls existing setup/revert scripts
   - Handles both AP and client modes

2. **crimp_app.rb** (modified)
   - Added `/api/network/switch-mode` endpoint
   - Validates input
   - Runs script in background

3. **views/config.erb** (modified)
   - Added "Network Mode" section
   - Shows current mode
   - Switch buttons with confirmations

4. **public/app.js** (modified)
   - `updateNetworkMode()` - Detects and displays mode
   - `showClientModeDialog()` - Prompts for WiFi credentials
   - `switchToAPMode()` - Confirms AP switch
   - `switchNetworkMode()` - API call to backend

5. **NETWORK_MODE_SWITCHER.md** (this file)
   - Complete documentation

---

## Summary

You now have a **self-contained mode switching solution**:

✅ No SSH required to switch modes
✅ Web UI button on settings page
✅ Clear current mode indicator
✅ Confirmation prompts before reboot
✅ Works in both AP and client mode
✅ Validates credentials before switching
✅ Graceful error handling

**You'll never get locked out** - you can always switch modes from the web interface before losing access!
