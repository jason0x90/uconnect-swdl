#!/bin/sh
#

#
# clear the backup archive
#

if [ -d /mnt/usb0 ]; then
  if [ -e /mnt/usb0/swdl_backup.tar ]; then
    rm -f /mnt/usb0/swdl_backup.tar
  fi
fi


