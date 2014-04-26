#!/bin/sh

# Handle an Ethernet connection via the CISCO Linksys USB300M adapter

# get the user variables if defined
if [ -e /fs/etfs/development/net ] ;  then
   . /fs/etfs/development/net
else
	echo "NETWORK variables not sourced from \"/fs/etfs/development/net\""
	echo "NETWORK see template file at \"/fs/mmc0/app/share/develop/net_template\""
fi

# Verify that the USB driver has been started properly
waitfor /dev/io-usb
if [ $? -ne 0 ] ;  then
   echo "NETWORK waited for 5 seconds, but the USB driver is not loaded"
   exit 1
fi

# Load the D-Link adapter driver
echo NETWORK starting ...
mount -T io-pkt devn-asix.so
waitfor /dev/io-net/en0
if [ $? -ne 0 ] ;  then
   echo "NETWORK waited for 5 seconds, but the D-Link adapter driver did not load"
   exit 2
fi

# Get IP address using development network configuration file if available
ifconfig en0 delete 2> /dev/null

if test -a /fs/etfs/useWLAN4QXDM ; then
 	rm /fs/etfs/useWLAN4QXDM
fi

# use static ip address if set, else use DHCP, else fall back to default static ip address
if [ $STATIC_IP ] ; then
   echo "Static IP $STATIC_IP requested, setting"
   ifconfig en0 $STATIC_IP   
else
   if [ $TARGET_NAME ] ;  then
      echo "NETWORK requesting IP address with name \"${TARGET_NAME}\" ..."
      nice -n-1 dhcp.client -umb -A0 -i en0 -t1 -T80 -h $TARGET_NAME
   else
      echo "NETWORK requesting IP address without setting TARGET_NAME ..."
      nice -n-1 dhcp.client -umb -A0 -i en0 -t1 -T80
   fi
   if [ $? -eq 3 ] ;  then
      STATIC_IP=192.168.6.1
      echo "NETWORK could not find a DHCP server, setting static IP to $STATIC_IP"
      ifconfig en0 $STATIC_IP   
   else
      touch /tmp/networkingpossible
      touch /fs/etfs/useWLAN4QXDM
   fi
fi

# Mount any network drives drives
if [ $SHARE_HOST ] && [ $SHARE_IP ] && [ $SHARE_NAME ] && [ $SHARE_USER ] && [ $SHARE_PASS ] ;  then
   echo "NETWORK mounting shared drives..."
   fs-cifs -a //${SHARE_HOST}:${SHARE_IP}:${SHARE_NAME} /mnt/net ${SHARE_USER} ${SHARE_PASS}
   if [ $? -ne 0 ] ;  then
      echo "NETWORK waited for 5 seconds, but could not mount the requested network drive"
      exit 6
   fi
   ln -fsP /mnt/net/tcfg/omap/images /images
else
   echo "NETWORK SHARE_* variables not set"
fi

# Start qconn and inetd networking daemons if START_DAEMONS is set
if [ "$START_DAEMONS" != "false" ] ; then
   slay -f qconn > /dev/null
   slay -f inetd > /dev/null
   slay -f sshd > /dev/null

   echo "NETWORK starting network daemons..."
   /fs/mmc0/app/bin/sshd
   if [ $? -ne 0 ] ;  then
      echo "NETWORK waited for 5 seconds, but the sshd did not start"
   fi

   inetd
   if [ $? -ne 0 ] ;  then
      echo "NETWORK waited for 5 seconds, but the inetd did not start"
   fi

   if [ -d /fs/etfs/development ]; then
      qconn
      if [ $? -ne 0 ] ;  then
         echo "NETWORK waited for 5 seconds, but qconn did not start"
      fi
      add pfctl settings for development here!
   fi
fi

# Start dbus-monitor only if its not forced  
if [ ! -e /fs/etfs/FORCE_DBUSTRACE_MON ]; then

   # returns 0 if already running, 1 if not...
   pidin a | grep dbustracemonitor | grep -v grep
   NOT_RUNNING=$?

   if [ $NOT_RUNNING == 1 ]; then
      echo "starting dbustracemonitor"
      dbustracemonitor --bp -f=/usr/var/trace/traceDbusServices --tp=/usr/var/trace/DBusTraceMonitor.hbtc &
   else
      echo "dbustractmonitor is already running"
   fi
fi


echo "NETWORK setup complete"

exit 0
