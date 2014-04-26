#!/bin/sh

#
# ISO_PATH must be defined and point to the root of the mounted update 
# ISO image.  We prefer binaries in the ISO over those in the IFS and 
# on the target.
#

#
# check whether USB_STICK has been exported, and if not, figure out what it should be
#
if [ x"$USB_STICK" == x ]; then
  if [ -d /fs/usb0 ]; then
    USB_STICK=/fs/usb0
  elif [ -d /mnt/usb0 ]; then
    USB_STICK=/mnt/usb0
  fi
fi

export USB_STICK

export PATH=$ISO_PATH/bin:$ISO_PATH/usr/bin:$ISO_PATH/usr/sbin:/bin:/usr/bin:/sbin:/usr/sbin
export LD_LIBRARY_PATH=$ISO_PATH/lib:$ISO_PATH/usr/lib:$ISO_PATH/usr/lib/dll:/lib:/usr/lib:/lib/dll:/usr/lib/dll:/usr/lib/lua

# Start io-pkt
io-pkt-v4 -ptcpip

# Start dbus
nice -n-2 dbus-launch --sh-syntax --config-file=/etc/dbus-1/session.conf > /tmp/envars.sh
echo "export SVCIPC_DISPATCH_PRIORITY=12;" >> /tmp/envars.sh
eval `cat /tmp/envars.sh`

# start dev-ipc 
ksh $ISO_PATH/usr/share/scripts/dev-ipc.sh start
# TODO: waitfor is commented out because of bootloader bug 
# this will open and close the channel which was causing problems
# eventually will remove this and will put the waitfor 
#waitfor /dev/ipc/ch4 20 
sleep 2

if [ x"$NO_UI" == x ]; then
  # Start screen
  screen
  waitfor /dev/screen

  # Start hmiGateway
  hmiGateway -sj &

# Create link to hmiVars file for HMI to read out the current language setting
ln -fsP /fs/fram/hmi /usr/share/hmi/Update/bin/hmiVars

# Start adl
adl -runtime /lib/air/runtimeSDK /usr/share/hmi/Update/bin/Update.xml &
fi

# set the enviornment variables for Part number
eval `variant export`

# Launch the sw update watchdog, in case the update process is blocked
export LUA_PATH="./?.lua;./installer/?.lua;/usr/bin/?.lua;/usr/bin/?/init.lua";
cd $ISO_PATH/usr/share/scripts/update
lua -s swUpdateWatchdog.lua &

# Launch the Lua installer
lua -s softwareupdate.lua $ISO_PATH 

