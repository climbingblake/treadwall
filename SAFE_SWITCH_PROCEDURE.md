# Safe Network Mode Switch Procedure

## Your Concern (Valid!)

If you switch to AP mode and the switch button doesn't work, you'll lose SSH access from your home network.

---

## Before Switching: Verification

### Run the Test Script

```bash
cd /home/pi/treadwall
./scripts/test_switch_button.sh
```

This verifies:
- ✅ Switch script exists
- ✅ Script is executable
- ✅ Required scripts are present
- ✅ API endpoint responds

---

## Backup Plans (If You Get Stuck)

### Option 1: Monitor + Keyboard
**Best option if you have physical access**

1. Connect monitor and keyboard to Pi
2. Login as pi user
3. Run:
   ```bash
   cd /home/pi/treadwall
   sudo ./scripts/revert_to_client.sh
   ```
4. Enter your home WiFi credentials
5. Reboot

### Option 2: SSH via AP (If AP is working)
**If AP mode works but you just can't switch back**

1. Connect your laptop to "TreadWall-Touch" WiFi
2. SSH to Pi: `ssh pi@192.168.4.1`
3. Run revert script:
   ```bash
   cd /home/pi/treadwall
   sudo ./scripts/revert_to_client.sh
   ```
4. Enter WiFi credentials
5. Reboot

### Option 3: SD Card Edit (Nuclear option)
**If nothing else works**

1. Power down Pi
2. Remove SD card
3. Insert into computer
4. Edit `/boot/wpa_supplicant.conf` on the SD card:
   ```
   country=US
   ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
   update_config=1

   network={
       ssid="YourHomeWiFi"
       psk="YourPassword"
   }
   ```
5. Save, eject, put SD card back in Pi
6. Boot Pi - it will connect to home WiFi

---

## Step-by-Step Safe Switch Test

### Phase 1: Verify (Current State: Client Mode, SSH Works)

1. **Run test script:**
   ```bash
   ./scripts/test_switch_button.sh
   ```
   All tests should pass ✅

2. **Verify scripts are in git (you can always recover):**
   ```bash
   git status
   # Make sure you've committed the new scripts
   ```

3. **Note your home WiFi credentials:**
   - SSID: _______________
   - Password: _______________

---

### Phase 2: Switch to AP Mode

**This will trigger a reboot and you'll lose SSH access from home network.**

**From web UI:**
1. Go to Settings → Network Mode
2. Click "Switch to AP Mode"
3. Confirm the dialog
4. Wait 30 seconds for reboot

**OR from command line:**
```bash
sudo ./scripts/switch_network_mode.sh ap
# System will reboot
```

---

### Phase 3: Connect to AP and Test Switch Back

**After reboot (30-60 seconds):**

1. **On your phone/laptop:**
   - Connect to WiFi: "TreadWall-Touch"
   - Password: yosemite

2. **Open browser:**
   - Go to: http://192.168.4.1:4567

3. **Verify app works:**
   - Should see the home page
   - Try moving the motor

4. **Test the switch button:**
   - Go to Settings (http://192.168.4.1:4567/config)
   - Find "Network Mode" section
   - Should show "Current Mode: AP Mode (WiFi Access Point)" in blue
   - Should see "Switch to Client Mode" button

5. **Switch back to client mode:**
   - Click "Switch to Client Mode"
   - Enter SSID: (your home network)
   - Enter password: (your home password)
   - Confirm
   - Wait 30 seconds for reboot

6. **After reboot:**
   - Connect back to home WiFi
   - SSH should work: `ssh pi@treadwall.local`
   - Web UI should work: http://treadwall.local:4567

---

## What Could Go Wrong?

### Problem 1: AP Mode doesn't start after switch
**Symptoms**: After reboot, can't find "TreadWall-Touch" WiFi

**Why**: hostapd failed to start (wpa_supplicant conflict)

**Fix**:
- Connect monitor/keyboard
- Run: `sudo ./scripts/force_ap_mode.sh`
- Check: `sudo systemctl status hostapd`

---

### Problem 2: Can switch TO AP but not BACK to client
**Symptoms**: Switch button doesn't work, or reboot hangs

**Why**: Script missing, permissions issue, or bad WiFi credentials

**Fix Option A - SSH via AP**:
```bash
# Connected to TreadWall-Touch WiFi
ssh pi@192.168.4.1
cd /home/pi/treadwall
sudo ./scripts/revert_to_client.sh
# Enter credentials
sudo reboot
```

**Fix Option B - Monitor/Keyboard**:
- Same as above, but directly on Pi

---

### Problem 3: Wrong WiFi credentials entered
**Symptoms**: Pi reboots but doesn't connect to home WiFi

**Why**: Typo in SSID or password

**Fix**:
- Pi should fall back to AP mode if WiFi fails
- Connect to "TreadWall-Touch" again
- SSH: `ssh pi@192.168.4.1`
- Run revert script with correct credentials

---

## Testing Checklist

Before you commit to switching:

- [ ] Test script passes all checks
- [ ] You have physical access to Pi (or monitor/keyboard available)
- [ ] You know your home WiFi credentials
- [ ] You've committed all code to git
- [ ] You're prepared for 2-3 minutes of downtime
- [ ] You have a phone/laptop that can connect to "TreadWall-Touch"

---

## My Recommendation

### Safest Approach:

1. **Have a monitor/keyboard ready** (or know where they are)
2. **Run the test script** - make sure it passes
3. **Switch to AP mode** using the button
4. **Connect to AP and verify** it works
5. **Test switching back** using the button
6. **If button works**, you're golden! ✅
7. **If button fails**, use monitor/keyboard to run revert script

### Alternative: Manual Command Line Test

Instead of using the button first time, manually test:

```bash
# While still in client mode with SSH access
cd /home/pi/treadwall

# Manually switch to AP
sudo ./scripts/switch_network_mode.sh ap

# After reboot and testing AP:
# Connect to TreadWall-Touch WiFi
ssh pi@192.168.4.1
cd /home/pi/treadwall

# Manually switch back to client
sudo ./scripts/switch_network_mode.sh client "YourSSID" "YourPassword"

# After reboot, verify you're back on home network
ssh pi@treadwall.local
```

This way you know the scripts work before relying on the web button.

---

## Summary

**Your concern is valid** - you could get locked out.

**But you have multiple escape routes**:
1. ✅ Monitor + keyboard (always works)
2. ✅ SSH via AP (if AP works at all)
3. ✅ SD card edit (nuclear option)

**Best path forward**:
1. Run test script
2. Have backup plan ready (monitor/keyboard)
3. Test switch manually via command line first
4. Then trust the web button

**Want me to walk you through the manual command line test first?** That way you'll know it works before clicking the web button.
