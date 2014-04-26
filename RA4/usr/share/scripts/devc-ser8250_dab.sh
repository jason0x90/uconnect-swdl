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

echo "dab serial driver script: Parameters="$1" "$2

#
# Parse through the command line options (start, stop).  No command line
# options is equivalent to "start".  This parsing is not checked well, so don't
# do anything dumb.
#

while [[ "$1" != "" ]]; do
  case $1 in
    stop)
      ACTION="stop"
      ;;
    start)
      ACTION="start"
      ;;
    4)
      SERIAL_UNIT_NUMBER="-u"$1
      PORT=0x09000000^1
      IRQ=167
      SER_RESOURCE="/dev/ser"$1
      DEVC_SER8250_NAME_FILE="/tmp/devc_ser8250_"$1".name"
      DEVC_SER8250_PID_FILE="/tmp/devc_ser8250_"$1".pid"
      ;;
    5)
      SERIAL_UNIT_NUMBER="-u"$1
      PORT=0x09000010^1
      IRQ=168
      SER_RESOURCE="/dev/ser"$1
      DEVC_SER8250_NAME_FILE="/tmp/devc_ser8250_"$1".name"
      DEVC_SER8250_PID_FILE="/tmp/devc_ser8250_"$1".pid"
      ;;
    *)
      exit 3
      ;;
  esac
  shift
done

echo "ACTION="$ACTION
echo "SERIAL_UNIT_NUMBER="$SERIAL_UNIT_NUMBER", PORT="$PORT", IRQ="$IRQ", SER_RESOURCE="$SER_RESOURCE
echo "DEVC_SER8250_NAME_FILE="$DEVC_SER8250_NAME_FILE
echo "DEVC_SER8250_PID_FILE="$DEVC_SER8250_PID_FILE

# Checking for ACTION.
# Checking for one of variables from iput parameters 4 & 5 would be sufficient to make sure we got 2 parameters as input.
if [ "$ACTION" == "" ] || [ "$SERIAL_UNIT_NUMBER" == "" ]; then
    echo "Invalid input parameters!!!"
    exit 3
fi

if [ "$ACTION" == "stop" ]; then
    if [ -e $DEVC_SER8250_PID_FILE ]; then
        echo "Stop the driver!"
        slay `cat $DEVC_SER8250_PID_FILE`
        rm -f $DEVC_SER8250_NAME_FILE
        rm -f $DEVC_SER8250_PID_FILE       
    fi         
    exit 0
fi

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
$DEVC_SER8250_DRIVER_NAME $SERIAL_UNIT_NUMBER -E -F -b115200 -c7372800/16 $PORT,$IRQ & 
DEVC_SER8250_PID=$!
waitfor $SER_RESOURCE

#
# Make sure the new driver started, else quit
#
if [ ! -e $SER_RESOURCE ]; then
  exit 2
fi

#
# If the driver started, place the filename into /tmp for slaying later
#
echo -n $DEVC_SER8250_DRIVER_NAME > $DEVC_SER8250_NAME_FILE
echo -n $DEVC_SER8250_PID > $DEVC_SER8250_PID_FILE
 
exit 0
