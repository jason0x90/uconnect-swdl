-- ioc bootloader installer

module("ioc_bootloader",package.seeall)

local onoff         = require "onoff"
local helper        = require "installerhelper"
local lfs            = require "lfs"
local os            = os
local printLog      = helper.printLog

local g_path        = nil
local g_progress    = nil
local g_unit        = nil
local g_percent     = 0


local IOCBOLOMODESTRING           = onoff.IOCBOLOMODESTRING
local IOCAPPMODESTRING            = onoff.IOCAPPMODESTRING
local IOCBOLOLOADERMODESTRING     = onoff.IOCBOLOLOADERMODESTRING



local function trim(s)
   local i,n = s:find("#")
   if i then s = s:sub(1,i-1) end
   return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end
----------------------------------------------------------------------
-- read bolo version from manifest 
----------------------------------------------------------------------
local function readBoloVersionFromManifest()
    local app_version = nil
    local bolo_version = nil
    local manifest_file = g_path.."/"..g_unit.manifest_file 
   
    if manifest_file == nil then
        printLog("Invalid arguments for parse_and_perform")
        return nil, "Invalid arguments for parse_and_perform"
    end

    local input = io.open(manifest_file, "r")
    if input == nil then 
        printLog("Unable to open config file")
        return nil, "Unable to open config file"
    end    
    
    for line in input:lines() do
        local s = trim(line)
        if s == "EOF" then 
            break 
        end
        app_version, bolo_version = s:match("^version.-(%d+%.%d+%.%d+).-(%d+%.%d+%.%d+)")        
        if (app_version ~= nil and bolo_version ~= nil) then        
            print(" app_version: "..app_version.." bolo_version: "..bolo_version )
            break
        end      
    end    
    return bolo_version
end         

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
-- checkBoloUpdateRequired()
-- this will check whether a bootloader update is required or not
-- will check whether the bootloader on target is same as 
-- bootloader on stick 
--------------------------------------------------------------- 
local function checkBoloUpdateRequired()
    -- get the bootloader version from target, this command is 
    -- recently added so its possible that we don't receive 
    -- response, so in this case its assumed that 
    -- will need an update
    
    local target_bolo_version = onoff.getBoloVersion()
  
    
    if target_bolo_version == nil then
        printLog(" no bolo version returned, assumption is its an old bootloader")
        return true
    else     
        printLog(" target bolo version "..target_bolo_version)    
        local target_num1, target_num2, target_num3 = string.match(target_bolo_version, ".-(%d+).-(%d+).-(%d+)") 
        print(target_num1.."."..target_num2.."."..target_num3)
        
        if ((target_num1 == nil) or (target_num2 == nil) or (target_num3 == nil) )then 
            return false, "incorrect target bolo version "
        end         
        
        -- read the manifest to find the bootloader version on the stick
        local stick_bolo_version = readBoloVersionFromManifest()
        printLog(" bolo version on stick "..stick_bolo_version)
        if (stick_bolo_version == nil) then 
            return false, "Unable to find bootloader version from stick"
        end
        local new_num1, new_num2, new_num3 = string.match(stick_bolo_version, ".-(%d+).-(%d+).-(%d+)")          
        if (new_num1 == nil or new_num2 == nil or new_num3 == nil) then 
            return false, "incorrect bolo version on maniefst"
        end 
                
        print(new_num1.."."..new_num2.."."..new_num3)     
        
        -- convert the string into numbers
        new_num1 = tonumber(new_num1)
        new_num2 = tonumber(new_num2)
        new_num3 = tonumber(new_num3)
        target_num1 = tonumber(target_num1)
        target_num2 = tonumber(target_num2)
        target_num3 = tonumber(target_num3)        
        
        -- check if we have newer version on stick then what's on target        
        if (  (new_num1 > target_num1) or 
              ((new_num1 == target_num1) and (new_num2 > target_num2)) or
              ((new_num1 == target_num1) and (new_num2 == target_num2) and (new_num3 > target_num3)) 
           ) then 
            printLog("New bootloader is available")
            return true          
        end           
    end    
              
    return false
end 

