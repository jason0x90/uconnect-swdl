#!/bin/sh

# to run this script
#dab_start.sh <tunerConfig=$1>
# tunerConfig = -d or -s

echo "starting DAB1 - UART4"
devc-ser8250 -u4 -E -F -b115200 -c7372800/16 0x09000000^1,167

echo "starting DAB2 - UART5"
devc-ser8250 -u5 -E -F -b115200 -c7372800/16 0x09000010^1,168

waitfor /dev/ser4 4
waitfor /dev/ser5 4

echo "starting dev-spi-omap35x drivers for DAB"
dev-spi-omap35x -c /etc/dab/dev-spi_1-dab.cfg &
dev-spi-omap35x -c /etc/dab/dev-spi_4-dab.cfg &

echo "starting servicebroker for DSI"
servicebroker -vvvvv -c &

echo "starting dev-tuner-dab"
dev-tuner-dab -p/usr/var/dab/devdab.pers -i/dev/null -u/dev/ser4 -r/dev/gpio/XM_DAB1Reset -s/dev/spi40 -u/dev/ser5 -r/dev/gpio/HD_DAB2Reset -s/dev/spi10 --tp=/fs/mmc0/app/share/trace/dev-tuner-dab.hbtc &

echo "starting TunerFollowingMasterApp"
TunerApp --tp=/fs/mmc0/app/share/trace/TunerApp.hbtc &

echo "starting TunerFollowingSlave"
lua -s -b /usr/bin/service/TunerFollowingSlave.lua
waitfor /dev/serv-mon/com.harman.service.DMMTunerFollowingSlave.AMFMTunerDSIDevice 5

echo "starting dabService"
dabService $1 --tp=/fs/mmc0/app/share/trace/dabService.hbtc &
