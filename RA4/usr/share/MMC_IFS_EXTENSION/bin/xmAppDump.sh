#!/bin/sh

. /tmp/envars.sh 
eval `cat /tmp/envars.sh`
 
#####
# Function DUMPER
# Dumps xmApp
# Adds a time stamp to the core file name
##### 
DUMPER () {
   dumper -p $PID -d $DUMP_DIR
   echo "Saving core to: $DUMP_DIR" >> $XMAPP_DUMP_LOG
   TIME=$(date +"-%m%d%y-%H%M%S")       
   NEWNAME="$DUMP_DIR$XMAPP_CORE$TIME"
   echo "Renaming core file from: $DUMP_DIR$XMAPP_CORE to $NEWNAME" >> $XMAPP_DUMP_LOG
   mv "$DUMP_DIR$XMAPP_CORE" "$NEWNAME"   
}

#####
# Function DumpXMApp
##### 
DumpXMApp () { 
   echo "Dumping xmApp" >> $XMAPP_DUMP_LOG
      
   USB=/fs/usb0/
   if [ ! -e "$USB" ]
   then
      DUMP_DIR=/fs/etfs/
   else
      DUMP_DIR=$USB  
   fi
   echo "Files will be saved to: $DUMP_DIR" >> $XMAPP_DUMP_LOG       
         
   # To dump xmApp, you need the PID
   pidin -p xmApp a | grep xmApp > /tmp/xmAppArgs 
   # Now, read the argument file and place the first argument (the PID) into a file 
   awk < /tmp/xmAppArgs  '{ printf "%s ", $1; printf ""; }' > /tmp/xmAppPID 
   PID=$(cat /tmp/xmAppPID)    
       
   DUMPER  
   DUMPER    
   DUMPER
   
   # Copy xmApp to dump directory
   XMAPP_FULL_NAME="$XMAPP_DIR"/"$XMAPP"
   if [ -e "$XMAPP_DIR" ]; then
      echo "Copying $XMAPP to $DUMP_DIR"  >> $XMAPP_DUMP_LOG
      cp "$XMAPP_FULL_NAME" "$DUMP_DIR"
   fi
}
#####

# Globals
XMAPP=xmApp
XMAPP_CORE="$XMAPP".core
XMAPP_DIR=/fs/mmc0/app/bin/
XMAPP_DUMP_LOG=/tmp/XMAppDump.log

echo "Clearing $XMAPP_DUMP_LOG" > $XMAPP_DUMP_LOG

# Dump xmApp  
DumpXMApp             

echo "$0 complete" >> $XMAPP_DUMP_LOG