-- ioc installer



module("ioc",package.seeall)

local onoff         = require "onoff"
local helper        = require "installerhelper"
local os            = os
local printLog      = helper.printLog

local g_path = nil

---------------------------------------------------------------
-- executeDevIPC 
-- Function to start dev-ipc
---------------------------------------------------------------
local function executeDevIPC(unit, operation)
    local cmd = g_path.."/"..unit.dev_ipc_script.." trace "..operation
    print(cmd)
    
    printLog(string.format("dev-ipc operation %s", operation))
    local ret_code = os.execute(cmd)/256
    
    -- Check for the return code     
    if (ret_code ~= 0) then 
        printLog(" Unable to"..operation.." dev-ipc successfully")
        return false, "Unable to"..operation.." dev-ipc successfully"
    end 
    
    return true 
end
 
---------------------------------------------------------------
-- install 
--  Function will be called by update
---------------------------------------------------------------
function install(unit, progress, mountpath, current_unit)

    local boloflag    
    local percent = 0
    
    -- set the g_path to mountpath 
    g_path = mountpath
    
    print("Start dev-ipc ")
    
    progress(unit, 0)     
    local ok, err = executeDevIPC(unit, "start")   
    
    if not ok then 
        return false, err 
    end 
   
    progress(unit, 1) 
    
    -- call preInstaller, if specified
    ok, err = helper.callPrePostInstaller(unit, mountpath, "pre")
    if not ok then 
        return false, "pre installer failure"
    end  
    
    
    print("dev-ipc started")   
 
    local cmd = "iocupdate -c 4 -p ".. mountpath.."/"..unit.data    
    local f = assert (io.popen (cmd, "r")) 
    for line in f:lines() do
        if (string.match(line,"^%s*%d") ~= nil) then 
            percent = tonumber(line)       
            print(percent)                 
            if (percent ~= 0) then 
                progress(unit, percent) 
            end   
        end             
        -- if case of error 
        if ( string.match(string.upper(line), "^%s*ERROR" ) ~= nil) then    
            printLog("error"..line)        
	        local ok, err = executeDevIPC(unit, "stop") 
	        if not ok then 
	            return false, err
	        end          
            return false, line
        end  
    end
    f:close()   
    
    if (percent < 100) then 
        return false, "Unable to finish ioc update"
    end
    
    -- call preInstaller, if specified
    ok, err = helper.callPrePostInstaller(unit, mountpath, "post")
    if not ok then 
        return false, "pre installer failure"
    end  
    
    printLog("ioc update done")
    return true
end    
        
    
       
    