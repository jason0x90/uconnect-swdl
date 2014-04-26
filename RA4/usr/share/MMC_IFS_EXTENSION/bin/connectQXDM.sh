#!/bin/ksh

#create a pid file for slaying 
if test -a /tmp/UMTSdebug.pid ; then 
   echo "Connection already running, exiting script"
   exit 0
fi

if test -a /fs/etfs/useWLAN4QXDM ; then
	if [ $# -ne 1 ] ; then 
		echo "Usage - connectQXDM ipAddress" 
		echo " Where ipAddress is your PC's IP address" 
		exit 0 
	fi 

   hostIP=$1
   
   # check if WLAN routing disable is required
   if test -a /fs/etfs/bin/disableWLANrouting.sh ; then 
      /fs/etfs/bin/disableWLANrouting.sh
   fi
else
	hostIP=192.168.6.2
fi

# run the debug channel 
test=1
while [[ $test -eq 1 ]];do
   echo "Waiting for Sierra Wireless ARx550 diagnosic port (/dev/swiusb2)"
   waitfor /dev/swiusb2 600
   
   echo "Using $hostIP"
   ping -c1 -w1 $hostIP
   hostAvailable=$?
   
   if [[ $hostAvailable == 0 ]]; then
      echo $$ > /tmp/UMTSdebug.pid
      echo "Connecting to tcp server with Sierra Wireless ARx550 diagnosic port (/dev/swiusb2)"
      /fs/mmc0/app/bin/netcat -vv -n $hostIP 2500 < /dev/swiusb2 > /dev/swiusb2 2>/tmp/qxdmstatus
      echo "Sierra Wireless ARx550 diagnosic port (/dev/swiusb2) connection broken, start again..."
   else 
      echo "Host not reachable";
   fi
   
   sleep 1
   
done
