#!/bin/sh

# NOTE:----- This is a template.. Please modify it according to your needs...
echo "starting network...."
waitfor /dev/io-usb
mount -T io-pkt devn-asix.so
sleep 2
dhcp.client -unb
inetd
qconn

echo "network done."
echo "mouting desktop....."
fs-cifs //<name>:<ip address>:/projects  /mnt/projects  target T123456789?
fs-cifs //<name>:<ip address>:/share     /mnt/share     target T123456789?

# map /images for reflash
ln -fsP /mnt/projects/Chrysler_Fiat-CMC_for_ED_HW/products/arm-qnx-m650-4.4.2-osp-trc-rel-ed-hw/tcfg /images

exit 0

if [ -a /fs/sd0/net ]; then
   # boot from network
   NETBOOT=/mnt/net/tcfg/mtp/omap/scripts/netboot
   waitfor $NETBOOT
   $NETBOOT
else
   # boot from sdcard
   /fs/sd0/boot-demo.sh
fi
