#!/bin/bash
# Quick network diagnostics

echo "=========================================="
echo "Network Diagnostics"
echo "=========================================="
echo ""

echo "Connected WiFi Network:"
iwgetid -r
echo ""

echo "IP Address:"
hostname -I
echo ""

echo "Full wlan0 details:"
ip addr show wlan0
echo ""

echo "Gateway (router):"
ip route | grep default
echo ""

echo "DNS servers:"
cat /etc/resolv.conf | grep nameserver
echo ""

echo "All WiFi networks in range:"
sudo iwlist wlan0 scan | grep -E "ESSID|Quality"
echo ""

echo "Internet connectivity:"
ping -c 2 8.8.8.8 && echo "✓ Can reach internet" || echo "✗ No internet"
echo ""
