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

echo "hd i2c driver script: Parameters="$1" "$2

#
# Parse through the command line options (start, stop).  No command line
# options is equivalent to "start".  This parsing is not checked well, so don't
# do anything dumb.
#
# i2c-omap35xx -a1 -i56 -p0x48070000
#

while [[ "$1" != "" ]]; do
  case $1 in
    stop)
      ACTION="stop"
      ;;
    start)
      ACTION="start"
      ;;
    1)
      I2C_UNIT_NUMBER=$1
      PORT=0x48070000
      IRQ=56
      I2C_RESOURCE="/dev/i2c"$1
      I2C_OMAP35XX_NAME_FILE="/tmp/i2c-omap35xx_"$1".name"
      I2C_OMAP35XX_PID_FILE="/tmp/i2c-omap35xx_"$1".pid"
      ;;
    *)
      exit 3
      ;;
  esac
  shift
done

echo "ACTION="$ACTION
echo "I2C_UNIT_NUMBER="$I2C_UNIT_NUMBER", PORT="$PORT", IRQ="$IRQ", I2C_RESOURCE="$I2C_RESOURCE
echo "I2C_OMAP35XX_NAME_FILE="$I2C_OMAP35XX_NAME_FILE
echo "I2C_OMAP35XX_PID_FILE="$I2C_OMAP35XX_PID_FILE

# Checking for ACTION.
# Checking for one of variables from iput parameters 4 & 5 would be sufficient to make sure we got 2 parameters as input.
if [ "$ACTION" == "" ] || [ "$I2C_UNIT_NUMBER" == "" ]; then
    echo "Invalid input parameters!!!"
    exit 3
fi

if [ "$ACTION" == "stop" ]; then
    if [ -e $I2C_OMAP35XX_PID_FILE ]; then
        echo "Stop the driver!"
        slay `cat $I2C_OMAP35XX_PID_FILE`
        rm -f $I2C_OMAP35XX_NAME_FILE
        rm -f $I2C_OMAP35XX_PID_FILE       
    fi         
    exit 0
fi

if [ -e $I2C_OMAP35XX_PID_FILE ]; then 
    echo "I2C-OMAP35XX already started don't need to start anything" 
    exit 0
fi     

# devc diver name 
I2C_OMAP35XX_DRIVER_NAME=/bin/i2c-omap35xx

#
# Make absolutely sure that the driver exist 
#
if [ ! -x $I2C_OMAP35XX_DRIVER_NAME ]; then
  exit 1
fi

#
# Start the driver
#
#i2c-omap35xx -a1 -i56 -p0x48070000 --u1
$I2C_OMAP35XX_DRIVER_NAME -a$I2C_UNIT_NUMBER -i$IRQ -p$PORT --u1& 
I2C_OMAP35XX_PID=$!
waitfor $I2C_RESOURCE

#
# Make sure the new driver started, else quit
#
if [ ! -e $I2C_RESOURCE ]; then
  exit 2
fi

#
# If the driver started, place the filename into /tmp for slaying later
#
echo -n $I2C_OMAP35XX_DRIVER_NAME > $I2C_OMAP35XX_NAME_FILE
echo -n $I2C_OMAP35XX_PID > $I2C_OMAP35XX_PID_FILE
 
exit 0