---------------------------------------------------------------
-- flashImage 
--  
---------------------------------------------------------------
local function flashImage(image)
    local percent = 0
    local cmd = "iocupdate -c 4 -p "..image        
    local f = assert (io.popen (cmd, "r")) 
    for line in f:lines() do
        if (string.match(line,"^%s*%d") ~= nil) then 
            local unit_percent = tonumber(line)       
            print(unit_percent)                 
            if (unit_percent ~= 0) then 
                percent = math.floor(g_percent + (unit_percent/2))
                g_progress(g_unit, percent) 
            end   
        end             
        -- if case of error 
        if ( string.match(string.upper(line), "^%s*ERROR" ) ~= nil) then    
            printLog("error"..line)        
	        local ok, err = executeDevIPC(g_unit, "stop") 
	        if not ok then 
	            return false, err
	        end          
            return false, line
        end  
    end
    f:close()   
end
 
 
---------------------------------------------------------------
-- install 
--  Function will be called by update
---------------------------------------------------------------
function install(unit, progress, mountpath, current_unit, total_units)
    local boloflag   
    local status = false
    local bootloaderUpdater = mountpath.."/"..unit.bootloaderUpdater
    local bootloader = mountpath.."/"..unit.bootloader
    local manifest_file = mountpath.."/"..unit.manifest_file 
    
    printLog(string.format("bootloaderUpdater %s",bootloaderUpdater))
    printLog(string.format("bootloader %s",bootloader))   
    
        -- Check if bolo and application binary files exists
    if ( (lfs.attributes( bootloaderUpdater, "mode" ) == nil) or 
         (lfs.attributes( bootloader, "mode" ) == nil) or 
         (lfs.attributes( manifest_file, "mode" ) == nil) ) then 
        printLog(string.format("IOC Bootloader update, binaries missing"))
        return false, "Unable to locate binary files"
    end       
    
    
    -- set the global veriables 
    g_path      = mountpath    
    g_progress  = progress
    g_unit      = unit    
 
    local ok, err = executeDevIPC(unit, "start")       
    if not ok then 
        return false, err 
    end 
    
    -- call preInstaller, if specified
    ok, err = helper.callPrePostInstaller(unit, mountpath, "pre")
    if not ok then 
        return false, "pre installer failure"
    end   
    
    -- ioc bootloader works in steps, 
    -- 1) Check whether in bolo mode or app
    -- 2) If in bolo mode 
    --  2.1) Check whether a bootloader update is required ( check what we have on target and what's on stick )
    --  2.2) If not needed then exit
    --  2.3) If required than flash the bootloader updater and the reset
    --       box in application mode( modify the fram bit)  
    -- 3) If in application mode that means IOC must be running bootloader 
    --     update 
    -- 4) flash the bootloader
    -- 5) reset the box in bolo mode now ( modify fram bit)    
   
    local bootmode, err= onoff.getBootMode(2000) 
    if (bootmode == nil) then 
        return false, "ipc communication is broken"             
    elseif (bootmode == IOCBOLOMODESTRING) then 
        -- in bolo mode
        g_percent = 1
        g_progress(g_unit, g_percent)        
        status, err = checkBoloUpdateRequired()            
        if err then
            return false, err
        end
        g_percent = 5
        g_progress(g_unit, g_percent)
        if (status == true) then
            status, err = flashImage(bootloaderUpdater) 
            if err then 
                return false, err        
            end
            -- will reset the box in bootloader update mode
            onoff.setExpectedIOCBootMode(IOCBOLOLOADERMODESTRING)
            onoff.setUpdateInProgress(current_unit)
            -- reset the box in application mode 
            onoff.reset()   
            -- should not return 
            os.sleep(5)           
        else
           printLog(" No Bootloader Update is needed")
            -- no update required
            g_percent = 100
            g_progress(g_unit, g_percent)
            return true
        end       
   -- if in BOLOLOADER updater mode
    elseif (bootmode == IOCBOLOLOADERMODESTRING) then 
        -- initialize the g_progress as 50 as we have already done half the 
        -- update for this unit before reset
        g_percent = 50               
        -- in application mode
        status, err = flashImage(bootloader) 
        if err then 
            return false, err        
        end

        -- check if there is any unit left after this, if this is last then we are done
        -- else reset the box in bolo and set update for next unit
        if ((current_unit + 1) > total_units) then 
            return true
        else
            onoff.setUpdateInProgress(current_unit+1)
            onoff.setExpectedIOCBootMode(IOCBOLOMODESTRING)
            onoff.reset(IOCBOLOMODESTRING)  
            -- should not return 
            os.sleep(5)            
        end 
    end          
end     
