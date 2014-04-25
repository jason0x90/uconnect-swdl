#!/bin/sh

# ----- Functions ----

loadtertiaryifs()
{
   echo memifs2 with 4-bit ECC
	# (use this if loading with etfs not already loaded) memifs2 -q -N -e 1 -n /
   memifs2 -p 3 -q -N -e 1 -n /
   if [[ 0 != $? ]] ; then
      echo "**********Failure while loading tertiary IFS**********" > /dev/ser3
      echo "**********Marking current IFS as invalid ***********"
      waitfor /dev/mmap/
      adjustImageState -c 1
      if [[ 0 == $? ]] ; then
         echo "**********Image state set to bad************"
      else
         echo "*******Unable to adjust image state - FRAM not available********"
      fi
      echo "**********Resetting the hardware********************"
      echo -n "\\0021" > /dev/ipc/ch4
   else
      echo "Tertiary IFS loaded successfully"
   fi
}



loadquadifs()
{
   echo memifs2 with 4-bit ECC
	# (use this if loading with etfs not already loaded) memifs2 -q -N -e 1 -n /
   memifs2 -q -l 40 -p 4 -N -e 1 -n /
   if [[ 0 != $? ]] ; then
      echo "**********Failure while loading quaternary IFS**********" > /dev/ser3
      echo "**********Marking current IFS as invalid ***********"
      waitfor /dev/mmap/
      adjustImageState -c 1
      if [[ 0 == $? ]] ; then
         echo "**********Image state set to bad************"
      else
         echo "*******Unable to adjust image state - FRAM not available********"
      fi
      adjustImageState -c 1
      echo "**********Resetting the hardware********************"
      echo -n "\\0021" > /dev/ipc/ch4
   else
      echo "quad IFS loaded successfully"
   fi
}

# ---- Main ----

export CONSOLE_DEVICE=/dev/ser3


# Redirect all output to /dev/null at startup to clean up the console
# Can turn on after etfs driver starts with /fs/etfs/VERBOSE_STARTUP
reopen /dev/null

echo ========= Start of boot.sh ====================

###   echo starting io-pkt............
qon -e LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/wicome io-pkt-v4 -ptcpip stacksize=8192


###   echo starting dbus............
qln -sfP /tmp /usr/var/run/dbus
qon -p 12 /usr/bin/dbus-launch --sh-syntax --config-file=/etc/dbus-1/session.conf > /tmp/envars.sh

echo "setting dbus variables for clients"
echo "export SVCIPC_DISPATCH_PRIORITY=12;" >> /tmp/envars.sh
eval `cat /tmp/envars.sh`

# Launch isp-screen AFTER DBUS is fully setup
echo "starting camera service"
qon -p 21 -d isp-screen -s -d /usr/bin/cmc/service/Ispvideo ispVideoService.lua

echo "starting service-monitor"
qon -d /usr/bin/service-monitor > $CONSOLE_DEVICE

# Set the platform variant information. Must come before launching platform services
eval `variant export`

 
# Extend the LUA path to include platform services and bundles
LUA_PATH="$LUA_PATH;/usr/bin/cmc/service/?.lua;/usr/bin/cmc/service/platform/?.lua"

qon -p 11 lua -s -b -d /usr/bin service.lua
# Run the platform launcher in a "managed" manner by service.lua borrowed from VP3L
qon -p 11 lua -b -d /usr/bin/cmc/service/platform platform_launcher.lua -m -n launch_bundle -p bundle.stage0 

#  Start the usb overcurrent monitor utility
qon -d usb_hub_oc -p 10 -i 10 -d 500

#Command to start a kernel trace if desired at startup
#tracelogger -M -S 64M -s 3 -w &

#io -a 0x48320010 > $CONSOLE_DEVICE &
# Things started and used before loading the secondary IFS must be in the boot.ifs
###   echo loading Tertiary IFS............
loadtertiaryifs &

#disable trace-client logging by default
if [ ! -e /fs/mmc1/LOGGING ]; then

