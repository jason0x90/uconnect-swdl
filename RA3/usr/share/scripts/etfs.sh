#!/bin/sh

# This script assumes that ISO_PATH has been exported.  It needs to know
# this path to start the appropriate driver.  If ISO_PATH is not defined, 
# this script will exit immediately.

# Exit codes:
#   0 = OK
#   1 = $ISO_PATH not set
#   2 = Could not detect HW revision
#   3 = Could not detect target BSP version
#   4 = Could not detect update BSP version
#   5 = Incompatible update of GAMMA BSP to BETA hardware target
#   6 = Incompatible update of BETA BSP to GAMMA hardware target with GAMMA BSP
#   7 = Could not determine ABI
#   8 = No usable NAND driver found
#   9 = ETFS driver in ISO image failed to start
#  10 = Unable to stop driver successfully
#  11 = Invalid option
#  12 = Driver is running, but mountpoint either does not exist OR is a not a directory (indicates corruption)
#
# Command line options:
#   -p /path/to/nand_partition.txt file
#   -v /path/to/version.txt file
#   start - Start driver
#   erase - Force erase of NAND at startup (launch driver with -e option)
#   format - Same as erase
#   stop - Stop the driver
#
# The -p and -v commands must come before the others.
#

NAME_FILE=/tmp/etfs.name
PID_FILE=/tmp/etfs.pid

if [[ "$ISO_PATH" == "" ]]; then
  exit 1
fi

#
# Parse out the partition map file and version file if available
#
while getopts "p:v:" flag
do
  case $flag in
    p)
      PARTITION_MAP=$OPTARG
      ;;
    v)
      UPDATE_VERSION=$OPTARG
      ;;
  esac
done

#
# See if the partition map file was passed in.  If not,
# default to the copy packaged on the ISO.
#
if [[ "$PARTITION_MAP" == "" ]]; then
  PARTITION_MAP=$ISO_PATH/etc/nand_partition.txt
fi

#
# See if the version file was passed in.  If not,
# default to the copy packaged on the ISO.
#
if [[ "$UPDATE_VERSION" == "" ]]; then
  UPDATE_VERSION=$ISO_PATH/etc/version.txt
fi



#
# Parse through the command line options (start, stop, erase).  No command line
# options is equivalent to "start".  This parsing is not checked well, so don't
# do anything dumb.
#
shift $((OPTIND-1))
while [[ "$1" != "" ]]; do
  case $1 in
  
    # 
    # When slaying the process need to make sure that process is 
    # slayed correctly,  will wait for 10 seconds for driver to disappear 
    # If still there will send a SIGKILL signal 
    #
    stop)
      if [ -e $PID_FILE ]; then
        slay `cat $PID_FILE`    
        LOOP_COUNT=0
        SIGKILL_DRIVER=1
        while ((LOOP_COUNT<10))
        do       
            pidin -p `cat $PID_FILE` > /dev/null 2>&1           
            if [ $? -eq 1 ]; then 
                SIGKILL_DRIVER=0
                break;           
            fi            
            sleep 1 
            LOOP_COUNT=$LOOP_COUNT+1    
        done     
        if [ $SIGKILL_DRIVER -eq 1 ]; then 
            slay -s KILL `cat $PID_FILE`    
            pidin -p `cat $PID_FILE` > /dev/null 2>&1
            if [ $? -eq 1 ]; then 
                rm -f $PID_FILE
                rm -f $NAME_FILE
            else
                exit 10                
            fi    
        fi     
      fi
      exit 0
      ;;
    format)
      ETFS_ERASE="-e"
      ;;
    erase)
      ETFS_ERASE="-e"
      ;;
    start)    
      ;;
    *)
      exit 11
      ;;
  esac
  shift
done



#
# Always use the 6.5.0 armle-v7 driver
#
ETFS_PATH="bin"

# 
# Only allow a single erase/format regardless of the reason
#
if [ "$ETFS_ERASE" != "" ]; then
  if [ -e /tmp/ETFS_FORMATTED ]; then
    unset ETFS_ERASE
  else
    touch /tmp/ETFS_FORMATTED
  fi
fi

#
# This function makes a legacy NAND partition map.  This layout is consistent 
# with the days before the partition mapping file existed.
#
function makeLegacyPartitionMap {
  print "Auto generated legacy NAND parition map" > $1
  print "# IPL PARTITION TABLE,  IPL SIZE IS CURRENTLY 1 BLOCK" >> $1
  print "IPL0,   0,    0" >> $1
  print "IPL1,   1,    1" >> $1
  print "IPL2,   2,    2" >> $1
  print "IPL3,   3,    3" >> $1
  print "" >> $1
  print "# IFS PARTITION TABLE,  IPL SIZE IS CURRENTLY 256 BLOCKS" >> $1
  print "IFS0,   4,    259" >> $1
  print "IFS1,   260,  515" >> $1
  print "IFS2,   516,  771" >> $1
  print "IFS3,   772,  1027" >> $1
  print "" >> $1
  print "# ETFS" >> $1
  print "ETFS, 1028, 2047" >> $1
}

#
# If the partition map does not exist, create an old legacy 
# mapping and put it into the place we were told to look.
#
if [ ! -e $PARTITION_MAP ]; then
  makeLegacyPartitionMap /tmp/nand_partition.txt
  ln -sP /tmp/nand_partition.txt $PARTITION_MAP
fi

#
# Now that we have everything sorted out, use the right driver
#
ETFS_DRIVER_FNAME=fs-etfs-omap3530_micron
ETFS_DRIVER=$ISO_PATH/$ETFS_PATH/$ETFS_DRIVER_FNAME

#
# Make absolutely sure all drivers, config files, and images
# are available
#
if [ ! -x $ETFS_DRIVER ]; then
  exit 8
fi

$ETFS_DRIVER -D cfg,teb -r131584 -m/fs/etfs $ETFS_ERASE -f $PARTITION_MAP > /dev/null 2>&1 &
ETFS_PID=$!
waitfor /dev/etfs1 15

#
# Make sure the new driver started, else quit
#
if [ ! -e /dev/etfs1 ]; then
  exit 9
fi

#
# If the driver started, place the filename into /tmp for slaying later
#
echo -n $ETFS_DRIVER_FNAME > $NAME_FILE
echo -n $ETFS_PID > $PID_FILE

#
# Check if the mountpoint exists as a directory
#
if [ ! -d /fs/etfs ]; then
  exit 12
fi

exit 0
