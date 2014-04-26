#!/bin/sh


echo "Sierra Wireless MP750 Binary Image Loader"
function mploaderfun
{
   if [ -a /dev/swiusb4 ]; then
   	echo "Make Sierra MP750 into boothold mode" 
   	echo "AT!BOOTHOLD\r" > /dev/swiusb4
   	sleep 10
   	waitfor /dev/swiusb1 5 
   	if [ -a /dev/swiusb1 ]; then
   		 echo "updating......"
   		 mploader /dev/swiusb1 $IMAGE_PATH -d
   	else
   		echo "CNS port /dev/swiusb1 is not available"		
   	fi	 
   else
   	echo "AT Command port (/dev/swiusb4) is not available"
   fi	
}

if [[ -f $1 && $1 != "" ]]; then
     IMAGE_PATH=$1    
     mploaderfun
else
   echo "Unable to find any files to flash or $IMAGE_PATH not available"
fi