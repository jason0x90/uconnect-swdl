--[[

 This module contains helper routines for installers  
 
]] 

module("installerhelper",package.seeall) 

local device = require("device")

-- Log file to be stored on USB stick 

local usbPath = os.getenv( "USB_STICK")
if usbPath == nil then
   usbPath = "/fs/usb0"
end
local logFilePath = usbPath.."/swdlLog.txt"
local logFileFd = nil
local logFileCreate = true

-- Global error codes, will be used by installer to return 
-- error code
STOP_SWDL_CLEAR_UPDATE        = 1    
STOP_SWDL_DONT_CLEAR_UPDATE   = 2 
CONTINUE_SWDL                 = 3 
RETRY_SWDL_UNIT               = 4

---------------------------------------------------------------
-- createLogFile 
-- Helper function to create log file
---------------------------------------------------------------
function createLogFile()
    local err
    print( " ********createLogFile ********")       
    -- First remove the logFile, if it exists 
    local cmd = "rm "..logFilePath.." > /dev/null 2>&1 "
    os.execute(cmd)   
    logFileFd, err = device.open(logFilePath, "rwc")   
    if (logFileFd == nil) then 
        print ("Unable to create logFile err "..err)
        logFileCreate = false
    else
        logFileFd:write(string.format("********SOFTWARE UPDATE LOG********\n"))
    end
end    

-------------------------------------------------------------------------------
-- printLog 
-- helper function to printLog in the log file
-------------------------------------------------------------------------------
function printLog(data)
    local err
    if (data == nil) then 
        return {}
    end
    
    if logFileCreate and ( logFileFd == nil) then         
        -- Open in update mode 
        logFileFd, err = device.open(logFilePath, "rwa")
        if (logFileFd == nil) then 
            print(data)    
            print(" Unable to open logFile")      
            logFileCreate = false
        end         
    end    
    print(data)    
    if ( logFileFd ~= nil) then
    logFileFd:write(string.format("%s\n",tostring(data))) 
    end
end

