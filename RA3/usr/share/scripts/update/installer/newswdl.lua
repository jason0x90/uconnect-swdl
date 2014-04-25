-- installer used for moving from KaliSWDL to NewSWDL
-- this will mount the ISO used by NewSWDL and mount it 
-- on the existing mount path

module("newswdl",package.seeall) 

local helper = require "installerhelper"
local os = os
local onoff = require "onoff"

local printLog   = helper.printLog

local path 

function executeDevIPC(unit, operation)
    local cmd = path.."/"..unit.dev_ipc_script.." "..operation
    printLog(cmd)
    
    local ret_code = os.execute(cmd)/256
    
    -- Check for the return code     
    if (ret_code ~= 0) then 
        printLog(" Unable to"..operation.." dev-ipc successfully")
        return false, "Unable to"..operation.." dev-ipc successfully"
    end 
    
    return true 
end

---------------------------------------------------------------
-- install function
--  Will be called by softwareUpdater
--------------------------------------------------------------- 
function install(unit, progress, mountpath) 
    local boloflag
    
    path = mountpath
    local ok, err = executeDevIPC(unit, "start")  
    if not ok then 
        return false, err 
    end
    boloflag, err = onoff.getBoloMode()
    if boloflag == 1 then  
        printLog(" already in bolo mode continue with ioc update ")
    elseif boloflag == 0 then
        printLog (" Not in bolo mode, will put v850 in bootloader mode")
        onoff.setBoloMode()          
        onoff.reset()
        os.sleep(5)    
        return false, "Unable to reset after putting v850 in bolo mode"  
        
    else
        printLog("Invalid value for boloflag")      
        return false, "Unable to initialize v850 in boot mode"        
    end 

    oldSWDLpath = mountpath.."/"..unit.newswdl_mnt_path
    oldISO =      unit.newswdl_iso_path
    printLog("oldISO "..oldISO)
    printLog("oldSWDLpath "..oldSWDLpath)
    local ok ,err = os.mount(oldISO,  oldSWDLpath, "r", "cd", "exe")
    if not ok then 
        return false, err
    end  
    return true    
end
