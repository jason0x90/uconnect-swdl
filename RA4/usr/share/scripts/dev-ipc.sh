#!/bin/sh

# Exit codes:
#   0 = OK
#   1 = Unable to find SPI-MASTER
#   2 = Unable to start SPI-MASTER successfully
#   3 = Unable to find dev-ipc
#   4 = Unable to start dev-ipc successfully
#   5 = Invalid option
#
# Command line options:
#   start - Start drivers needed for dev-ipc
#   stop - Stop the drivers started  
#

DEV_IPC_NAME_FILE=/tmp/dev_ipc.name
DEV_IPC_PID_FILE=/tmp/dev_ipc.pid

SPI3_NAME_FILE=/tmp/spi3.name
SPI3_PID_FILE=/tmp/spi3.pid
 

#
# Parse through the command line options (start, stop, erase).  No command line
# options is equivalent to "start".  This parsing is not checked well, so don't
# do anything dumb.
#
while [[ "$1" != "" ]]; do
  case $1 in
    stop)
      if [ -e $DEV_IPC_PID_FILE ]; then
        slay `cat $DEV_IPC_PID_FILE`
        rm -f $DEV_IPC_NAME_FILE
        rm -f $DEV_IPC_PID_FILE       
      fi    
      if [ -e $SPI3_PID_FILE ]; then 
        slay `cat $SPI3_PID_FILE`
        rm -f $SPI3_NAME_FILE
        rm -f $SPI3_PID_FILE       
      fi      
      
      exit 0
      ;; 
    start)
      ;;      
    trace)
        ENABLE_TRACE="1"
      ;;      
    *)
      exit 5
      ;;
  esac
  shift
done


if [ -e $DEV_IPC_PID_FILE ]; then 
    echo "DEV IPC already started don't need to start anything"
    if [ "$ENABLE_TRACE" != "" ]; then
        waitfor /dev/ipc/debug
        echo "enableTrace(0)" > /dev/ipc/debug
        echo "enableTrace(2)" > /dev/ipc/debug
        echo "enableTrace(3)" > /dev/ipc/debug
        echo "enableTrace(4)" > /dev/ipc/debug
        echo "enableTrace(5)" > /dev/ipc/debug
        echo "traceChannel(1)" > /dev/ipc/debug
        echo "verbose(7)" > /dev/ipc/debug        
    fi    
    exit 0
fi     


# Start the SPI driver for channel 3 ( Used for dev-ipc)
SPI_DRIVER_NAME=/bin/spi-master

#
# Make absolutely sure that the driver exist 
#
if [ ! -x $SPI_DRIVER_NAME ]; then
  exit 1
fi


#
# Start the spi driver
#
$SPI_DRIVER_NAME  -u3 -domap3530 base=0x480B8000,bitrate=2000000,clock=48000000,irq=91,channel=3,force=1,num_cs=2
SPI3_PID=$!
waitfor /dev/spi3

#
# Make sure the new driver started, else quit
#
if [ ! -e /dev/spi3 ]; then
  exit 2
fi

#
# If the driver started, place the filename into /tmp for slaying later
#
echo -n $SPI_DRIVER_NAME > $SPI3_NAME_FILE
echo -n $SPI3_PID > $SPI3_PID_FILE
 
# Start the dev-ipc
DEV_IPC_DRIVER_NAME=/bin/dev-ipc

#
# Make absolutely sure that the driver exist 
#
if [ ! -x $DEV_IPC_DRIVER_NAME ]; then
  exit 3
fi
 
#
# Start dev-ipc
#
$DEV_IPC_DRIVER_NAME -c27 -o -K2000000 -D 0x708 -C0 -I235,291 -A5 -R32 &
DEV_IPC_PID=$!

#waitfor /dev/ipc/ch3


# TODO: Check is commented out because of bootloader bug 
# this will open and close the channel which was causing problems
# eventually will put this back
#
# Make sure the new driver started, else quit
#
#if [ ! -e /dev/ipc/ch3 ]; then
#  exit 4
#fi

#enable debug ( for old bootloader support)
if [ "$ENABLE_TRACE" != "" ]; then
    waitfor /dev/ipc/debug
    echo "enableTrace(0)" > /dev/ipc/debug
    echo "enableTrace(2)" > /dev/ipc/debug
    echo "enableTrace(3)" > /dev/ipc/debug
    echo "enableTrace(4)" > /dev/ipc/debug
    echo "enableTrace(5)" > /dev/ipc/debug
    echo "traceChannel(1)" > /dev/ipc/debug
    echo "verbose(7)" > /dev/ipc/debug  
fi

#
# If the driver started, place the filename into /tmp for slaying later
#
echo -n $DEV_IPC_DRIVER_NAME > $DEV_IPC_NAME_FILE
echo -n $DEV_IPC_PID > $DEV_IPC_PID_FILE

waitfor /dev/ipc/debug
echo "enableTrace(0)" > /dev/ipc/debug
echo "verbose(7)" > /dev/ipc/debug  

exit 0