qln -sP / /fs/mmc0/app/share/trace
qln -sP /dev/null /hbsystem/multicore/navi/3
qln -sP /dev/null /hbsystem/multicore/navi/4
qln -sP /dev/null /hbsystem/multicore/navi/J
qln -sP /dev/null /hbsystem/multicore/navi/dbglvl
qln -sP /dev/null /hbsystem/multicore/navi/g
qln -sP /dev/null /hbsystem/multicore/navi/multi
qln -sP /dev/null /hbsystem/multicore/navi/r
qln -sP /dev/null /hbsystem/multicore/temic/0
qln -sP /dev/null /hbsystem/multicore/trace/0
qon -d dev-mv2trace -b 10000 -w 5 -m socket

else
# if want to write log directly to usb, make sure the mark /fs/mmc1/USB_LOGGING is removed.
   if [ -e /fs/mmc1/USB_LOGGING ]; then
     ###   echo starting trace client............
    qon -d multicored -D2 -F2 -n500 -Q -c file -q -m /hbsystem/multicore -R -f /fs/mmc1/LOGFILE.DAT -s 524288000
    qwaitfor /hbsystem/multicore
    qon -d dev-mv2trace -b 10000 -w 5 -m multicored -f
    qon mount -uw /fs/mmc1
   else
     if [ -e /fs/mmc0/nav/GNLOG_MSD ]; then
        qon -d multicored -D2 -F2 -n500 -Q -c file -q -m /hbsystem/multicore -R -f /fs/usb0/LOGFILE.DAT -s 524288000
     else
        qon -d multicored -D0 -F0 -n500 -Q -c file -q -m /hbsystem/multicore
     fi
    qwaitfor /hbsystem/multicore
    ###   echo starting trace client............
    qon -d dev-mv2trace -b 10000 -w 5 -m multicored
   fi

fi


echo "starting io-audio "
qon -p 211 io-audio -osw_mixer_samples=3072,intr_thread_prio=254 -domap35xx-dsp mcbsp=2,clk_mode=1,tx_voices=4,rx_voices=4,protocol=tdm,xclk_pol=1,sample_size=16 -osw_mixer_samples=768,intr_thread_prio=254 -domap35xx-bt mcbsp=4,clk_mode=1,sample_size=16,tx_voices=1,rx_voices=1,protocol=tdm,bit_delay=1,cap_name=bt_capture,play_name=bt_play -osw_mixer_samples=1536,intr_thread_prio=254 -domap35xx-bt mcbsp=5,clk_mode=1,sample_size=16,tx_voices=2,rx_voices=2,protocol=pcm,bit_delay=1,cap_name=embedded_capture,play_name=embedded_play 

###   echo make mmc1 r/w (REMOVE WHEN CONNECTIVITY IS READY)
#PAS mount -uw /fs/mmc1/

# launching persistency manager is dependent on qdb
echo "starting persistency_mgr"
qon persistency_mgr -p -v 2 -c /etc/persistency_mgr/pmem.ini > $CONSOLE_DEVICE 2>&1

###   echo starting pps............
qwaitfor /dev/pmfs 
qon pps -p /dev/pmfs 

qwaitfor /dev/serv-mon/com.harman.service.PersistentKeyValue

qon set_default_theme

###   echo starting canservice............
qon canservice 

# temp link so touch input works
qln -sfP /tmp /dev/devi

qwaitfor /bin/fs-etfs-omap3530_micron
echo "tertiary loaded"  > $CONSOLE_DEVICE &
#io -a 0x48320010 > $CONSOLE_DEVICE &

#starting the random generator now
qon -d random -t -p

###   echo starting ETFS driver............
qon fs-etfs-omap3530_micron -c 1024 -D cfg -m/fs/etfs -f /etc/system/config/nand_partition.txt

qon hmiGateway -sj 

# Must start prior to USB enumeration. We must ensure the itun
# setup is not delayed when an iPhone is connected at startup
# with the entune app running. We have 5 seconds to start the 
# itun driver and reply to the iPhone. If we miss this window 
# the user will have to disconnect/connect the entune app. So
# start this driver early so it has time to initialize.
qon mount -T io-pkt lsm-tun-v4.so


# Ensure qdb directories exists before starting it
if [ ! -d /usr/var/qdb ]; then
qon mkdir -p /usr/var/qdb
fi
echo "starting qdb"
if [ ! -e /fs/etfs/VERBOSE_QDB ]; then
    qon qdb -c /etc/qdb.cfg -s latin2@unicode -o unblock=0,tempstore=/usr/var/qdb -R auto -X /bin/qdb_recover.sh
