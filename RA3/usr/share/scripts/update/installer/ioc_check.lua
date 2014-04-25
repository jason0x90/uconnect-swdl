-- ioc installer



module("ioc_check",package.seeall)

local onoff         = require "onoff"
local helper        = require "installerhelper"
local string        = require "string"
local os            = os


local printLog      = helper.printLog

-- error code 
local STOP_SWDL_CLEAR_UPDATE        = helper.STOP_SWDL_CLEAR_UPDATE 
local STOP_SWDL_DONT_CLEAR_UPDATE   = helper.STOP_SWDL_DONT_CLEAR_UPDATE
local CONTINUE_SWDL                 = helper.CONTINUE_SWDL

local g_path = nil

---------------------------------------------------------
--  executeDevIPC  
--  start/stop dev-ipc
--------------------------------------------------------------------------------
local function executeDevIPC(unit, operation)
    local cmd = g_path.."/"..unit.dev_ipc_script.." trace "..operation
    
    printLog(string.format("dev-ipc operation %s", operation))
    local ret_code = os.execute(cmd)/256
    
    -- Check for the return code     
    if (ret_code ~= 0) then 
        printLog(" Unable to"..operation.." dev-ipc successfully")
        return false, "Unable to"..operation.." dev-ipc successfully"
    end 
    
    return true 
end

--------------------------------------------------------------------------------
-- install  
--  
--------------------------------------------------------------------------------
function install(unit, mountpath)

    g_path = mountpath
    local ok ,err = executeDevIPC(unit, "start")    
    if not ok then 
        return false, err 
    end   
    
    -- get the bootloader version running on target
    local target_bolo_version = onoff.getBoloVersion()
    if target_bolo_version == nil then
        printLog(" no bolo version returned, assumption is its an old bootloader")
        return false, "Incompatible firmware detected", CONTINUE_SWDL
    else   
        printLog(" target_bolo_version : "..target_bolo_version)
        -- get the bootloader version allowed
        local target_num1, target_num2, target_num3 = string.match(target_bolo_version, ".-(%d+).-(%d+).-(%d+)")     
        if ((target_num1 == nil) or (target_num2 == nil) or (target_num3 == nil) )then 
            return false, "Incompatible firmware detected", CONTINUE_SWDL
        end         
        -- get the bootloader version allowed
        if (unit.bootloader_version_required == nil) then 
            printLog(" manifest is bad ")
            return false, "bad manifest"
        end
        printLog(" allowed : "..unit.bootloader_version_required)
       
        local allowed_num1, allowed_num2, allowed_num3 = string.match(unit.bootloader_version_required, ".-(%d+).-(%d+).-(%d+)")          
        if ( (target_num1 < allowed_num1) or 
             ( (target_num1 == allowed_num1) and (target_num2 < allowed_num2 ) ) or 
             ( (target_num1 == allowed_num1) and (target_num2 == allowed_num2 ) and  (target_num3 < allowed_num3 )) ) then        
            printLog("Incompatible firmware detected ") 
            return false, "Incompatible firmware detected", CONTINUE_SWDL
        end      
    end    
    return true             
 end