#!/bin/sh

# start the Nuance NATP application. It has it's own library path because it 
# has some shared objects with the same name as the Wicome shared objects 
# due to their shared past history

echo Start natp for speech recognition and tts

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/speech

# Make sure there is no hardlink from the ETFS to the MMC (boot.sh once did this).
# This will only remove the directory if it is a link.  A normal directory will be left alone.
# There is currently no way of doing this in the installer, so we are doing it here.
qon find /fs/etfs/usr/var/speech_service -type l -exec rm -fr {}

#Check if folders are present, else create them
if [ ! -e /fs/etfs/usr/var/speech_service/dialog/grammar/ ]; then
   qon mkdir -p /fs/etfs/usr/var/speech_service/dialog/grammar/
fi

if [ ! -e /fs/etfs/usr/var/speech_service/dialog/common/ ]; then
   qon mkdir -p /fs/etfs/usr/var/speech_service/dialog/common/
fi

if [ ! -e /fs/etfs/usr/var/speechTEFiles/mediaOutOfSync/ ]; then
   qon mkdir -p /fs/etfs/usr/var/speechTEFiles/mediaOutOfSync/
fi

if [ ! -e /fs/etfs/usr/var/speechTEFiles/extPhones/ ]; then
   qon mkdir -p /fs/etfs/usr/var/speechTEFiles/extPhones/
fi

if [ ! -e /fs/etfs/usr/var/speechTEFiles/sat/ ]; then
   qon mkdir -p /fs/etfs/usr/var/speechTEFiles/sat/
fi

if [ ! -e /fs/etfs/usr/var/speechTEFiles/apps/ ]; then
   qon mkdir -p /fs/etfs/usr/var/speechTEFiles/apps/
fi

# ARGUMENT TO SET NATP PID
NATP_PID_FILE=/tmp/natpid

if [[ (-e /fs/mmc0/speech_service) ]]; then
   # temporarily raising priority of natp until its fixed 
   qon -d natp -f /fs/mmc0/speech_service/config/natp.cfg -s natp_config -k VerboseLevel=1
   NATP_PID=$!
   echo -n $NATP_PID > $NATP_PID_FILE
else
   echo ERROR : /fs/mmc0/speech_service does not exist....
fi

# Start UISpeechService
qwaitfor /dev/scp_natp 30

qon -d UISpeechService /dev/shmem/natp/ /fs/etfs/usr/var/ /fs/etfs/ -- --bp=/usr/var/trace/ --tp=/fs/mmc0/app/share/trace/VR.hbtc

#Use this to raise VR priority to 1 higher than base priority. This enhances latency performance and prevents 'stalls' when paired with priority
#adjustments for NAV and ADL. Threads 32 and 34 get slayed back down to regular priority since these are used during media sync and should
#run at the higher priority. Eventually these could be adjusted inside the Nuance delivery using the natp.cfg file, but this implementation 
#is cleaner in the near-term. BCG 8/5/13
renice -1 $(cat /tmp/natpid)
slay -T 32 -P 9 natp
slay -T 34 -P 9 natp