#!/bin/sh 

NAV_DIR=/fs/mmc0/nav

if [ ! -e $NAV_DIR ]; then
   echo $NAV_DIR "does not exist, flexgps & ndr exiting"
   exit 1
fi

if [[ -e /fs/etfs/NO_GPS && $VARIANT_ECELL = "NO" ]]; then
   qon touch /tmp/GPS_DISABLED
elif [ $VARIANT_ECELL = "NO" ]; then
   # starting serial driver (/dev/ser2) for GPS...
   qon devc-seromap -u2 -e -F -p -b9600 -c48000000/16 0x4806C000^2,73
   qwaitfor /dev/ser2
   # Start GPS driver
   qon -d -p 11 vdev-flexgps -P/dev/gpio/GPSReset -d/hbsystem/multicore/navi/g -b9600 -c/dev/ser2 -C115200 -g$NAV_DIR/g5.cfg -L20 -r1 -R
fi

# Start NDR
if [ ! -d /fs/etfs/usr/var/ndr ]; then
    qon mkdir -p /fs/etfs/usr/var/ndr
fi
 
if [ -e /fs/mmc1/LOGGING ]; then 
qon -d ndr -e=disChina -e=DR -ch5=/dev/ipc/ch5 -hfs=/etc/ndr/hfs.cfg -SavePath=/dev/fram
else
qon -d ndr -e=disChina -e=DR -ch5=/dev/ipc/ch5 -hfs=/etc/ndr/hfs.cfg -DisableServerSocket -SavePath=/dev/fram -logToConsole -d=0 > /dev/null
fi

qwaitfor /dev/navi/Navigation/CalibrationLevel
qon -d NDRToJSON -sigOff -path=/fs/etfs
