#!/bin/sh

# Exit codes:
#   0 = OK
#   1 = MMC driver already running
#   2 = Failed to start MMC driver
#   3 = Error partitioning MMC
#   4 = Error re-reading partition table MMC
#   5 = Error formatting QNX6 filesystem(s) onto MMC
#   6 = MMC failed to mount filesystem(s)
#   7 = Filesystem check failed 
#  10 = Invalid option
#
# Command line options:
#   start - Start driver (defaults to update mode)
#   erase - Force erase/format of MMC at startup
#   format - Same as erase
#   stop - Stop the driver
#   umount - Unmount the filesystems (depricated for CMC)
#   mount - Mount the filesystems (depricated for CMC)
#   application - When scrips is used in non update mode 
#   checkfs - check the file system integrity

NAME_FILE=/tmp/mmc.name
PID_FILE=/tmp/mmc.pid
RAW_DEV="/dev/mmc0"
READ_DISTURB_DEV="/dev/mmc0t77"
APPLICATION_DEV="/dev/mmc0t177"
XLET_DEV="/dev/mmc0t178"
APPLICATION_PATH="/fs/mmc0"
XLET_PATH="/fs/mmc1"

#
# This function does general clean-up and reporting in case of errors
#
quit() {
   echo "MMC.SH: Quitting $1"

   sf=$1

   # unmount the application path
   if [[ -e $APPLICATION_PATH ]]; then
      umount -fv $APPLICATION_PATH
   fi
   
   # unmount the xlet path
   if [[ -e $XLET_PATH ]]; then
      umount -fv $XLET_PATH
   fi

   # unload the driver from memory
   if [[ -e $RAW_DEV ]]; then
   
      # slay the driver
      slay `cat $PID_FILE`
      
      # wait for it to end fully
      for k in 1 2 3 4 5 6 ; do
         
         waitfor $RAW_DEV 1  > /dev/null 2>&1
         if [[ $? -eq 0 ]]; then
            echo "MMC.SH: Waiting for $RAW_DEV to disappear on try $k"
         else
            break
         fi
         
         sleep 5

      done 

      # handle result
      if [[ $k -lt 5 ]]; then
         echo "MMC.SH: Driver for $RAW_DEV successfully slayed"
         
         # remove the pid and name files
         rm -f $PID_FILE
         rm -f $NAME_FILE

      else
         echo "MMC.SH: Unable to slay $RAW_DEV driver"
         sf=127
      fi

   else
      echo "MMC.SH: Driver for $RAW_DEV was not running"
   fi

   exit $sf
}

#
#  partitions the MMC device
#
partition() {
   echo "MMC.SH: Creating partitions on $RAW_DEV"

   # Grab the size of the MMC device
   MMC_SIZE=`fdisk $RAW_DEV query -T`
   ((MMC_END_CELL=MMC_SIZE-1))

   # make sure we got a response from fdisk
   if [[ MMC_END_CELL -lt 5 ]]; then
      quit 3
   fi
   
   # Get partition information.  If you change the numbers below, you 
   # must also change the MMC update script in the software download 
   # located here: /<project_root>/tcfg/omap/scripts/formatMMC.sh
   READ_DISTURB_SECTORS=0,1
   if [[ $MMC_SIZE -gt 15000 ]] then
      APPLICATION_SECTORS=2,10294
      # MICRON=15007, SANDISK=15187
      XLET_SECTORS=10295,$MMC_END_CELL
   else
      APPLICATION_SECTORS=2,6597
      # MICRON=7503, SANDISK=7575
      XLET_SECTORS=6598,$MMC_END_CELL
   fi

   # add partitions to table   
   echo "MMC.SH: Partitions on $MMC_SIZE cell device are ($READ_DISTURB_SECTORS $APPLICATION_SECTORS $XLET_SECTORS)"
   fdisk $RAW_DEV delete -a

   fdisk $RAW_DEV add -s 1 -t 77 -c $READ_DISTURB_SECTORS
   if [[ $? != 0 ]]; then 
      quit 3
   fi
   fdisk $RAW_DEV add -s 2 -t 177 -c $APPLICATION_SECTORS
   if [[ $? != 0 ]]; then 
     quit 3
   fi
   fdisk $RAW_DEV add -s 3 -t 178 -c $XLET_SECTORS
   if [[ $? != 0 ]]; then 
     quit 3
   fi
   
   # Rescan the partition table
   mount -e $RAW_DEV

   # Make sure they are ready
   if [[ -e $READ_DISTURB_DEV && -e $APPLICATION_DEV && -e $XLET_DEV ]]; then
      echo "MMC.SH: New partition table completed"
   else
      echo "MMC.SH: New partition table not detected"
      quit 4
   fi
   
}

format() {
   echo "MMC.SH: Formatting partitions on $RAW_DEV"
   
   if [[ -e $APPLICATION_DEV && -e $XLET_DEV ]]; then
      # Format the partitions.
      mkqnx6fs -q $APPLICATION_DEV
      if [[ $? != 0 ]]; then
         quit 5
      fi
      mkqnx6fs -q $XLET_DEV
      if [[ $? != 0 ]]; then
         quit 5
      fi
   else
      echo "MMC.SH: No partitons detected for format operatons"
   fi
}

