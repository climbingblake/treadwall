#!/bin/bash
#
# Test Network Mode Switch Button
# This verifies the switch button will work WITHOUT actually switching
#

echo "=========================================="
echo "Testing Network Mode Switch Button"
echo "=========================================="
echo ""

echo "Test 1: Check if switch script exists..."
if [ -f "/home/pi/treadwall/scripts/switch_network_mode.sh" ]; then
    echo "✓ switch_network_mode.sh found"
else
    echo "✗ switch_network_mode.sh NOT FOUND"
    echo "  This is the problem - the script is missing!"
    exit 1
fi
echo ""

echo "Test 2: Check if switch script is executable..."
if [ -x "/home/pi/treadwall/scripts/switch_network_mode.sh" ]; then
    echo "✓ switch_network_mode.sh is executable"
else
    echo "✗ switch_network_mode.sh is NOT executable"
    echo "  Fix: chmod +x /home/pi/treadwall/scripts/switch_network_mode.sh"
    exit 1
fi
echo ""

echo "Test 3: Check if crimp-app service can run sudo..."
echo "  Checking crimp-app service user..."
SERVICE_USER=$(systemctl show crimp-app.service -p User --value)
if [ -z "$SERVICE_USER" ] || [ "$SERVICE_USER" = "root" ]; then
    echo "✓ Service runs as root (can use sudo)"
else
    echo "⚠ Service runs as user: $SERVICE_USER"
    echo "  This user needs sudo permissions for the scripts"
fi
echo ""

echo "Test 4: Test API endpoint (dry run)..."
echo "  Calling /api/network/switch-mode with test mode..."
RESPONSE=$(curl -s -X POST http://localhost:4567/api/network/switch-mode \
    -H "Content-Type: application/json" \
    -d '{"mode":"ap","test":true}' 2>&1)

if echo "$RESPONSE" | grep -q "success"; then
    echo "✓ API endpoint exists and responds"
    echo "  Response: $RESPONSE"
else
    echo "⚠ API response: $RESPONSE"
    echo "  (This is expected if endpoint doesn't support test mode)"
fi
echo ""

echo "Test 5: Verify setup scripts exist..."
if [ -f "/home/pi/treadwall/scripts/setup_usb_tethering.sh" ]; then
    echo "✓ setup_usb_tethering.sh found"
else
    echo "✗ setup_usb_tethering.sh NOT FOUND"
    exit 1
fi

if [ -f "/home/pi/treadwall/scripts/revert_to_client.sh" ]; then
    echo "✓ revert_to_client.sh found"
else
    echo "✗ revert_to_client.sh NOT FOUND"
    exit 1
fi
echo ""

echo "Test 6: Can we detect current mode?"
if ip addr show wlan0 | grep -q "192.168.4.1"; then
    echo "  Current mode: AP"
elif ip addr show wlan0 | grep -q "10.0.0"; then
    echo "  Current mode: Client"
else
    echo "  Current mode: Unknown"
fi
echo ""

echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""
echo "If all tests passed, the switch button SHOULD work."
echo ""
echo "To test switch to AP mode (WARNING: will reboot):"
echo "  Use the web UI button, OR"
echo "  Run: sudo /home/pi/treadwall/scripts/switch_network_mode.sh ap"
echo ""
echo "To ensure you can get back:"
echo "  1. Connect to WiFi 'TreadWall-Touch' after reboot"
echo "  2. Go to http://192.168.4.1:4567/config"
echo "  3. Click 'Switch to Client Mode'"
echo "  4. Enter your home WiFi credentials"
echo ""
echo "BACKUP PLAN if switch button doesn't work in AP mode:"
echo "  1. Connect monitor and keyboard to Pi"
echo "  2. Run: sudo /home/pi/treadwall/scripts/revert_to_client.sh"
echo "  3. Enter WiFi credentials when prompted"
echo "  4. Reboot"
echo ""
