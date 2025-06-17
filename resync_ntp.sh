#!/bin/bash

echo "Check for root priviliges"
if [ "$(id -u)" -ne 0 ]; then
   echo "Please run as root."
   exit 1
fi

echo "off ntp"
timedatectl set-ntp false
timedatectl set-ntp true
echo "on ntp"
echo "datetime on this machine should be synced"
