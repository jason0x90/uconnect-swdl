#!/bin/sh

# Exit codes:
#   0 = OK
#   1 = Unable to find DEVC-8250 Driver
#   2 = Unable to start DEVC-8250 successfully 
#   3 = INVAILD ARGUMENT
#
# Command line options:
#   start - Start drivers needed for devc-seroamp
#   stop - Stop the drivers started  
#

DEVC_SER8250_NAME_FILE=/tmp/devc_seromap.name
DEVC_SER8250_PID_FILE=/tmp/devc_seromap.pid

 

#
# Parse through the command line options (start, stop, erase).  No command line
# options is equivalent to "start".  This parsing is not checked well, so don't
# do anything dumb.
#
while [[ "$1" != "" ]]; do
  case $1 in
    stop)
      if [ -e $DEVC_SER8250_PID_FILE ]; then
        slay `cat $DEVC_SER8250_PID_FILE`
        rm -f $DEVC_SER8250_NAME_FILE
        rm -f $DEVC_SER8250_PID_FILE       
      fi         
      exit 0
      ;; 
    start)
      ;;         
    *)
      exit 3
      ;;
  esac
  shift
done


if [ -e $DEVC_SER8250_PID_FILE ]; then 
    echo "DEVC-SER8250 already started don't need to start anything" 
    exit 0
fi     

# devc diver name 
DEVC_SER8250_DRIVER_NAME=/bin/devc-ser8250

#
# Make absolutely sure that the driver exist 
#
if [ ! -x $DEVC_SER8250_DRIVER_NAME ]; then
  exit 1
fi


#
# Start the spi driver
#
$DEVC_SER8250_DRIVER_NAME -u4 -e -S -b230400 -c7372800/16 0x09000000^1,167 & 
DEVC_SER8250_PID=$!
waitfor /dev/ser4

#
# Make sure the new driver started, else quit
#
if [ ! -e /dev/ser4 ]; then
  exit 2
fi

#
# If the driver started, place the filename into /tmp for slaying later
#
echo -n $DEVC_SER8250_DRIVER_NAME > $DEVC_SER8250_NAME_FILE
echo -n $DEVC_SER8250_PID > $DEVC_SER8250_PID_FILE
 

exit 0
