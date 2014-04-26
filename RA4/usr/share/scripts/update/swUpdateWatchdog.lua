--[[
     This file serves as a watchdog for the softwareupdate process.
	 In case the software update process becomes 'unresponsive' for 
	 any number of reasons, this script will still detect an EJECTED 
	 event of the USB and can reset the radio, preventing the possible
	 need for a battery disconnect.
]]


local mcd       = require "mcd"
local onoff     = require "onoff"
local helper    = require "installerhelper" 
local os        = os


local mcdEjectRule       = "EJECTED"
local IOCBOLOMODESTRING  = "bolo"
local swdlStateFile      = "/dev/mmap/swdl"
local bootModeBit        = 2
local normalModeFlag     = "A"


-- Get the boot mode flag. Return string or nil and an error message.
local function getOmapBootMode()
   local bootmode
   print("getOmapBootMode: swdlStateFile: ", swdlStateFile)
   local fd, err =  io.open(swdlStateFile, "r")
   local unit_number = nil
   if fd then
      fd:seek("set", bootModeBit)
      bootmode, err = fd:read(1)
      fd:close()
   end
   return bootmode, err
end


----------------------------------------------------------------------
-- Media has been ejected, reset into bolo
----------------------------------------------------------------------
local function processEject(path)   
   local resetMode = IOCBOLOMODESTRING
   local mode, err = getOmapBootMode()

   if (not err) and (mode == normalModeFlag) then
      -- We are here because the user has removed a USB update stick during an update,
      -- and the update mode has been set to 'normal' mode.  This could occur when:
      --
      -- 1) The user removes the USB stick right after successful completion of an update 
      --    (and setting of the update mode flag), but before the normal reset occurs (very short time window)
      --
      -- 2) A unit completed with success==false, and an error code of STOP_SWDL_CLEAR_UPDATE 
      --    (currently only used by system_module_check.lua); In this case a popup window is present
      --    instructing the user to remove the USB update stick, and the normal softwareupdate.lua
      --    processing will handle this case anyway, so we shouldn't also reset the radio.
      --
      -- So, in these cases, don't reset the radio from here at all.  The situation will 
      -- successfully be handled by softwareupdate.lua.
      print("##### swUpdateWatchdog.lua::processEject: OmapBootMode is 'NORMAL' so just exiting here, letting softwareupdate.lua handle things ####")
      return
   end
   
   if (path ~= nil) and (string.find(path, "usb" ) ~= nil) then  
      helper.printLog("swUpdateWatchdog.lua: USB EJECTED... resetting Radio") 
      -- sync the file system before resetting
      os.execute("sync")
      os.sleep(1)  
      onoff.reset(IOCBOLOMODESTRING)

      -- sleep to give IOC time to reset us
      os.sleep(1)

      -- NOTE: We should never get here because the IOC shoudl reset the radio...
      os.exit(2)
   else
      print("swUpdateWatchdog.lua::processEject called with path:", path, ", but no usb ejection")
   end 
end


--------------------------------------------------------------------------------
-- Set notifications for USB eject
--------------------------------------------------------------------------------
mcd.notify(mcdEjectRule, processEject)
print("swUpdateWatchdog.lua LISTENING for mcd EJECTED events")