else
    qon qdb -c /etc/qdb.cfg -s latin2@unicode -vvvvvv -o unblock=0,tempstore=/usr/var/qdb,trace,profile -R auto -X /bin/qdb_recover.sh
fi

# Redirect all output back to the console if developer wants verbose output
if [ -e /fs/etfs/VERBOSE_STARTUP ]; then
   reopen $CONSOLE_DEVICE
fi

echo "starting flexgps & ndr"
qon flexgps_ndr.sh 

# start packet filtering early enough to prevent telnet access 
# even if user has DHCP server on connected PC
# starts enabled and reads config from default /etc/pf.conf
qon mount -T io-pkt lsm-pf-v4.so
 
if [ -x /fs/etfs/custom.sh ]; then
   echo running custom.sh............ > $CONSOLE_DEVICE
   qon /fs/etfs/custom.sh > $CONSOLE_DEVICE
fi

# This script can be used to set configuration settings after an update (if needed)
if [ -x /fs/mmc0/app/bin/runafterupdate.sh ]; then
   echo running runafterupdate.sh............ > $CONSOLE_DEVICE
   qon /fs/mmc0/app/bin/runafterupdate.sh &
fi

qwaitfor /dev/qdb


qon -p 21 -d audioCtrlSvc -c /etc/audioCtrlSvcDEFAULT.conf

#echo "starting adl"
#io -a 0x48320010 > $CONSOLE_DEVICE &

# ARGUMENT TO SET ADL PID
ADL_PID_FILE=/tmp/adlpid

# Set HMI boost time in msec and priority
# Set time to 0 to disable priority boost
echo -n 400 > /tmp/HMI_BOOST_TIME
echo -n 11 > /tmp/HMI_BOOST_PRIORITY

# Running ADL at priority 11 for hmi improvement
qon -d -e MALLOC_ARENA_SIZE=65535 nice -n-1 adl -runtime /lib/air/runtimeSDK /fs/mmc0/app/share/hmi/main.xml &  

AD3_PID=$!
echo -n $AD3_PID > $ADL_PID_FILE

#temporarily raising priority of onoff, until natp is fixed
qon -p 11 lua -s -b /usr/bin/onoff/main.lua > $CONSOLE_DEVICE

echo "starting hwctrl"
qon hwctrl

# THIS IS CREATED BY ADL WHEN DISCLAIMER IS SHOWN
#TODO: REMOVE THIS WHEN ANGELO STARTUP CHANGES ARE BROUGHT IN
#waitfor /tmp/adl_startup.txt 10



# Stage1 Lua scripts
echo "bundle::bundle.stage1" >> /pps/launch_bundle




if [ $VARIANT_DAB = "YES" ]; then
   #temp echo to fire up DAB module
   echo "\0000\0001\0001" >/dev/ipc/ch10   
fi

echo "starting AM/FM tuner"
#-DEST uses DEST code
#-VEHLINE uses VC_VEH_LINE
if [ -e /var/override/verboseTunerStart ]; then
   qon lua -s -b /usr/bin/cmc/service/Tuner/main.lua -VEHLINE -DEST -v 0x8000 > $CONSOLE_DEVICE
else
   qon lua -s -b /usr/bin/cmc/service/Tuner/main.lua -VEHLINE -DEST
fi

echo "starting audio manager"
qon -d cmcManager -m autoplay &
qon lua -s -b /usr/bin/cmc/audioMgtWatchdog.lua

if [[ $(cat /tmp/lastAudioMode) = *cd* ]]; then
    echo "last audio mode is CD"  > $CONSOLE_DEVICE &
    #starting RSE as independent entity
    qon lua -s -b /usr/bin/cmc/service/platform/rse/rse.lua
fi

# Launch stage2 Lua scripts (software/hardware key processing)
echo "bundle::bundle.stage2" >> /pps/launch_bundle

echo "starting appManager"
if [ ! -d /fs/etfs/usr/var/appman/xletRMS ]; then
	qon mkdir -p /fs/etfs/usr/var/appman/xletRMS
fi
if [ -e /fs/etfs/disableDRM ]; then
  qon -d appManager -s -j -c=/etc/system/config/appManager.cfg --tp=/fs/mmc0/app/share/trace/appManager.hbtc
