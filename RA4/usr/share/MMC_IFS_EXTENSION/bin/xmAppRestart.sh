#!/bin/sh

. /tmp/envars.sh 
eval `cat /tmp/envars.sh`

XMAPP_RESTART_LOG=/tmp/XMAppRestart.log
echo Clearing $XMAPP_RESTART_LOG > $XMAPP_RESTART_LOG

# Set the platform variant information. 
eval `variant export`

echo Variant is: $VARIANT_MODEL >> $XMAPP_RESTART_LOG
if [ $VARIANT_MODEL = "VP4" ]; then
   # Special cfg file that starts data services
   XMAPP_CFG_FILE=/etc/sdars/XMAppRestart.cfg    
else
   # No data services
   XMAPP_CFG_FILE=/fs/etfs/XMAppAudioOnly.cfg
fi

XMAPP_DIR=/fs/mmc0/app/bin/
if [ ! -e "$XMAPP_DIR" ]; then
   echo $XMAPP_DIR "does not exist, unable to restart xmApp"  >> $XMAPP_RESTART_LOG
   exit 1
fi

# change to the directory where xmApp and devc-ser8250 are located.
cd $XMAPP_DIR

# Determine whether to restart the xmApp or the xmApp and the driver.
if [ "$1" = "APP" ]; then
   echo "Restarting xmApp" >> $XMAPP_RESTART_LOG
   
   # Slay xmApp and wait for it to die.   
   slay xmApp
   sleep 3  
     
   xmApp -c $XMAPP_CFG_FILE --tp=/fs/mmc0/app/share/trace/XMApp.hbtc &     
elif [ "$1" = "APPDRIVER" ]
then
   echo "Restarting xmApp and Driver" >> $XMAPP_RESTART_LOG
   
   # Slay xmApp and wait for it to die.   
   slay xmApp
   sleep 3   
 
   # Before slaying devc-ser8250, determine the command line arguments and place them in a file.
   pidin -p devc-ser8250 a | grep devc-ser8250 > /tmp/devc-ser8250args 
   # Now, read the argument file and place all the command line arguments 
   # (except the first one - the process id) and the background character "&" into a command file.
   # Make the command file executable.
   awk < /tmp/devc-ser8250args  '{ for (i=2; i<=NF; i++) printf "%s ", $i; printf "&"; }' > /tmp/devc-ser8250cmd   
   chmod +x  /tmp/devc-ser8250cmd   
      
   # Slay devc-ser8250 and wait for it to die.      
   slay devc-ser8250 
   sleep 3     
     
   # Restart devc-ser8250 and give it some time to come up  
   eval /tmp/devc-ser8250cmd     
   sleep 3      

   # Restart xmApp      
   xmApp -c $XMAPP_CFG_FILE --tp=/fs/mmc0/app/share/trace/XMApp.hbtc &  
   
else
   echo "Error: Unknown argument" \"$1\" "supplied to $0"  >> $XMAPP_RESTART_LOG
   exit 1
fi

echo "$0 complete" >> $XMAPP_RESTART_LOG








