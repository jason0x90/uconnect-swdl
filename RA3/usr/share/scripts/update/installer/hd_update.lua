-- HD Update installer

function pdbg(des)
   print("PAS ("..des..") start")
   os.execute("pwd")
   os.execute("sleep 5")
   print("PAS ("..des..") end")
end

module("hd_update",package.seeall)

local helper        = require "installerhelper"
local lfs           = require "lfs"
local os            = os
local printLog      = helper.printLog

-- error code returned by installer
local STOP_SWDL_CLEAR_UPDATE        = helper.STOP_SWDL_CLEAR_UPDATE 
local STOP_SWDL_DONT_CLEAR_UPDATE   = helper.STOP_SWDL_DONT_CLEAR_UPDATE
local CONTINUE_SWDL                 = helper.CONTINUE_SWDL

---------------------------------------------------------------
-- executeI2cOpmap
-- Function to start i2c-omap35xx
---------------------------------------------------------------
local function executeI2cOpmap(operation, port)
    local i2c_omap35xx_hd_script = g_path.."/"..g_unit.i2c_omap35xx_hd_script
    local cmd

    if port then
      cmd = i2c_omap35xx_hd_script.." "..operation.." "..port
    else
      cmd = i2c_omap35xx_hd_script.." "..operation
    end
    print(cmd)

    printLog(string.format("i2c-omap35xx operation %s", operation))
    local ret_code = os.execute(cmd)/256
    print("return code = "..ret_code)

    -- Check for the return code
    if (ret_code ~= 0) then
        printLog(" Unable to "..operation.." i2c-omap35xx successfully")
        return false, "Unable to "..operation.." i2c-omap35xx successfully"
    end

    return true
end

local function getFirmwareName(mountpath, unit)
    return mountpath.."/"..unit.dir_root.."/hdcurrent.bin"
end

--[[
    There is one HD chip to flash.
--]]
local function flashHDfirmware(cmd, progress, unit)
   local util_percent = 0
   local line

   print(cmd)
   local f = assert (io.popen (cmd, "r"))
    
   progress(unit, util_percent)
   for line in f:lines() do
      print(line)
   
      if ( string.match(string.upper(line), "^ERROR" ) ~= nil) then
         printLog("error"..line) 
         util_percent = 0
      end  

      if ( string.match(string.upper(line), "^DONE" ) ~= nil) then
         break      
      end
 
      if (string.match(line,"^%d*") ~= nil) then 
         util_percent = tonumber(line)
         progress(unit, util_percent)
      end 
   end
    
   f:close()

   if util_percent < 100 then
      util_percent = nil
   end
    
   return util_percent
end

---------------------------------------------------------------
-- install
--  Function will be called by update
---------------------------------------------------------------
function install(unit, progress, mountpath, current_unit)

    local percent = 0
    local current_hw_type = nil
    local cmd
    local util_percent
    local ok, err

    -- set the g_path to mountpath
    g_path = mountpath
    g_unit = unit

    local firmwareFullPath = getFirmwareName(mountpath, unit)
    if (firmwareFullPath == nil) then
        printLog(" Unable to find update file for HD Update")
        return false, " Unable to find update file for HD Update"
    end

    print("Firmware = "..firmwareFullPath)

    -- start i2c-omap35xx driver
    ok,err = executeI2cOpmap("start", 1)
    if not ok then
        executeI2cOpmap("stop", 1)
        return false, err, CONTINUE_SWDL
    end
    
    -- Start programming the HD chip
    -- cmd = "hdupdate -s -f "..firmwareFullPath -- debugging
    cmd = "hdupdate -s "..firmwareFullPath
    util_percent = flashHDfirmware(cmd, progress, unit)
    print("flashHDfirmware returned "..util_percent)
    
    executeI2cOpmap("stop", 1)
    if util_percent == nil then
        return false, line, CONTINUE_SWDL
    end

    printLog("HD update done")

    return true
end



