#!/bin/sh

echo Cleaning up FRAM...
find /dev/mmap/ -type n ! -name ipl ! -name partnumber ! -name productid ! -name hwtype ! -name screen-calib -exec dd if=/fs/mmc0/app/share/misc/f_up_fram of={}
