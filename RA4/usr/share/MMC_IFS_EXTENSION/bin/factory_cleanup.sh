#!/bin/sh

if [ ! -e /tmp/boot_done ]; then
   echo "###################################################################"
   echo "### CANNOT begin factory_cleanup before boot.sh is finished !!! ###"
   echo "###################################################################"
   exit 255
fi     

echo Checking temperature of MMC...
# check temperature here and exit script if not > -25
T=`check_temperature.lua`
if [[ $T -ne 0 ]]; then
   echo Brrrr too cold to do this now...
   exit 255
fi

# source DBUS environment
. /tmp/envars.sh

# signal that services have 5 seconds to shut down before factory reset, wait 5 seconds and then signal that we are starting
echo 5 second timeout while signaling on dbus for factory cleanup...
dbus-send --type=signal /com/harman/service/platform com.harman.service.platform.factory_reset string:"notifying" string:"{\"timeout\":5}"
sleep 5
dbus-send --type=signal /com/harman/service/platform com.harman.service.platform.factory_reset string:"starting"

echo Killing lua services and apps...
slay -f lua > /dev/null

# pet the watchdog so that we can slay/restart onOff safely with all other LUA's
echo Starting mongrel to pet the dog...
waitfor /usr/local/bin/mongrel.lua
lua -s -b /usr/local/bin/mongrel.lua &

if [ $VARIANT_MODEL = "VP3" ]; then
	mount -uw /fs/mmc0
	echo Deactivating Navigation
	rm -rf /fs/mmc0/nav/NNG/license/ACTIVATION_CODES
	rm -rf /fs/mmc0/nav/NNG/license/device.nng
fi

echo Resetting factory installed JAR files... 
mount -uw /fs/mmc1
rm -rf /fs/mmc1/xletsdir/xlets/*
cp -rp /fs/mmc1/kona/preload/xlets/* /fs/mmc1/xletsdir/xlets/
rm -rf /fs/mmc1/kona/data/DRM.jar
cp -rp /fs/mmc1/kona/preload/DRM.jar /fs/mmc1/kona/data/

# call factory_cleanup_support here
echo "Running factory cleanup support script ($1)..."
factory_cleanup_support.lua $1
echo ""