else
  qon -d appManager -s -j -d -c=/etc/system/config/appManager.cfg --tp=/fs/mmc0/app/share/trace/appManager.hbtc
fi

if [ $VARIANT_SDARS = "YES" ]; then
   echo "starting XM control port"
   ####
   # Note: If the command line for the serial driver is changed, please make the same change in platform_xmApp.lua
   ####
   qon devc-ser8250 -u4 -I32768 -r200 -R50 -D800 -c7372800/16 0x09000000^1,167
   qwaitfor /dev/ser4 4
fi

if [[ $(cat /tmp/lastAudioMode) = *sat* ]]; then
    echo "[BOOT] Last audio mode is XM"  > $CONSOLE_DEVICE &
    if [ $VARIANT_SDARS = "YES" ]; then
        echo "[BOOT] Starting xmApp"    
        if [ -e /fs/etfs/SYSTEM_UPDATE_DONE ]; then
            echo "Copying from /fs/mmc0/app/share/sdars/traffic to /fs/etfs/usr/var/sdars/ (no overwrite)"  > $CONSOLE_DEVICE
            qon cp -RX /fs/mmc0/app/share/sdars/traffic /fs/etfs/usr/var/sdars/ 

            echo "Copying from /fs/mmc0/app/share/sdars/sports to /fs/etfs/usr/var/sdars/ (no overwrite)" >  $CONSOLE_DEVICE
            qon cp -RX /fs/mmc0/app/share/sdars/sports /fs/etfs/usr/var/sdars/ 

            echo "Copying from /fs/mmc0/app/share/sdars/sportsservice to /fs/etfs/usr/var/sdars/ (no overwrite)" >  $CONSOLE_DEVICE
            qon cp -RX /fs/mmc0/app/share/sdars/sportsservice /fs/etfs/usr/var/sdars/ 

            echo "Copying from /fs/mmc0/app/share/sdars/channelart to /fs/etfs/usr/var/sdars/ (no overwrite)" >  $CONSOLE_DEVICE
            qon cp -RX /fs/mmc0/app/share/sdars/channelart /fs/etfs/usr/var/sdars/ 

            qon chmod  -R +rwx /fs/etfs/usr/var/sdars 
        fi              

        if [ $VARIANT_MODEL = "VP4" ]; then
            (waitfor /tmp/xm_shdn_line_ready.txt; xmApp -c /etc/sdars/XMApp.cfg --tp=/fs/mmc0/app/share/trace/XMApp.hbtc) &      
            qon lua -s -b /usr/bin/cmc/xmwatchdog.lua
        else
            (waitfor /tmp/xm_shdn_line_ready.txt; xmApp -c /etc/sdars/XMAppAudioOnly.cfg --tp=/fs/mmc0/app/share/trace/XMApp.hbtc) &      
            qon lua -s -b /usr/bin/cmc/xmwatchdog.lua
        fi
        qwaitfor /tmp/xmAppModuleInitializing 10 
    fi
fi


# Starting dabLauncher
# DR: Temporary until DAB_PRSNT is added to canservice
if [ -e /var/override/forceDABStart ]; then
   qon lua -s -b /usr/bin/cmc/dabLauncher.lua -v -f
else
   qon lua -s -b /usr/bin/cmc/dabLauncher.lua
fi

loadquadifs &

# THIS IS CREATED BY  LAYER MANAGER WHEN ACCEPT BUTTON IS READY
qwaitfor /tmp/accept.txt 10

# save sequentual dumps to ETFS if requested
##if [ -e /fs/etfs/enableDumper ]; then
#   qon -d dumper -d /fs/etfs -n
##fi

echo copy resolv.conf to /tmp....
qon cp /fs/mmc0/app//share/ppp/resolv.conf /tmp/resolv.conf

# Proxy should start prior to connmgr
echo "starting 3proxy"
qon /usr/bin/3proxy /etc/system/config/3proxy.cfg

# Must start prior to USB enumeration. We must ensure the itun
# setup is not delayed when an iPhone is connected at startup
# with the entune app running.
echo "starting connection manager"
qon connmgr -c "/etc/system/config/connmgr_P_1_2.json"

