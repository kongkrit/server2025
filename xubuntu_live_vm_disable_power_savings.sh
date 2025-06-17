#!/bin/bash
# disable-powersave.sh — for Xubuntu Live session in VM

echo "Disabling power management, suspend, and screen blanking..."

# Disable screen blanking and power saving via xset
xset -dpms
xset s off
xset s noblank

# Stop xscreensaver if running
xscreensaver-command -exit 2>/dev/null

# Disable xfce4 power manager inactivity actions
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-ac -n -t int -s 0
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-battery -n -t int -s 0
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/critical-power-action -n -t int -s 0

# Optionally stop xfce4-power-manager (if you don't want it running at all)
pkill -f xfce4-power-manager

# Confirm settings
echo "Current xset settings:"
xset -q | grep -A 1 "DPMS"

echo "Power saving and suspend features disabled."
