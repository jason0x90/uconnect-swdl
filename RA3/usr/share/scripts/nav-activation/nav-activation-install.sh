#!/bin/sh

#
# ISO_PATH must be an environment variable set upon being called
#
if [[ "$ISO_PATH" == "" ]]; then
   echo "No ISO_PATH"
   exit 1
fi

#
# USB_PATH must be set as well
#
if [[ "$USB_PATH" == "" ]]; then
   echo "No USB_PATH"
   exit 2
fi

echo "ISO_PATH=$ISO_PATH  and  USB_PATH=$USB_PATH"

#
# ISO_PATH must be defined and point to the root of the mounted update 
# ISO image.  We prefer binaries in the ISO over those in the IFS and 
# on the target.
#
PATH=$ISO_PATH/bin:$ISO_PATH/usr/bin:$ISO_PATH/sbin:$ISO_PATH/usr/sbin:$PATH
LD_LIBRARY_PATH=$ISO_PATH/lib:$ISO_PATH/usr/lib:$ISO_PATH/lib/dll:$ISO_PATH/usr/lib/dll:/lib:/usr/lib:/lib/dll:/usr/lib/dll:/usr/lib/lua

# Launch the Lua installer
export LUA_PATH="./?.lua;./update/?.lua;./installer/?.lua;/usr/bin/?.lua;/usr/bin/?/init.lua";
cd $ISO_PATH/usr/share/scripts
lua -s ./nav-activation/nav-activation.lua $ISO_PATH $USB_PATH
