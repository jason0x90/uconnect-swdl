#!/bin/sh
#


BACKUP_DIR=$1

if [ x"$BACKUP_DIR" == x ]; then
  BACKUP_DIR=$USB_STICK
fi

if [ x"$BACKUP_DIR" == x ]; then
  BACKUP_DIR=/mnt/usb0
fi


#
# clear the backup archive
#

if [ -d $BACKUP_DIR ]; then
  if [ -e $BACKUP_DIR/swdl_backup.tar ]; then
    rm -f $BACKUP_DIR/swdl_backup.tar
  fi
fi


