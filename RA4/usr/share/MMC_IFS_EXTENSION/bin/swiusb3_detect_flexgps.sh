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

# slay Antenna Monitor if running
var1=$(pidin a | grep AntennaMonitor | grep -v grep )
if [ -n "$var1" ]; then
   slay -s KILL AntennaMonitor
fi

# Start Antenna Monitor
/fs/mmc0/app/bin/AntennaMonitor &

# slay flex-gps if running
var2=$(pidin a | grep vdev-flexgps | grep -v grep )
if [ -n "$var2" ]; then
  slay -f vdev-flexgps
fi

if [ ! -e /fs/etfs/NO_GPS ]; then
#	waitfor /hbsystem/multicore

    if [ ! -e /tmp/GPSResetAR5550_count ]; then
	   countdown=6
    else
	   countdown=50
	fi

	cat /dev/swiusb3 > /tmp/swiusb3_data &
	CAT_PID=$!
	sleep 2 
	slay $CAT_PID
	
	until [[ ( -e /tmp/swiusb3_data && -s /tmp/swiusb3_data ) || $countdown -le 0 ]] do
		if [[ $countdown -lt 50 ]]; then
			sleep 3;
		fi
	  
		cat /dev/swiusb3 > /tmp/swiusb3_data &
		CAT_PID=$!
		sleep 2
		slay $CAT_PID
		((countdown--));
		
	done

	sleep 5
	nice -n -1 vdev-flexgps -d/hbsystem/multicore/navi/g -b115200 -c/dev/swiusb3 -n -x/bin/restartGPS.sh &
	rm /tmp/swiusb3_data
	
else
    touch /tmp/ECELL_GPS_DISABLED
fi
