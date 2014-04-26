#!/bin/sh

# Exit codes:
#   0 = OK
#   1 = $ISO_PATH not set
#   2 = SyncTool not found
#   3 = SyncTool failed to start
#   4 = SyncTool Controller not found
#   5 = SyncTool Controller failed to start
#   6 = Invalid option

#
# Command line options: 
#   start - Start drivers needed for navi-sync
#   stop - Stop the drivers started  
#

SYNC_CTRL_NAME_FILE=/tmp/sync_ctrl.name
SYNC_CTRL_PID_FILE=/tmp/sync_ctrl.pid

SYNC_TOOL_NAME_FILE=/tmp/sync_tool.name
SYNC_TOOL_PID_FILE=/tmp/sync_tool.pid

if [[ "$ISO_PATH" == "" ]]; then
  echo "navi-sync.sh: ISO_PATH is not set"
  exit 1
fi

#
# Parse through the command line options (start, stop, erase).  No command line
# options is equivalent to "start".  This parsing is not checked well, so don't
# do anything dumb.
#
while [[ "$1" != "" ]]; do
  case $1 in
    stop)
      if [ -e $SYNC_CTRL_NAME_FILE ]; then
        slay `cat $SYNC_CTRL_NAME_FILE`
        rm -f $SYNC_CTRL_NAME_FILE
        rm -f $SYNC_CTRL_NAME_FILE       
      fi    
      if [ -e $SYNC_TOOL_PID_FILE ]; then 
        slay `cat $SYNC_TOOL_PID_FILE`
        rm -f $SYNC_TOOL_NAME_FILE
        rm -f $SYNC_TOOL_PID_FILE       
      fi      
      
      exit 0
      ;; 
    start)
      ;;      
    *)
      exit 6
      ;;
  esac
  shift
done

# Start the sync tool
SYNC_TOOL_PATH=$ISO_PATH/usr/bin/nav/NNG_SyncTool
SYNC_TOOL_FNAME=Synctool

#
# Make absolutely sure that the sync tool program exists and can be executed
#
if [ ! -x "$SYNC_TOOL_PATH/$SYNC_TOOL_FNAME" ]; then
  echo "navi-sync.sh: $SYNC_TOOL_PATH/$SYNC_TOOL_FNAME is not available or is not executable"
  exit 2
fi

#
# Start the sync tool
#
cd $SYNC_TOOL_PATH
./$SYNC_TOOL_FNAME &
SYNC_TOOL_PID=$!

#
# Wait a bit to give it time (nothing to use waitfor)
#
sleep 3

#
# Make sure the new driver started, else quit
#
if [ ! -e /proc/$SYNC_TOOL_PID/as ]; then
  echo "navi-sync.sh: $SYNC_TOOL_PATH/$SYNC_TOOL_FNAME startup was unsuccessful"
  exit 3
fi

#
# If the driver started, place the filename into /tmp for slaying later
#
echo -n $SYNC_TOOL_FNAME > $SYNC_TOOL_NAME_FILE
echo -n $SYNC_TOOL_PID   > $SYNC_TOOL_PID_FILE
 
# Start the sync tool controller
SYNC_TOOL_CTRL_PATH=$ISO_PATH/usr/bin/nav/update
SYNC_TOOL_CTRL_FNAME=NavUpdateController

#
# Make absolutely sure that the driver exist 
#
if [ ! -x $SYNC_TOOL_CTRL_PATH/$SYNC_TOOL_CTRL_FNAME ]; then
  echo "navi-sync.sh: $SYNC_TOOL_CTRL_PATH/$SYNC_TOOL_CTRL_FNAME is not available or is not executable"
  exit 4
fi
 
#
# Start sync tool controller
#
cd $SYNC_TOOL_CTRL_PATH
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:. ./$SYNC_TOOL_CTRL_FNAME &
SYNC_CTRL_PID=$!
waitfor /dev/serv-mon/com.harman.service.NavigationUpdate 10

#
# Make sure the new controller started, else quit
#
if [ ! -e /dev/serv-mon/com.harman.service.NavigationUpdate ]; then
  echo "navi-sync.sh: $SYNC_TOOL_CTRL_PATH/$SYNC_TOOL_CTRL_FNAME startup was unsuccessful"
  exit 5
fi

#
# If the service started, place the filename into /tmp for slaying later
#
echo -n $SYNC_TOOL_CTRL_FNAME > $SYNC_CTRL_NAME_FILE
echo -n $SYNC_CTRL_PID        > $SYNC_CTRL_PID_FILE

echo "navi-sync.sh completed"

exit 0
