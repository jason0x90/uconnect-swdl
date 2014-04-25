#!/bin/sh

echo "Setup WLAN"

#Start WiFiSvc
qon -d -e LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/wicome WifiSvc --tp=/fs/mmc0/app/share/trace/WifiSvc.hbtc &

echo "WLAN configured"