-------------------------------------------------------------------------------
-- executeETFS 
-- Helper function to start ETFS driver, will be used by installers
-- operation : "start" , "stop" or "format"
-------------------------------------------------------------------------------
function executeETFS(path, unit, operation)
   
    local reformat              = false
    local new_nand_partition    = nil
    local version_file          = nil
    local new_start, new_end, old_start, old_end
    local cmd
    local cmd2    
    local ret_code
    
    -- target nand partition file 
    local target_nand_partition = "/etc/system/config/nand_partition.txt"
    
    if unit == nil then 
        printLog("ExecuteETFS, no unit specified")
        return false, "No unit specified"
    end
    
    print("config file from manifest "..unit.config_file)    
    print("version_file from manifest "..unit.version_file) 
    printLog(string.format("Operation on etfs : %s for unit %s", operation, unit.name))     
    
    -- the path for config file is absoulte path if 
    -- if starts with /. for example /fs/usb0/nand_partition.txt,
    -- else it is relative to mountpath
    if (string.match(unit.config_file,"^/") ~= nil) then 
        new_nand_partition = unit.config_file
    else
        new_nand_partition = path.."/"..unit.config_file
    end
    
    print("new_nand_partition  "..new_nand_partition)    
    
    -- the path for version file is absoulte path if 
    -- if starts with / for example /fs/usb0/nand_partition.txt,
    -- else it is relative to mountpath
    if (string.match(unit.version_file,"^/") ~= nil) then 
        version_file = unit.version_file
    else
        version_file = path.."/"..unit.version_file
    end
    
    print("version_file  "..version_file)   
    
    -- if operation is start then, check whether nand partition file on target and 
    -- new nand partition contains different blocksize for ETFS section, if that's the case
    -- then need to reformat ETFS
    if (operation == "start") then                     
        -- find start,end block from new nand partition file 
        local f = io.open ( new_nand_partition, "r")
        if not f then
            return false,"Unable to open cofig file"
        end        
        for line in f:lines() do                
            -- parse etfs block section 
            -- example line "ETFS 1223 1666"
            local start_block,end_block =  string.match(string.upper(line),"^%s*ETFS%s*,%s*(%d+)%s*,%s(%d+)")    
            if (start_block ~= nil) and (end_block ~= nil) then 
                new_start = start_block
                new_end   = end_block     
            end     
        end 
        f:close()        
        if (new_start == nil) or (new_end == nil) then 
            return false, "new config file parsing error"           
        end
        
        -- find start,end block from target nand partition file 
        local f = io.open ( target_nand_partition, "r")        
        if f then
            for line in f:lines() do                 
                local start_block, end_block =  string.match(string.upper(line),"^%s*ETFS%s*,%s*(%d+)%s*,%s(%d+)")   
                if (start_block ~= nil) and (end_block ~= nil) then 
                    old_start = start_block
                    old_end   = end_block
                end         
            end 
            f:close()    
        end        
        -- reformat ETFS if there is a change in etfs partition 
        -- also will reformat if no nand_partition file exists on target
        if ((new_start ~= old_start) or (new_end ~= old_end)) then 
            printLog(" Will be reformatting etfs because of nand paritition changes ")
            reformat = true
        end                    
    end           
    
    -- default reformat is false so this will be executed for any operation other than "start"
    -- if operation is "start" and needs a reformat then reformat flag will be true
    if not reformat then    
        cmd = path.."/"..unit.etfs_start_script.." -p "..new_nand_partition.." -v "..version_file.." "..operation
    else
        cmd = path.."/"..unit.etfs_start_script.." -p "..new_nand_partition.." -v "..version_file.." "..operation.." format"
    end
            
    print(cmd)          
    ret_code = os.execute(cmd)/256   
    -- Check for the return code     
    if (ret_code == nil or ret_code ~= 0) then 
        printLog(string.format(" Unable to %s etfs driver successfully ret_code = %s", 
                operation, (ret_code ~= nil) and tostring(ret_code) or "ret_code is nil"))
        -- ret_code 9 = ETFS driver in ISO image failed to start
        -- Attempt to restart the etfs with format option
        if (ret_code == 9 and not reformat) then
           printLog(" Attempting to restart etfs driver with format option")
           cmd = cmd.." format"
           ret_code = os.execute(cmd)/256
           if (ret_code == nil or ret_code ~= 0) then 
              printLog(string.format(" Unable to %s etfs driver (with format option) successfully ret_code = %s", 
                      operation, (ret_code ~= nil) and tostring(ret_code) or "ret_code is nil"))
              return false, "Unable to "..operation.."  etfs driver successfully"
           end
        -- ret_code 12 = Driver is running, but mountpoint either does not exist OR is a not a directory (indicates corruption)
        -- Attempt to stop and then restart the etfs driver with format option
        elseif (ret_code == 12 and not reformat) then
           printLog(" ETFS driver started, but mountpoint is not a directory")
           printLog(" Attempting to stop ETFS driver so we can restart it with format option")
           -- create stop command
           cmd2 = path.."/"..unit.etfs_start_script.." -p "..new_nand_partition.." -v "..version_file.." stop"
           ret_code = os.execute(cmd2)/256
           if (ret_code == nil or ret_code ~= 0) then 
              printLog(string.format(" Unable to stop etfs driver successfully ret_code = %s", 
                      (ret_code ~= nil) and tostring(ret_code) or "ret_code is nil"))
              return false, "Unable to stop etfs driver successfully"
           end
           printLog(" Attempting to restart etfs driver with format option")
           cmd = cmd.." format"
           ret_code = os.execute(cmd)/256
           if (ret_code == nil or ret_code ~= 0) then 
              printLog(string.format(" Unable to %s etfs driver (with format option) successfully ret_code = %s", 
                      operation, (ret_code ~= nil) and tostring(ret_code) or "ret_code is nil"))
              return false, "Unable to "..operation.."  etfs driver successfully"
           end
        else
           return false, "Unable to "..operation.."  etfs driver successfully"
        end
    end 
    
    return true 
end

local function callInstall(subunit, mountpath)
    print( string.format("Installing unit %s",subunit.name))
    local installer = require(subunit.name)    
    return installer.install(subunit, mountpath)
end

-- generic function to call installer
function callPrePostInstaller(unit, mountpath, mode)
    local installer
    local subunit = {}   
    if (mode == "pre") then 
        if (unit.preInstaller == nil)  then
            print(" no pre installer ")    
            return true
        end  
        subunit = unit.preInstaller  
    elseif (mode == "post") then 
       if (unit.postInstaller == nil)  then
            print(" no post installer ")    
            return true
        end       
        subunit = unit.postInstaller
    else
        print("no pre or post specified")
        return false
    end 
    
    local function xpCallErrorHandler(o)
       printLog( debug.traceback(o, 2) )
    end
    
    local completed, success, err, err_code = xpcall( function() return callInstall(subunit,mountpath) end, xpCallErrorHandler)
    -- xpcall failure
    if not completed then 
        err = "INSTALL ERROR"     
        print("pre-post install error")
        return false, err
    end      
    
    return success, err, err_code
end     

-- generic function called before calling installer
function checkModuleAvailable(unit)
    local env_value = nil
  
    if (unit == nil) then 
        printLog("checkModuleAvailable, No Unit specified")
        return false
    end 
    
    -- if not env name then that means that 
    -- there is no check
    if (unit.env_name == nil) then 
        return true
    end    
    
    env_value = os.getenv(unit.env_name)       
    if (env_value == nil) then
        printLog(string.format(" checkModuleAvailable, Unable to find environment varible %s\n", unit.env_name))
        return false
    else    
        if ((string.match(env_value, "YES")) == nil) then 
            printLog(string.format(" checkModuleAvailable, environment variable %s is not set, value = %s",unit.env_name, env_value))
            return false
        end
    end
    printLog(string.format(" checkModuleAvailable, environment variable %s is set = %s",unit.env_name, env_value))
    return true
end