echo "starting usb detection"
qon enum-devices -c /etc/system/enum/common 

# Start media.  Do not background this.
qon media.sh
qwaitfor /dev/serv-mon/com.harman.service.Media

# Slay audioCtrlSvc worker thread to higher priority. This reduces lag during volume adjustments in 
# non amplified vehicles, especially under heavy CPU load conditions
slay -T 1 -P 21 audioCtrlSvc

# Launch the bundle that launches vehicle status, and CAN reporting services
echo "bundle::bundle.stage3" >> /pps/launch_bundle

# Explicitly have to start clock separately because as written it
# consumes too much of the platform_launcher's time-slice
qon lua -s -b -d /usr/bin/cmc/service/platform/clock clock.lua


# Start dbus-monitor  only if this flag is set  else its started when 
# cisco or dlink adapter is detected
if [ -e /fs/etfs/FORCE_DBUSTRACE_MON ]; then
    echo "starting dbustracemonitor"
    qon -d dbustracemonitor --bp -f=/usr/var/trace/traceDbusServices --tp=/usr/var/trace/DBusTraceMonitor.hbtc
fi

if [[ $(cat /tmp/lastAudioMode) != *sat* ]]; then
    echo "[BOOT] Last audio mode is not XM"  > $CONSOLE_DEVICE &
    if [ $VARIANT_SDARS = "YES" ]; then
        echo "[BOOT] Starting xmApp"    
        if [ -e /fs/etfs/SYSTEM_UPDATE_DONE ]; then
            echo "Copying from /fs/mmc0/app/share/sdars/traffic to /fs/etfs/usr/var/sdars/ (no overwrite)"  > $CONSOLE_DEVICE
            qon cp -RX /fs/mmc0/app/share/sdars/traffic /fs/etfs/usr/var/sdars/ 

            echo "Copying from /fs/mmc0/app/share/sdars/sports to /fs/etfs/usr/var/sdars/ (no overwrite)" >  $CONSOLE_DEVICE
            qon cp -RX /fs/mmc0/app/share/sdars/sports /fs/etfs/usr/var/sdars/ 

            echo "Copying from /fs/mmc0/app/share/sdars/sportsservice to /fs/etfs/usr/var/sdars/ (no overwrite)" >  $CONSOLE_DEVICE
            qon cp -RX /fs/mmc0/app/share/sdars/sportsservice /fs/etfs/usr/var/sdars/ 

            echo "Copying from /fs/mmc0/app/share/sdars/channelart to /fs/etfs/usr/var/sdars/ (no overwrite)" >  $CONSOLE_DEVICE
            qon cp -RX /fs/mmc0/app/share/sdars/channelart /fs/etfs/usr/var/sdars/ 

            qon chmod  -R +rwx /fs/etfs/usr/var/sdars 
        fi              
        if [ $VARIANT_MODEL = "VP4" ]; then
            (waitfor /tmp/xm_shdn_line_ready.txt; xmApp -c /etc/sdars/XMApp.cfg --tp=/fs/mmc0/app/share/trace/XMApp.hbtc) &
            qon lua -s -b /usr/bin/cmc/xmwatchdog.lua
        else
            (waitfor /tmp/xm_shdn_line_ready.txt; xmApp -c /etc/sdars/XMAppAudioOnly.cfg --tp=/fs/mmc0/app/share/trace/XMApp.hbtc) &      
            qon lua -s -b /usr/bin/cmc/xmwatchdog.lua
        fi
    fi
    

fi

# echo "starting diag service"
qon lua -s -b  /usr/bin/cmc/service/diagserv.lua

echo "starting Vehicle Lua services" 

# Launch the bundle that launches personal configuration, swcPal, vehicle settings,
# hvac, climate and psse 
echo "bundle::bundle.stage4" >> /pps/launch_bundle

if [[ $(cat /tmp/lastAudioMode) != *cd* ]]; then
    echo "last audio mode is not CD"  > $CONSOLE_DEVICE &
    #starting RSE as independent entity
    qon lua -s -b /usr/bin/cmc/service/platform/rse/rse.lua
fi

echo "Starting Authentication Service"
qon -d authenticationService -k /etc/system/config/authenticationServiceKeyFile.json

