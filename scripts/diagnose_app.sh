#!/bin/bash
# Diagnose Sinatra app connectivity issues

echo "=========================================="
echo "CRIMP App Diagnostics"
echo "=========================================="
echo ""

echo "1. Check if Sinatra app is running:"
if pgrep -f crimp_app.rb > /dev/null; then
    echo "   ✓ crimp_app.rb process is running"
    ps aux | grep crimp_app.rb | grep -v grep
else
    echo "   ✗ crimp_app.rb is NOT running"
    echo "   Start it with: cd /home/pi/treadwall && ruby crimp_app.rb"
fi
echo ""

echo "2. Check if port 4567 is listening:"
if netstat -tuln | grep -q ":4567 "; then
    echo "   ✓ Port 4567 is open"
    netstat -tuln | grep ":4567 "
else
    echo "   ✗ Port 4567 is NOT listening"
fi
echo ""

echo "3. Check systemd service (if using service):"
if systemctl is-active crimp.service >/dev/null 2>&1; then
    echo "   ✓ crimp.service is active"
    systemctl status crimp.service --no-pager -l
elif systemctl list-unit-files | grep -q crimp.service; then
    echo "   ⚠ crimp.service exists but not active"
    systemctl status crimp.service --no-pager -l
else
    echo "   ℹ No crimp.service found (running manually?)"
fi
echo ""

echo "4. Check WiFi AP (wlan0):"
if ip addr show wlan0 | grep -q "192.168.4.1"; then
    echo "   ✓ wlan0 has IP 192.168.4.1"
    ip addr show wlan0 | grep "inet "
else
    echo "   ✗ wlan0 doesn't have expected IP"
    ip addr show wlan0
fi
echo ""

echo "5. Check if hostapd is running:"
if systemctl is-active hostapd >/dev/null 2>&1; then
    echo "   ✓ hostapd is active"
else
    echo "   ✗ hostapd is NOT active"
    echo "   Start it with: sudo systemctl start hostapd"
fi
echo ""

echo "6. Test local connectivity:"
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4567/api/status | grep -q "200"; then
    echo "   ✓ App responds on localhost"
else
    echo "   ✗ App doesn't respond on localhost"
fi
echo ""

echo "7. Test AP interface connectivity:"
if curl -s -o /dev/null -w "%{http_code}" http://192.168.4.1:4567/api/status | grep -q "200"; then
    echo "   ✓ App responds on 192.168.4.1"
else
    echo "   ✗ App doesn't respond on 192.168.4.1"
fi
echo ""

echo "8. Check for firewall rules:"
if iptables -L INPUT -v | grep -q "4567"; then
    echo "   ⚠ Found firewall rules for port 4567"
    iptables -L INPUT -v | grep "4567"
else
    echo "   ✓ No firewall blocking port 4567"
fi
echo ""

echo "9. Recent app logs (if running as service):"
if journalctl -u crimp.service -n 10 --no-pager >/dev/null 2>&1; then
    journalctl -u crimp.service -n 10 --no-pager
else
    echo "   ℹ No service logs (check manual run output)"
fi
echo ""

echo "=========================================="
echo "Quick Fixes:"
echo "=========================================="
echo ""
echo "If app is NOT running:"
echo "  cd /home/pi/treadwall"
echo "  ruby crimp_app.rb"
echo ""
echo "If using systemd service:"
echo "  sudo systemctl start crimp.service"
echo "  sudo systemctl status crimp.service"
echo ""
echo "If WiFi AP is down:"
echo "  sudo systemctl start hostapd"
echo "  sudo systemctl start dnsmasq"
echo ""
