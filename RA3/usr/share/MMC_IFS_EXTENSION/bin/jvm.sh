#!/bin/sh

export KD_QNX_WINDOWPROPERTY_CLASS=FlashWindow
export KD_QNX_WINDOWPROPERTY_ID_STRING=AMS
export KD_WINDOWPROPERTY_VISIBILITY=false

export SCREENSIZE=640x480
export WIDTH=640
export HEIGHT=480
export AMS_CLIP_WITH_SCISSORS=false
export AMS_JAVA_STACK_SIZE=20k
export AMS_NATIVE_STACK_SIZE=64k
export AMS_HEAP_SIZE=60M
export AMS_NUM_THREADS=200
export AMS_MAX_NUM_THREADS=200
export AMS_PRIORITY_MAP=0=1,1=7,2..4=9,5..37=10,38..39=11

export AMS_TEXTURE_CACHE_SIZE=14336
export AMS_MAX_NUMBER_GC_CALLS=6

AMS -installationDirectory /fs/mmc1/xletsdir -extensionDirectory /fs/mmc1/kona/extension -initializerJar ams_initializer.jar -xletExtensionDirectory /fs/mmc1/kona/lib -amsPropertyFile /fs/mmc1/kona/data/ams.properties -securityConfiguration /fs/mmc1/kona/security/security.jar -secure &
