#!/bin/sh 

NAV_DIR=/fs/mmc0/nav

if [ ! -e $NAV_DIR ]; then
   echo $NAV_DIR "does not exist, starting flexgps exiting"
   exit 1
fi

# To get ditto on USB 3 
if [ -e /fs/etfs/SWIUSB3_DUPLICATE ]; then
   /fs/mmc0/app/bin/devc-ditto /dev/swiusb3
fi

# To get ditto on USB 4 
if [ -e /fs/etfs/SWIUSB4_DUPLICATE ]; then
   /fs/mmc0/app/bin/devc-ditto /dev/swiusb4
fi

# To get ditto on USB 5 
if [ -e /fs/etfs/SWIUSB5_DUPLICATE ]; then
   /fs/mmc0/app/bin/devc-ditto /dev/swiusb5
fi

# Start GPS driver
/fs/mmc0/app/bin/AntennaMonitor &

waitfor /hbsystem/multicore

if [ ! -e /fs/etfs/NO_GPS ]; then
    sleep 5
    nice -n -1 vdev-flexgps -d/hbsystem/multicore/navi/g -b115200 -c/dev/swiusb3 -n -x/bin/restartGPS.sh &
else
    touch /tmp/ECELL_GPS_DISABLED
fi
