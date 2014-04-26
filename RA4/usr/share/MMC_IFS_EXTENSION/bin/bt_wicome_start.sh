#!/bin/sh

echo "bt_wicome_start.sh -- Start wicome SCP"

echo "starting serial driver for Bluetooth"
qon devc-seromap -t56 -h60,40,0x4800217e,0x0000,0x0004,0x49056034,0x49056094,21 -p -u1 -c48000000/16 0x4806A000^2,72
qwaitfor /dev/ser1 4

#Fix the reference clock for the McBSP5 to the correct reference of McBSP_CLKS (12.28MHz)
qon io -a 0x480022d8 -l4 -o0x00000055

# Determing whether the unit is a DV or PV unit
set -A prefix no no builtin
hw=$(cat /dev/mmap/hwtype 2>/dev/null)

echo Use ${prefix[$hw]}MAC_wicome.cfg file

#make sure there is a unique BDADDR 
#get the current value
btid=$( cat /dev/mmap/BT_ID 2>/dev/null )
#it must be exactly 12 hexadecimal digits
if [[ ( 12 != ${#btid} ) || ( $btid != 001CD7+([0-9a-fA-F]) ) ]]; then
    echo Setting unique Bluetooth address 
    printf "001CD7%0.6X" $RANDOM > /dev/mmap/BT_ID
    echo @@@@@@@@@@@@@@@@@@@@@@@@@
    echo -n New BDADDR. From $btid to: 
    cat /dev/mmap/BT_ID
    echo '\n@@@@@@@@@@@@@@@@@@@@@@@@@'
fi

export DSI_PATH="/fs/mmc0/app/lib/fwcommon/dsi"
export ICURES_PATH=/fs/mmc0/app/share/wicome
export SCP_REG_PATH=/fs/mmc0/app/share/wicome
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/wicome
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/fs/mmc0/app/lib/fwcommon/dsi

echo "starting servicebroker"
qon -d /fs/mmc0/app/bin/servicebroker -vvv

echo "starting DbService"
qon -d DbService -c /etc/wicome/dbservice_default.cfg -- --bp /usr/var/trace --tp=/fs/mmc0/app/share/trace/DbService.hbtc


echo "starting wicome"
qon -d WicomeSCP -f /etc/wicome/${prefix[$hw]}MAC_wicome.cfg -s wicome_config


qwaitfor /dev/wicome 10
if [ -a /dev/wicome ] ; then
   echo "Start Bluetooth Service"
   qon io-fs-media -dmediabt,wicome=/dev/wicome,verbose=2
   qon -d btservice -s /usr/bin/cmc/service/Bluetooth/main.lua -- --bp /usr/var/trace --tp=/HBpersistence/Bluetooth.hbtc
   LD_LIBRARY_PATH=:/fs/mmc0/app/lib/handsfree:$LD_LIBRARY_PATH
	qon -d -p 210 psse -f /fs/mmc0/app/share/handsfree/config/config.txt
fi