#
# Parse through the command line options (start, stop, erase).  No command line
# options is equivalent to "start".  This parsing is not checked well, so don't
# do anything dumb.
#
while [[ "$1" != "" ]]; do
   case $1 in
      stop)
         quit 0
      ;;
      format)
         MMC_INIT=1
      ;;
      erase)
         MMC_INIT=1
      ;;
      start)
      ;;
      umount)
         umount -f $APPLICATION_PATH
         umount -f $XLET_PATH
         exit 0
      ;;
      mount)
         mount -t qnx6 $APPLICATION_DEV $APPLICATION_PATH 
         waitfor $APPLICATION_PATH 1 > /dev/null 2>&1
         if [[ ! -e $APPLICATION_PATH ]]; then
            quit 6
         fi
         mount -t qnx6 $XLET_DEV $XLET_PATH 
         waitfor $XLET_PATH 1 > /dev/null 2>&1
         if [[ ! -e $XLET_PATH ]]; then
            quit 6
         fi
         exit 0  
      ;;   
      application)
         APPLICATION_MODE=1     
      ;;
      checkfs)
         CHECK_FS=1
      ;;
      *)
         exit 10
      ;;
  esac
  shift
done

# Make sure the driver hasn't already been started
if [[ -e $PID_FILE ]]; then
   echo "MMC.SH: Driver for $RAW_DEV is already running"
else
   # Define MMC driver options
   if [[ $APPLICATION_MODE -eq 1 ]]; then
      echo "MMC.SH: Using application mode settings"
      MMC_DRIVER_FNAME=devb-mmcsd-omap3730teb
      # possible clock speeds: 24000000 48000000
      MMC_CLOCK=48000000
      AUTOMOUNT=1
      MMCSD_OPTIONS="mmcsd ioport=0x480b4000,ioport=0x48056000,irq=86,dma=30,dma=47,dma=48,noac12,normv,clock=$MMC_CLOCK"
      CAM_OPTIONS="cam cache"
      BLK_OPTIONS="blk noatime,cache=512k,lock,normv,rmvto=none,automount=mmc0t177:/fs/mmc0:qnx6:ro,automount=mmc0t178:/fs/mmc1:qnx6:ro"
      DISK_OPTIONS="disk name=mmc"
   else
      echo "MMC.SH: Using update mode settings"
      MMC_DRIVER_FNAME=devb-mmcsd-omap3730teb
      # possible clock speeds: 24000000 48000000
      MMC_CLOCK=48000000
      MMCSD_OPTIONS="mmcsd ioport=0x480b4000,ioport=0x48056000,irq=86,dma=30,dma=47,dma=48,noac12,normv,clock=$MMC_CLOCK"
      CAM_OPTIONS="cam cache"
      BLK_OPTIONS="blk noatime,cache=8m"
      DISK_OPTIONS="disk name=mmc"
   fi

   # start up the driver
   echo "MMC.SH: $MMC_DRIVER_FNAME $MMCSD_OPTIONS $CAM_OPTIONS $BLK_OPTIONS $DISK_OPTIONS"
   $MMC_DRIVER_FNAME $MMCSD_OPTIONS $CAM_OPTIONS $BLK_OPTIONS $DISK_OPTIONS &
   MMC_PID=$!

   # Make sure we have a raw device
   waitfor $RAW_DEV 5
   if [[ -e $RAW_DEV ]]; then
      # if no partition exists, then force creation and a format
      waitfor $APPLICATION_DEV 5 > /dev/null 2>&1
      waitfor $XLET_DEV 5 > /dev/null 2>&1
      waitfor $READ_DISTURB_DEV 5 > /dev/null 2>&1
      if [[ -e $READ_DISTURB_DEV && -e $APPLICATION_DEV && -e $XLET_DEV ]]; then
         # Place the driver PID and name  into /tmp for slaying later
         echo "MMC.SH: Driver started"
         echo -n $MMC_DRIVER_FNAME > $NAME_FILE
         echo -n $MMC_PID > $PID_FILE
      else
         echo "MMC.SH: Driver started, but no partitions (use \"mmc.sh format\")"
         MMC_INIT=1
      fi
   else
      echo "MMC.SH: No raw MMC device, driver not loaded"
      exit 2
   fi
fi

# create partitions and format if needed
if [[ $MMC_INIT -eq 1 ]]; then
   echo "MMC.SH: Initializing MMC"
   partition
   format
fi

# Check the filesystems if requested (do before mounting)
if [[ $CHECK_FS -eq 1 ]]; then
   echo "MMC.SH: Checking file systems on $RAW_DEV (must re-mount or re-start)"

   umount -f $APPLICATION_PATH
   umount -f $XLET_PATH

   chkqnx6fs -fv $APPLICATION_DEV
   if [[ $? != 0 ]]; then
      # Clean up any stray clusters found in chkqnx6fs.
      rm -f $APPLICATION_PATH/lost+found
      quit 7
   fi
   chkqnx6fs -fv $XLET_DEV
   if [[ $? != 0 ]]; then
      # Clean up any stray clusters found in chkqnx6fs.
      rm -f $XLET_PATH/lost+found
      quit 7
   fi
   AUTOMOUNT=0
fi

# mount the file system(s) if needed
if [[ $AUTOMOUNT -ne 1 ]]; then
   echo "MMC.SH: Mounting file systems on $RAW_DEV"
   mount -t qnx6 $APPLICATION_DEV $APPLICATION_PATH
   mount -t qnx6 $XLET_DEV $XLET_PATH
fi

# check if successfully mounted
waitfor $APPLICATION_PATH > /dev/null 2>&1
if [[ -e $APPLICATION_PATH ]]; then
   echo "MMC.SH: $APPLICATION_PATH detected"
else
   echo "MMC.SH: $APPLICATION_PATH not detected"
   quit 6
fi

waitfor $XLET_PATH > /dev/null 2>&1
if [[ -e $XLET_PATH ]]; then
   echo "MMC.SH: $XLET_PATH detected"
else
   echo "MMC.SH: $XLET_PATH not detected"
   quit 6
fi

exit 0
