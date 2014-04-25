-- DMB Update installer

module("dmb_update",package.seeall)

local helper        = require "installerhelper"
local lfs           = require "lfs"
local json          = require "json"
local os            = os
local printLog      = helper.printLog

-- error code returned by installer
local STOP_SWDL_CLEAR_UPDATE        = helper.STOP_SWDL_CLEAR_UPDATE 
local STOP_SWDL_DONT_CLEAR_UPDATE   = helper.STOP_SWDL_DONT_CLEAR_UPDATE
local CONTINUE_SWDL                 = helper.CONTINUE_SWDL

local dmbSvc = "com.harman.service.dmbApp"


---------------------------------------------------------------
-- executedevcSer8250
-- Function to start decv_ser8250
---------------------------------------------------------------
local function executedevcSer8250(operation, port)
    local devc_ser8250_dab_script = g_path.."/"..g_unit.devc_ser8250_script
    local cmd

    if port then
      cmd = devc_ser8250_dab_script.." "..operation.." "..port
    else
      cmd = devc_ser8250_dab_script.." "..operation
    end
    print(cmd)

    printLog(string.format("devc-ser8250 operation %s", operation))
    local ret_code = os.execute(cmd)/256
    print("return code = "..ret_code)

    -- Check for the return code
    if (ret_code ~= 0) then
        printLog(" Unable to"..operation.." devc-ser8250 successfully")
        return false, "Unable to"..operation.." devc-ser8250 successfully"
    end

    return true
end


function getListing (path, pattern)
   local result = {}
   local exists, error = lfs.chdir(path)
   local total = 0 

   if not exists then
      return nil, {error=error} 
   end
    
   for file in lfs.dir(path) do
      local fileAttrs = lfs.attributes(path.."/"..file)
      local match, error = string.match(file, pattern)
      if (fileAttrs.mode == "file") and (file ~= ".") and (file ~= "..") and (match ~= nil) then
            result[file] = {size = fileAttrs.size}
            total = total + 1
      end
   end
   
   return {listing = result, total = total}, nil
end



local function getFirmwareName(mountpath, unit)
   local src_dir = mountpath.."/"..unit.dir_root
   local result, error = lfs.chdir(src_dir)
   
   if error or (result == nil) then
      return nil
   end

   -- Grab the *.bin file out of the DMB update folder   
   local filename = nil
   for file in lfs.dir(src_dir) do
      local match, error = string.match(file, ".*%.bin")
     if match and (not error) then
         filename = src_dir.."/"..file
      end
   end
   
   return filename
end


---------------------------------------------------------------
-- install
--  Function will be called by update
---------------------------------------------------------------
function install(unit, progress, mountpath, current_unit)

   local percent = 0
   local result, err
   local i = 0

   -- set the g_path to mountpath
   g_path = mountpath
   g_unit = unit

   -- Set initial progress
   progress(unit, percent)

   -- Start the serial driver necessary for dmbApp to communicate with the module
   result, err = executedevcSer8250("start", 4)
   if not result then
      executedevcSer8250("stop", 4)
      printLog(" ERROR: Unable to start serial driver for dmbApp ")
      return false, err, STOP_SWDL_CLEAR_UPDATE
   end

   -- Get the path to the DMB module firmware    
   local firmwareFullPath = getFirmwareName(mountpath, unit)
   if (firmwareFullPath == nil) then
      printLog(" Unable to find update file for DAB Update")
      return false, " Unable to find update file for DAB Update"
   end

   -- Get the path to the dmbApp binary which does the programming
   local dmbAppPath = mountpath.."/"..unit.dir_root.."/dmbApp &"
   printLog("DMB Firmware = "..firmwareFullPath)
   printLog("DMB app path = "..dmbAppPath)

   -- Launch dmbApp, and retrieve it's output
   local f = assert (io.popen (dmbAppPath, "r"))
   printLog("launched dmbApp...")
   
   -- Wait up to 30 seconds for dmbApp to publish itself on DBUS
   for i = 0, 30, 1 do 
      if service.nameHasOwner(dmbSvc) then  break  end
      os.sleep(1)
   end

   -- Initiate the firmware update
   if service.nameHasOwner(dmbSvc) then
      result, err = service.invoke(dmbSvc, "DMB_Update_Start_Path", {UpdatePath=firmwareFullPath}, 30000)
      printLog(string.format("dmb_update.lua: DMB_Update_Start_Path: result = %s, err = [%s]", json.encode(result), json.encode(err)))
      if err or (result == nil) then
         err = string.format("ERROR: Invoke of DMB_Update_Start_Path resulted in: [%s]", json.encode(err))
         return false, err, STOP_SWDL_CLEAR_UPDATE
      end
   else
      err = "dmb_update.lua: ERROR dmbApp did not appear on DBUS"
      printLog(err)
      return false, err, STOP_SWDL_CLEAR_UPDATE
   end

   -- Monitor progress of the update...   
   for line in f:lines() do
      local pcnt = string.match(line,"%[(%d*)%]%%")
      if pcnt ~= nil then
         printLog(string.format("dmb_update: %d%% complete", tonumber(pcnt)))
         percent = tonumber(pcnt)
         progress(unit, percent)
      end 
      if percent >= 100 then  break  end
   end

   f:close()
   executedevcSer8250("stop", 4)
   printLog("dmb update done")
   return true
end