# Renice adl to normal priority
# Angelo Giannotti Removed - don't need to do this unless you nice adl when it is launched.
# renice +1 -p `cat  $ADL_PID_FILE`

echo "starting Navigation"
qon nav.sh

qwaitfor /dev/serv-mon/com.harman.service.Navigation 10 

echo "starting WavePrompter service"
qon mqueue
qon -d wavePrompter -p12 -c /fs/mmc0/app/share/wavePrompter/wavePrompter.conf

echo "starting Bluetooth"
qon bt_wicome_start.sh 

qwaitfor /dev/serv-mon/com.harman.service.BluetoothService 5

echo "starting UISpeechService and natp for speech recognition and tts"
#/bin/sh /fs/mmc0/app/bin/start_natp.sh
qon speech.sh 

qwaitfor /tmp/waitfornothing 12 

qwaitfor /dev/serv-mon/com.harman.service.UISpeechService 5

echo "starting embeddedPhoneDbusService"
qon -d -e LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib/wicome embeddedPhone -s /usr/bin/cmc/service/embeddedPhoneDbusService.lua

# Start sideStreamer, create system directory files used by mediaService for streaming files
#   these entries must match entries in mcd.conf and mme_data.sql
if [ -e /fs/etfs/VERBOSE_SIDESTREAMER_USB ]; then
	echo starting sideStreamer verbosely with log
	qon -d /usr/bin/sideStreamer -v 7ff -s /etc/system/config/sideStreamer.conf > /fs/usb0/streamer.log
elif [ -e /fs/etfs/VERBOSE_SIDESTREAMER_ETFS ]; then
	echo starting sideStreamer verbosely with log
	if [! -e /fs/etfs/tmp/sideStreamer ]; then
		mkdir /fs/etfs/tmp/sideStreamer
	fi
	qon -d /usr/bin/sideStreamer -v 7ff -s /etc/system/config/sideStreamer.conf > /fs/etfs/tmp/sideStreamer/streamer.log
else
	echo starting sideStreamer 
	qon -d /usr/bin/sideStreamer -v 1 -s /etc/system/config/sideStreamer.conf
fi


echo "starting ecallService"
(waitfor /dev/serv-mon/com.harman.service.EmbeddedPhone 30; ecallService)  &


echo "starting connectivity"
qon -d connectivity_startup.sh

echo "starting voltage regulator in normal mode............."
qon isendrecv -a0x48 -n/dev/i2c2 -l2 0x04 0xb7
echo "starting eqService............."
qon lua -s -b  -d /usr/bin/service/eqService/ eqService.lua -i /dev/mcd/SER_ATTACH -e /dev/mcd/SER_DETACH -b /fs/mmc0/eq

# Launch the bundle that launches embedded phone, SDP DataManager, and DTC services
echo "bundle::bundle.stage5" >> /pps/launch_bundle  

#lets start the service which are less important after navigation is up 
qwaitfor /dev/serv-mon/com.aicas.xlet.manager.AMS 30 

# Launch the bundle that launches systemInfo, screen shot, nav trail service,
# and file services
echo "bundle::bundle.stage6" >> /pps/launch_bundle

echo "starting software update service"
(cd /usr/bin/cmc/service/swdlMediaDetect; lua -s -b  ./swdlMediaDetect.lua) &

echo "Starting Anti Read Disturb Service"
qon -d ards_startup.sh

echo "Starting omapTempService ........."
qon omapTempService -d -p 2000 

# Start Image Rot Fixer, currently started with high verbosity
# Options -v for Verbosity and -p for priority
qon image_rot_fixer -v 6 -p 9

qon -d lua -s -b /usr/bin/cmc/service/platform/platform_ams_restart.lua > $CONSOLE_DEVICE

if [ ! -e /fs/etfs/BOX_INITIALIZED ]; then
    # script to perform factory initialization (reset requred for changes to be effective)
    qon -p 9 initialize_hu.lua
    qon touch /fs/etfs/BOX_INITIALIZED
fi     

# Clear the flag set by software update, used to initialize 
# XMAPP datatbase after a system update
qon rm -rf /fs/etfs/SYSTEM_UPDATE_DONE

# Create a flag indicating boot.sh has completed executing
# (Used to prohibit certain actions prematurely; i.e., factory_cleanup.sh)
qon touch /tmp/boot_done
